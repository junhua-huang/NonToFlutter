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
        for name in ['Compliance.json', 'privacy.txt', 'terms.txt', 'PrivacyInfo.xcprivacy']:
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
        data.update(contactEmail='privacy@operator.cn', privacyPolicyURL='https://operator.cn/privacy', termsURL='https://operator.cn/terms', releaseReviewed=True)
        path.write_text(json.dumps(data))
        self.assertTrue(checker.inspect(self.resources)[1])
        data['verification'] = {key: True for key in checker.EVIDENCE}
        path.write_text(json.dumps(data))
        errors, blockers = checker.inspect(self.resources)
        self.assertEqual(errors, [])
        self.assertEqual(len(blockers), 2)
        self.assertTrue(all('Public operator identity disclosure' in item for item in blockers))
        for name in ('privacy', 'terms'):
            policy = self.resources / (name + '.txt')
            policy.write_text(policy.read_text() + '\n运营者：{{operatorName}}\n')
        self.assertEqual(checker.inspect(self.resources), ([], []))
    def test_example_contacts_remain_blocked(self):
        path = self.resources / 'Compliance.json'
        data = json.loads(path.read_text()); data['contactEmail'] = 'support@facebook-clone.app'
        path.write_text(json.dumps(data))
        self.assertTrue(any('contactEmail' in item for item in checker.inspect(self.resources)[1]))
    def run_build_action(self, action):
        scripts = self.root / 'scripts'; scripts.mkdir()
        shutil.copy(SCRIPTS / 'check_compliance.py', scripts / 'check_compliance.py')
        tree = ast.parse((SCRIPTS / 'generate_project.py').read_text())
        script = next(ast.literal_eval(node.value) for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'archive_script' for target in node.targets))
        env = dict(os.environ, ACTION=action, SRCROOT=str(self.root))
        return subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True, text=True)
    def test_archive_blocks_incomplete_operator_information(self):
        result = self.run_build_action('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('RELEASE BLOCKER', result.stdout)
    def test_normal_build_is_available_for_local_testing(self):
        self.assertEqual(self.run_build_action('build').returncode, 0)
