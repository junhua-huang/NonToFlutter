import json
from pathlib import Path
import sys
from types import SimpleNamespace

import pytest
from sqlalchemy import Column, DateTime, String, Text, create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

sys.path.insert(0, str(Path(__file__).parent))
import deployment_worker as dw

Base = declarative_base()


class Job(Base):
    __tablename__ = 'jobs'
    id = Column(String, primary_key=True)
    artifact_id = Column(String)
    operation = Column(String)
    status = Column(String)
    phase = Column(String)
    error_code = Column(String)
    events_json = Column(Text, default='[]')
    created_by = Column(String)
    approved_by = Column(String)
    reason = Column(String)
    created_at = Column(DateTime, default=dw.utcnow)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)


class Artifact(Base):
    __tablename__ = 'artifacts'
    id = Column(String, primary_key=True)
    manifest_json = Column(Text)
    bundle_sha256 = Column(String)


@pytest.fixture
def setup(tmp_path):
    engine = create_engine('sqlite://')
    Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    with sessions() as db:
        db.add(Artifact(id='a', manifest_json=json.dumps({'bundle_sha256': 'abc'}), bundle_sha256='abc'))
        db.add(Job(id='j', artifact_id='a', operation='deploy', status='queued', created_by='1', approved_by='1', reason='release'))
        db.commit()
    (tmp_path / 'a').mkdir()
    audits = []
    executor = SimpleNamespace(execute=lambda *args: None)
    worker = dw.Worker(sessions, Job, Artifact, tmp_path, executor, lambda *a: True,
                       lambda db, **kw: audits.append(kw))
    yield worker, sessions, audits
    engine.dispose()


def test_worker_claims_and_completes_durably(setup):
    worker, sessions, audits = setup
    assert worker.run_once()
    with sessions() as db:
        job = db.get(Job, 'j')
        assert job.status == 'succeeded' and job.finished_at
        assert json.loads(job.events_json)[-1]['phase'] == 'completed'
    assert len(audits) >= 2
    assert not worker.run_once()


def test_revoked_permissions_prevent_execution(setup):
    worker, sessions, audits = setup
    worker.authorized = lambda *a: False
    worker.executor.execute = lambda *a: pytest.fail('must not execute')
    worker.run_once()
    with sessions() as db:
        assert db.get(Job, 'j').error_code == 'DEPLOYMENT_FORBIDDEN'


def test_interrupted_jobs_require_manual_recovery(setup):
    worker, sessions, audits = setup
    with sessions() as db:
        db.get(Job, 'j').status = 'running'
        db.commit()
    worker.recover_interrupted()
    with sessions() as db:
        assert db.get(Job, 'j').status == 'manual_recovery'
        assert db.get(Job, 'j').error_code == 'WORKER_INTERRUPTED'


def test_migration_failure_redacts_secrets_and_blocks_next_job(setup):
    worker, sessions, audits = setup
    def execute(job, directory, manifest, progress):
        progress('migration')
        raise RuntimeError('SECRET PASSWORD ACCESS_TOKEN')
    worker.executor.execute = execute
    worker.run_once()
    with sessions() as db:
        job = db.get(Job, 'j')
        assert job.status == 'manual_recovery'
        assert 'SECRET' not in job.events_json
        db.add(Job(id='next', artifact_id='a', status='queued', operation='deploy', created_by='1', approved_by='1'))
        db.commit()
    assert not worker.run_once()


def test_registration_failure_can_be_retried_without_auto_deploy(setup):
    worker, sessions, audits = setup
    def execute(job, directory, manifest, progress):
        progress('registering')
        raise RuntimeError('token must not appear')
    worker.executor.execute = execute
    worker.run_once()
    with sessions() as db:
        job = db.get(Job, 'j')
        assert job.status == 'failed' and job.error_code == 'REGISTRATION_FAILED'


def test_worker_lock_rejects_second_process(tmp_path):
    with dw.process_lock(tmp_path / 'worker.lock'):
        with pytest.raises(OSError):
            with dw.process_lock(tmp_path / 'worker.lock'):
                pytest.fail('second worker acquired lock')
    with dw.process_lock(tmp_path / 'worker.lock'):
        pass
