"""A fake transport that records exactly the D-Bus writes we would send."""
import copy
import json

from backend.aura_backend.busctl import AuraBus

PATH = "/xyz/ljones/aura/1866_3_3"


class FakeBus:
    def __init__(self):
        self.values = {
            "Brightness": 0, "LedMode": 1,
            "LedModeData": [1, 0, [255, 127, 0], [0, 0, 0], "Low", "Right"],
            "SupportedBasicModes": [0, 1, 2, 3, 10],
            "SupportedBasicZones": [1, 2, 3, 4],
            "SupportedBrightness": [0, 1, 2, 3],
            "DeviceType": 1, "SupportedPowerZones": [1, 2],
            "LedPower": [[[1, False, True, False, False], [2, True, True, False, True]]],
        }
        self.calls = []
        self.writes = []
        self.fail_on = set()
        self.bus = AuraBus(self.run)

    def run(self, operation, *args):
        self.calls.append((operation, args))
        if operation == "tree":
            return PATH + "\n/xyz/ljones/asus_armoury\n"
        if operation == "get-property":
            return "\n".join(json.dumps({"data": copy.deepcopy(self.values[prop])})
                             for prop in args[3:])
        if operation == "set-property":
            prop, signature, *values = args[3:]
            self.writes.append((prop, signature, values))
            if prop in self.fail_on:
                raise RuntimeError(f"{prop} failed")
            if prop == "Brightness":
                self.values[prop] = int(values[0])
            return ""
        raise AssertionError(f"Unexpected operation {operation}")
