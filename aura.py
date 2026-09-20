#!/usr/bin/env python3
"""Validated Aura operations. D-Bus writes only; daemon config is read-only.

asusd 6.4 has no multizone-state/readback API. Read only the top-level
multizone_on flag from its known config location, failing closed if unavailable.
Never claim LedModeData describes the active per-zone colours.
"""
import json
from pathlib import Path
import re
import sys

from resync import busctl, get, resync, set_property, SERVICE, INTERFACE

PATH_RE = r"/xyz/ljones/aura/([A-Za-z0-9]+)_[A-Za-z0-9_]+"
PROPERTIES = ["Brightness", "LedMode", "LedModeData", "LedPower",
              "SupportedBasicModes", "SupportedBrightness", "DeviceType",
              "SupportedBasicZones", "SupportedPowerZones"]
FIELDS = {"colour1": 2, "colour2": 3, "speed": 4, "direction": 5}
# Matches upstream rog-control-center 6.4.0, not generic struct fields.
EFFECT_FIELDS = {
    0: {"colour1"}, 1: {"colour1", "colour2", "speed"}, 2: {"speed"},
    3: {"speed", "direction"}, 4: {"colour1", "colour2", "speed"},
    5: {"speed"}, 6: {"colour1", "speed"}, 7: {"colour1", "speed"},
    8: {"colour1", "speed"}, 10: {"colour1"}, 11: {"colour1"},
    12: {"colour1"},
}


def validate_path(path):
    if not re.fullmatch(PATH_RE, path):
        raise ValueError("Invalid ASUS Aura device path")


def multizone_flag(text):
    """Read one root-level bool without interpreting colours or enum IDs.

    Tokenize strings/comments so nested fields and commented-out values cannot
    masquerade as the root flag. Unknown/malformed layouts fail closed.
    """
    tokens = re.findall(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'
                        r'[A-Za-z_][A-Za-z0-9_]*|[^\s]', text)
    tokens = [t for t in tokens if not t.startswith(('//', '/*'))]
    stack, values = [], []
    pairs = {')': '(', ']': '[', '}': '{'}
    for i, token in enumerate(tokens):
        if token == 'multizone_on' and stack == ['(']:
            if tokens[i + 1:i + 3] not in [[':', 'true'], [':', 'false']]:
                return None
            if tokens[i + 3:i + 4] not in [[','], [')']]:
                return None
            values.append(tokens[i + 2] == 'true')
        if token in ('(', '[', '{'):
            stack.append(token)
        elif token in pairs:
            if not stack or stack.pop() != pairs[token]:
                return None
    return values[0] if not stack and len(values) == 1 else None


def zone_state(path, zones):
    if not zones:
        return False
    product = re.fullmatch(PATH_RE, path)[1]
    try:
        return multizone_flag(Path(f"/etc/asusd/aura_{product}.ron").read_text())
    except (OSError, UnicodeError):
        return None


def discover():
    objects = busctl("tree", "--list", SERVICE).splitlines()
    paths = [p.strip() for p in objects if re.fullmatch(PATH_RE, p.strip())]
    if not paths:
        raise RuntimeError("No supported ASUS Aura device found")
    return sorted(paths)[0]


def state(path):
    validate_path(path)
    # busctl emits one JSON object per property.
    raw = busctl("get-property", SERVICE, path, INTERFACE, *PROPERTIES)
    values = [json.loads(line)["data"] for line in raw.splitlines() if line.strip()]
    if len(values) != len(PROPERTIES):
        raise RuntimeError("Incomplete ASUS lighting state")
    brightness, mode, data, power, modes, levels, device, zones, power_zones = values
    return dict(available=True, path=path, brightness=brightness, mode=mode,
                data=data, power=power[0], modes=modes, levels=levels,
                deviceType=device, zones=zones, powerZones=power_zones,
                multizone=zone_state(path, zones))


def preserve_brightness(path, operation):
    brightness = get(path, "Brightness")
    error = None
    try:
        operation()
    except Exception as exc:
        error = exc
    try:
        set_property(path, "Brightness", "u", brightness)
    except Exception as exc:
        raise RuntimeError(f"{str(error) + '; ' if error else ''}"
                           f"Could not restore brightness: {exc}") from exc
    if error:
        raise error


def write_effect(path, data):
    set_property(path, "LedModeData", "(uu(yyy)(yyy)ss)",
                 data[0], data[1], *data[2], *data[3], data[4], data[5])


def power_controls(device, supported, rows):
    """Capabilities, not the generic four-bool D-Bus structure."""
    zones = [r[0] for r in rows if r[0] in supported]
    if device == 1:  # pre-2021: OR-combined Boot/Sleep, independent Awake
        return ([(-1, "boot"), (-1, "sleep")] if zones else []) + [
            (z, "awake") for z in zones if z in (1, 2, 5)]
    if device == 2:  # TUF: first row only, no Shutdown
        return [(zones[0], f) for f in ("boot", "awake", "sleep")] if zones else []
    if device in (0, 4):
        return [(z, f) for z in zones for f in ("boot", "awake", "sleep", "shutdown")]
    return []  # Do not guess for unknown protocols.


def apply_power(path, zone, field, value):
    if type(zone) is not int or type(value) is not bool:
        raise ValueError("Invalid lighting power value")
    device = get(path, "DeviceType")
    supported = get(path, "SupportedPowerZones")
    rows = get(path, "LedPower")[0]
    if (zone, field) not in power_controls(device, supported, rows):
        raise ValueError("Power control is not supported by this controller")
    index = {"boot": 1, "awake": 2, "sleep": 3, "shutdown": 4}[field]
    for row in rows:
        # Shared bits are OR'ed across ALL rows by asusd, so normalize all.
        if zone == -1 or row[0] == zone:
            row[index] = value
    set_property(path, "LedPower", "(a(ubbbb))", len(rows),
                 *(v for row in rows for v in row))


def apply(path, request):
    validate_path(path)
    kind = request["kind"]
    if kind == "brightness":
        value = request["value"]
        if type(value) is not int or value not in get(path, "SupportedBrightness"):
            raise ValueError("Unsupported brightness")
        set_property(path, "Brightness", "u", value)
    elif kind == "mode":
        mode = request["value"]
        if type(mode) is not int or mode not in get(path, "SupportedBasicModes"):
            raise ValueError("Unsupported effect")
        preserve_brightness(path, lambda: set_property(path, "LedMode", "u", mode))
    elif kind in ("effect", "global"):
        data = get(path, "LedModeData")
        if request["mode"] != get(path, "LedMode") or request["mode"] != data[0]:
            raise ValueError("Effect changed externally; refresh and try again")
        zones = get(path, "SupportedBasicZones")
        if kind == "effect":
            if zone_state(path, zones) is not False:
                raise ValueError("Zoned lighting is active or unknown. Explicitly choose 'Use global effect' first")
            field, value = request["field"], request["value"]
            if field not in EFFECT_FIELDS.get(data[0], set()):
                raise ValueError("This effect does not support that control")
            if field.startswith("colour"):
                if not isinstance(value, list) or len(value) != 3 or any(
                        type(v) is not int or not 0 <= v <= 255 for v in value):
                    raise ValueError("Invalid RGB colour")
            elif field == "speed" and value not in ("Low", "Med", "High"):
                raise ValueError("Invalid speed")
            elif field == "direction" and value not in ("Right", "Left", "Up", "Down"):
                raise ValueError("Invalid direction")
            data[FIELDS[field]] = value
        data[1] = 0
        preserve_brightness(path, lambda: write_effect(path, data))
    elif kind == "power":
        apply_power(path, request["zone"], request["field"], request["value"])
    elif kind == "resync":
        resync(path)
    else:
        raise ValueError("Unknown Aura operation")


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "state":
            print(json.dumps(state(discover())))
        elif len(sys.argv) == 4 and sys.argv[1] == "apply":
            apply(sys.argv[2], json.loads(sys.argv[3]))
        else:
            raise ValueError("Expected state or apply PATH JSON")
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
