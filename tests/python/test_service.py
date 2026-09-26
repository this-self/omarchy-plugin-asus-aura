import copy
from pathlib import Path
import json
import unittest

from backend.aura_backend.capabilities import effect_info, power_keys
from backend.aura_backend.service import AuraService
from .fakes import FakeBus, PATH


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeBus()
        self.zone_state = "global"
        self.service = AuraService(self.fake.bus, lambda path, zones: self.zone_state)

    def apply(self, **request):
        self.service.apply(PATH, request)

    def test_shared_boot_updates_every_row_including_unadvertised_rows(self):
        self.fake.values["LedPower"][0].append([99, True, False, True, True])
        self.apply(kind="power", zone=-1, field="boot", value=False)
        self.assertEqual(self.fake.writes, [("LedPower", "(a(ubbbb))", [
            "3", "1", "false", "true", "false", "false", "2", "false", "true", "false", "true",
            "99", "false", "false", "true", "true"])])

    def test_lightbar_awake_preserves_other_flags(self):
        self.apply(kind="power", zone=2, field="awake", value=False)
        self.assertEqual(self.fake.writes[0][2], [
            "2", "1", "false", "true", "false", "false", "2", "true", "false", "false", "true"])

    def test_unsupported_power_controls_do_not_write(self):
        for zone, field in [(1, "shutdown"), (2, "shutdown"), (1, "boot")]:
            with self.subTest(zone=zone, field=field), self.assertRaises(ValueError):
                self.apply(kind="power", zone=zone, field=field, value=True)
        self.assertEqual(self.fake.writes, [])

    def test_controller_capabilities(self):
        rows = self.fake.bus.read_power(PATH)
        self.assertEqual(len(power_keys(0, [1, 2], rows)), 8)
        self.assertEqual(power_keys(2, [1], rows), [(1, "boot"), (1, "awake"), (1, "sleep")])
        self.assertEqual(power_keys(255, [1, 2], rows), [])
        self.assertEqual(effect_info(999)["fields"], [])
        self.assertEqual(effect_info(999)["name"], "Mode 999")
        self.assertNotIn("speed", effect_info(10)["fields"])

    def test_mode_preserves_off(self):
        self.apply(kind="mode", value=10)
        self.assertEqual(self.fake.writes, [("LedMode", "u", ["10"]), ("Brightness", "u", ["0"])])

    def test_brightness_restored_even_on_operation_failure(self):
        def fail():
            self.fake.values["Brightness"] = 2
            raise RuntimeError("effect failed")
        with self.assertRaisesRegex(RuntimeError, "effect failed"):
            self.service.preserve_brightness(PATH, fail)
        self.assertEqual(self.fake.values["Brightness"], 0)

    def test_restore_failure_reports_both_errors(self):
        self.fake.fail_on = {"LedMode", "Brightness"}
        with self.assertRaisesRegex(RuntimeError, "LedMode failed; Could not restore brightness: Brightness failed"):
            self.apply(kind="mode", value=1)

    def test_effect_patch_preserves_other_live_fields_and_off(self):
        self.apply(kind="effect", mode=1, field="colour2", value=[1, 2, 3])
        self.assertEqual(self.fake.writes[0], ("LedModeData", "(uu(yyy)(yyy)ss)",
            ["1", "0", "255", "127", "0", "1", "2", "3", "Low", "Right"]))
        self.assertEqual(self.fake.writes[-1], ("Brightness", "u", ["0"]))

    def test_global_edits_fail_closed_for_zoned_or_unknown_state(self):
        for state in ["zoned", "unknown"]:
            self.zone_state = state
            with self.assertRaisesRegex(ValueError, "Zoned lighting"):
                self.apply(kind="effect", mode=1, field="speed", value="Low")
        self.assertEqual(self.fake.writes, [])

    def test_zone_guard_is_checked_again_at_write_time(self):
        self.assertEqual(self.service.state(PATH)["zoneState"], "global")
        self.zone_state = "zoned"
        with self.assertRaisesRegex(ValueError, "Zoned lighting"):
            self.apply(kind="effect", mode=1, field="speed", value="Low")
        self.assertEqual(self.fake.writes, [])

    def test_explicit_global_conversion(self):
        self.zone_state = "zoned"
        self.fake.values["LedModeData"][1] = 2
        self.apply(kind="global", mode=1)
        self.assertEqual(self.fake.writes[0][2][1], "0")
        self.assertEqual(self.fake.writes[-1], ("Brightness", "u", ["0"]))

    def test_external_mode_change_rejected(self):
        for changed in ["LedMode", "LedModeData"]:
            fake = FakeBus()
            if changed == "LedMode":
                fake.values[changed] = 0
            else:
                fake.values[changed][0] = 0
            with self.assertRaisesRegex(ValueError, "changed externally"):
                AuraService(fake.bus).apply(PATH, dict(kind="effect", mode=1, field="colour1", value=[1, 2, 3]))
            self.assertEqual(fake.writes, [])

    def test_inapplicable_fields_rejected(self):
        for mode, field, value in [(0, "colour2", [1, 2, 3]), (10, "speed", "Low"), (2, "colour1", [1, 2, 3])]:
            self.fake.values["LedMode"] = mode
            self.fake.values["LedModeData"][0] = mode
            with self.assertRaises(ValueError):
                self.apply(kind="effect", mode=mode, field=field, value=value)
        self.assertEqual(self.fake.writes, [])

    def test_invalid_requests_do_not_write(self):
        requests = [dict(kind="mode", value=9), dict(kind="brightness", value=True),
                    dict(kind="effect", mode=1, field="speed", value="slow"),
                    dict(kind="effect", mode=1, field="colour1", value=[256, 0, 0]),
                    dict(kind="effect", mode=True, field="speed", value="Low"),
                    dict(kind="power", zone=2, field="awake", value="false"),
                    dict(kind="unknown"), []]
        for request in requests:
            with self.subTest(request=request), self.assertRaises(ValueError):
                self.service.apply(PATH, request)
        with self.assertRaises(ValueError):
            self.service.apply("/xyz/ljones/aura/../../etc", dict(kind="mode", value=0))
        self.assertEqual(self.fake.writes, [])

    def test_snapshot_matches_frontend_contract_fixture(self):
        fixture = Path(__file__).parents[1] / "fixtures" / "pre2021-global.json"
        self.assertEqual(self.service.state(), json.loads(fixture.read_text()))

    def test_unknown_controller_and_effect_do_not_guess_controls(self):
        self.fake.values["DeviceType"] = 255
        self.fake.values["SupportedBasicModes"] = [999]
        state = self.service.state(PATH)
        self.assertEqual(state["powerControls"], [])
        self.assertEqual(state["effects"][0]["colourCount"], 0)

    def test_resync_snapshots_all_reads_before_writing_and_preserves_off(self):
        saved = copy.deepcopy(self.fake.values)
        self.apply(kind="resync")
        self.assertEqual([w[0] for w in self.fake.writes], ["LedPower", "LedMode", "Brightness"])
        self.assertEqual(self.fake.writes[-1][2], ["0"])
        self.assertEqual(self.fake.values, saved)
        operations = [call[0] for call in self.fake.calls]
        self.assertEqual(operations, ["get-property"] * 3 + ["set-property"] * 3)

    def test_resync_restores_brightness_on_power_or_mode_failure(self):
        for prop in ["LedPower", "LedMode"]:
            fake = FakeBus()
            fake.fail_on.add(prop)
            with self.assertRaisesRegex(RuntimeError, prop + " failed"):
                AuraService(fake.bus).resync(PATH)
            self.assertEqual(fake.writes[-1], ("Brightness", "u", ["0"]))

    def test_resync_rejects_bad_snapshot_without_writing(self):
        self.fake.values["Brightness"] = 99
        with self.assertRaisesRegex(ValueError, "Unexpected keyboard brightness"):
            self.service.resync(PATH)
        self.assertEqual(self.fake.writes, [])
