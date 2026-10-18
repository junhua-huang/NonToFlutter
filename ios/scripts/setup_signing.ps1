# One-time Windows setup for NonTo's reusable distribution signing key.
# No Apple certificate is created or revoked by this script.
param(
    [string]$Directory = 'C:\NonToAppleConnect',
    [string]$ImportP12 = '',
    [switch]$RepairUnsupportedKeySize
)
$ErrorActionPreference = 'Stop'
$NontoRepository = 'junhua-huang/NonToFlutter'
$NontoSecretName = 'IOS_SIGNING_KEY'
$NontoSecretPage = 'https://github.com/junhua-huang/NonToFlutter/settings/secrets/actions/new'
$NontoKeyPath = Join-Path $Directory 'NonToDistribution.key'
$NontoHasSecretAccess = $false

try {
    # Inspect names only. GitHub never returns secret values through this API.
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        try {
            $NontoSecretsJson = & gh secret list --repo $NontoRepository --json name 2>$null
            if ($LASTEXITCODE -eq 0) {
                $NontoSecrets = $NontoSecretsJson | ConvertFrom-Json
                $NontoHasSecretAccess = $true
                if (-not $RepairUnsupportedKeySize -and @($NontoSecrets | Where-Object { $_.name -eq $NontoSecretName }).Count -gt 0) {
                    Write-Host 'IOS_SIGNING_KEY already exists. It was kept unchanged.' -ForegroundColor Green
                    Write-Host 'Tell the assistant it is present so the existing configuration can be verified.'
                    exit 0
                }
            }
        } catch {
            # An unavailable CLI session falls back to the user's browser.
            $NontoHasSecretAccess = $false
        }
    }

    $NontoPython = Get-Command py -ErrorAction SilentlyContinue
    $NontoPythonArgs = @('-3')
    if (-not $NontoPython) {
        $NontoPython = Get-Command python -ErrorAction SilentlyContinue
        $NontoPythonArgs = @()
    }
    if (-not $NontoPython) { throw 'Python 3 is required. Install Python 3, then run this script again.' }
    & $NontoPython.Source @NontoPythonArgs -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('cryptography') else 1)"
    if ($LASTEXITCODE -ne 0) {
        & $NontoPython.Source @NontoPythonArgs -m pip install 'cryptography>=45,<47'
        if ($LASTEXITCODE -ne 0) { throw 'Could not install cryptography. Check the Python/pip installation and retry.' }
    }

    # Private material stays on this computer and goes directly to GitHub Secrets.
    # Never print the key or place it in command-line arguments.
    $NontoPythonSetup = @'
import getpass
import hashlib
import os
from pathlib import Path
import sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
path = Path(sys.argv[1])
source = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != '-' else ''
repair = len(sys.argv) > 3 and sys.argv[3] == 'repair'
try:
    if path.exists():
        if source:
            raise ValueError('Refusing to replace an existing key with a P12 import.')
        key = serialization.load_pem_private_key(path.read_bytes(), password=None)
        if not isinstance(key, rsa.RSAPrivateKey) or key.key_size < 2048:
            raise ValueError('Existing file is not a valid RSA signing key; it was kept unchanged.')
        if key.key_size != 2048:
            if not repair:
                raise ValueError('Apple Distribution needs RSA 2048. Run once with -RepairUnsupportedKeySize; existing file was preserved.')
            backup = path.with_name(path.name + '.rsa' + str(key.key_size) + '.backup')
            descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as output:
                output.write(path.read_bytes())
            replacement = rsa.generate_private_key(public_exponent=65537, key_size=2048)
            temporary = path.with_name(path.name + '.replacement')
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as output:
                output.write(replacement.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            os.replace(temporary, path)
            key = replacement
            print('Backed up the unsupported local key:', backup)
            print('Saved the compatible RSA 2048 persistent signing key. Update IOS_SIGNING_KEY once.')
        else:
            print('Reusing existing RSA 2048 signing key.')
    else:
        if source:
            password = getpass.getpass('P12 password (input is hidden): ').encode()
            key, _, _ = pkcs12.load_key_and_certificates(Path(source).read_bytes(), password)
            if not isinstance(key, rsa.RSAPrivateKey) or key.key_size != 2048:
                raise ValueError('P12 does not contain a supported RSA signing private key.')
        else:
            key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        path.parent.mkdir(parents=True, exist_ok=True)
        data = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
        print('Saved the persistent signing key locally. Keep a secure backup.')
    public = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    print('Public-key SHA-256:', hashlib.sha256(public).hexdigest())
except (ValueError, TypeError, OSError) as error:
    print(str(error) if isinstance(error, ValueError) else 'Local signing-file operation failed.', file=sys.stderr)
    print('Could not prepare the signing key. Check RSA 2048 compatibility, file permissions, backups, or the P12 password.', file=sys.stderr)
    sys.exit(1)
'@
    $NontoSourceArgument = if ($ImportP12) { $ImportP12 } else { '-' }
    $NontoRepairArgument = if ($RepairUnsupportedKeySize) { 'repair' } else { 'keep' }
    & $NontoPython.Source @NontoPythonArgs -c $NontoPythonSetup $NontoKeyPath $NontoSourceArgument $NontoRepairArgument
    if ($LASTEXITCODE -ne 0) { throw 'Signing key preparation stopped. No GitHub Secret was changed.' }

    if ($NontoHasSecretAccess) {
        # stdin is encrypted by GitHub CLI before storage; the private key is not an argument.
        [System.IO.File]::ReadAllText($NontoKeyPath) | & gh secret set $NontoSecretName --repo $NontoRepository
        if ($LASTEXITCODE -ne 0) { throw 'GitHub could not save the Secret. The local key is retained; retry after checking repository access.' }
        Write-Host 'IOS_SIGNING_KEY was saved to the correct repository.' -ForegroundColor Green
    } else {
        Set-Clipboard -Value ([System.IO.File]::ReadAllText($NontoKeyPath))
        if ($RepairUnsupportedKeySize) {
            Start-Process 'https://github.com/junhua-huang/NonToFlutter/settings/secrets/actions/IOS_SIGNING_KEY'
        } else {
            Start-Process $NontoSecretPage
        }
        Write-Host ''
        Write-Host 'The key has been copied to your clipboard. In the GitHub page:' -ForegroundColor Cyan
        Write-Host '  Name: IOS_SIGNING_KEY'
        Write-Host '  Secret: paste the clipboard contents, then click Add secret.'
        if ($RepairUnsupportedKeySize) {
            Write-Host 'Repair mode: replace the existing Secret value with the clipboard, then click Update secret.'
        } else {
            Write-Host 'If that Secret already exists, keep it unchanged until its signing identity is verified.'
        }
        Write-Host 'Paste the key only into the GitHub Secret field, not into chat.'
    }
    Write-Host ''
    Write-Host ('Local backup: ' + $NontoKeyPath)
    Write-Host 'No Apple certificate/profile was created, revoked, or deleted.'
    Write-Host 'Tell the assistant when IOS_SIGNING_KEY is saved. Do not re-run the old publishing workflow.'
} catch {
    Write-Host ('Setup stopped: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
