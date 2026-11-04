import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '.github' / 'scripts'))
spec = importlib.util.spec_from_file_location('internal_distribution', ROOT / '.github/scripts/distribute_internal_testflight.py')
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class InternalDistributionTests(unittest.TestCase):
    def api(self, assigned=None, state='VALID', groups=True):
        assigned = [] if assigned is None else assigned
        api = Mock()
        def request(method, resource, **kwargs):
            if resource == 'apps/' + distribution.APP_ID:
                return {'data': {'attributes': {'bundleId': distribution.BUNDLE}}}
            if resource == 'builds':
                return {'data': [{'id': 'build', 'attributes': {'processingState': state}}]}
            if resource.endswith('/betaGroups'):
                return {'data': ([{'id': 'internal', 'attributes': {'isInternalGroup': True}},
                                  {'id': 'external', 'attributes': {'isInternalGroup': False}}] if groups else [])}
            if method == 'POST':
                self.assertEqual(resource, 'betaGroups/internal/relationships/builds')
                self.assertEqual(kwargs['data'], {'data': [{'type': 'builds', 'id': 'build'}]})
                assigned.append({'id': 'build'}); return {}
            return {'data': list(assigned)}
        api.request.side_effect = request
        return api
    def test_assigns_only_existing_internal_group_and_verifies_readback(self):
        api = self.api()
        self.assertEqual(distribution.distribute(api, '120.1'), 1)
        self.assertEqual(sum(c.args[0] == 'POST' for c in api.request.call_args_list), 1)
    def test_existing_assignment_is_idempotent(self):
        api = self.api(assigned=[{'id': 'build'}])
        distribution.distribute(api, '120.1')
        self.assertFalse(any(c.args[0] == 'POST' for c in api.request.call_args_list))
    def test_invalid_build_or_absent_groups_never_change_apple(self):
        for api in (self.api(state='PROCESSING'), self.api(groups=False)):
            with self.assertRaises(ValueError): distribution.distribute(api, '120.1')
            self.assertFalse(any(c.args[0] == 'POST' for c in api.request.call_args_list))
