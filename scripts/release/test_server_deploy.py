import hashlib
import json
import os
import tarfile
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).parent))
import server_deploy as sd

def make_bundle(tmp_path):
    stage = tmp_path / "stage"; (stage / "backend/app").mkdir(parents=True); (stage / "web").mkdir(); (stage / "downloads").mkdir()
    (stage / "backend/app/main.py").write_text("x")
    files = []
    for p in stage.rglob("*"):
        if p.is_file(): files.append({"path": p.relative_to(stage).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "size": p.stat().st_size})
    bundle = tmp_path / "bundle.tar.gz"
    with tarfile.open(bundle, "w:gz") as t:
        for f in files: t.add(stage / f["path"], arcname=f["path"])
    manifest = {"release_id":"r-1", "version":"1.0.0", "build_number":1, "components":["backend"], "files":files, "bundle_sha256":hashlib.sha256(bundle.read_bytes()).hexdigest()}
    mf = tmp_path / "manifest.json"; mf.write_text(json.dumps(manifest)); return bundle, manifest, mf

def config(tmp_path):
    dirs = {k: tmp_path / k for k in ("backend", "web", "downloads", "state")}
    sd.WEBSITE_ROOT = str(dirs["web"])
    sd.WEB_ROOT = str(dirs["web"]) + "/"
    for p in dirs.values(): p.mkdir()
    (dirs["backend"] / ".env").write_text("x")
    exe = tmp_path / "python"; exe.write_text("#"); exe.chmod(0o755)
    return {"server": {"backend_dir":str(dirs["backend"]), "web_dir":str(dirs["web"])+"/", "download_dir":str(dirs["downloads"]), "state_dir":str(dirs["state"]), "python_executable":str(exe), "stop_command":[sys.executable,"-c","pass"], "start_command":[sys.executable,"-c","pass"], "database_backup_command":[sys.executable,"-c","print('CREATE TABLE backup_marker (id INTEGER);')"], "health_url":"http://unused"}}

@pytest.fixture(autouse=True)
def restore_constants():
    web, website = sd.WEB_ROOT, sd.WEBSITE_ROOT
    yield
    sd.WEB_ROOT, sd.WEBSITE_ROOT = web, website


def test_config_rejects_traversal(tmp_path):
    c=config(tmp_path); c["server"]["state_dir"] = str(tmp_path / "a/../state")
    with pytest.raises(ValueError): sd.validate_config(c)

def test_verify_bundle_and_manifest(tmp_path):
    b, m, _ = make_bundle(tmp_path); assert sd.verify_bundle(b, m)
    m["files"][0]["sha256"] = "0" * 64
    with pytest.raises(ValueError): sd.verify_bundle(b, m)

def test_verify_rejects_unsafe_tar(tmp_path):
    b, m, _ = make_bundle(tmp_path)
    with tarfile.open(b, "w:gz") as t:
        p=tmp_path/"x"; p.write_text("x"); t.add(p, arcname="../x")
    m["bundle_sha256"] = hashlib.sha256(b.read_bytes()).hexdigest(); m["files"]=[{"path":"../x","sha256":"0"*64,"size":1}]
    with pytest.raises(ValueError): sd.verify_bundle(b,m)

def test_preflight(tmp_path):
    c=config(tmp_path); s=sd.validate_config(c); sd.preflight(s)

def test_deploy_and_restore(tmp_path, monkeypatch):
    c=config(tmp_path); c["server"]["python_executable"] = sys.executable
    s=sd.validate_config(c); b,m,_=make_bundle(tmp_path)
    backend = Path(s["backend_dir"])
    (backend / "unknown.txt").write_text("keep")
    (backend / "uploads").mkdir(); (backend / "uploads/user.bin").write_text("keep")
    monkeypatch.setattr(sd, "_run", lambda *args, **kwargs: None)
    monkeypatch.setattr(sd, "urlopen", lambda *args, **kwargs: type("Response", (), {"__enter__":lambda self:self, "__exit__":lambda self,*args:None, "read":lambda self:b'{"status":"healthy","database":"connected"}'})())
    sd.deploy(s,b,m)
    assert (backend / "app/main.py").exists()
    assert (backend / "unknown.txt").read_text() == "keep"
    assert (backend / "uploads/user.bin").read_text() == "keep"
    backup = Path(s['state_dir']) / 'backups' / 'r-1'
    assert (backup / "database.sql").read_text().startswith("CREATE TABLE")
    with pytest.raises(ValueError, match='compatibility'):
        sd.restore(s, 'r-1')
    sd.restore(s, 'r-1', schema_compatible=True)
    assert (backend / "unknown.txt").read_text() == "keep"

def test_cli_restore_does_not_require_bundle_or_manifest(tmp_path, monkeypatch):
    c=config(tmp_path); config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(c))
    monkeypatch.setattr(sd, "restore", lambda s, rid, **kw: (None if rid == "r-1" else (_ for _ in ()).throw(AssertionError())))
    sd.main(["--config", str(config_path), "--mode", "restore", "--release-id", "r-1"])

def test_verify_active_requires_receipt_and_current_files(tmp_path, monkeypatch):
    c=config(tmp_path); c["server"]["python_executable"] = sys.executable
    s=sd.validate_config(c); b,m,_=make_bundle(tmp_path)
    monkeypatch.setattr(sd, "_run", lambda *args, **kwargs: None)
    monkeypatch.setattr(sd, "urlopen", lambda *args, **kwargs: type("Response", (), {"__enter__":lambda self:self, "__exit__":lambda self,*args:None, "read":lambda self:b'{"status":"healthy","database":"connected"}'})())
    with pytest.raises(ValueError): sd.verify_active(s, b, m)
    sd.deploy(s,b,m)
    sd.verify_active(s,b,m)
