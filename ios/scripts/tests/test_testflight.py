import base64
from datetime import datetime, timedelta
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from cryptography import x509

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

spec = importlib.util.spec_from_file_location('testflight', Path(__file__).parents[1] / 'testflight.py')
tf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tf)


class TestFlightChecks(unittest.TestCase):
    def profile(self):
        return {'UUID': '11111111-2222-3333-4444-555555555555', 'TeamIdentifier': [tf.TEAM],
                'DeveloperCertificates': [b'certificate'], 'ExpirationDate': datetime.now() + timedelta(days=1),
                'Entitlements': {'application-identifier': tf.TEAM + '.' + tf.BUNDLE,
                                 'com.apple.developer.team-identifier': tf.TEAM,
                                 'aps-environment': 'production', 'get-task-allow': False}}

    def test_jwt_has_correct_claims_and_verifiable_raw_es256_signature(self):
        key = ec.generate_private_key(ec.SECP256R1())
        jwt = tf.token(key, 'ABC123DEF4', 'issuer', now=1000)
        header, claims, signature = jwt.split('.')
        decode = lambda part: base64.urlsafe_b64decode(part + '=' * (-len(part) % 4))
        self.assertEqual(json.loads(decode(header))['kid'], 'ABC123DEF4')
        self.assertEqual(json.loads(decode(claims)), {'iss': 'issuer', 'iat': 990, 'exp': 1300, 'aud': 'appstoreconnect-v1'})
        raw = decode(signature)
        self.assertEqual(len(raw), 64)
        der = encode_dss_signature(int.from_bytes(raw[:32], 'big'), int.from_bytes(raw[32:], 'big'))
        key.public_key().verify(der, (header + '.' + claims).encode(), ec.ECDSA(hashes.SHA256()))

    def test_profile_requires_same_team_bundle_certificate_and_production(self):
        self.assertEqual(tf.validate_profile(self.profile(), b'certificate'), self.profile()['UUID'])
        variants = [({'TeamIdentifier': ['OTHER']}, None),
                    ({'ProvisionedDevices': ['device']}, None),
                    ({'ProvisionsAllDevices': True}, None),
                    ({'ExpirationDate': datetime.now() - timedelta(days=1)}, None),
                    ({'DeveloperCertificates': [b'other']}, None),
                    ({}, {'aps-environment': 'development'}),
                    ({}, {'get-task-allow': True}),
                    ({}, {'application-identifier': tf.TEAM + '.other.app'})]
        for fields, entitlements in variants:
            with self.subTest(fields=fields, entitlements=entitlements):
                profile = self.profile(); profile.update(fields)
                if entitlements:
                    profile['Entitlements'].update(entitlements)
                with self.assertRaises(ValueError):
                    tf.validate_profile(profile, b'certificate')

    def test_export_cannot_be_used_for_external_testflight_or_store(self):
        options = tf.export_options('profile-id', 'identity')
        self.assertIs(options['testFlightInternalTestingOnly'], True)
        self.assertEqual(options['destination'], 'upload')
        self.assertEqual(options['provisioningProfiles'], {tf.BUNDLE: 'profile-id'})
        self.assertFalse(options['manageAppVersionAndBuildNumber'])

    def test_archive_requires_internal_channel_and_production_apns(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / 'Products/Applications/Nonto.app'; app.mkdir(parents=True)
            info = {'CFBundleIdentifier': tf.BUNDLE, 'NontoDistributionChannel': tf.CHANNEL,
                    'NontoAPNSEnvironment': 'production', 'ITSAppUsesNonExemptEncryption': False}
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            tf.verify_archive(temp, unsigned=True)
            for field, value in [('CFBundleIdentifier', 'other.app'), ('NontoDistributionChannel', 'app-store'),
                                 ('NontoAPNSEnvironment', 'development')]:
                (app / 'Info.plist').write_bytes(plistlib.dumps(info | {field: value}))
                with self.assertRaises(ValueError):
                    tf.verify_archive(temp, unsigned=True)

    def test_api_errors_do_not_expose_tokens_or_response_bodies(self):
        key = ec.generate_private_key(ec.SECP256R1())
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
        with patch.dict(os.environ, {'ASC_KEY_ID': 'ABC123DEF4', 'ASC_ISSUER_ID': '11111111-2222-3333-4444-555555555555', 'ASC_PRIVATE_KEY': pem}):
            apple = tf.Apple(); apple.opener = Mock()
            apple.opener.open.side_effect = HTTPError('https://secret.test/token', 403, 'JWT=super-secret', {}, None)
            with self.assertRaises(ValueError) as failure:
                apple.request('GET', 'apps')
            self.assertIn('HTTP 403', str(failure.exception))
            self.assertNotIn('secret', str(failure.exception))
            with self.assertRaises(ValueError):
                apple.request('GET', '../another-origin')
            self.assertEqual(apple.opener.open.call_count, 1)

    def test_cleanup_never_touches_resources_from_another_run(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); tf.save_state(root, {'team': 'OTHER', 'bundle': tf.BUNDLE, 'run': 'local', 'certificate': 'old'})
            apple = Mock()
            with self.assertRaises(ValueError):
                tf.cleanup(root, apple)
            apple.request.assert_not_called()

    def test_temporary_api_failures_are_distinct_and_mutations_are_not_replayed(self):
        apple = tf.Apple.__new__(tf.Apple)
        apple.key = ec.generate_private_key(ec.SECP256R1())
        apple.key_id = 'ABC123DEF4'; apple.issuer = 'synthetic-issuer'; apple.opener = Mock()
        for error in [TimeoutError('secret'), HTTPError('https://secret.test', 429, 'secret', {}, None),
                      HTTPError('https://secret.test', 503, 'secret', {}, None)]:
            with self.subTest(error=type(error).__name__):
                apple.opener.reset_mock(); apple.opener.open.side_effect = error
                with self.assertRaises(tf.AppleUnavailable) as failure:
                    apple.request('POST', 'certificates', data={'data': {}})
                self.assertNotIn('secret', str(failure.exception))
                self.assertEqual(apple.opener.open.call_count, 1)

    def test_processing_recovers_after_timeout_without_uploading_again(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(tf.time, 'sleep'):
            root = Path(temp); tf.save_state(root, {'app': 'own-app', 'build': '2.3'})
            apple = Mock()
            apple.request.side_effect = [tf.AppleUnavailable('Timeout'), {'data': []},
                                        {'data': [{'attributes': {'processingState': 'VALID'}}]}]
            tf.wait_for_build(root, apple)
            self.assertTrue(json.loads(tf.state_path(root).read_text())['processed'])
            self.assertEqual(apple.request.call_count, 3)
            self.assertTrue(all(call.args == ('GET', 'builds') for call in apple.request.call_args_list))

    def test_processing_outage_is_bounded_and_never_marked_successful(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(tf.time, 'sleep'), \
                patch.object(tf.time, 'monotonic', side_effect=[0, 0, 601]):
            root = Path(temp); tf.save_state(root, {'app': 'own-app', 'build': '2.3'})
            apple = Mock(); apple.request.side_effect = tf.AppleUnavailable('Timeout')
            with self.assertRaisesRegex(ValueError, 'still pending'):
                tf.wait_for_build(root, apple)
            self.assertNotIn('processed', json.loads(tf.state_path(root).read_text()))
            self.assertEqual(apple.request.call_count, 1)

    def test_processing_does_not_retry_access_errors_or_rejected_builds(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(tf.time, 'sleep') as sleep:
            root = Path(temp); tf.save_state(root, {'app': 'own-app', 'build': '2.3'})
            apple = Mock(); apple.request.side_effect = ValueError('HTTP 403')
            with self.assertRaisesRegex(ValueError, 'HTTP 403'):
                tf.wait_for_build(root, apple)
            apple.request.side_effect = None
            apple.request.return_value = {'data': [{'attributes': {'processingState': 'INVALID'}}]}
            with self.assertRaisesRegex(ValueError, 'Apple rejected'):
                tf.wait_for_build(root, apple)
            sleep.assert_not_called()
            self.assertNotIn('processed', json.loads(tf.state_path(root).read_text()))

    def test_cleanup_outage_preserves_resources_and_reports_ids_for_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            state = {'team': tf.TEAM, 'bundle': tf.BUNDLE, 'run': os.environ.get('GITHUB_RUN_ID', 'local'),
                     'app': 'own-app', 'build': '2.3', 'upload_attempted': True,
                     'certificate': 'new-cert', 'profile': 'new-profile'}
            tf.save_state(root, state)
            summary = root / 'summary.md'
            apple = Mock(); apple.request.side_effect = tf.AppleUnavailable('Timeout')
            with patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': str(summary)}):
                tf.cleanup(root, apple)
            self.assertEqual(json.loads(tf.state_path(root).read_text()), state)
            self.assertEqual(apple.request.call_count, 1)
            self.assertIn('new-cert', summary.read_text())
            self.assertIn('new-profile', summary.read_text())
            self.assertIn('2.3', summary.read_text())

    def test_pending_upload_preserves_signing_and_cleanup_deletes_only_owned_resources(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            state = {'team': tf.TEAM, 'bundle': tf.BUNDLE, 'run': os.environ.get('GITHUB_RUN_ID', 'local'),
                     'app': 'own-app', 'build': '1.1', 'upload_attempted': True, 'certificate': 'new-cert', 'profile': 'new-profile'}
            tf.save_state(root, state)
            apple = Mock(); apple.request.return_value = {'data': [{'attributes': {'processingState': 'PROCESSING'}}]}
            tf.cleanup(root, apple)
            self.assertEqual(apple.request.call_count, 1)
            self.assertEqual(json.loads(tf.state_path(root).read_text())['certificate'], 'new-cert')
            state['processed'] = True; tf.save_state(root, state); apple.reset_mock()
            tf.cleanup(root, apple)
            self.assertEqual([call.args for call in apple.request.call_args_list], [('DELETE', 'profiles/new-profile'), ('DELETE', 'certificates/new-cert')])
            self.assertNotIn('certificate', json.loads(tf.state_path(root).read_text()))

    def test_credential_files_are_owner_only_and_redirects_are_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'private.key'; tf.write_private(path, b'private')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertIsNone(tf.NoRedirect().redirect_request())

    def test_signing_container_roundtrip_preserves_certificate_and_private_key(self):
        key = ec.generate_private_key(ec.SECP256R1())
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Synthetic signing fixture')])
        now = datetime.now()
        cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                .public_key(key.public_key()).serial_number(1).not_valid_before(now)
                .not_valid_after(now + timedelta(days=1)).sign(key, hashes.SHA256()))
        data = tf.signing_p12(key, cert, 'synthetic-test-password')
        restored_key, restored_cert, _ = pkcs12.load_key_and_certificates(data, b'synthetic-test-password')
        self.assertEqual(restored_key.public_key().public_numbers(), key.public_key().public_numbers())
        self.assertEqual(restored_cert.fingerprint(hashes.SHA256()), cert.fingerprint(hashes.SHA256()))
        with self.assertRaises(ValueError):
            pkcs12.load_key_and_certificates(data, b'wrong-password')
