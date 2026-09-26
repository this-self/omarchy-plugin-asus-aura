"""The only module that knows busctl arguments and Aura's D-Bus tuples."""
import json
import re
import subprocess

from .models import Colour, DeviceState, Effect, PATH_RE, PowerRow

SERVICE = "xyz.ljones.Asusd"
INTERFACE = "xyz.ljones.Aura"
PROPERTIES = ("Brightness", "LedMode", "LedModeData", "LedPower",
              "SupportedBasicModes", "SupportedBrightness", "DeviceType",
              "SupportedBasicZones", "SupportedPowerZones")


def run_busctl(*args):
    result = subprocess.run(
        ["busctl", "--system", "--timeout=5s", "--json=short", *args],
        capture_output=True, text=True, timeout=7, check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "ASUS service request failed")
    return result.stdout


def decode_effect(data):
    mode, zone, colour1, colour2, speed, direction = data
    return Effect(mode, zone, Colour(*colour1), Colour(*colour2), speed, direction)


def decode_power(data):
    return [PowerRow(*row) for row in data[0]]


def effect_data(effect):
    first, second = effect.colour1, effect.colour2
    return [effect.mode, effect.zone, [first.red, first.green, first.blue],
            [second.red, second.green, second.blue], effect.speed, effect.direction]


def power_data(rows):
    return [[r.zone, r.boot, r.awake, r.sleep, r.shutdown] for r in rows]


class AuraBus:
    def __init__(self, run=run_busctl):
        self.run = run

    def discover(self):
        objects = self.run("tree", "--list", SERVICE).splitlines()
        paths = [p.strip() for p in objects if re.fullmatch(PATH_RE, p.strip())]
        if not paths:
            raise RuntimeError("No supported ASUS Aura device found")
        return sorted(paths)[0]

    def get(self, path, prop):
        raw = self.run("get-property", SERVICE, path, INTERFACE, prop)
        return json.loads(raw)["data"]

    def set(self, path, prop, signature, *values):
        self.run("set-property", SERVICE, path, INTERFACE, prop, signature,
                 *(str(v).lower() if isinstance(v, bool) else str(v) for v in values))

    def snapshot(self, path):
        raw = self.run("get-property", SERVICE, path, INTERFACE, *PROPERTIES)
        values = [json.loads(line)["data"] for line in raw.splitlines() if line.strip()]
        if len(values) != len(PROPERTIES):
            raise RuntimeError("Incomplete ASUS lighting state")
        values[2] = decode_effect(values[2])
        values[3] = decode_power(values[3])
        return DeviceState(*values)

    def read_effect(self, path):
        return decode_effect(self.get(path, "LedModeData"))

    def read_power(self, path):
        return decode_power(self.get(path, "LedPower"))

    def write_brightness(self, path, value):
        self.set(path, "Brightness", "u", value)

    def write_mode(self, path, mode):
        self.set(path, "LedMode", "u", mode)

    def write_effect(self, path, effect):
        mode, zone, first, second, speed, direction = effect_data(effect)
        self.set(path, "LedModeData", "(uu(yyy)(yyy)ss)", mode, zone,
                 *first, *second, speed, direction)

    def write_power(self, path, rows):
        self.set(path, "LedPower", "(a(ubbbb))", len(rows),
                 *(v for row in power_data(rows) for v in row))
