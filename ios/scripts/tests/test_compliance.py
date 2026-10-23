import ast
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('check_compliance', SCRIPTS / 'check_compliance.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

class ComplianceChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.resources = self.root / 'Nonto' / 'Resources'
        self.resources.mkdir(parents=True)
        for name in ['Compliance.json', 'privacy.txt', 'terms.txt', 'community.txt', 'PrivacyInfo.xcprivacy']:
            shutil.copy(checker.RESOURCES / name, self.resources / name)
        path = self.resources / 'Compliance.json'
        data = json.loads(path.read_text())
        data.update({key: '' for key in checker.REQUIRED_FIELDS})
        data['releaseReviewed'] = False
        data['verification'] = {key: False for key in checker.EVIDENCE}
        path.write_text(json.dumps(data))
    def tearDown(self):
        self.temp.cleanup()
    def test_incomplete_metadata_is_not_release_ready(self):
        errors, blockers = checker.inspect(self.resources)
        self.assertEqual(errors, [])
        self.assertTrue(any('operatorName' in item for item in blockers))
        self.assertTrue(any('accountDeletionVerified' in item for item in blockers))
    def test_private_messages_must_be_disclosed(self):
        path = self.resources / 'PrivacyInfo.xcprivacy'
        data = plistlib.loads(path.read_bytes())
        data['NSPrivacyCollectedDataTypes'] = [row for row in data['NSPrivacyCollectedDataTypes'] if row['NSPrivacyCollectedDataType'] != 'NSPrivacyCollectedDataTypeEmailsOrTextMessages']
        path.write_bytes(plistlib.dumps(data))
        self.assertTrue(any('EmailsOrTextMessages' in item for item in checker.inspect(self.resources)[0]))
    def test_completed_metadata_requires_operational_evidence_too(self):
        path = self.resources / 'Compliance.json'
        data = json.loads(path.read_text())
        for key in checker.REQUIRED_FIELDS:
            data[key] = '运营方核实的处理规则'
        data.update(contactEmail='privacy@operator.cn', privacyPolicyURL='https://operator.cn/privacy', termsURL='https://operator.cn/terms', communityRulesURL='https://operator.cn/community', appFilingNumber='桂ICP备2026012531号-1A', releaseReviewed=True)
        path.write_text(json.dumps(data))
        self.assertTrue(checker.inspect(self.resources)[1])
        data['verification'] = {key: True for key in checker.EVIDENCE}
        path.write_text(json.dumps(data))
        errors, blockers = checker.inspect(self.resources)
        self.assertEqual(errors, [])
        self.assertEqual(checker.inspect(self.resources), ([], []))
        for name in checker.DOCUMENTS:
            path = self.resources / (name + '.txt')
            original = path.read_text()
            path.write_text(original.replace('{{operatorName}}', '南图'))
            self.assertIn('Public operator identity disclosure is missing: ' + name, checker.inspect(self.resources)[1])
            path.write_text(original)
    def test_website_filing_is_not_accepted_as_an_app_filing(self):
        path = self.resources / 'Compliance.json'
        data = json.loads(path.read_text())
        for value in ('桂ICP备2026012531号', '桂ICP备2026012531号-1', 'not-an-app-filing'):
            data['appFilingNumber'] = value
            path.write_text(json.dumps(data))
            self.assertTrue(any('website ICP number' in item for item in checker.inspect(self.resources)[1]))
        data['appFilingNumber'] = '桂ICP备2026012531号-1A'
        path.write_text(json.dumps(data))
        self.assertFalse(any('website ICP number' in item for item in checker.inspect(self.resources)[1]))
    def test_example_contacts_remain_blocked(self):
        path = self.resources / 'Compliance.json'
        data = json.loads(path.read_text()); data['contactEmail'] = 'support@facebook-clone.app'
        path.write_text(json.dumps(data))
        self.assertTrue(any('contactEmail' in item for item in checker.inspect(self.resources)[1]))
    def test_published_documents_do_not_contain_engineering_audit_notes(self):
        for name in checker.DOCUMENTS:
            self.assertIsNone(checker.PUBLIC_DRAFT.search((checker.RESOURCES / (name + '.txt')).read_text()), name)

    def test_flags_cannot_approve_unverified_public_wording(self):
        path = self.resources / 'Compliance.json'
        data = json.loads(path.read_text())
        for key in checker.REQUIRED_FIELDS:
            data[key] = '明确的信息处理规则'
        data.update(contactEmail='privacy@operator.cn', privacyPolicyURL='https://operator.cn/privacy', termsURL='https://operator.cn/terms', communityRulesURL='https://operator.cn/community', appFilingNumber='桂ICP备2026012531号-2A', releaseReviewed=True)
        data['verification'] = {key: True for key in checker.EVIDENCE}
        path.write_text(json.dumps(data))
        self.assertEqual(checker.inspect(self.resources), ([], []))
        for wording in ('实际服务方仍须核验', '完整删除尚未完成验证', '本版本处于开发测试', '服务商未核实'):
            policy = self.resources / 'privacy.txt'
            original = policy.read_text()
            policy.write_text(original + '\n' + wording)
            self.assertTrue(any('internal draft' in item for item in checker.inspect(self.resources)[1]), wording)
            policy.write_text(original)
            data['storageSummary'] = wording
            path.write_text(json.dumps(data))
            self.assertTrue(any('unresolved public disclosure' in item for item in checker.inspect(self.resources)[1]), wording)
            data['storageSummary'] = '明确的信息处理规则'
            path.write_text(json.dumps(data))
    def run_build_action(self, action, channel="app-store"):
        scripts = self.root / 'scripts'; scripts.mkdir()
        shutil.copy(SCRIPTS / 'check_compliance.py', scripts / 'check_compliance.py')
        tree = ast.parse((SCRIPTS / 'generate_project.py').read_text())
        script = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'archive_script' for target in node.targets))
        env = dict(os.environ, ACTION=action, SRCROOT=str(self.root), NONTO_DISTRIBUTION_CHANNEL=channel)
        return subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True, text=True)
    def test_archive_blocks_incomplete_operator_information(self):
        result = self.run_build_action('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('RELEASE BLOCKER', result.stdout)
    def test_normal_build_is_available_for_local_testing(self):
        self.assertEqual(self.run_build_action('build').returncode, 0)

    def test_internal_archive_keeps_structural_checks_but_allows_testing(self):
        result = self.run_build_action('install', 'testflight-internal')
        self.assertEqual(result.returncode, 0)
        self.assertIn('RELEASE BLOCKER', result.stdout)

    def test_internal_archive_rejects_broken_privacy_manifest(self):
        path = self.resources / 'PrivacyInfo.xcprivacy'
        data = plistlib.loads(path.read_bytes()); data['NSPrivacyTracking'] = True
        path.write_bytes(plistlib.dumps(data))
        self.assertNotEqual(self.run_build_action('install', 'testflight-internal').returncode, 0)

    def test_store_draft_upload_preserves_unreviewed_operational_evidence(self):
        path = self.resources / 'Compliance.json'; before = path.read_bytes()
        result = self.run_build_action('install', 'app-store-upload')
        self.assertEqual(result.returncode, 0)
        self.assertIn('RELEASE BLOCKER', result.stdout)
        self.assertEqual(path.read_bytes(), before)

    def test_store_draft_upload_still_rejects_broken_privacy_structure(self):
        path = self.resources / 'PrivacyInfo.xcprivacy'
        data = plistlib.loads(path.read_bytes()); data['NSPrivacyTracking'] = True
        path.write_bytes(plistlib.dumps(data))
        self.assertNotEqual(self.run_build_action('install', 'app-store-upload').returncode, 0)
