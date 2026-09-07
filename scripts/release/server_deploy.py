"""Validated server-side release protocol. Commands always execute without a shell."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
from urllib.request import urlopen

WEBSITE_ROOT = "/www/wwwroot/nonto.online"
WEB_ROOT = WEBSITE_ROOT + "/nonto/"
REQUIRED = ("backend_dir", "web_dir", "download_dir", "state_dir", "python_executable",
            "stop_command", "start_command", "database_backup_command", "health_url")
MANAGED_BACKEND_ROOTS = ("app", "alembic")
MANAGED_BACKEND_FILES = {"requirements.txt", "alembic.ini"}
COMPONENTS = {"backend", "web", "android", "windows"}
PRESERVED_BACKEND = {".env", "uploads", "logs", "venv", ".venv"}


def _managed_backend_rel(rel):
    return (rel in MANAGED_BACKEND_FILES or
            (rel.startswith("app/") and rel.endswith(".py")) or
            (rel.startswith("alembic/") and (rel.endswith(".py") or rel == "alembic/script.py.mako")))


def _payload_components(manifest):
    components = set(manifest.get("components", ()))
    selected = {component for component in ("backend", "web") if component in components}
    if components & {"android", "windows"}:
        selected.add("downloads")
    return selected


def _normalized(value):
    return value.replace("\\", "/").rstrip("/") or "/"


def _under(value, parent):
    value, parent = _normalized(value), _normalized(parent)
    return value == parent or value.startswith(parent + "/")


def _path(value, key, exact=False):
    if not isinstance(value, str) or "\x00" in value or not (
            value.startswith("/") or (len(value) > 2 and value[1] == ":" and value[2] in "/\\")):
        raise ValueError(f"{key} must be absolute")
    normalized = value.replace("\\", "/")
    parts = normalized.rstrip("/").split("/")
    if any(part in ("", ".", "..") for part in parts[1:]):
        raise ValueError(f"unsafe path: {key}")
    if exact and value != WEB_ROOT:
        raise ValueError("web_dir must be exactly /www/wwwroot/nonto.online/nonto/")
    return Path(value)


def _reject_symlink_ancestors(path, allow_final_symlink=False):
    path = Path(path)
    current = path
    while True:
        if current.is_symlink() and not (allow_final_symlink and current == path):
            raise ValueError(f"symlink path is forbidden: {path}")
        if current.parent == current:
            return
        current = current.parent


def validate_config(config):
    s = config.get("server", config) if isinstance(config, dict) else {}
    for key in REQUIRED:
        if key not in s:
            raise ValueError(f"missing server.{key}")
    paths = {key: _path(s[key], f"server.{key}", key == "web_dir") for key in
             ("backend_dir", "web_dir", "download_dir", "state_dir", "python_executable")}
    website = _normalized(WEBSITE_ROOT)
    if any(_under(str(paths[key]), website) for key in ("backend_dir", "state_dir")):
        raise ValueError("backend and state must be outside the website root")
    values = [str(paths[key]) for key in ("backend_dir", "web_dir", "download_dir", "state_dir")]
    for index, left in enumerate(values):
        for right in values[index + 1:]:
            if _under(left, right) or _under(right, left):
                raise ValueError("deployment paths must be disjoint and non-nested")
    for key in ("stop_command", "start_command", "database_backup_command"):
        command = s[key]
        if (not isinstance(command, list) or not command or
                any(not isinstance(arg, str) or not arg or any(ord(c) < 32 for c in arg) for arg in command)):
            raise ValueError(f"server.{key} must be a nonempty argv array")
    if not isinstance(s["health_url"], str) or not s["health_url"]:
        raise ValueError("health_url is required")
    for key in ("health_attempts",):
        if key in s and (type(s[key]) is not int or not 1 <= s[key] <= 120):
            raise ValueError(f"server.{key} must be a positive bounded integer")
    if "health_interval_seconds" in s and (type(s["health_interval_seconds"]) not in (int, float) or s["health_interval_seconds"] < 0):
        raise ValueError("server.health_interval_seconds must be nonnegative")
    return s


def validate_manifest(manifest):
    if not isinstance(manifest, dict) or not isinstance(manifest.get("release_id"), str) or not manifest["release_id"]:
        raise ValueError("invalid release_id")
    rid = manifest["release_id"]
    if rid in (".", "..") or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for c in rid):
        raise ValueError("invalid release_id")
    if not isinstance(manifest.get("components"), list) or not manifest["components"] or not set(manifest["components"]) <= COMPONENTS:
        raise ValueError("invalid components")
    if not isinstance(manifest.get("files"), list) or not isinstance(manifest.get("bundle_sha256"), str):
        raise ValueError("invalid manifest")
    seen = set()
    for item in manifest["files"]:
        path = item.get("path") if isinstance(item, dict) else None
        if (not isinstance(path, str) or not path or path.startswith("/") or "\\" in path or
                any(part in ("", ".", "..") for part in path.split("/"))):
            raise ValueError("unsafe manifest path")
        component, separator, rel = path.partition("/")
        if not separator or component not in {"backend", "web", "downloads"}:
            raise ValueError("unsupported manifest component path")
        if component == "backend" and (not _managed_backend_rel(rel) or any(part.startswith('.') or part in PRESERVED_BACKEND for part in rel.split('/'))):
            raise ValueError("unsupported managed backend path")
        if component not in manifest["components"] and not (component == "downloads" and any(c in manifest["components"] for c in ("android", "windows"))):
            raise ValueError("manifest file does not match components")
        if (path in seen or not isinstance(item.get("sha256"), str) or len(item["sha256"]) != 64 or
                type(item.get("size")) is not int or item["size"] < 0):
            raise ValueError("invalid manifest file")
        seen.add(path)
    return manifest


def _run(argv, cwd=None):
    return subprocess.run([str(value) for value in argv], cwd=str(cwd) if cwd else None, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def _run_database_backup(argv, destination):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output:
        result = subprocess.run([str(value) for value in argv], stdout=output, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise RuntimeError(f"{Path(str(argv[0])).name} failed (exit {result.returncode})")
    if destination.stat().st_size == 0:
        raise RuntimeError("database backup command produced an empty backup")
    return destination


def _digest(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _safe_relative(path):
    if (not isinstance(path, str) or not path or path.startswith("/") or "\\" in path or
            any(part in ("", ".", "..") for part in path.split("/"))):
        raise ValueError("unsafe relative path")
    return path


def _target(s, path):
    component, _, rel = path.partition("/")
    _safe_relative(rel)
    roots = {"backend": Path(s["backend_dir"]), "web": Path(s["web_dir"]), "downloads": Path(s["download_dir"])}
    if component not in roots:
        raise ValueError("unsupported component")
    target = roots[component] / Path(*rel.split("/"))
    _reject_symlink_ancestors(target)
    return target


def _manifest_files(manifest):
    return {item["path"]: item for item in manifest["files"]}


def _receipt_path(state):
    return Path(state) / "active-release.json"


def _read_receipt(state):
    path = _receipt_path(state)
    if not path.exists():
        return None
    if path.is_symlink():
        raise ValueError("active release receipt is a symlink")
    receipt = json.loads(path.read_text(encoding="utf-8"))
    validate_manifest(receipt)
    return receipt


def _write_receipt(state, manifest):
    path = _receipt_path(state)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")
    os.replace(temp, path)


def _journal(state, entry):
    state = Path(state)
    state.mkdir(parents=True, exist_ok=True)
    with (state / "deploy.journal.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps({"time": time.time(), **entry}) + "\n")


def _validate_tar_members(members, expected):
    names = []
    for member in members:
        names.append(member.name)
        if (not member.isfile() or member.type not in (tarfile.REGTYPE, tarfile.AREGTYPE) or
                member.name.startswith("/") or "\\" in member.name or
                any(part in ("", ".", "..") for part in member.name.split("/"))):
            raise ValueError("unsafe tar member")
    if set(names) != set(expected) or len(names) != len(set(names)):
        raise ValueError("tar members do not match manifest")


def verify_bundle(bundle, manifest):
    validate_manifest(manifest)
    bundle = Path(bundle)
    if not bundle.is_file() or _digest(bundle) != manifest["bundle_sha256"]:
        raise ValueError("bundle hash mismatch")
    expected = _manifest_files(manifest)
    with tarfile.open(bundle, "r:gz") as archive:
        members = archive.getmembers()
        _validate_tar_members(members, expected)
        for member in members:
            item = expected[member.name]
            stream = archive.extractfile(member)
            digest = hashlib.sha256()
            size = 0
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
                size += len(block)
            if size != item["size"] or digest.hexdigest() != item["sha256"]:
                raise ValueError(f"file hash mismatch: {member.name}")
    return expected


def _extract_verified(bundle, expected, directory):
    root = Path(directory)
    with tarfile.open(bundle, "r:gz") as archive:
        members = {member.name: member for member in archive.getmembers()}
        for name in expected:
            target = root / Path(*name.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            source = archive.extractfile(members[name])
            with target.open("wb") as output:
                shutil.copyfileobj(source, output)
    return root


def _managed_receipt_paths(receipt, component):
    return {item["path"] for item in (receipt or {}).get("files", []) if item["path"].startswith(component + "/")}


def _receipt_for_deployment(previous, manifest):
    selected = _payload_components(manifest)
    old = {item["path"]: item for item in (previous or {}).get("files", [])}
    incoming = _manifest_files(manifest)
    for component in selected:
        old = {path: item for path, item in old.items() if not path.startswith(component + "/")}
    old.update({path: item for path, item in incoming.items() if path.split("/", 1)[0] in selected})
    result = dict(manifest)
    result["components"] = sorted(set((previous or {}).get("components", [])) | set(manifest["components"]))
    result["files"] = [old[path] for path in sorted(old)]
    return result


def _copy_regular(source, target):
    source, target = Path(source), Path(target)
    if source.is_symlink() or not source.is_file():
        raise ValueError(f"managed source is not a regular file: {source}")
    _reject_symlink_ancestors(target)
    if target.exists() and (target.is_symlink() or not target.is_file()):
        raise ValueError(f"managed target is not a regular file: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def _remove_managed(path):
    path = Path(path)
    _reject_symlink_ancestors(path)
    if path.exists() or path.is_symlink():
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"managed target is not a regular file: {path}")
        path.unlink()


def _snapshot_files(s, backup, manifest, previous):
    backup = Path(backup)
    entries = []
    incoming = _manifest_files(manifest)
    for component in ("backend", "web"):
        if component not in manifest['components']:
            continue
        paths = _managed_receipt_paths(previous, component) | {path for path in incoming if path.startswith(component + "/")}
        for path in sorted(paths):
            target = _target(s, path)
            entry = {"path": path, "existed": target.is_file() and not target.is_symlink()}
            if target.exists() and (target.is_symlink() or not target.is_file()):
                raise ValueError(f"managed target is not a regular file: {target}")
            if entry["existed"]:
                destination = backup / Path(*path.split("/"))
                _copy_regular(target, destination)
                entry.update(size=target.stat().st_size, sha256=_digest(target))
            entries.append(entry)
    for path in sorted(path for path in incoming if path.startswith("downloads/")):
        target = _target(s, path)
        entry = {"path": path, "existed": target.is_file() and not target.is_symlink()}
        if target.exists() and (target.is_symlink() or not target.is_file()):
            raise ValueError(f"download target is not a regular file: {target}")
        if entry["existed"]:
            destination = backup / Path(*path.split("/"))
            _copy_regular(target, destination)
            entry.update(size=target.stat().st_size, sha256=_digest(target))
        entries.append(entry)
    (backup / "managed-backup.json").write_text(json.dumps({"files": entries}, sort_keys=True), encoding="utf-8")
    (backup / "previous-release.json").write_text(json.dumps(previous or {}, sort_keys=True), encoding="utf-8")


def _build_stage(root, s, manifest, state):
    if "backend" not in manifest["components"]:
        return None
    live = Path(s["backend_dir"])
    stage = Path(state) / ("stage-" + manifest["release_id"])
    stage.mkdir(mode=0o700, exist_ok=False)
    env = live / ".env"
    if env.is_symlink() or not env.is_file():
        raise ValueError("backend .env must be a regular file")
    _copy_regular(env, stage / ".env")
    incoming = _manifest_files(manifest)
    requirements = incoming.get("backend/requirements.txt")
    old_requirements = live / "requirements.txt"
    if requirements:
        if not old_requirements.is_file() or _digest(old_requirements) != requirements["sha256"]:
            shutil.rmtree(stage)
            raise ValueError("requirements changed; dependency installation is not allowed during deploy")
    for base in MANAGED_BACKEND_ROOTS:
        source = live / base
        if source.is_dir():
            for item in source.rglob("*"):
                rel = (Path(base) / item.relative_to(source)).as_posix()
                if item.is_file() and not item.is_symlink() and _managed_backend_rel(rel):
                    _copy_regular(item, stage / Path(*rel.split("/")))
    for filename in MANAGED_BACKEND_FILES:
        source = live / filename
        if source.is_file() and not source.is_symlink():
            _copy_regular(source, stage / filename)
    for path in incoming:
        if path.startswith("backend/"):
            _copy_regular(root / Path(*path.split("/")), stage / Path(*path.split("/")[1:]))
    previous = _read_receipt(state)
    new_paths = {path for path in incoming if path.startswith('backend/')}
    for path in _managed_receipt_paths(previous, 'backend') - new_paths:
        _remove_managed(stage / Path(*path.split('/')[1:]))
    _run([s["python_executable"], "-m", "pip", "check"], stage)
    return stage


def _activate(root, s, manifest, previous):
    incoming = _manifest_files(manifest)
    for component in ("backend", "web"):
        if component not in manifest['components']:
            continue
        old = _managed_receipt_paths(previous, component)
        new = {path for path in incoming if path.startswith(component + "/")}
        for path in sorted(old - new):
            _remove_managed(_target(s, path))
        for path in sorted(new):
            _copy_regular(root / Path(*path.split("/")), _target(s, path))
    for path in sorted(path for path in incoming if path.startswith("downloads/")):
        target = _target(s, path)
        source = root / Path(*path.split("/"))
        if target.exists():
            if target.is_symlink() or not target.is_file() or target.stat().st_size != incoming[path]["size"] or _digest(target) != incoming[path]["sha256"]:
                raise ValueError(f"download collision differs: {path}")
        else:
            _copy_regular(source, target)


def preflight(s):
    for key in ("backend_dir", "web_dir", "download_dir", "state_dir"):
        _reject_symlink_ancestors(s[key])
        if not Path(s[key]).is_dir():
            raise ValueError(f"missing directory: {key}")
    env = Path(s["backend_dir"]) / ".env"
    if env.is_symlink() or not env.is_file():
        raise ValueError("backend .env missing or unsafe")
    _reject_symlink_ancestors(s["python_executable"], allow_final_symlink=True)
    if not os.access(s["python_executable"], os.X_OK):
        raise ValueError("python executable unavailable")
    if shutil.disk_usage(s["state_dir"]).free <= 100 * 1024 * 1024:
        raise ValueError("insufficient free space")
    for key in ("stop_command", "start_command", "database_backup_command"):
        if not shutil.which(s[key][0]) and not Path(s[key][0]).is_file():
            raise ValueError(f"command unavailable: {key}")


def _lock(state):
    path = Path(state) / ".deploy.lock"
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except FileExistsError:
        raise RuntimeError("deployment already locked")
    return path


def _health(s, manifest):
    attempts = s.get("health_attempts", 12)
    interval = s.get("health_interval_seconds", 2)
    last = None
    for attempt in range(attempts):
        try:
            with urlopen(s["health_url"], timeout=5) as response:
                data = json.load(response)
            if data.get("status") == "healthy" and data.get("database") == "connected":
                if s.get("version_url"):
                    with urlopen(s["version_url"], timeout=5) as response:
                        version = json.load(response)
                    if version.get("version") != manifest.get("version") or str(version.get("build_number")) != str(manifest.get("build_number")):
                        raise RuntimeError("version check failed")
                return
            last = RuntimeError("health response is not healthy")
        except Exception as error:
            last = error
        if attempt + 1 < attempts:
            time.sleep(interval)
    raise RuntimeError(f"health check failed after {attempts} attempts: {last}")


def deploy(s, bundle, manifest):
    validate_config(s)
    validate_manifest(manifest)
    preflight(s)
    expected = verify_bundle(bundle, manifest)
    rid, state = manifest['release_id'], Path(s['state_dir'])
    for path, item in expected.items():
        target = _target(s, path)
        if path.startswith('downloads/') and target.exists() and (
                not target.is_file() or _digest(target) != item['sha256']):
            raise ValueError(f'download collision differs: {path}')
    stage = None
    stopped = start_attempted = migration_attempted = False
    lock = _lock(state)
    try:
        previous = _read_receipt(state)
        backup = state / 'backups' / rid
        _reject_symlink_ancestors(backup)
        backup.mkdir(parents=True, exist_ok=False)
        os.chmod(backup, 0o700)
        _snapshot_files(s, backup, manifest, previous)
        (backup / 'release.json').write_text(json.dumps(manifest), encoding='utf-8')
        with tempfile.TemporaryDirectory(dir=state) as extracted:
            root = _extract_verified(bundle, expected, extracted)
            stage = _build_stage(root, s, manifest, state)
            _journal(state, {'release_id': rid, 'phase': 'stop'})
            _run(s['stop_command'])
            stopped = True
            if stage is not None:
                _run_database_backup(s['database_backup_command'], backup / 'database.sql')
                _journal(state, {'release_id': rid, 'phase': 'database_backup'})
                migration_attempted = True
                (backup / 'migration-attempted').touch()
                _journal(state, {'release_id': rid, 'phase': 'migration'})
                _run([s['python_executable'], '-m', 'alembic', 'upgrade', 'head'], stage)
            _journal(state, {'release_id': rid, 'phase': 'activate'})
            _activate(root, s, manifest, previous)
        start_attempted = True
        _journal(state, {'release_id': rid, 'phase': 'start'})
        _run(s['start_command'])
        _health(s, manifest)
        _write_receipt(state, _receipt_for_deployment(previous, manifest))
        _journal(state, {'release_id': rid, 'phase': 'healthy'})
        return rid
    except Exception:
        if start_attempted:
            # Do not touch live files if the service could still be writing them.
            _run(s['stop_command'])
        if migration_attempted:
            _journal(state, {'release_id': rid, 'phase': 'manual_recovery_required',
                             'reason': 'database schema may have changed; service left stopped'})
        elif stopped:
            _validate_backup(s, backup)
            _restore_backup(s, backup, previous)
            _run(s['start_command'])
            _health(s, previous or manifest)
            _journal(state, {'release_id': rid, 'phase': 'files_restored'})
        raise
    finally:
        try:
            if stage is not None and stage.exists():
                shutil.rmtree(stage)
        finally:
            lock.unlink(missing_ok=True)


def _restore_backup(s, backup, previous):
    metadata = json.loads((Path(backup) / "managed-backup.json").read_text(encoding="utf-8"))
    for entry in metadata.get("files", []):
        path = entry["path"]
        target = _target(s, path)
        source = Path(backup) / Path(*path.split("/"))
        if entry.get("existed"):
            _copy_regular(source, target)
        elif path.startswith(("backend/", "web/")):
            _remove_managed(target)
        elif target.exists() and target.is_file() and not target.is_symlink():
            if _digest(target) == entry.get("sha256"):
                target.unlink()
    if previous:
        _write_receipt(s["state_dir"], previous)
    else:
        _receipt_path(s["state_dir"]).unlink(missing_ok=True)


def _validate_backup(s, backup):
    _reject_symlink_ancestors(backup)
    metadata = json.loads((backup / 'managed-backup.json').read_text(encoding='utf-8'))
    for entry in metadata['files']:
        _target(s, entry['path'])
        if entry['existed']:
            source = backup / Path(*entry['path'].split('/'))
            _reject_symlink_ancestors(source)
            if not source.is_file() or source.stat().st_size != entry['size'] or _digest(source) != entry['sha256']:
                raise ValueError('Backup checksum mismatch')


def restore(s, rid, schema_compatible=False):
    validate_config(s)
    if not isinstance(rid, str) or not rid or rid in ('.', '..') or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-' for c in rid):
        raise ValueError('invalid release_id')
    preflight(s)
    lock = _lock(s['state_dir'])
    try:
        backup = Path(s['state_dir']) / 'backups' / rid
        _validate_backup(s, backup)
        previous = json.loads((backup / 'previous-release.json').read_text(encoding='utf-8')) or None
        current = _read_receipt(s['state_dir'])
        if current and current.get('release_id') not in {rid, (previous or {}).get('release_id')}:
            raise ValueError('Refusing restore over a newer deployment')
        if (backup / 'migration-attempted').exists() and not schema_compatible:
            raise ValueError('Review database compatibility first; --schema-compatible is required')
        _run(s['stop_command'])
        _restore_backup(s, backup, previous)
        _run(s['start_command'])
        _health(s, previous or {})
        _journal(s['state_dir'], {'release_id': rid, 'phase': 'restore', 'database_restored': False})
    finally:
        lock.unlink(missing_ok=True)


def verify_active(s, bundle, manifest):
    validate_manifest(manifest)
    preflight(s)
    verify_bundle(bundle, manifest)
    receipt = _read_receipt(s["state_dir"])
    if not receipt or receipt.get("release_id") != manifest["release_id"] or receipt.get("version") != manifest.get("version") or str(receipt.get("build_number")) != str(manifest.get("build_number")):
        raise ValueError("active release receipt mismatch")
    expected = _manifest_files(manifest)
    if any(_manifest_files(receipt).get(path) != item for path, item in expected.items()):
        raise ValueError("active release file receipt mismatch")
    for path, item in expected.items():
        target = _target(s, path)
        if not target.is_file() or target.is_symlink() or target.stat().st_size != item["size"] or _digest(target) != item["sha256"]:
            raise ValueError(f"active deployed file mismatch: {path}")
    _health(s, manifest)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--bundle")
    parser.add_argument("--manifest")
    parser.add_argument("--mode", choices=["preflight", "deploy", "verify", "restore"], required=True)
    parser.add_argument("--release-id")
    parser.add_argument('--schema-compatible', action='store_true')
    args = parser.parse_args(argv)
    config = validate_config(json.loads(Path(args.config).read_text(encoding="utf-8-sig")))
    if args.mode == "restore":
        if not args.release_id:
            raise ValueError("--release-id required for restore")
        restore(config, args.release_id, schema_compatible=args.schema_compatible)
        return
    if not args.bundle or not args.manifest:
        parser.error("--bundle and --manifest are required for preflight, deploy, and verify")
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8-sig"))
    if args.mode == "preflight":
        preflight(config)
    elif args.mode == "verify":
        verify_active(config, args.bundle, manifest)
    else:
        deploy(config, args.bundle, manifest)


if __name__ == "__main__":
    main()
