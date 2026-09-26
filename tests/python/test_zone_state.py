import unittest
from unittest.mock import patch

from backend.aura_backend.zone_state import multizone_flag, read_zone_state
from .fakes import PATH


class ZoneStateTests(unittest.TestCase):
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
                self.assertIs(multizone_flag(text), value)

    def test_no_rgb_zones_needs_no_config_read(self):
        with patch('pathlib.Path.read_text', side_effect=AssertionError("must not read")):
            self.assertEqual(read_zone_state(PATH, []), "global")

    def test_config_is_read_only_and_unknown_fails_closed(self):
        for contents, expected in [('(multizone_on: true)', 'zoned'),
                                   ('(multizone_on: false)', 'global'), ('garbage', 'unknown')]:
            with patch('pathlib.Path.read_text', return_value=contents):
                self.assertEqual(read_zone_state(PATH, [1]), expected)
        with patch('pathlib.Path.read_text', side_effect=PermissionError):
            self.assertEqual(read_zone_state(PATH, [1]), 'unknown')

    def test_invalid_path_rejected_before_config_access(self):
        with patch('pathlib.Path.read_text') as read, self.assertRaises(ValueError):
            read_zone_state('/etc/passwd', [1])
        read.assert_not_called()
