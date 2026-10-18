import base64
from datetime import datetime, timedelta
import importlib.util
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SCRIPTS = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('testflight', SCRIPTS / 'testflight.py')
tf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tf)
spec = importlib.util.spec_from_file_location('retire_legacy_signing', SCRIPTS / 'retire_legacy_signing.py')
retirement = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'testflight': tf}):
    spec.loader.exec_module(retirement)


class LegacyRetirementChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.new_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Synthetic legacy fixture'),
                            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, retirement.TEAM)])
        now = datetime.now()
        cls.cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                    .public_key(cls.old_key.public_key()).serial_number(int(retirement.LEGACY_SERIAL, 16))
                    .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=1))
                    .sign(cls.old_key, hashes.SHA256()))

    def setUp(self):
        self.env = patch.dict(os.environ, {'GITHUB_REPOSITORY': retirement.REPOSITORY,
                                          'GITHUB_REF': 'refs/heads/ios'})
        self.env.start(); self.addCleanup(self.env.stop)
        self.key = patch.object(retirement, 'load_signing_key', return_value=self.new_key)
        self.key.start(); self.addCleanup(self.key.stop)
        self.fingerprint = patch.object(retirement, 'LEGACY_SHA1', self.cert.fingerprint(hashes.SHA1()).hex().upper())
        self.fingerprint.start(); self.addCleanup(self.fingerprint.stop)
        self.target = {'id': retirement.LEGACY_CERTIFICATE, 'attributes': {
            'certificateType': 'DISTRIBUTION', 'serialNumber': retirement.LEGACY_SERIAL,
            'certificateContent': base64.b64encode(self.cert.public_bytes(serialization.Encoding.DER)).decode()}}
        self.certificates = [self.target, {'id': retirement.PRESERVED_CERTIFICATE}]
        self.profiles = [{'id': retirement.LEGACY_PROFILE, 'attributes': {
            'name': retirement.LEGACY_PROFILE_NAME, 'profileType': 'IOS_APP_STORE'}},
            {'id': 'OTHER_APP_PROFILE', 'attributes': {'name': 'Other app'}}]
        self.other_uses_target = False
        self.bundle = retirement.BUNDLE
        self.apple = Mock(); self.apple.request.side_effect = self.request

    def request(self, method, resource, **kwargs):
        if method == 'DELETE':
            self.assertEqual(resource, 'certificates/' + retirement.LEGACY_CERTIFICATE)
            return {}
        self.assertEqual(method, 'GET')
        if resource == 'certificates': return {'data': self.certificates}
        if resource == 'profiles': return {'data': self.profiles}
        if resource == 'profiles/' + retirement.LEGACY_PROFILE + '/certificates':
            return {'data': [self.target]}
        if resource == 'profiles/OTHER_APP_PROFILE/certificates':
            return {'data': [self.target] if self.other_uses_target else [{'id': retirement.PRESERVED_CERTIFICATE}]}
        if resource == 'profiles/' + retirement.LEGACY_PROFILE + '/bundleId':
            return {'data': {'attributes': {'identifier': self.bundle}}}
        self.fail('Unexpected request: ' + resource)

    def assert_no_mutations(self):
        self.assertTrue(all(c.args[0] == 'GET' for c in self.apple.request.call_args_list))

    def test_dry_run_is_read_only_and_execution_deletes_only_the_exact_certificate(self):
        retirement.retire(self.apple)
        self.assert_no_mutations()
        self.apple.reset_mock()
        retirement.retire(self.apple, execute=True)
        changes = [c.args for c in self.apple.request.call_args_list if c.args[0] != 'GET']
        self.assertEqual(changes, [('DELETE', 'certificates/' + retirement.LEGACY_CERTIFICATE)])

    def test_other_repository_or_branch_is_rejected_before_apple_calls(self):
        for env in ({'GITHUB_REPOSITORY': 'junhua-huang/OtherApp'}, {'GITHUB_REF': 'refs/heads/main'}):
            with patch.dict(os.environ, env), self.assertRaises(ValueError):
                retirement.retire(self.apple, execute=True)
        self.apple.request.assert_not_called()

    def test_other_app_profile_or_bundle_blocks_revocation(self):
        self.other_uses_target = True
        with self.assertRaisesRegex(ValueError, 'Another profile'):
            retirement.retire(self.apple, execute=True)
        self.assert_no_mutations()
        self.other_uses_target = False; self.bundle = 'online.other.app'
        with self.assertRaisesRegex(ValueError, 'another app'):
            retirement.retire(self.apple, execute=True)
        self.assert_no_mutations()

    def test_fingerprint_serial_type_or_reusable_identity_mismatch_blocks_revocation(self):
        for field, value in [('serialNumber', 'WRONG'), ('certificateType', 'DEVELOPMENT')]:
            with patch.dict(self.target['attributes'], {field: value}), self.assertRaises(ValueError):
                retirement.retire(self.apple, execute=True)
        with patch.object(retirement, 'LEGACY_SHA1', '0' * 40), self.assertRaises(ValueError):
            retirement.retire(self.apple, execute=True)
        with patch.object(retirement, 'load_signing_key', return_value=self.old_key), self.assertRaises(ValueError):
            retirement.retire(self.apple, execute=True)
        self.assert_no_mutations()

    def test_missing_protected_certificate_or_legacy_profile_blocks_revocation(self):
        self.certificates = [self.target]
        with self.assertRaisesRegex(ValueError, 'preserved'):
            retirement.retire(self.apple, execute=True)
        self.certificates.append({'id': retirement.PRESERVED_CERTIFICATE})
        self.profiles = []
        with self.assertRaisesRegex(ValueError, 'not verified'):
            retirement.retire(self.apple, execute=True)
        self.assert_no_mutations()

    def test_repeated_execution_when_old_certificate_is_absent_is_read_only(self):
        self.certificates = [{'id': retirement.PRESERVED_CERTIFICATE}]
        retirement.retire(self.apple, execute=True)
        self.assert_no_mutations()
