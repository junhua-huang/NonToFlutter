import io
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import server_deploy as sd
from test_server_deploy import config, make_bundle


@pytest.fixture
def setup(tmp_path, monkeypatch):
    monkeypatch.setattr(sd, 'WEB_ROOT', sd.WEB_ROOT)
    monkeypatch.setattr(sd, 'WEBSITE_ROOT', sd.WEBSITE_ROOT)
    s = config(tmp_path)['server']
    s['python_executable'] = sys.executable
    s['health_attempts'] = 1
    calls = []
    monkeypatch.setattr(sd, '_run', lambda args, *a, **kw: calls.append(args))
    monkeypatch.setattr(sd, 'urlopen', lambda *a, **kw: io.BytesIO(b'{"status":"healthy","database":"connected"}'))
    b, m, _ = make_bundle(tmp_path)
    return s, b, m, calls


def test_migration_failure_never_restarts_old_code(setup, monkeypatch):
    s, b, m, calls = setup
    def run(args, *a, **kw):
        calls.append(args)
        if 'alembic' in args:
            raise RuntimeError('migration failed')
    monkeypatch.setattr(sd, '_run', run)
    with pytest.raises(RuntimeError, match='migration failed'):
        sd.deploy(s, b, m)
    assert not (Path(s['backend_dir']) / 'app/main.py').exists()
    assert calls[-1][2] == 'alembic'
    assert 'manual_recovery_required' in (Path(s['state_dir']) / 'deploy.journal.jsonl').read_text()
    assert not (Path(s['state_dir']) / '.deploy.lock').exists()


def test_backup_failure_prevents_migration(setup, monkeypatch):
    s, b, m, calls = setup
    monkeypatch.setattr(sd, '_run_database_backup', lambda *a: (_ for _ in ()).throw(RuntimeError('backup failed')))
    with pytest.raises(RuntimeError, match='backup failed'):
        sd.deploy(s, b, m)
    assert not any('alembic' in command for command in calls)
    assert not (Path(s['backend_dir']) / 'app/main.py').exists()


def test_web_partial_activation_preserves_backend(setup, tmp_path):
    s, b, backend_manifest, calls = setup
    sd.deploy(s, b, backend_manifest)
    root = tmp_path / 'web-payload'
    (root / 'web').mkdir(parents=True)
    page = root / 'web/index.html'
    page.write_text('new web')
    web = {'release_id': 'web-2', 'version': '1.0.1', 'build_number': 2, 'bundle_sha256': 'a' * 64,
           'components': ['web'], 'files': [{'path': 'web/index.html', 'size': page.stat().st_size, 'sha256': sd._digest(page)}]}
    previous = sd._read_receipt(s['state_dir'])
    backup = tmp_path / 'snapshot'
    backup.mkdir()
    sd._snapshot_files(s, backup, web, previous)
    sd._activate(root, s, web, previous)
    receipt = sd._receipt_for_deployment(previous, web)
    sd._write_receipt(s['state_dir'], receipt)
    sd._restore_backup(s, backup, previous)
    assert (Path(s['backend_dir']) / 'app/main.py').read_text() == 'x'
    assert not (Path(s['web_dir']) / 'index.html').exists()


def test_restore_refuses_newer_deployment(setup):
    s, b, m, calls = setup
    sd.deploy(s, b, m)
    sd._write_receipt(s['state_dir'], dict(m, release_id='newer'))
    calls.clear()
    with pytest.raises(ValueError, match='newer'):
        sd.restore(s, m['release_id'], schema_compatible=True)
    assert calls == []


def test_backup_tampering_detected_before_stop(setup):
    s, b, m, calls = setup
    app = Path(s['backend_dir']) / 'app'
    app.mkdir()
    (app / 'main.py').write_text('old')
    sd.deploy(s, b, m)
    (Path(s['state_dir']) / 'backups/r-1/backend/app/main.py').write_text('tampered')
    calls.clear()
    with pytest.raises(ValueError, match='checksum'):
        sd.restore(s, m['release_id'], schema_compatible=True)
    assert calls == []


def test_verify_checks_live_file_not_only_uploaded_bundle(setup):
    s, b, m, calls = setup
    sd.deploy(s, b, m)
    (Path(s['backend_dir']) / 'app/main.py').write_text('changed')
    with pytest.raises(ValueError, match='deployed file'):
        sd.verify_active(s, b, m)


def test_duplicate_deploy_releases_lock(setup):
    s, b, m, calls = setup
    sd.deploy(s, b, m)
    with pytest.raises(FileExistsError):
        sd.deploy(s, b, m)
    assert not (Path(s['state_dir']) / '.deploy.lock').exists()


def test_manifest_cannot_overwrite_runtime_files(setup):
    s, b, m, calls = setup
    m['files'][0]['path'] = 'backend/app/uploads/keep.py'
    with pytest.raises(ValueError):
        sd.validate_manifest(m)


def test_public_download_directory_allowed(setup):
    s, b, m, calls = setup
    sd.WEBSITE_ROOT = '/www/wwwroot/nonto.online'
    sd.WEB_ROOT = '/www/wwwroot/nonto.online/nonto/'
    s.update(web_dir=sd.WEB_ROOT, backend_dir='/www/backend', state_dir='/www/release-state',
             download_dir='/www/wwwroot/nonto.online/downloads/')
    sd.validate_config(s)
    s['state_dir'] = '/www/wwwroot/nonto.online/private'
    with pytest.raises(ValueError):
        sd.validate_config(s)
