import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import aura

PATH = "/xyz/ljones/aura/1866_3_3"


class AuraTests(unittest.TestCase):
    def setUp(self):
        self.values = {
            "Brightness": 0, "LedMode": 1,
            "LedModeData": [1, 0, [255, 127, 0], [0, 0, 0], "Low", "Right"],
            "SupportedBasicModes": [0, 1, 2, 3, 10],
            "SupportedBasicZones": [1, 2, 3, 4],
            "SupportedBrightness": [0, 1, 2, 3],
            "DeviceType": 1, "SupportedPowerZones": [1, 2],
            "LedPower": [[[1, False, True, False, False], [2, True, True, False, True]]],
        }
        self.writes = []
        self.get_patch = patch.object(aura, "get", side_effect=lambda p, k: copy.deepcopy(self.values[k]))
        self.set_patch = patch.object(aura, "set_property", side_effect=self.set_property)
        self.zone_patch = patch.object(aura, "zone_state", return_value=False)
        self.get_patch.start()
        self.set_patch.start()
        self.zone = self.zone_patch.start()
        self.addCleanup(patch.stopall)

    def set_property(self, path, prop, signature, *values):
        self.writes.append((prop, signature, values))
        if prop == "Brightness":
            self.values[prop] = values[0]

    def test_shared_boot_updates_every_row(self):
        aura.apply(PATH, dict(kind="power", zone=-1, field="boot", value=False))
        self.assertEqual(self.writes, [("LedPower", "(a(ubbbb))", (
            2, 1, False, True, False, False, 2, False, True, False, True))])

    def test_lightbar_awake_preserves_other_flags(self):
        aura.apply(PATH, dict(kind="power", zone=2, field="awake", value=False))
        self.assertEqual(self.writes[0][2], (
            2, 1, False, True, False, False, 2, True, False, False, True))

    def test_old_shutdown_and_independent_boot_rejected(self):
        for zone, field in [(1, "shutdown"), (2, "shutdown"), (1, "boot")]:
            with self.assertRaises(ValueError):
                aura.apply(PATH, dict(kind="power", zone=zone, field=field, value=True))
        self.assertEqual(self.writes, [])

    def test_controller_capabilities(self):
        rows = self.values["LedPower"][0]
        self.assertEqual(len(aura.power_controls(0, [1, 2], rows)), 8)
        self.assertEqual(aura.power_controls(2, [1], rows), [(1, "boot"), (1, "awake"), (1, "sleep")])
        self.assertEqual(aura.power_controls(255, [1, 2], rows), [])

    def test_mode_preserves_off(self):
        aura.apply(PATH, dict(kind="mode", value=10))
        self.assertEqual(self.writes, [("LedMode", "u", (10,)), ("Brightness", "u", (0,))])

    def test_brightness_restored_even_on_failure(self):
        def fail():
            self.values["Brightness"] = 2
            raise RuntimeError("effect failed")
        with self.assertRaisesRegex(RuntimeError, "effect failed"):
            aura.preserve_brightness(PATH, fail)
        self.assertEqual(self.values["Brightness"], 0)

    def test_brightness_restore_failure_reports_both_errors(self):
        with patch.object(aura, "set_property", side_effect=RuntimeError("restore failed")):
            with self.assertRaisesRegex(RuntimeError, "effect failed; Could not restore brightness: restore failed"):
                aura.preserve_brightness(PATH, lambda: (_ for _ in ()).throw(RuntimeError("effect failed")))

    def test_effect_patch_preserves_other_live_fields_and_off(self):
        aura.apply(PATH, dict(kind="effect", mode=1, field="colour2", value=[1, 2, 3]))
        self.assertEqual(self.writes[0][2], (1, 0, 255, 127, 0, 1, 2, 3, "Low", "Right"))
        self.assertEqual(self.writes[-1], ("Brightness", "u", (0,)))

    def test_global_edits_fail_closed_for_zoned_or_unknown_state(self):
        for value in [True, None]:
            self.zone.return_value = value
            with self.assertRaisesRegex(ValueError, "Zoned lighting"):
                aura.apply(PATH, dict(kind="effect", mode=1, field="speed", value="Low"))
        self.assertEqual(self.writes, [])

    def test_explicit_global_conversion(self):
        self.zone.return_value = True
        aura.apply(PATH, dict(kind="global", mode=1))
        self.assertEqual(self.writes[0][2][1], 0)
        self.assertEqual(self.writes[-1], ("Brightness", "u", (0,)))

    def test_external_mode_change_rejected(self):
        with self.assertRaisesRegex(ValueError, "changed externally"):
            aura.apply(PATH, dict(kind="effect", mode=0, field="colour1", value=[1, 2, 3]))
        self.assertEqual(self.writes, [])

    def test_inapplicable_fields_rejected(self):
        for mode, field, value in [(0, "colour2", [1, 2, 3]), (10, "speed", "Low"), (2, "colour1", [1, 2, 3])]:
            self.values["LedMode"] = mode
            self.values["LedModeData"][0] = mode
            with self.assertRaises(ValueError):
                aura.apply(PATH, dict(kind="effect", mode=mode, field=field, value=value))
        self.assertEqual(self.writes, [])

    def test_invalid_requests_do_not_write(self):
        for request in [dict(kind="mode", value=9), dict(kind="brightness", value=True),
                        dict(kind="effect", mode=1, field="speed", value="slow"),
                        dict(kind="effect", mode=1, field="colour1", value=[256, 0, 0])]:
            with self.assertRaises(ValueError):
                aura.apply(PATH, request)
        with self.assertRaises(ValueError):
            aura.apply("/xyz/ljones/aura/../../etc", dict(kind="mode", value=0))
        self.assertEqual(self.writes, [])

    def test_discovery_and_state_read(self):
        with patch.object(aura, "busctl", return_value=PATH + "\n/xyz/ljones/asus_armoury\n"):
            self.assertEqual(aura.discover(), PATH)
        payload = "\n".join(json.dumps({"data": self.values[k]}) for k in aura.PROPERTIES)
        with patch.object(aura, "busctl", return_value=payload):
            state = aura.state(PATH)
        self.assertEqual(state["powerZones"], [1, 2])
        self.assertIs(state["multizone"], False)

    def test_multizone_parser(self):
        cases = {
            '(multizone_on: false,)': False,
            '(multizone_on: true)': True,
            '(nested: (multizone_on: true,), multizone_on: false,)': False,
            '(label: "multizone_on: true", multizone_on: false,)': False,
            '(// multizone_on: true\n multizone_on: false,)': False,
            '(/* multizone_on: true */ multizone_on: false,)': False,
            '(multizone_on: true, multizone_on: false,)': None,
            '(multizone_on: true': None,
            '(nested: (multizone_on: true,))': None,
            '(multizone_on: falsehood,)': None,
            '(multizone_on: false + true,)': None,
        }
        for text, value in cases.items():
            with self.subTest(text=text):
                self.assertIs(aura.multizone_flag(text), value)


if __name__ == "__main__":
    unittest.main()
