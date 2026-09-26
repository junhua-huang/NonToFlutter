"""Local release builder. Default mode is read-only; no credentials in bundles."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import time
from urllib.parse import urlsplit
import urllib.error
import urllib.request
import uuid
import zipfile

HERE = Path(__file__).resolve().parent
CLIENT = HERE.parents[1]
BACKEND = Path('D:/NanTuPy')
ALLOWED = {'backend', 'web', 'android', 'windows'}
EXCLUDED = {'.git', '.env', '.venv', 'venv', '__pycache__', 'uploads', 'logs', '.pytest_cache'}
BACKEND_ROOTS = ('app', 'alembic', 'requirements.txt', 'alembic.ini')
SERVER_KEYS = {'backend_dir', 'web_dir', 'download_dir', 'state_dir', 'python_executable',
               'stop_command', 'start_command', 'database_backup_command', 'health_url',
               'service_environment_confirmed', 'database_backup_credentials_file'}


def validators():
    # Imported lazily so a read-only plan does not require remote runtime dependencies.
    from server_deploy import validate_config, validate_manifest
    return validate_config, validate_manifest


def run(args, cwd=None, capture=False, input=None):
    args = [str(a) for a in args]
    if os.name == 'nt' and args[0].lower().endswith(('.bat', '.cmd')):
        args = [os.environ.get('COMSPEC', 'cmd.exe'), '/d', '/s', '/c', subprocess.list2cmdline(args)]
    result = subprocess.run(args, cwd=cwd, input=input, text=True, encoding='utf-8', errors='replace',
                            stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE)
    if result.returncode:
        # Child commands can print credentials; keep the default diagnostic bounded.
        raise RuntimeError(f'{Path(args[0]).name} failed (exit {result.returncode})')
    return result.stdout or ''


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def version(value=None):
    if not value:
        match = re.search(r'^version:\s*(\S+)', (CLIENT / 'pubspec.yaml').read_text(encoding='utf-8-sig'), re.M)
        value = match.group(1) if match else ''
    match = re.fullmatch(r'(\d+\.\d+\.\d+)\+([1-9]\d*)', value)
    if not match:
        raise ValueError('Version must be x.y.z+positive-build')
    return match.group(1), int(match.group(2))


def https_base(value, origin=False):
    if not isinstance(value, str) or re.search(r'[\s\x00-\x1f\x7f]', value):
        raise ValueError('Invalid HTTPS base URL')
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or
            parsed.password is not None or parsed.query or parsed.fragment or
            (origin and parsed.path not in ('', '/'))):
        raise ValueError('Expected HTTPS origin' if origin else 'Expected HTTPS API base URL')
    return value.rstrip('/')


def server_config(c):
    return {key: value for key, value in c['server'].items() if key in SERVER_KEYS}


def validate_remote(c):
    s = c['server']
    validators()[0](server_config(c))
    if s.get('service_environment_confirmed') is not True:
        raise ValueError('Remote publishing requires server.service_environment_confirmed=true')
    if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_-]*', s.get('user', '')):
        raise ValueError('Invalid SSH user')
    if not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?', s.get('host', '')):
        raise ValueError('Invalid SSH host')
    if type(s.get('port')) is not int or not 1 <= s['port'] <= 65535:
        raise ValueError('Invalid SSH port')
    for key in ('identity_file', 'known_hosts_file'):
        value = s.get(key, '')
        if not isinstance(value, str) or re.search(r'[\x00-\x1f\x7f"\r\n]', value) or not Path(value).is_absolute() or not Path(value).is_file():
            raise ValueError(f'Expected existing absolute server.{key}')
    for key in ('backend_dir', 'web_dir', 'download_dir', 'state_dir', 'python_executable', 'database_backup_credentials_file'):
        value = s.get(key, '')
        if (not isinstance(value, str) or not re.fullmatch(r'/[A-Za-z0-9_./-]+', value) or
                any(part in ('.', '..', '') for part in value.rstrip('/').split('/')[1:])):
            raise ValueError(f'Unsafe remote path: server.{key}')
    if not s['web_dir'].rstrip('/').endswith('/nonto'):
        raise ValueError('server.web_dir must end in /nonto/')
    for key in ('stop_command', 'start_command', 'database_backup_command'):
        command = s.get(key)
        if not isinstance(command, list) or not command or not all(isinstance(arg, str) and arg and not re.search(r'[\x00-\x1f\x7f]', arg) for arg in command):
            raise ValueError(f'Expected argv array server.{key}')
        if any(re.search(r'(?i)(password|passwd|token|secret)(?:=|$)|://[^/\s]*@', arg) for arg in command):
            raise ValueError('Credentials must be in protected server files, never command arguments')
    backup = s['database_backup_command']
    credentials = s['database_backup_credentials_file']
    if (backup[0] != 'mysqldump' or '--single-transaction' not in backup or
            f'--defaults-extra-file={credentials}' not in backup or
            any(arg.startswith('-p') or re.search(r'(?i)(password|passwd|secret|token)=', arg) for arg in backup[1:])):
        raise ValueError('Backup requires mysqldump, --single-transaction, protected --defaults-extra-file, and no password arguments')


def config(path, remote=False):
    data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    p = data['publish']
    p['public_base_url'] = https_base(p.get('public_base_url', 'https://www.nonto.online'), origin=True)
    p['api_base_url'] = https_base(p['api_base_url'])
    if not re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,31}', p.get('channel', '')):
        raise ValueError('Invalid release channel')
    if type(p.get('minimum_supported_build_number')) is not int or p['minimum_supported_build_number'] < 0 or type(p.get('force_update')) is not bool:
        raise ValueError('Invalid minimum build or force_update')
    notes = p.get('release_notes')
    if not isinstance(notes, list) or len(notes) > 20 or not all(isinstance(note, str) and note.strip() and len(note.strip()) <= 500 for note in notes):
        raise ValueError('release_notes must contain at most 20 nonempty strings of at most 500 characters')
    p['release_notes'] = [note.strip() for note in notes]
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', p.get('admin_token_env', '')):
        raise ValueError('Invalid admin token environment variable name')
    if remote:
        validate_remote(data)
    return data


def ssh_args(c, scp=False):
    s = c['server']
    return ['scp' if scp else 'ssh', '-P' if scp else '-p', str(s['port']),
            '-i', s['identity_file'], '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
            '-o', 'ConnectTimeout=15', '-o', f"UserKnownHostsFile={s['known_hosts_file']}"]


def remote(c, command, input=None):
    validate_remote(c)
    return run(ssh_args(c) + [f"{c['server']['user']}@{c['server']['host']}", command], capture=True, input=input)


def remote_preflight(c):
    s = c['server']
    # Read-only checks before building or creating/uploading anything on the server.
    checks = [('d', s[key]) for key in ('backend_dir', 'web_dir', 'download_dir', 'state_dir')]
    checks += [('x', s['python_executable']),
               ('f', s['backend_dir'].rstrip('/') + '/.env'),
               ('r', s['backend_dir'].rstrip('/') + '/.env'),
               ('f', s['database_backup_credentials_file'])]
    remote(c, ' && '.join(f'test -{flag} {shlex.quote(path)}' for flag, path in checks))


def reject_link(path):
    if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()) or (path.exists() and path.lstat().st_file_attributes & 0x400 if os.name == 'nt' else False):
        raise ValueError(f'Link/reparse point forbidden: {path.name}')


def check_source_secret(path, rel):
    text = path.read_text(encoding='utf-8-sig')
    if re.search(r'-----BEGIN (?:[A-Z ]*PRIVATE KEY|OPENSSH PRIVATE KEY)-----|[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/\"\'{}]+:[^\s/@\"\'{}]+@', text):
        raise ValueError(f'Potential embedded credentials in backend source: {rel}')
    if path.suffix == '.py':
        try:
            tree = ast.parse(text)
        except SyntaxError:
            raise ValueError(f'Invalid Python syntax or source encoding: {rel}') from None
        for node in ast.walk(tree):
            if isinstance(node, (ast.Assign, ast.AnnAssign)) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                if any(isinstance(target, ast.Name) and re.search(r'(?i)(password|passwd|secret|token|private_key|access_key|cos_key)', target.id) for target in targets) and node.value.value not in ('', 'change-me-in-production'):
                    raise ValueError(f'Potential hardcoded credential in backend source: {rel}')


def backend_files(root):
    for name in BACKEND_ROOTS:
        base = root / name
        if not base.exists():
            raise ValueError(f'Missing backend payload root: {name}')
        reject_link(base)
        for path in sorted(base.rglob('*') if base.is_dir() else [base]):
            rel = path.relative_to(root)
            if any(p in EXCLUDED or p.startswith('.') for p in rel.parts):
                continue
            reject_link(path)
            allowed = (rel.as_posix() in {'requirements.txt', 'alembic.ini', 'alembic/script.py.mako'} or
                       rel.parts[0] in {'app', 'alembic'} and path.suffix == '.py')
            if path.is_file() and allowed:
                check_source_secret(path, rel)
                yield path, rel


def clean_generated(relative):
    if relative not in {'build/app/outputs/flutter-apk', 'build/windows/x64/runner/Release'}:
        raise ValueError('Refusing to clean an unowned output path')
    target = CLIENT / relative
    for parent in (target, *target.parents):
        reject_link(parent)
        if parent == CLIENT:
            break
    if target.exists():
        if not target.is_dir():
            raise ValueError('Generated output path is not a directory')
        for path in target.rglob('*'):
            reject_link(path)
        shutil.rmtree(target)
    return target


def require_fresh(path, started):
    reject_link(path)
    if not path.is_file() or path.stat().st_size == 0 or path.stat().st_mtime_ns < started:
        raise ValueError(f'Missing or stale build artifact: {path.name}')


def verify_windows(source, name, build, started):
    exe = source / 'nonto.exe'
    for path in (exe, source / 'flutter_windows.dll', source / 'data/app.so', source / 'data/icudtl.dat'):
        require_fresh(path, started if path == exe else 0)
    if not (source / 'data/flutter_assets').is_dir():
        raise ValueError('Windows Flutter assets are missing')
    escaped = str(exe).replace("'", "''")
    command = ("$v=(Get-Item -LiteralPath '{0}').VersionInfo; "
               "[Console]::WriteLine((ConvertTo-Json @{{product=$v.ProductVersion;file=$v.FileVersion;build=$v.FilePrivatePart}} -Compress))").format(escaped)
    actual = json.loads(run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command], capture=True))
    if actual.get('product') not in (name, f'{name}+{build}') or actual.get('file') not in (name, f'{name}+{build}', f'{name}.{build}'):
        raise ValueError('Windows executable version mismatch')
    if actual.get('build') != build:
        raise ValueError('Windows executable build number mismatch')


def copy_tree(source, destination):
    reject_link(source)
    for path in source.rglob('*'):
        reject_link(path)
        if path.is_file() and path.suffix not in {'.map', '.symbols', '.zip'}:
            target = destination / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def verify_android(apk, expected_version, expected_build, c):
    tools = c.get('android', {})
    cert = re.sub(r'[^a-f0-9]', '', tools.get('certificate_sha256', '').lower())
    if len(cert) != 64 or not tools.get('apksigner') or not tools.get('aapt'):
        raise ValueError('Configure android.apksigner, aapt and trusted certificate_sha256 before publishing')
    output = run([tools['apksigner'], 'verify', '--print-certs', apk], capture=True)
    values = re.findall(r'certificate SHA-256 digest:\s*([a-fA-F0-9]+)', output, re.I)
    if not values or any(v.lower() != cert for v in values) or re.search(r'android\s+debug', output, re.I):
        raise ValueError('APK signing certificate mismatch or Debug certificate')
    package_name = tools.get('package_name', '')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+', package_name):
        raise ValueError('Configure a valid android.package_name')
    output = run([tools['aapt'], 'dump', 'badging', apk], capture=True)
    package_line = next((line for line in output.splitlines() if line.startswith('package: ')), '')
    fields = dict(re.findall(r"(\w+)='([^']*)'", package_line))
    if fields.get('name') != package_name or fields.get('versionCode') != str(expected_build) or fields.get('versionName') != expected_version:
        raise ValueError('APK package name or version mismatch')


def package(c, components, requested):
    if not components or not set(components) <= ALLOWED:
        raise ValueError('Unknown or empty components')
    name, build = version(requested)
    if c['publish']['minimum_supported_build_number'] > build:
        raise ValueError('Minimum supported build exceeds release build')
    flutter = shutil.which('flutter')
    if components - {'backend'} and not flutter:
        raise ValueError('Flutter is not on PATH')
    if 'android' in components:
        if not (CLIENT / 'android/key.properties').is_file() or not c.get('android', {}).get('certificate_sha256'):
            raise ValueError('Formal Android signing configuration is required')
    release_id = f'{name}-{build}-{uuid.uuid4().hex[:12]}'
    out = HERE / 'out' / release_id
    out.mkdir(parents=True, exist_ok=False)
    stage = out / 'stage'
    stage.mkdir()
    if components - {'backend'}:
        run([flutter, 'pub', 'get'], CLIENT)
        run([flutter, 'analyze', 'lib', '--no-pub'], CLIENT)
        run([flutter, 'test', '--no-pub'], CLIENT)
    flags = ['--release', '--no-pub', f'--build-name={name}', f'--build-number={build}']
    if 'backend' in components:
        python = BACKEND / '.venv/Scripts/python.exe'
        run([python, '-m', 'pytest', 'tests/test_app_updates_api.py', '-q'], BACKEND)
        for path, rel in backend_files(BACKEND):
            target = stage / 'backend' / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    if 'web' in components:
        source = out / 'web-build'
        started = time.time_ns()
        run([flutter, 'build', 'web', *flags, '--base-href=/nonto/', '--no-source-maps', f'--output={source}'], CLIENT)
        for filename in ('version.json', 'index.html', 'main.dart.js', 'flutter_bootstrap.js'):
            require_fresh(source / filename, started)
        metadata = json.loads((source / 'version.json').read_text())
        if metadata.get('version') != name or str(metadata.get('build_number')) != str(build):
            raise ValueError('Web version mismatch')
        if not re.search(r'<base\s+href=[\"\']/nonto/[\"\']', (source / 'index.html').read_text(encoding='utf-8')):
            raise ValueError('Web base href must be /nonto/')
        copy_tree(source, stage / 'web')
    downloads = stage / 'downloads'
    downloads.mkdir(exist_ok=True)
    if 'android' in components:
        source = clean_generated('build/app/outputs/flutter-apk')
        started = time.time_ns()
        run([flutter, 'build', 'apk', *flags], CLIENT)
        apk = source / 'app-release.apk'
        require_fresh(apk, started)
        verify_android(apk, name, build, c)
        shutil.copy2(apk, downloads / f'nonto-{name}-{build}.apk')
    if 'windows' in components:
        source = clean_generated('build/windows/x64/runner/Release')
        started = time.time_ns()
        run([flutter, 'build', 'windows', *flags], CLIENT)
        verify_windows(source, name, build, started)
        with zipfile.ZipFile(downloads / f'nonto-windows-{name}-{build}.zip', 'w', zipfile.ZIP_DEFLATED) as z:
            for path in source.rglob('*'):
                reject_link(path)
                if path.is_file():
                    z.write(path, path.relative_to(source))
    files = [{'path': p.relative_to(stage).as_posix(), 'sha256': digest(p), 'size': p.stat().st_size}
             for p in sorted(stage.rglob('*')) if p.is_file()]
    bundle = out / 'bundle.tar.gz'
    with tarfile.open(bundle, 'w:gz') as tar:
        for item in files:
            tar.add(stage / item['path'], arcname=item['path'], recursive=False)
    manifest = dict(release_id=release_id, version=name, build_number=build,
                    components=sorted(components), files=files, bundle_sha256=digest(bundle))
    validate_local_manifest(manifest)
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(f'Package ready: {out}')
    return out


def api(c, path, payload=None):
    token = os.environ.get(c['publish']['admin_token_env'], '')
    if not token:
        raise ValueError('Set the configured admin token environment variable; never put it in a URL')
    url = c['publish']['api_base_url'].rstrip('/') + path
    if not url.startswith('https://'):
        raise ValueError('Admin API must use HTTPS')
    req = urllib.request.Request(url, data=json.dumps(payload).encode() if payload is not None else None,
                                 headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
    # Never forward an Authorization header across redirects.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f'Admin API HTTP {exc.code}; response omitted to protect credentials') from None


def records(c):
    rows, page = [], 1
    while True:
        result = api(c, f'/admin/app-releases?page={page}&page_size=100')
        if not isinstance(result, dict) or not isinstance(result.get('items'), list) or type(result.get('total')) is not int or result['total'] < 0:
            raise ValueError('Invalid admin release listing')
        rows.extend(result['items'])
        if len(rows) >= result['total']:
            return rows
        if not result['items'] or page >= 10000:
            raise ValueError('Incomplete admin release listing')
        page += 1


def publication(c, manifest):
    p = c['publish']
    if p['minimum_supported_build_number'] > manifest['build_number']:
        raise ValueError('Minimum supported build exceeds release build')
    public = https_base(p.get('public_base_url', 'https://www.nonto.online'), origin=True)
    for platform in manifest['components']:
        if platform == 'backend':
            continue
        item = next((f for f in manifest['files'] if f['path'].startswith('downloads/') and
                     f['path'].endswith('.apk' if platform == 'android' else '.zip')), None) if platform != 'web' else None
        yield dict(platform=platform, channel=p['channel'], version_name=manifest['version'],
                   build_number=manifest['build_number'], minimum_supported_build_number=p['minimum_supported_build_number'],
                   force_update=p['force_update'], update_action='refresh' if platform == 'web' else 'download',
                   download_url=public + '/nonto/' if platform == 'web' else
                   public + '/' + item['path'], release_notes=p['release_notes'], enabled=True,
                   sha256=item['sha256'] if item else None, file_size=item['size'] if item else None,
                   reason=f"Release {manifest['release_id']}")


def check_records(c, manifest, register=False):
    if not set(manifest['components']) - {'backend'}:
        return
    rows = records(c)
    for payload in publication(c, manifest):
        matching = [r for r in rows if r['platform'] == payload['platform'] and r['channel'] == payload['channel']]
        if any(r['build_number'] > payload['build_number'] for r in matching):
            raise ValueError('Refusing an older build')
        same = next((r for r in matching if r['build_number'] == payload['build_number']), None)
        if same:
            keys = ('version_name', 'download_url', 'sha256', 'file_size', 'force_update', 'minimum_supported_build_number', 'enabled', 'update_action', 'release_notes')
            if any(same.get(k) != payload[k] for k in keys):
                raise ValueError('Same build has a different publication record')
            continue
        if register:
            api(c, '/admin/app-releases', payload)


def validate_local_manifest(manifest):
    validators()[1](manifest)
    if (not re.fullmatch(r'\d+\.\d+\.\d+', str(manifest.get('version', ''))) or
            type(manifest.get('build_number')) is not int or manifest['build_number'] < 1 or
            not isinstance(manifest.get('components'), list) or
            not manifest['components'] or set(manifest['components']) - ALLOWED):
        raise ValueError('Invalid release version, build number, or components')
    files = {item['path']: item for item in manifest['files']}
    for component in manifest['components']:
        if component == 'backend':
            if not any(path.startswith('backend/') for path in files):
                raise ValueError('Backend component has no payload')
        elif component == 'web':
            if not all(name in files for name in ('web/index.html', 'web/version.json')):
                raise ValueError('Web component is incomplete')
        else:
            suffix = '.apk' if component == 'android' else '.zip'
            if not any(path.startswith('downloads/') and path.endswith(suffix) for path in files):
                raise ValueError(f'{component} component has no download')


def load_manifest(out):
    reject_link(out)
    reject_link(out / 'manifest.json')
    manifest = json.loads((out / 'manifest.json').read_text(encoding='utf-8'))
    validate_local_manifest(manifest)
    rid = manifest['release_id']
    if not re.fullmatch(r'[0-9A-Za-z][0-9A-Za-z._-]*', rid) or '..' in rid:
        raise ValueError('Invalid release ID')
    return manifest


def validate_bundle(out, manifest):
    bundle = out / 'bundle.tar.gz'
    reject_link(bundle)
    if digest(bundle) != manifest['bundle_sha256']:
        raise ValueError('Local bundle hash mismatch')
    expected = {item['path']: item for item in manifest['files']}
    seen = set()
    with tarfile.open(bundle, 'r:gz') as archive:
        for member in archive:
            item = expected.get(member.name)
            if not member.isfile() or item is None or member.name in seen or member.size != item['size']:
                raise ValueError('Unexpected local archive entry')
            with archive.extractfile(member) as stream:
                h = hashlib.sha256()
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    h.update(block)
            if h.hexdigest() != item['sha256']:
                raise ValueError('Local archive content hash mismatch')
            seen.add(member.name)
    if seen != set(expected):
        raise ValueError('Local archive missing manifest entries')


def config_bytes(c):
    return json.dumps(server_config(c), sort_keys=True, separators=(',', ':')).encode('utf-8')


def check_uploaded(c, out, base):
    expected = {'server-config.json': hashlib.sha256(config_bytes(c)).hexdigest(),
                'manifest.json': digest(out / 'manifest.json'),
                'server_deploy.py': digest(HERE / 'server_deploy.py')}
    script = ('import hashlib,json,pathlib,sys; root=pathlib.Path(sys.argv[1]); '
              'expected=json.load(sys.stdin); '
              'ok=all(not (root/name).is_symlink() and '
              'hashlib.sha256((root/name).read_bytes()).hexdigest()==sha '
              'for name,sha in expected.items()); sys.exit(0 if ok else 1)')
    remote(c, shlex.join([c['server']['python_executable'], '-c', script, base]), input=json.dumps(expected))


def preflight_records(c, components, build):
    if c['publish']['minimum_supported_build_number'] > build:
        raise ValueError('Minimum supported build exceeds release build')
    if not set(components) - {'backend'}:
        return
    rows = records(c)
    if any(row['platform'] in components and row['channel'] == c['publish']['channel'] and row['build_number'] >= build for row in rows):
        raise ValueError('A new package requires a build above all existing publication records')


def preflight_remote_before_package(c, mode, components, build):
    if mode not in {'deploy', 'register', 'restore'}:
        return
    remote_preflight(c)
    if mode in {'deploy', 'register'}:
        preflight_records(c, components, build)


def deploy(c, out, mode, schema_compatible=False):
    if mode not in {'deploy', 'register', 'restore'}:
        raise ValueError('Invalid remote mode')
    validate_remote(c)
    manifest = load_manifest(out)
    validate_bundle(out, manifest)
    if mode in ('deploy', 'register'):
        check_records(c, manifest)
    remote_preflight(c)
    s = c['server']
    base = s['state_dir'].rstrip('/') + '/incoming/' + manifest['release_id']
    if mode == 'deploy':
        # Never reuse/overwrite an incoming release directory, including symlinks.
        script = ('import os,pathlib,sys; p=pathlib.Path(sys.argv[1]); '
                  'assert all(not x.is_symlink() for x in (p,*p.parents)); '
                  'os.umask(0o077); p.parent.mkdir(parents=True,exist_ok=True); p.mkdir(mode=0o700)')
        remote(c, shlex.join([s['python_executable'], '-c', script, base]))
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / 'server-config.json'
            cfg.write_bytes(config_bytes(c))
            for source in (cfg, out / 'manifest.json', out / 'bundle.tar.gz', HERE / 'server_deploy.py'):
                run(ssh_args(c, True) + [source, f"{s['user']}@{s['host']}:{base}/{source.name}"])
    check_uploaded(c, out, base)
    command = [s['python_executable'], base + '/server_deploy.py', '--config', base + '/server-config.json',
               '--bundle', base + '/bundle.tar.gz', '--manifest', base + '/manifest.json', '--mode']
    if mode == 'deploy':
        print(remote(c, shlex.join(command + ['preflight'])))
        check_records(c, manifest)
    runner_mode = 'verify' if mode == 'register' else mode
    runner_args = command + [runner_mode]
    if mode == 'restore':
        runner_args += ['--release-id', manifest['release_id']]
        if schema_compatible:
            runner_args += ['--schema-compatible']
    print(remote(c, shlex.join(runner_args)))
    if mode in ('deploy', 'register'):
        verify_public(c, manifest)
        check_records(c, manifest, register=True)
        print('Deployment and update registration completed')


def verify_public(c, manifest):
    public = https_base(c['publish'].get('public_base_url', 'https://www.nonto.online'), origin=True)
    for platform in manifest['components']:
        if platform == 'backend':
            continue
        url = public + '/nonto/version.json' if platform == 'web' else next(
            public + '/' + f['path'] for f in manifest['files']
            if f['path'].startswith('downloads/') and f['path'].endswith('.apk' if platform == 'android' else '.zip'))
        with urllib.request.urlopen(url, timeout=60) as response:
            if platform == 'web':
                data = json.load(response)
                if data['version'] != manifest['version'] or str(data['build_number']) != str(manifest['build_number']):
                    raise ValueError('Published Web metadata mismatch')
            else:
                item = next(f for f in manifest['files'] if url.endswith(f['path']))
                h, size = hashlib.sha256(), 0
                for block in iter(lambda: response.read(1024 * 1024), b''):
                    h.update(block)
                    size += len(block)
                if h.hexdigest() != item['sha256'] or size != item['size']:
                    raise ValueError('Published download hash mismatch')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default=str(HERE / 'release.config.json'))
    parser.add_argument('--mode', choices=['plan', 'package', 'deploy', 'register', 'restore'], default='plan')
    parser.add_argument('--components', default='backend,web,android')
    parser.add_argument('--version')
    parser.add_argument('--release', help='Existing local package directory')
    parser.add_argument('--schema-compatible', action='store_true', help='Confirm old code supports current schema before file restore')
    args = parser.parse_args()
    c = config(args.config, remote=args.mode in {'deploy', 'register', 'restore'})
    components = {part.strip() for part in args.components.split(',') if part.strip()}
    if not components or not components <= ALLOWED:
        raise ValueError('Unknown component')
    name, build = version(args.version)
    if args.mode in ('register', 'restore') and not args.release:
        raise ValueError('--release is required')
    if not args.release:
        preflight_remote_before_package(c, args.mode, components, build)
    if args.mode == 'plan':
        print(json.dumps({'mode': 'plan (no writes or network)', 'version': name, 'build': build,
                          'components': sorted(components), 'web_dir': c['server']['web_dir'],
                          'required': ['SSH identity and known host', 'service stop/start', 'database backup', 'admin token']}, indent=2))
        return
    if args.mode in ('register', 'restore') and not args.release:
        raise ValueError('--release is required')
    out = Path(args.release).resolve() if args.release else package(c, components, args.version)
    if args.mode != 'package':
        deploy(c, out, args.mode, schema_compatible=args.schema_compatible)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'FAILED: {type(error).__name__}: {error}')
        raise SystemExit(1)
