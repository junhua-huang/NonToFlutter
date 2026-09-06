import copy
import json
from pathlib import Path
import sys
from unittest.mock import Mock

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import publish as p


@pytest.fixture
def config():
    return p.config(p.HERE / 'release.config.example.json')


def manifest():
    return {'release_id': '1.0.1-2-test', 'version': '1.0.1', 'build_number': 2,
            'components': ['web'], 'files': []}


def test_plan_has_no_network_or_mutations(config, monkeypatch, capsys):
    monkeypatch.setattr(sys, 'argv', ['publish.py', '--mode', 'plan', '--config',
                                    str(p.HERE / 'release.config.example.json')])
    for name in ('remote', 'api', 'package'):
        monkeypatch.setattr(p, name, Mock(side_effect=AssertionError(name)))
    p.main()
    assert json.loads(capsys.readouterr().out)['web_dir'].endswith('/nonto/')


def test_remote_missing_confirmation_fails_before_network(config, monkeypatch):
    monkeypatch.setattr(p, 'run', Mock(side_effect=AssertionError('must not execute')))
    with pytest.raises(ValueError):
        p.validate_remote(config)


def test_register_retry_uses_package_manifest(config, monkeypatch):
    monkeypatch.setattr(sys, 'argv', ['publish.py', '--mode', 'register', '--release', 'saved-package'])
    monkeypatch.setattr(p, 'config', lambda *a, **k: config)
    monkeypatch.setattr(p, 'preflight_remote_before_package', Mock(side_effect=AssertionError('new-build check')))
    deploy = Mock()
    monkeypatch.setattr(p, 'deploy', deploy)
    p.main()
    assert deploy.call_args.args[2] == 'register'


def test_backend_bootstrap_does_not_require_app_release_table(config, monkeypatch):
    monkeypatch.setattr(p, 'records', Mock(side_effect=AssertionError('schema not created yet')))
    p.preflight_records(config, {'backend'}, 2)
    p.check_records(config, {'components': ['backend']}, register=True)


def test_registration_is_idempotent(config, monkeypatch):
    m = manifest()
    row = next(p.publication(config, m))
    monkeypatch.setattr(p, 'records', lambda c: [row])
    request = Mock(side_effect=AssertionError('duplicate POST'))
    monkeypatch.setattr(p, 'api', request)
    p.check_records(config, m, register=True)
    changed = copy.deepcopy(row)
    changed['download_url'] = 'https://example.org/different'
    monkeypatch.setattr(p, 'records', lambda c: [changed])
    with pytest.raises(ValueError, match='different'):
        p.check_records(config, m, register=True)


def test_higher_build_rejected_even_if_same_record_exists(config, monkeypatch):
    m = manifest()
    row = next(p.publication(config, m))
    newer = dict(row, build_number=3)
    monkeypatch.setattr(p, 'records', lambda c: [row, newer])
    with pytest.raises(ValueError, match='older'):
        p.check_records(config, m)


def test_source_secret_scanner_allows_environment_fstrings(tmp_path):
    source = tmp_path / 'config.py'
    source.write_text('URI = f"mysql://{USER}:{PASSWORD}@{HOST}/db"')
    p.check_source_secret(source, 'config.py')
    source.write_text('URI = "mysql://actual-user:actual-password@example.org/db"')
    with pytest.raises(ValueError, match='credentials'):
        p.check_source_secret(source, 'config.py')


def test_malformed_python_reports_path(tmp_path):
    source = tmp_path / 'bad.py'
    source.write_bytes(b'x\x00=\x001')
    with pytest.raises(ValueError, match='bad.py'):
        p.check_source_secret(source, 'bad.py')


def test_debug_certificate_rejected_case_insensitively(config, monkeypatch, tmp_path):
    config['android']['certificate_sha256'] = 'a' * 64
    config['android'].update(apksigner='signer', aapt='aapt')
    monkeypatch.setattr(p, 'run', lambda *a, **k: 'certificate SHA-256 digest: ' + 'a' * 64 + '\nCN=ANDROID DEBUG')
    with pytest.raises(ValueError, match='Debug'):
        p.verify_android(tmp_path / 'app.apk', '1.0.1', 2, config)


def test_android_package_version_verified(config, monkeypatch, tmp_path):
    config['android'].update(certificate_sha256='a' * 64, apksigner='signer', aapt='aapt')
    outputs = iter(['certificate SHA-256 digest: ' + 'a' * 64,
                    "package: name='com.nonto.nonto' versionCode='2' versionName='1.0.1'"])
    monkeypatch.setattr(p, 'run', lambda *a, **k: next(outputs))
    p.verify_android(tmp_path / 'app.apk', '1.0.1', 2, config)


def test_local_paths_and_credentials_not_uploaded(config):
    config['server']['identity_file'] = 'private-key'
    config['server']['unrecognized_secret'] = 'do not send'
    result = p.server_config(config)
    assert 'identity_file' not in result
    assert 'unrecognized_secret' not in result


def test_backend_only_package_without_flutter(config, monkeypatch, tmp_path):
    backend = tmp_path / 'backend'
    (backend / 'app').mkdir(parents=True)
    (backend / 'alembic').mkdir()
    (backend / 'app/main.py').write_text('answer = 42')
    (backend / 'requirements.txt').write_text('')
    (backend / 'alembic.ini').write_text('[alembic]')
    monkeypatch.setattr(p, 'BACKEND', backend)
    monkeypatch.setattr(p, 'HERE', tmp_path / 'release')
    monkeypatch.setattr(p.shutil, 'which', lambda *a: None)
    commands = []
    monkeypatch.setattr(p, 'run', lambda args, *a, **k: commands.append(args))
    out = p.package(config, {'backend'}, '1.0.1+2')
    metadata = p.load_manifest(out)
    p.validate_bundle(out, metadata)
    assert metadata['components'] == ['backend']
    assert len(commands) == 1 and 'pytest' in commands[0]


def test_shell_failure_redacts_child_output(monkeypatch):
    monkeypatch.setattr(p.subprocess, 'run', lambda *a, **k: Mock(returncode=1, stdout='password', stderr='token'))
    with pytest.raises(RuntimeError) as error:
        p.run(['command'])
    assert 'password' not in str(error.value) and 'token' not in str(error.value)
