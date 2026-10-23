import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[3] / '.github' / 'scripts' / 'wait_native_checks.py'
SPEC = importlib.util.spec_from_file_location('native_upload_checks', SCRIPT)
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


class NativeUploadChecks(unittest.TestCase):
    def fixture(self, name, **changes):
        return {'name': name, 'head_sha': 'own-commit', 'head_branch': 'ios', 'event': 'push',
                'status': 'completed', 'conclusion': 'success', **changes}

    def test_both_systems_must_pass(self):
        one = self.fixture('Native iOS')
        self.assertEqual(checks.check_states([one], 'own-commit')['Native iOS 27 Regression'], 'missing')
        both = [one, self.fixture('Native iOS 27 Regression')]
        self.assertTrue(all(x == 'success' for x in checks.check_states(both, 'own-commit').values()))

    def test_other_commits_branches_and_events_cannot_satisfy_upload_checks(self):
        for changes in ({'head_sha': 'other'}, {'head_branch': 'main'}, {'event': 'pull_request'}):
            states = checks.check_states([self.fixture('Native iOS', **changes)], 'own-commit')
            self.assertEqual(states['Native iOS'], 'missing')

    def test_failure_or_cancellation_stops_the_upload(self):
        for conclusion in ('failure', 'cancelled', 'skipped'):
            with self.assertRaises(ValueError):
                checks.check_states([self.fixture('Native iOS', conclusion=conclusion)], 'own-commit')
