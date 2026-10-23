import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock

SCRIPT = Path(__file__).resolve().parents[3] / '.github' / 'scripts' / 'appstore_metadata.py'
SPEC = importlib.util.spec_from_file_location('appstore_metadata_checks', SCRIPT)
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


class AppStoreDraftChecks(unittest.TestCase):
    def report(self, audience='APP_STORE_ELIGIBLE', state='PREPARE_FOR_SUBMISSION'):
        return {'versions': [{'id': 'own-version', 'attributes': {
            'platform': 'IOS', 'versionString': '1.0.0', 'appStoreState': state}}],
            'builds': [{'id': 'own-build', 'version': '80.1', 'processingState': 'VALID',
                        'buildAudienceType': audience, 'expired': False}]}

    def test_only_matching_eligible_build_can_be_selected_and_read_back(self):
        api = Mock(); api.request.side_effect = [{}, {'data': {'id': 'own-build'}}]
        metadata.select_build(api, self.report(), {'version': '1.0.0'}, '80.1')
        self.assertEqual(api.request.call_args_list[0].args,
                         ('PATCH', 'appStoreVersions/own-version/relationships/build'))
        self.assertEqual(api.request.call_args_list[0].kwargs['data'],
                         {'data': {'type': 'builds', 'id': 'own-build'}})
        self.assertEqual(api.request.call_args_list[1].args, ('GET', 'appStoreVersions/own-version/build'))

    def test_internal_builds_and_submitted_versions_never_change_the_draft(self):
        for report in [self.report(audience='INTERNAL_ONLY'), self.report(state='WAITING_FOR_REVIEW')]:
            api = Mock()
            with self.assertRaises(ValueError):
                metadata.select_build(api, report, {'version': '1.0.0'}, '80.1')
            api.request.assert_not_called()

    def test_other_build_numbers_and_versions_never_change_the_draft(self):
        for config, number in [({'version': '2.0.0'}, '80.1'), ({'version': '1.0.0'}, '81.1')]:
            api = Mock()
            with self.assertRaises(ValueError):
                metadata.select_build(api, self.report(), config, number)
            api.request.assert_not_called()
