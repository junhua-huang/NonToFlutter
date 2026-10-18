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
from urllib.parse import parse_qsl, urlencode, urlsplit
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
PROFILE_PREFIX = 'NonTo-TestFlight-'


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


class AppleUnavailable(ValueError):
    """A temporary API failure; callers may retry read-only status checks."""


def apple_error_diagnostic(error):
    """Classify Apple's error without logging raw bodies, headers or credentials."""
    try:
        errors = json.loads(error.read(65536)).get('errors', [])
        detail = ' '.join(str(item.get('detail', '')) for item in errors).casefold()
        codes = sorted({item.get('code', '') for item in errors
                        if re.fullmatch(r'(?:ENTITY_ERROR|STATE_ERROR|PARAMETER_ERROR|FORBIDDEN_ERROR|NOT_FOUND|UNAUTHORIZED_ERROR|RATE_LIMIT_EXCEEDED|INTERNAL_ERROR)(?:[._][A-Z0-9_]+)*', item.get('code', ''))})
    except (ValueError, TypeError, AttributeError, OSError):
        return 'No structured diagnostic was available.'
    if 'certificate' in detail and any(word in detail for word in ('maximum', 'limit', 'already have', 'too many')):
        hint = 'Apple reports a certificate limit/current-certificate conflict. Review existing distribution certificates; none were revoked.'
    elif 'agreement' in detail or 'contract' in detail:
        hint = 'Apple reports an agreement/contract issue; the account holder must review agreements.'
    elif 'csr' in detail or 'certificate signing request' in detail:
        hint = 'Apple rejected the certificate signing request.'
    elif 'permission' in detail or 'not authorized' in detail:
        hint = 'Apple reports insufficient API permissions.'
    else:
        hint = 'Use the read-only signing diagnosis and review the Apple account configuration.'
    return ('Codes: ' + ', '.join(codes) + '. ' if codes else '') + hint


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
            # Never expose raw response bodies, JWTs, private keys, or headers.
            if error.code in (408, 429, 500, 502, 503, 504):
                raise AppleUnavailable(f'Apple API {method} {resource}: temporary HTTP {error.code}.') from None
            raise ValueError(f'Apple API {method} {resource}: HTTP {error.code}. ' + apple_error_diagnostic(error)) from None
        except (URLError, TimeoutError, OSError):
            raise AppleUnavailable('Apple API connection failed; no credential details were logged.') from None


def validate_profile(profile, certificate):
    entitlements = profile.get('Entitlements', {})
    require(profile.get('TeamIdentifier') == [TEAM], 'Provisioning profile belongs to another team.')
    require(entitlements.get('application-identifier') == TEAM + '.' + BUNDLE, 'Profile Bundle ID does not match NonTo.')
    require(entitlements.get('com.apple.developer.team-identifier') == TEAM, 'Profile entitlement team mismatch.')
    require(entitlements.get('aps-environment') == 'production', 'App Store profile must enable production APNs.')
    require(entitlements.get('get-task-allow') is False, 'Development profiles cannot be uploaded to TestFlight.')
    require(not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'), 'An App Store distribution profile is required.')
    require(certificate in profile.get('DeveloperCertificates', []), 'Profile does not contain the configured signing certificate.')
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


def list_records(apple, resource, query=None):
    """Follow pagination only within the same authenticated Apple API resource."""
    rows, seen = [], set()
    for _ in range(20):
        page = apple.request('GET', resource, query=query or {'limit': '200'})
        rows.extend(page['data'])
        following = page.get('links', {}).get('next')
        if not following:
            return rows
        parsed = urlsplit(following)
        require(parsed.scheme == 'https' and parsed.netloc == 'api.appstoreconnect.apple.com'
                and parsed.path == '/v1/' + resource and not parsed.fragment,
                'Refusing an unexpected Apple pagination URL.')
        require(following not in seen, 'Apple pagination repeated; refusing incomplete signing lookup.')
        seen.add(following); query = dict(parse_qsl(parsed.query))
    raise ValueError('Apple signing lookup exceeded the page limit; no resources were created.')


def load_signing_key():
    pem = os.environ.get('IOS_SIGNING_KEY', '').strip().encode()
    require(pem, 'Add IOS_SIGNING_KEY once in repository Actions Secrets; see ios/TESTFLIGHT.md. No certificate was created.')
    try:
        key = serialization.load_pem_private_key(pem, password=None)
    except (ValueError, TypeError):
        raise ValueError('IOS_SIGNING_KEY must be the unencrypted PEM signing private key, not an APNs or App Store Connect key.') from None
    require(isinstance(key, rsa.RSAPrivateKey) and key.key_size >= 2048,
            'IOS_SIGNING_KEY must be an RSA signing key of at least 2048 bits.')
    return key


def validate_certificate(certificate, key):
    require(certificate.public_key().public_numbers() == key.public_key().public_numbers(),
            'Certificate does not match IOS_SIGNING_KEY.')
    require(any(a.value == TEAM for a in certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)),
            'Signing certificate belongs to another team.')
    now = datetime.now(timezone.utc)
    require(certificate.not_valid_before_utc <= now < certificate.not_valid_after_utc,
            'Signing certificate is not currently valid; explicitly initialize or renew signing.')


def reusable_certificate(apple, key, *, initialize=False):
    candidates = []
    for row in list_records(apple, 'certificates'):
        attributes = row['attributes']
        if attributes.get('certificateType') not in ('DISTRIBUTION', 'IOS_DISTRIBUTION'):
            continue
        certificate = x509.load_der_x509_certificate(base64.b64decode(attributes['certificateContent'], validate=True))
        if certificate.public_key().public_numbers() != key.public_key().public_numbers():
            continue
        try:
            validate_certificate(certificate, key)
        except ValueError:
            continue
        candidates.append((row, certificate))
    if candidates:
        return max(candidates, key=lambda item: item[1].not_valid_after_utc)
    require(initialize, 'No valid distribution certificate matches IOS_SIGNING_KEY. Run explicit [signing-setup] initialization once. Daily uploads never create certificates.')
    csr = x509.CertificateSigningRequestBuilder().subject_name(x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, 'NonTo Distribution'),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, TEAM),
    ])).sign(key, hashes.SHA256())
    row = apple.request('POST', 'certificates', data={'data': {'type': 'certificates', 'attributes': {
        'certificateType': 'DISTRIBUTION', 'csrContent': csr.public_bytes(serialization.Encoding.PEM).decode()}}})['data']
    certificate = x509.load_der_x509_certificate(base64.b64decode(row['attributes']['certificateContent'], validate=True))
    validate_certificate(certificate, key)
    print('Initialized reusable signing certificate:', row['id'])
    return row, certificate


def decode_profile(root, row, certificate_der):
    path = root / 'NonTo.mobileprovision'
    write_private(path, base64.b64decode(row['attributes']['profileContent'], validate=True))
    decoded = subprocess.run(['security', 'cms', '-D', '-i', str(path)], check=True, capture_output=True).stdout
    profile = plistlib.loads(decoded)
    return validate_profile(profile, certificate_der), profile['ExpirationDate']


def reusable_profile(root, apple, bundle_id, cert, certificate_der, *, initialize=False):
    prefix = PROFILE_PREFIX + cert['id'] + '-'
    candidates = []
    for row in list_records(apple, f'bundleIds/{bundle_id}/profiles'):
        attributes = row['attributes']
        if not (attributes.get('name', '').startswith(prefix) and attributes.get('profileType') == 'IOS_APP_STORE'
                and attributes.get('profileState') == 'ACTIVE'):
            continue
        try:
            profile_uuid, expiry = decode_profile(root, row, certificate_der)
        except ValueError:
            continue
        candidates.append((row, profile_uuid, expiry))
    if candidates:
        row, profile_uuid, _ = max(candidates, key=lambda item: item[2])
        # The last decoded candidate may differ from the selected profile.
        decode_profile(root, row, certificate_der)
        return row, profile_uuid
    require(initialize, 'No valid reusable App Store profile is available. Run explicit [signing-setup] initialization or renewal. Daily uploads never create profiles.')
    row = apple.request('POST', 'profiles', data={'data': {'type': 'profiles', 'attributes': {
        'name': prefix + uuid.uuid4().hex[:8], 'profileType': 'IOS_APP_STORE'}, 'relationships': {
        'bundleId': {'data': {'type': 'bundleIds', 'id': bundle_id}},
        'certificates': {'data': [{'type': 'certificates', 'id': cert['id']}]}}}})['data']
    profile_uuid, _ = decode_profile(root, row, certificate_der)
    print('Initialized reusable provisioning profile:', row['id'])
    return row, profile_uuid


def prepare(root, apple, *, initialize=False):
    # Fail before any Apple request if the one-time signing key is absent/invalid.
    signing_key = load_signing_key()
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
    cert, certificate = reusable_certificate(apple, signing_key, initialize=initialize)
    cert_der = certificate.public_bytes(serialization.Encoding.DER)
    profile, profile_uuid = reusable_profile(root, apple, bundle_id, cert, cert_der, initialize=initialize)
    state.update(signing_certificate=cert['id'], signing_profile=profile['id'])
    save_state(root, state)
    print('Using reusable signing certificate:', cert['id'], 'profile:', profile['id'])
    write_private(root / 'AuthKey.p8', apple.pem)
    install = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (profile_uuid + '.mobileprovision')
    install.parent.mkdir(parents=True, exist_ok=True)
    require(not install.exists(), 'Runner already has this profile installed; refusing to overwrite existing signing material.')
    write_private(install, (root / 'NonTo.mobileprovision').read_bytes())
    state['installed_profile'] = str(install); save_state(root, state)
    password, keychain_password = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
    print('::add-mask::' + password); print('::add-mask::' + keychain_password)
    write_private(root / 'Signing.p12', signing_p12(signing_key, certificate, password))
    identity = hashlib.sha1(cert_der).hexdigest().upper()
    write_private(root / 'ExportOptions.plist', plistlib.dumps(export_options(profile_uuid, identity)))
    variables = {'TF_PROFILE_UUID': profile_uuid, 'TF_SIGNING_IDENTITY': identity, 'TF_P12_PASSWORD': password,
                 'TF_KEYCHAIN_PASSWORD': keychain_password, 'TF_BUILD_NUMBER': state['build']}
    with open(os.environ['GITHUB_ENV'], 'a') as f:
        for name, value in variables.items():
            f.write(name + '=' + value + '\n')


def diagnose(apple):
    """Read-only public signing metadata. Never read or print signing private keys."""
    certificates = [row for row in list_records(apple, 'certificates')
                    if row['attributes'].get('certificateType') in ('DISTRIBUTION', 'IOS_DISTRIBUTION')]
    print('Distribution certificates visible to this API key:', len(certificates))
    for row in certificates:
        attributes = row['attributes']
        print(json.dumps({'id': row['id'], 'type': attributes.get('certificateType'),
                          'expires': attributes.get('expirationDate'), 'serial': attributes.get('serialNumber')}, ensure_ascii=True))
    bundles = apple.request('GET', 'bundleIds', query={'filter[identifier]': BUNDLE})['data']
    require(len(bundles) == 1, 'NonTo App ID was not found.')
    for row in list_records(apple, f'bundleIds/{bundles[0]["id"]}/profiles'):
        attributes = row['attributes']
        print(json.dumps({'profile': row['id'], 'name': attributes.get('name'), 'state': attributes.get('profileState'),
                          'expires': attributes.get('expirationDate')}, ensure_ascii=True))
    apps = apple.request('GET', 'apps', query={'filter[bundleId]': BUNDLE})['data']
    require(len(apps) == 1, 'NonTo App Store Connect record was not found.')
    for row in apple.request('GET', 'builds', query={'filter[app]': apps[0]['id'], 'limit': '10'})['data']:
        attributes = row['attributes']
        print('Build:', attributes.get('version'), 'processing:', attributes.get('processingState'))
    print('Read-only diagnosis complete. No certificate/profile was created, revoked, or deleted.')


def build_status(apple, state):
    rows = apple.request('GET', 'builds', query={'filter[app]': state['app'], 'filter[version]': state['build'], 'limit': '10'})['data']
    require(len(rows) <= 1, 'Build number is ambiguous; check App Store Connect manually.')
    return rows[0]['attributes'].get('processingState', 'UNKNOWN') if rows else 'NOT_VISIBLE'


def wait_for_build(root, apple):
    state = json.loads(state_path(root).read_text())
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        try:
            status = build_status(apple, state)
        except AppleUnavailable as error:
            print('Apple processing query temporarily unavailable; retrying:', error, flush=True)
            time.sleep(20)
            continue
        print('Apple build processing:', status, flush=True)
        if status == 'VALID':
            state['processed'] = True; save_state(root, state)
            print('Build processed successfully. Add it to an internal tester group in App Store Connect.')
            return
        require(status not in ('FAILED', 'INVALID'), 'Apple rejected the build; inspect TestFlight build details.')
        time.sleep(20)
    raise ValueError('Upload returned, but Apple processing is still pending. Check TestFlight later; this is not a confirmed successful release.')


def cleanup(root):
    """Remove only this runner's installed copy. Reusable Apple resources stay."""
    if not state_path(root).exists():
        return
    state = json.loads(state_path(root).read_text())
    require(state.get('team') == TEAM and state.get('bundle') == BUNDLE
            and state.get('run') == os.environ.get('GITHUB_RUN_ID', 'local'),
            'Refusing cleanup of another run\'s local signing material.')
    if state.get('installed_profile'):
        path = Path(state['installed_profile'])
        expected = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
        require(path.parent == expected and re.fullmatch(r'[A-Fa-f0-9-]{36}\.mobileprovision', path.name),
                'Refusing cleanup outside the runner provisioning-profile directory.')
        path.unlink(missing_ok=True)
    print('Runner profile copy removed. Reusable Apple certificate and profile were retained.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'verify', 'mark-uploading', 'wait', 'cleanup', 'diagnose'])
    parser.add_argument('--root', type=Path)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--unsigned', action='store_true')
    parser.add_argument('--initialize-signing', action='store_true', help='Explicitly allow one-time signing setup/renewal; never used by ordinary uploads.')
    args = parser.parse_args()
    try:
        if args.command == 'verify':
            require(args.archive is not None, '--archive is required.')
            verify_archive(args.archive, unsigned=args.unsigned)
        elif args.command == 'diagnose':
            diagnose(Apple())
        else:
            require(args.root is not None, '--root is required.')
            if args.command == 'mark-uploading':
                state = json.loads(state_path(args.root).read_text()); state['upload_attempted'] = True; save_state(args.root, state)
            elif args.command == 'cleanup':
                cleanup(args.root)
            elif args.command == 'prepare':
                prepare(args.root, Apple(), initialize=args.initialize_signing)
            else:
                wait_for_build(args.root, Apple())
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        # Subprocess stderr / API payloads can contain credentials; do not dump them.
        print('ERROR:', str(error) if isinstance(error, ValueError) else type(error).__name__ + ': signing step failed; inspect the named step.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
