import base64
from datetime import datetime, timedelta
import importlib.util
import io
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
from cryptography.hazmat.primitives.asymmetric import ec, rsa
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
                tf.cleanup(root)
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

    def test_cleanup_is_offline_and_never_revokes_reusable_or_legacy_resources(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(tf, 'Apple') as apple:
            root = Path(temp)
            state = {'team': tf.TEAM, 'bundle': tf.BUNDLE, 'run': os.environ.get('GITHUB_RUN_ID', 'local'),
                     'build': '2.3', 'upload_attempted': True, 'certificate': 'legacy-cert',
                     'profile': 'legacy-profile', 'signing_certificate': 'reusable-cert'}
            tf.save_state(root, state)
            tf.cleanup(root)
            apple.assert_not_called()
            self.assertEqual(json.loads(tf.state_path(root).read_text()), state)

    def test_cleanup_rejects_profile_path_outside_runner_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); victim = root / 'keep.key'; victim.write_text('fixture')
            tf.save_state(root, {'team': tf.TEAM, 'bundle': tf.BUNDLE,
                                'run': os.environ.get('GITHUB_RUN_ID', 'local'), 'installed_profile': str(victim)})
            with self.assertRaises(ValueError): tf.cleanup(root)
            self.assertTrue(victim.exists())

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


class ReusableSigningChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    def certificate(self, key=None, *, expired=False, team=tf.TEAM):
        key = key or self.key
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Synthetic distribution'),
                            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, team)])
        now = datetime.now()
        return (x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(key.public_key())
                .serial_number(1).not_valid_before(now - timedelta(days=2))
                .not_valid_after(now + timedelta(days=-1 if expired else 30)).sign(key, hashes.SHA256()))

    def record(self, key=None, **kwargs):
        cert = self.certificate(key, **kwargs)
        return {'id': 'OWNCERT', 'attributes': {'certificateType': 'DISTRIBUTION',
                'certificateContent': base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode()}}

    def test_daily_reuse_never_creates_a_certificate_even_in_initialization_mode(self):
        for initialize in (False, True):
            apple = Mock(); apple.request.return_value = {'data': [self.record()]}
            row, certificate = tf.reusable_certificate(apple, self.key, initialize=initialize)
            self.assertEqual(row['id'], 'OWNCERT'); tf.validate_certificate(certificate, self.key)
            self.assertEqual([call.args for call in apple.request.call_args_list], [('GET', 'certificates')])

    def test_missing_expired_wrong_team_and_wrong_key_never_trigger_daily_creation(self):
        for records in [[], [self.record(expired=True)], [self.record(team='OTHER')], [self.record(self.other_key)]]:
            apple = Mock(); apple.request.return_value = {'data': records}
            with self.assertRaisesRegex(ValueError, 'Daily uploads never create'):
                tf.reusable_certificate(apple, self.key)
            self.assertEqual(apple.request.call_count, 1)

    def test_explicit_initialization_creates_once_and_reuses_afterward(self):
        row = self.record(); apple = Mock()
        apple.request.side_effect = [{'data': []}, {'data': row}]
        created, _ = tf.reusable_certificate(apple, self.key, initialize=True)
        self.assertEqual(created['id'], row['id'])
        csr_text = apple.request.call_args.kwargs['data']['data']['attributes']['csrContent']
        csr = x509.load_pem_x509_csr(csr_text.encode())
        self.assertEqual(csr.public_key().public_numbers(), self.key.public_key().public_numbers())
        self.assertTrue(csr.is_signature_valid)
        apple.request.side_effect = None; apple.request.return_value = {'data': [row]}; apple.reset_mock()
        tf.reusable_certificate(apple, self.key, initialize=True)
        self.assertEqual([call.args for call in apple.request.call_args_list], [('GET', 'certificates')])

    def test_unsupported_initialization_key_size_is_rejected_without_posting_csr(self):
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        apple = Mock(); apple.request.return_value = {'data': []}
        with self.assertRaisesRegex(ValueError, 'requires RSA 2048'):
            tf.reusable_certificate(apple, key, initialize=True)
        self.assertTrue(all(call.args[0] == 'GET' for call in apple.request.call_args_list))

    def test_profiles_reuse_validated_matching_profile_and_create_only_explicitly(self):
        row = {'id': 'PROFILE', 'attributes': {'name': tf.PROFILE_PREFIX + 'OWNCERT-1234',
                                               'profileType': 'IOS_APP_STORE', 'profileState': 'ACTIVE'}}
        with tempfile.TemporaryDirectory() as temp, patch.object(tf, 'decode_profile', return_value=('uuid', datetime.now())):
            root = Path(temp); apple = Mock(); apple.request.return_value = {'data': [row]}
            for initialize in (False, True):
                apple.reset_mock()
                selected, _ = tf.reusable_profile(root, apple, 'bundle', {'id': 'OWNCERT'}, b'der', initialize=initialize)
                self.assertEqual(selected['id'], 'PROFILE')
                self.assertTrue(all(call.args[0] == 'GET' for call in apple.request.call_args_list))
            apple.request.return_value = {'data': []}
            with self.assertRaisesRegex(ValueError, 'Daily uploads never create'):
                tf.reusable_profile(root, apple, 'bundle', {'id': 'OWNCERT'}, b'der')
            apple.request.side_effect = [{'data': []}, {'data': row}]
            tf.reusable_profile(root, apple, 'bundle', {'id': 'OWNCERT'}, b'der', initialize=True)
            self.assertEqual(apple.request.call_args.args, ('POST', 'profiles'))

    def test_profile_validation_rejects_mismatch_without_creating_replacement(self):
        row = {'id': 'PROFILE', 'attributes': {'name': tf.PROFILE_PREFIX + 'OWNCERT-1234',
                                               'profileType': 'IOS_APP_STORE', 'profileState': 'ACTIVE'}}
        with tempfile.TemporaryDirectory() as temp, patch.object(tf, 'decode_profile', side_effect=ValueError('Wrong team')):
            apple = Mock(); apple.request.return_value = {'data': [row]}
            with self.assertRaises(ValueError): tf.reusable_profile(Path(temp), apple, 'bundle', {'id': 'OWNCERT'}, b'der')
            self.assertEqual(apple.request.call_count, 1)

    def test_signing_key_is_required_and_apns_key_is_rejected_before_api_calls(self):
        with tempfile.TemporaryDirectory() as temp:
            for pem in ['', 'malformed', ec.generate_private_key(ec.SECP256R1()).private_bytes(
                    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()]:
                apple = Mock()
                with patch.dict(os.environ, {'IOS_SIGNING_KEY': pem}), self.assertRaises(ValueError):
                    tf.prepare(Path(temp) / 'signing', apple)
                apple.request.assert_not_called()

    def test_lookup_follows_safe_pagination_and_never_creates_on_incomplete_results(self):
        apple = Mock(); apple.request.side_effect = [
            {'data': [], 'links': {'next': tf.API + 'certificates?cursor=next'}}, {'data': [self.record()]}]
        tf.reusable_certificate(apple, self.key)
        self.assertEqual(apple.request.call_count, 2)
        self.assertEqual(apple.request.call_args.kwargs['query'], {'cursor': 'next'})
        apple.request.side_effect = None
        apple.request.return_value = {'data': [], 'links': {'next': 'https://other.test/certificates'}}
        with self.assertRaises(ValueError): tf.reusable_certificate(apple, self.key, initialize=True)
        self.assertTrue(all(call.args[0] == 'GET' for call in apple.request.call_args_list))

    def test_apple_error_diagnosis_reports_known_causes_without_raw_secrets(self):
        for detail, expected in [('You already have the maximum number of distribution certificates. token=secret', 'certificate limit'),
                                 ('The CSR is invalid; secret', 'signing request'),
                                 ('CSR algorithm/size incorrect. Expected: RSA(2048) secret', 'RSA 2048'),
                                 ('Accept your agreement secret', 'agreement')]:
            body = json.dumps({'errors': [{'code': 'ENTITY_ERROR.ATTRIBUTE.INVALID', 'detail': detail}]}).encode()
            error = HTTPError('https://secret.test', 409, 'secret', {}, io.BytesIO(body))
            message = tf.apple_error_diagnostic(error)
            self.assertIn(expected, message); self.assertIn('ENTITY_ERROR.ATTRIBUTE.INVALID', message)
            self.assertNotIn('secret', message)

    def test_local_key_creation_is_stable_and_never_overwrites(self):
        spec = importlib.util.spec_from_file_location('create_signing_key', Path(__file__).parents[1] / 'create_signing_key.py')
        helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'signing.key'
            fingerprint = helper.create_key(path)
            saved = path.read_bytes(); self.assertEqual(len(fingerprint), 64)
            loaded = serialization.load_pem_private_key(saved, password=None)
            self.assertIsInstance(loaded, rsa.RSAPrivateKey)
            self.assertEqual(loaded.key_size, 2048)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(ValueError): helper.create_key(path)
            self.assertEqual(path.read_bytes(), saved)

    def test_two_upload_preparations_keep_same_identity_and_make_only_get_requests(self):
        row = self.record()
        cert_der = base64.b64decode(row['attributes']['certificateContent'])
        profile = {'UUID': '11111111-2222-3333-4444-555555555555', 'TeamIdentifier': [tf.TEAM],
                   'DeveloperCertificates': [cert_der], 'ExpirationDate': datetime.now() + timedelta(days=2),
                   'Entitlements': {'application-identifier': tf.TEAM + '.' + tf.BUNDLE,
                                    'com.apple.developer.team-identifier': tf.TEAM,
                                    'aps-environment': 'production', 'get-task-allow': False}}
        profile_row = {'id': 'PROFILE', 'attributes': {'name': tf.PROFILE_PREFIX + 'OWNCERT-stable',
                       'profileType': 'IOS_APP_STORE', 'profileState': 'ACTIVE',
                       'profileContent': base64.b64encode(b'synthetic-cms').decode()}}
        responses = {'apps': [{'id': 'app'}], 'bundleIds': [{'id': 'bundle'}],
                     'bundleIds/bundle/bundleIdCapabilities': [{'attributes': {'capabilityType': 'PUSH_NOTIFICATIONS'}}],
                     'certificates': [row], 'bundleIds/bundle/profiles': [profile_row]}
        def request(method, resource, **kwargs):
            self.assertEqual(method, 'GET')
            return {'data': responses[resource]}
        apple = Mock(); apple.pem = b'synthetic-asc-key'; apple.request.side_effect = request
        pem = self.key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
        with tempfile.TemporaryDirectory() as temp, patch.object(tf.subprocess, 'run', return_value=Mock(stdout=plistlib.dumps(profile))):
            parent = Path(temp)
            with patch.dict(os.environ, {'HOME': str(parent), 'IOS_SIGNING_KEY': pem, 'GITHUB_ENV': str(parent / 'env'),
                                         'GITHUB_RUN_ID': 'synthetic-run', 'GITHUB_RUN_NUMBER': '7', 'GITHUB_RUN_ATTEMPT': '1'}):
                for index in (1, 2):
                    root = parent / str(index); tf.prepare(root, apple)
                    state = json.loads(tf.state_path(root).read_text())
                    self.assertEqual(state['signing_certificate'], 'OWNCERT')
                    self.assertEqual(state['signing_profile'], 'PROFILE')
                    self.assertTrue(Path(state['installed_profile']).exists())
                    tf.cleanup(root)
                    self.assertFalse(Path(state['installed_profile']).exists())
        self.assertTrue(all(call.args[0] == 'GET' for call in apple.request.call_args_list))

    def test_diagnosis_confirms_key_match_without_revealing_private_material_or_writing(self):
        certificate = self.record()
        responses = {'certificates': [certificate], 'bundleIds': [{'id': 'bundle'}],
                     'bundleIds/bundle/profiles': [], 'apps': [{'id': 'app'}],
                     'builds': [{'attributes': {'version': '2.3', 'processingState': 'VALID'}}]}
        def request(method, resource, **kwargs):
            self.assertEqual(method, 'GET')
            return {'data': responses[resource]}
        pem = self.key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
        apple = Mock(); apple.request.side_effect = request
        with patch.dict(os.environ, {'IOS_SIGNING_KEY': pem}), patch('sys.stdout', new_callable=io.StringIO) as output:
            tf.diagnose(apple)
        text = output.getvalue()
        self.assertIn('Matching valid distribution certificates: OWNCERT', text)
        information = json.loads(next(line.removeprefix('App filing certificate: ') for line in text.splitlines()
                                      if line.startswith('App filing certificate: ')))
        expected_certificate = x509.load_der_x509_certificate(base64.b64decode(certificate['attributes']['certificateContent']))
        self.assertEqual(information['bundleID'], tf.BUNDLE)
        self.assertEqual(information['certificateID'], 'OWNCERT')
        self.assertEqual(information['sha1'], expected_certificate.fingerprint(hashes.SHA1()).hex().upper())
        self.assertEqual(serialization.load_der_public_key(bytes.fromhex(information['publicKey'])).public_numbers(),
                         self.key.public_key().public_numbers())
        self.assertIn('2.3 processing: VALID', text)
        self.assertNotIn('PRIVATE KEY', text)
        self.assertNotIn(pem, text)
        self.assertTrue(all(call.args[0] == 'GET' for call in apple.request.call_args_list))
