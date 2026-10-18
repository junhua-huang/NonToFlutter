#!/usr/bin/env python3
"""Retire the single lost-key NonTo CI certificate approved on 2026-10-19.

This is deliberately not a general certificate cleanup command. The old CI log
(run 39149553391, attempt 3) records the exact certificate and profile below.
"""
import argparse
import base64
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.x509.oid import NameOID

from testflight import Apple, list_records, load_signing_key, require

REPOSITORY = 'junhua-huang/NonToFlutter'
TEAM = 'B2Y3564MKK'
BUNDLE = 'online.nonto.native'
LEGACY_CERTIFICATE = '37RD8K9T45'
LEGACY_SHA1 = 'CB53021D4A736386ACC07D394C2BCE8F9BCC1D80'
LEGACY_SERIAL = '6AD4B45609DC2611C07378922723AA01'
LEGACY_PROFILE = '54ACA6Y6M9'
LEGACY_PROFILE_NAME = 'NonTo-TF-39149553391-3'
PRESERVED_CERTIFICATE = '7L43F2X39Q'


def retire(apple, *, execute=False):
    require(os.environ.get('GITHUB_REPOSITORY') == REPOSITORY
            and os.environ.get('GITHUB_REF') == 'refs/heads/ios',
            'This operation is restricted to NonToFlutter/ios.')
    key = load_signing_key()
    certificates = list_records(apple, 'certificates')
    require(any(row['id'] == PRESERVED_CERTIFICATE for row in certificates),
            'The certificate that must be preserved is missing; stop for review.')
    targets = [row for row in certificates if row['id'] == LEGACY_CERTIFICATE]
    if not targets:
        print('Approved legacy certificate is already absent. No certificate was revoked.')
        return
    require(len(targets) == 1, 'Ambiguous legacy certificate.')
    attrs = targets[0]['attributes']
    certificate = x509.load_der_x509_certificate(base64.b64decode(attrs['certificateContent'], validate=True))
    require(attrs.get('certificateType') == 'DISTRIBUTION'
            and attrs.get('serialNumber', '').upper() == LEGACY_SERIAL
            and format(certificate.serial_number, 'X') == LEGACY_SERIAL
            and certificate.fingerprint(hashes.SHA1()).hex().upper() == LEGACY_SHA1
            and any(a.value == TEAM for a in certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)),
            'Certificate identity differs from the approved NonTo CI certificate; nothing was revoked.')
    require(certificate.public_key().public_numbers() != key.public_key().public_numbers(),
            'Legacy certificate matches the persistent key; do not revoke a reusable identity.')
    # Distribution certificates are team-wide. Inspect every visible profile,
    # including profiles for other apps, before changing this single certificate.
    profiles = list_records(apple, 'profiles')
    linked = []
    for profile in profiles:
        certs = list_records(apple, 'profiles/' + profile['id'] + '/certificates')
        if not any(row['id'] == LEGACY_CERTIFICATE for row in certs):
            continue
        require(profile['id'] == LEGACY_PROFILE
                and profile['attributes'].get('name') == LEGACY_PROFILE_NAME
                and profile['attributes'].get('profileType') == 'IOS_APP_STORE',
                'Another profile uses the old certificate; stop to avoid affecting another app.')
        bundle = apple.request('GET', 'profiles/' + profile['id'] + '/bundleId')['data']
        require(bundle['attributes'].get('identifier') == BUNDLE,
                'Legacy profile belongs to another app; nothing was revoked.')
        linked.append(profile['id'])
    require(linked == [LEGACY_PROFILE], 'Expected NonTo legacy profile was not verified; nothing was revoked.')
    print('Verified repository:', REPOSITORY, 'branch: ios; team:', TEAM, 'bundle:', BUNDLE, flush=True)
    print('Verified legacy certificate:', LEGACY_CERTIFICATE, 'profile:', LEGACY_PROFILE, flush=True)
    print('Preserving certificate:', PRESERVED_CERTIFICATE, '; APNs keys are outside this operation.', flush=True)
    if execute:
        # No retry: if the response is lost, rerun starts with the read-only lookup.
        apple.request('DELETE', 'certificates/' + LEGACY_CERTIFICATE)
        print('Revoked only the approved legacy certificate:', LEGACY_CERTIFICATE, flush=True)
    else:
        print('Dry run complete. No Apple resource changed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', help='Execute the previously approved single-certificate retirement.')
    args = parser.parse_args()
    try:
        retire(Apple(), execute=args.execute)
        return 0
    except (ValueError, KeyError, OSError) as error:
        print('ERROR:', str(error) if isinstance(error, ValueError) else 'Legacy certificate verification failed.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
