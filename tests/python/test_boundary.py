from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

from backend.aura_backend.busctl import AuraBus, run_busctl
from backend.aura_backend.cli import main
from backend.aura_backend.service import AuraService
from .fakes import FakeBus, PATH


class BoundaryTests(unittest.TestCase):
    def test_incomplete_snapshot_is_an_error(self):
        bus = AuraBus(lambda *args: '{"data": 1}')
        with self.assertRaisesRegex(RuntimeError, 'Incomplete'):
            bus.snapshot(PATH)

    def test_discovery_does_not_accept_unrelated_paths(self):
        bus = AuraBus(lambda *args: '/xyz/ljones/asus_armoury\n')
        with self.assertRaisesRegex(RuntimeError, 'No supported'):
            bus.discover()

    def test_busctl_execution_uses_argument_array_and_timeouts(self):
        result = subprocess.CompletedProcess([], 0, 'response', '')
        with patch('subprocess.run', return_value=result) as run:
            self.assertEqual(run_busctl('tree', '--list', 'service'), 'response')
        self.assertEqual(run.call_args.args[0], [
            'busctl', '--system', '--timeout=5s', '--json=short', 'tree', '--list', 'service'])
        self.assertEqual(run.call_args.kwargs['timeout'], 7)
        result.returncode, result.stderr = 1, 'offline\n'
        with patch('subprocess.run', return_value=result), self.assertRaisesRegex(RuntimeError, 'offline'):
            run_busctl('tree')

    def test_cli_state_stdout_contains_only_json(self):
        fake = FakeBus()
        service = AuraService(fake.bus, lambda path, zones: 'global')
        output, errors = StringIO(), StringIO()
        with redirect_stdout(output), redirect_stderr(errors):
            self.assertEqual(main(['state'], service), 0)
        self.assertEqual(json.loads(output.getvalue()), service.state())
        self.assertEqual(errors.getvalue(), '')
        self.assertEqual(fake.writes, [])

    def test_legacy_state_keeps_cached_widgets_and_existing_callers_working(self):
        fake = FakeBus()
        service = AuraService(fake.bus, lambda path, zones: 'global')
        with redirect_stdout(StringIO()) as output:
            self.assertEqual(main(['state'], service, legacy_state=True), 0)
        self.assertEqual(json.loads(output.getvalue()), {
            'available': True, 'path': PATH, 'brightness': 0, 'mode': 1,
            'data': fake.values['LedModeData'], 'power': fake.values['LedPower'][0],
            'modes': [0, 1, 2, 3, 10], 'levels': [0, 1, 2, 3], 'deviceType': 1,
            'zones': [1, 2, 3, 4], 'powerZones': [1, 2], 'multizone': False,
        })
        self.assertEqual(fake.writes, [])

    def test_cli_apply_and_standalone_recovery_share_service(self):
        for args in [['apply', PATH, '{"kind":"resync"}'], ['resync', PATH]]:
            fake = FakeBus()
            with redirect_stdout(StringIO()) as output:
                self.assertEqual(main(args, AuraService(fake.bus)), 0)
            self.assertEqual(output.getvalue(), '')
            self.assertEqual([w[0] for w in fake.writes], ['LedPower', 'LedMode', 'Brightness'])

    def test_cli_errors_use_stderr_and_nonzero_exit(self):
        fake = FakeBus()
        for args in [[], ['apply', PATH, '{'], ['apply', PATH, 'null'], ['resync', '/invalid']]:
            output, errors = StringIO(), StringIO()
            with redirect_stdout(output), redirect_stderr(errors):
                self.assertEqual(main(args, AuraService(fake.bus)), 1)
            self.assertEqual(output.getvalue(), '')
            self.assertTrue(errors.getvalue())
        self.assertEqual(fake.writes, [])

    def test_launcher_works_outside_project_without_installation(self):
        # Invalid input exits before any bus access; safe on any machine.
        root = Path(__file__).resolve().parents[2]
        for launcher in ['backend/aura_cli.py', 'aura.py', 'resync.py']:
            with self.subTest(launcher=launcher):
                result = subprocess.run([sys.executable, '-B', str(root / launcher)],
                                        cwd='/tmp', capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertIn('Expected state', result.stderr)
                self.assertEqual(result.stdout, '')
