"""Validated use cases. All writes read fresh state, never a UI snapshot."""
from dataclasses import replace

from .busctl import AuraBus
from .capabilities import DIRECTIONS, SPEEDS, effect_info, power_controls, power_keys
from .models import Colour, validate_path
from .zone_state import read_zone_state


class AuraService:
    def __init__(self, bus=None, zone_reader=read_zone_state):
        self.bus = bus if bus is not None else AuraBus()
        self.zone_reader = zone_reader

    def read_device(self, path=None):
        path = self.bus.discover() if path is None else path
        validate_path(path)
        return path, self.bus.snapshot(path)

    def state(self, path=None):
        path, st = self.read_device(path)
        return dict(
            version=1, path=path,
            device=dict(type=st.device_type, rgbZones=st.zones, powerZones=st.power_zones),
            brightness=dict(value=st.brightness, levels=st.levels),
            modeId=st.mode, savedEffect=st.effect.to_dict(),
            effects=[effect_info(mode) for mode in st.modes],
            zoneState=self.zone_reader(path, st.zones),
            powerControls=power_controls(st.device_type, st.power_zones, st.power),
        )

    def preserve_brightness(self, path, operation, brightness=None):
        if brightness is None:
            brightness = self.bus.get(path, "Brightness")
        error = None
        try:
            operation()
        except Exception as exc:
            error = exc
        try:
            self.bus.write_brightness(path, brightness)
        except Exception as exc:
            raise RuntimeError(f"{str(error) + '; ' if error else ''}"
                               f"Could not restore brightness: {exc}") from exc
        if error:
            raise error

    def apply_power(self, path, zone, field, value):
        if type(zone) is not int or type(value) is not bool:
            raise ValueError("Invalid lighting power value")
        device = self.bus.get(path, "DeviceType")
        supported = self.bus.get(path, "SupportedPowerZones")
        rows = self.bus.read_power(path)
        if (zone, field) not in power_keys(device, supported, rows):
            raise ValueError("Power control is not supported by this controller")
        # Shared flags are OR'ed across ALL daemon rows, including unadvertised
        # rows. Normalizing every row is essential when disabling a shared bit.
        rows = [replace(row, **{field: value}) if zone == -1 or row.zone == zone else row
                for row in rows]
        self.bus.write_power(path, rows)

    def apply_effect(self, path, request):
        effect = self.bus.read_effect(path)
        mode = request["mode"]
        if type(mode) is not int or mode != self.bus.get(path, "LedMode") or mode != effect.mode:
            raise ValueError("Effect changed externally; refresh and try again")
        if request["kind"] == "effect":
            zones = self.bus.get(path, "SupportedBasicZones")
            if self.zone_reader(path, zones) != "global":
                raise ValueError("Zoned lighting is active or unknown. Explicitly choose 'Use global effect' first")
            field, value = request["field"], request["value"]
            if field not in effect_info(effect.mode)["fields"]:
                raise ValueError("This effect does not support that control")
            if field.startswith("colour"):
                if not isinstance(value, list) or len(value) != 3:
                    raise ValueError("Invalid RGB colour")
                value = Colour(*value)
            elif field == "speed" and value not in SPEEDS:
                raise ValueError("Invalid speed")
            elif field == "direction" and value not in DIRECTIONS:
                raise ValueError("Invalid direction")
            effect = replace(effect, **{field: value})
        effect = replace(effect, zone=0)
        self.preserve_brightness(path, lambda: self.bus.write_effect(path, effect))

    def resync(self, path):
        validate_path(path)
        # Snapshot everything before any writes. LedMode reloads saved global
        # or zoned settings; LedModeData would silently replace active zones.
        brightness = self.bus.get(path, "Brightness")
        mode = self.bus.get(path, "LedMode")
        rows = self.bus.read_power(path)
        if type(brightness) is not int or not 0 <= brightness <= 3:
            raise ValueError("Unexpected keyboard brightness")
        if type(mode) is not int or not rows:
            raise ValueError("Unexpected ASUS lighting settings")

        def resend():
            self.bus.write_power(path, rows)
            self.bus.write_mode(path, mode)

        self.preserve_brightness(path, resend, brightness)

    def apply(self, path, request):
        validate_path(path)
        if not isinstance(request, dict):
            raise ValueError("Expected an Aura request object")
        kind = request.get("kind")
        if kind == "brightness":
            value = request["value"]
            if type(value) is not int or value not in self.bus.get(path, "SupportedBrightness"):
                raise ValueError("Unsupported brightness")
            self.bus.write_brightness(path, value)
        elif kind == "mode":
            mode = request["value"]
            if type(mode) is not int or mode not in self.bus.get(path, "SupportedBasicModes"):
                raise ValueError("Unsupported effect")
            self.preserve_brightness(path, lambda: self.bus.write_mode(path, mode))
        elif kind in ("effect", "global"):
            self.apply_effect(path, request)
        elif kind == "power":
            self.apply_power(path, request["zone"], request["field"], request["value"])
        elif kind == "resync":
            self.resync(path)
        else:
            raise ValueError("Unknown Aura operation")
