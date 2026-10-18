#!/usr/bin/env python3
"""Create a persistent signing key locally, or extract one from your existing P12."""
import argparse
import getpass
import hashlib
import os
from pathlib import Path
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12


def create_key(path, source=None, password=None):
    path = Path(path)
    if path.exists():
        raise ValueError('Output already exists. Keep your existing signing key; do not overwrite it.')
    if source:
        try:
            key, _, _ = pkcs12.load_key_and_certificates(Path(source).read_bytes(), password)
        except ValueError:
            raise ValueError('Could not open P12; check the file and password.') from None
        if not isinstance(key, rsa.RSAPrivateKey) or key.key_size < 2048:
            raise ValueError('P12 must contain an RSA distribution signing private key of at least 2048 bits.')
    else:
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    data = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as output:
        output.write(data)
    public = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return hashlib.sha256(public).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--from-p12', type=Path)
    args = parser.parse_args()
    try:
        password = getpass.getpass('P12 password (input is hidden): ').encode() if args.from_p12 else None
        fingerprint = create_key(args.output, args.from_p12, password)
        print('Signing key saved locally:', args.output)
        print('Public-key SHA-256:', fingerprint)
        print('Add the complete file contents to GitHub Actions Secret IOS_SIGNING_KEY once. Keep a secure local backup.')
        print('No Apple API calls were made. No certificate was created or revoked.')
        return 0
    except (ValueError, OSError) as error:
        print('ERROR:', str(error) if isinstance(error, ValueError) else 'Could not read/write the local signing file.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
