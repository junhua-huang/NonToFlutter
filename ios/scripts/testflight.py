#!/usr/bin/env python3
"""Internal TestFlight signing. Secrets are read only from the runner environment."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

TEAM = 'B2Y3564MKK'
BUNDLE = 'online.nonto.native'
CHANNEL = 'testflight-internal'
API = 'https://api.appstoreconnect.apple.com/v1/'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def write_private(path, contents):
    path = Path(path)
    with path.open('wb') as f:
        os.chmod(path, 0o600)
        f.write(contents)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def token(key, key_id, issuer, now=None):
    now = int(time.time() if now is None else now)
    header = b64url(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    claims = b64url(json.dumps({'iss': issuer, 'iat': now - 10, 'exp': now + 300, 'aud': 'appstoreconnect-v1'}).encode())
    signing = (header + '.' + claims).encode()
    r, s = decode_dss_signature(key.sign(signing, ec.ECDSA(hashes.SHA256())))
    return signing.decode() + '.' + b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Apple:
    def __init__(self):
        self.key_id = os.environ.get('ASC_KEY_ID', '').strip()
        self.issuer = os.environ.get('ASC_ISSUER_ID', '').strip()
        self.pem = os.environ.get('ASC_PRIVATE_KEY', '').strip().encode()
        require(re.fullmatch(r'[A-Z0-9]{10}', self.key_id), 'ASC_KEY_ID must be a 10-character App Store Connect key ID.')
        try:
            uuid.UUID(self.issuer)
            self.key = serialization.load_pem_private_key(self.pem, password=None)
            require(isinstance(self.key, ec.EllipticCurvePrivateKey) and isinstance(self.key.curve, ec.SECP256R1), 'ASC_PRIVATE_KEY must be an EC P-256 key.')
        except (ValueError, TypeError):
            raise ValueError('Invalid ASC_ISSUER_ID or ASC_PRIVATE_KEY. Use the App Store Connect key, not the APNs key.') from None
        require(self.key_id != '544CPXFY57', 'The APNs key cannot upload to App Store Connect.')
        self.opener = build_opener(NoRedirect())

    def request(self, method, resource, *, query=None, data=None):
        require(re.fullmatch(r'[A-Za-z0-9/_-]+', resource), 'Invalid Apple API resource.')
        url = API + resource + ('?' + urlencode(query) if query else '')
        request = Request(url, data=json.dumps(data).encode() if data is not None else None,
                          headers={'Authorization': 'Bearer ' + token(self.key, self.key_id, self.issuer),
                                   'Content-Type': 'application/json'}, method=method)
        try:
            with self.opener.open(request, timeout=45) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except HTTPError as error:
            # Never expose response bodies, JWTs, private keys, or request headers.
            raise ValueError(f'Apple API {method} {resource}: HTTP {error.code}. Check API access, agreements, and certificate quotas in Apple Developer.') from None
        except (URLError, TimeoutError, OSError):
            raise ValueError('Apple API connection failed; no credential details were logged.') from None


def validate_profile(profile, certificate):
    entitlements = profile.get('Entitlements', {})
    require(profile.get('TeamIdentifier') == [TEAM], 'Provisioning profile belongs to another team.')
    require(entitlements.get('application-identifier') == TEAM + '.' + BUNDLE, 'Profile Bundle ID does not match NonTo.')
    require(entitlements.get('com.apple.developer.team-identifier') == TEAM, 'Profile entitlement team mismatch.')
    require(entitlements.get('aps-environment') == 'production', 'App Store profile must enable production APNs.')
    require(entitlements.get('get-task-allow') is False, 'Development profiles cannot be uploaded to TestFlight.')
    require(not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'), 'An App Store distribution profile is required.')
    require(certificate in profile.get('DeveloperCertificates', []), 'Profile does not contain this run\'s certificate.')
    require(re.fullmatch(r'[A-Fa-f0-9-]{36}', profile.get('UUID', '')), 'Invalid provisioning profile UUID.')
    expiry = profile.get('ExpirationDate')
    require(isinstance(expiry, datetime) and expiry.replace(tzinfo=timezone.utc) > datetime.now(timezone.utc), 'Expired provisioning profile.')
    return profile['UUID']


def export_options(profile_id, identity):
    return {'method': 'app-store-connect', 'destination': 'upload', 'teamID': TEAM,
            'signingStyle': 'manual', 'signingCertificate': identity,
            'provisioningProfiles': {BUNDLE: profile_id}, 'uploadSymbols': True,
            'stripSwiftSymbols': True, 'manageAppVersionAndBuildNumber': False,
            'testFlightInternalTestingOnly': True}


def signing_p12(key, certificate, password):
    # macOS security's PKCS12 importer requires the interoperable PBE format.
    # This temporary container is never part of the app or a public artifact.
    encryption = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(20000)
                  .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
                  .hmac_hash(hashes.SHA1()).build(password.encode()))
    return pkcs12.serialize_key_and_certificates(b'NonTo TestFlight', key, certificate, None, encryption)


def verify_archive(archive, *, unsigned=False):
    app = Path(archive) / 'Products/Applications/Nonto.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == BUNDLE, 'Archive contains another app.')
    require(info.get('NontoDistributionChannel') == CHANNEL, 'This uploader only accepts an internal-test archive.')
    require(info.get('NontoAPNSEnvironment') == 'production', 'Archive does not use production APNs.')
    require(info.get('ITSAppUsesNonExemptEncryption') is False, 'Review the encryption declaration before upload.')
    if not unsigned:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
        result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], check=True, capture_output=True)
        entitlements = plistlib.loads(result.stdout)
        require(entitlements.get('aps-environment') == 'production', 'Signed app is missing production APNs entitlement.')
        require(entitlements.get('application-identifier') == TEAM + '.' + BUNDLE, 'Signed app identity mismatch.')
        require(entitlements.get('get-task-allow') is not True, 'Development signature is not allowed.')
    print('Archive identity, internal distribution channel, and production APNs verified.')


def state_path(root):
    return root / 'state.json'


def save_state(root, state):
    write_private(state_path(root), json.dumps(state).encode())


def prepare(root, apple):
    root.mkdir(parents=True, exist_ok=False, mode=0o700)
    run = os.environ.get('GITHUB_RUN_NUMBER', '1')
    attempt = os.environ.get('GITHUB_RUN_ATTEMPT', '1')
    require(run.isdigit() and 0 < int(run) < 10000 and attempt.isdigit() and 0 < int(attempt) < 100, 'Invalid build number.')
    state = {'team': TEAM, 'bundle': BUNDLE, 'run': os.environ.get('GITHUB_RUN_ID', 'local'), 'build': run + '.' + attempt}
    save_state(root, state)
    apps = apple.request('GET', 'apps', query={'filter[bundleId]': BUNDLE})['data']
    require(len(apps) == 1, 'Create the online.nonto.native app record in App Store Connect first.')
    state['app'] = apps[0]['id']; save_state(root, state)
    bundles = apple.request('GET', 'bundleIds', query={'filter[identifier]': BUNDLE})['data']
    require(len(bundles) == 1, 'App ID online.nonto.native was not found for this API key.')
    bundle_id = bundles[0]['id']
    capabilities = apple.request('GET', f'bundleIds/{bundle_id}/bundleIdCapabilities')['data']
    require(any(c['attributes']['capabilityType'] == 'PUSH_NOTIFICATIONS' for c in capabilities), 'Enable Push Notifications for the App ID first.')
    write_private(root / 'AuthKey.p8', apple.pem)
    signing_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, 'NonTo TestFlight CI'),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, TEAM),
    ])).sign(signing_key, hashes.SHA256())
    cert = apple.request('POST', 'certificates', data={'data': {'type': 'certificates', 'attributes': {
        'certificateType': 'DISTRIBUTION', 'csrContent': csr.public_bytes(serialization.Encoding.PEM).decode()}}})['data']
    state['certificate'] = cert['id']; save_state(root, state)
    print('Created temporary signing certificate:', cert['id'])
    cert_der = base64.b64decode(cert['attributes']['certificateContent'], validate=True)
    certificate = x509.load_der_x509_certificate(cert_der)
    require(certificate.public_key().public_numbers() == signing_key.public_key().public_numbers(), 'Certificate public key does not match this run.')
    require(any(a.value == TEAM for a in certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)), 'Certificate belongs to another team.')
    profile = apple.request('POST', 'profiles', data={'data': {'type': 'profiles', 'attributes': {
        'name': 'NonTo-TF-' + state['run'] + '-' + attempt, 'profileType': 'IOS_APP_STORE'}, 'relationships': {
        'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_id}},
        'certificates': {'data': [{'type': 'certificates', 'id': cert['id']}]}}}})['data']
    state['profile'] = profile['id']; save_state(root, state)
    print('Created temporary provisioning profile:', profile['id'])
    profile_path = root / 'NonTo.mobileprovision'
    write_private(profile_path, base64.b64decode(profile['attributes']['profileContent'], validate=True))
    decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile_path)], check=True, capture_output=True).stdout
    profile_id = validate_profile(plistlib.loads(decoded), cert_der)
    install = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (profile_id + '.mobileprovision')
    install.parent.mkdir(parents=True, exist_ok=True)
    write_private(install, profile_path.read_bytes())
    state['installed_profile'] = str(install); save_state(root, state)
    password = secrets.token_urlsafe(32)
    keychain_password = secrets.token_urlsafe(32)
    print('::add-mask::' + password); print('::add-mask::' + keychain_password)
    write_private(root / 'Signing.p12', signing_p12(signing_key, certificate, password))
    identity = hashlib.sha1(cert_der).hexdigest().upper()
    write_private(root / 'ExportOptions.plist', plistlib.dumps(export_options(profile_id, identity)))
    variables = {'TF_PROFILE_UUID': profile_id, 'TF_SIGNING_IDENTITY': identity, 'TF_P12_PASSWORD': password,
                 'TF_KEYCHAIN_PASSWORD': keychain_password, 'TF_BUILD_NUMBER': state['build']}
    with open(os.environ['GITHUB_ENV'], 'a') as f:
        for key, value in variables.items():
            f.write(key + '=' + value + '\n')


def build_status(apple, state):
    rows = apple.request('GET', 'builds', query={'filter[app]': state['app'], 'filter[version]': state['build'], 'limit': '10'})['data']
    require(len(rows) <= 1, 'Build number is ambiguous; check App Store Connect manually.')
    return rows[0]['attributes'].get('processingState', 'UNKNOWN') if rows else 'NOT_VISIBLE'


def wait_for_build(root, apple):
    state = json.loads(state_path(root).read_text())
    for _ in range(30):
        status = build_status(apple, state)
        print('Apple build processing:', status, flush=True)
        if status == 'VALID':
            state['processed'] = True; save_state(root, state)
            print('Build processed successfully. Add it to an internal tester group in App Store Connect.')
            return
        require(status not in ('FAILED', 'INVALID'), 'Apple rejected the build; inspect TestFlight build details.')
        time.sleep(20)
    raise ValueError('Upload returned, but Apple processing is still pending. Check TestFlight later; this is not a confirmed successful release.')


def cleanup(root, apple):
    if not state_path(root).exists():
        return
    state = json.loads(state_path(root).read_text())
    require(state.get('team') == TEAM and state.get('bundle') == BUNDLE and state.get('run') == os.environ.get('GITHUB_RUN_ID', 'local'), 'Refusing cleanup of another run\'s signing resources.')
    if state.get('upload_attempted') and not state.get('processed'):
        status = build_status(apple, state)
        if status not in ('VALID', 'FAILED', 'INVALID'):
            print('Apple processing is unconfirmed. Preserving temporary signing resources to avoid invalidating a pending build:')
            print('certificate:', state.get('certificate'), 'profile:', state.get('profile'))
            return
    failed = False
    for resource in ('profile', 'certificate'):
        resource_id = state.get(resource)
        if resource_id:
            try:
                apple.request('DELETE', ('profiles/' if resource == 'profile' else 'certificates/') + resource_id)
                state.pop(resource); save_state(root, state)
            except ValueError as error:
                failed = True; print('Cleanup incomplete:', resource, resource_id, str(error))
    if state.get('installed_profile'):
        Path(state['installed_profile']).unlink(missing_ok=True)
    require(not failed, 'Some temporary Apple resources require manual cleanup. Existing certificates were not modified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'verify', 'mark-uploading', 'wait', 'cleanup'])
    parser.add_argument('--root', type=Path)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--unsigned', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            require(args.archive is not None, '--archive is required.')
            verify_archive(args.archive, unsigned=args.unsigned)
        else:
            require(args.root is not None, '--root is required.')
            if args.command == 'mark-uploading':
                state = json.loads(state_path(args.root).read_text()); state['upload_attempted'] = True; save_state(args.root, state)
            else:
                apple = Apple()
                {'prepare': prepare, 'wait': wait_for_build, 'cleanup': cleanup}[args.command](args.root, apple)
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        # Subprocess stderr / API payloads can contain credentials; do not dump them.
        print('ERROR:', str(error) if isinstance(error, ValueError) else type(error).__name__ + ': signing step failed; inspect the named step.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
