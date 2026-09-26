"""Private deployment worker. Install outside the backend directory it updates."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import importlib
import json
import os
from pathlib import Path
import sys
import time

import publish
import server_deploy

TERMINAL = {'succeeded', 'failed', 'cancelled', 'manual_recovery'}
PHASES = {'preflight', 'stop', 'backup', 'database_backup', 'migration', 'activate',
          'start', 'healthy', 'verifying', 'registering', 'manual_recovery_required',
          'files_restored', 'restore'}
HEARTBEAT_STATUSES = {'idle', 'disabled', 'running', 'error'}
HEARTBEAT_ERRORS = {None, 'SETTINGS_UNAVAILABLE', 'DEPLOYMENT_FORBIDDEN',
                    'DEPLOYMENT_EXECUTION_FAILED', 'REGISTRATION_FAILED',
                    'WORKER_INTERRUPTED'}


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


@contextmanager
def process_lock(path):
    """An OS lock is released on crash; never delete a potentially live lock file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    stream = path.open('a+b')
    try:
        stream.seek(0)
        if stream.read(1) == b'':
            stream.write(b'0')
            stream.flush()
        stream.seek(0)
        if os.name == 'nt':
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        stream.close()


class Executor:
    def __init__(self, config, validate_artifact=None):
        self.validate_artifact = validate_artifact
        self.config = config
        self.server = publish.server_config(config)
        server_deploy.validate_config(self.server)
        if self.server.get('service_environment_confirmed') is not True:
            raise ValueError('Production environment confirmation is required')

    def execute(self, job, directory, manifest, progress, settings=None):
        operation = job.operation
        bundle = directory / 'bundle.tar.gz'
        publish.validate_local_manifest(manifest)
        if self.validate_artifact:
            self.validate_artifact(bundle, manifest, settings)
        server_deploy.verify_bundle(bundle, manifest)
        progress('preflight')
        server_deploy.preflight(self.server)
        if operation == 'preflight':
            return
        if operation in {'deploy', 'register'}:
            publish.check_records(self.config, manifest)
        if operation == 'deploy':
            if 'backend' in manifest['components'] and not job.migration_confirmed:
                raise ValueError('Migration approval required')
            original = server_deploy._journal
            def journal(state, entry):
                original(state, entry)
                phase = entry.get('phase')
                if phase in PHASES:
                    progress(phase)
            server_deploy._journal = journal
            try:
                server_deploy.deploy(self.server, bundle, manifest)
            finally:
                server_deploy._journal = original
        elif operation == 'restore':
            if not job.schema_compatible:
                raise ValueError('Schema compatibility review required')
            progress('restore')
            server_deploy.restore(self.server, manifest['release_id'], schema_compatible=True)
            return
        elif operation != 'register':
            raise ValueError('Unsupported operation')
        progress('verifying')
        server_deploy.verify_active(self.server, bundle, manifest)
        publish.verify_public(self.config, manifest)
        progress('registering')
        publish.check_records(self.config, manifest, register=True)


class Worker:
    def __init__(self, sessions, job_model, artifact_model, artifact_root, executor,
                 authorized, audit, settings_loader=None, heartbeat=None):
        self.sessions = sessions
        self.Job = job_model
        self.Artifact = artifact_model
        self.artifact_root = Path(artifact_root).resolve()
        self.executor = executor
        self.authorized = authorized
        self.audit = audit
        self.settings_loader = settings_loader
        self.heartbeat_callback = heartbeat

    @staticmethod
    def _setting(settings, name, default=None):
        if settings is None:
            return default
        if isinstance(settings, dict):
            return settings.get(name, default)
        return getattr(settings, name, default)

    def heartbeat(self, status, error_code=None):
        """Send only bounded worker state to the optional backend hook."""
        if (status not in HEARTBEAT_STATUSES or error_code not in HEARTBEAT_ERRORS or
                not self.heartbeat_callback):
            return
        try:
            with self.sessions() as heartbeat_db:
                self.heartbeat_callback(heartbeat_db, status, error_code)
                heartbeat_db.commit()
        except Exception:
            # Health reporting must never interrupt or alter a deployment.
            return

    def _settings(self, db):
        return self.settings_loader(db) if self.settings_loader else None

    def _operator_allowed(self, settings, user_id):
        operator_ids = self._setting(settings, 'operator_ids')
        if operator_ids is None:
            return True
        try:
            return int(user_id) in {int(value) for value in operator_ids}
        except (TypeError, ValueError):
            return False

    def event(self, db, job, phase, status=None, error_code=None):
        previous = job.status
        if status:
            job.status = status
        job.phase = phase
        job.error_code = error_code
        events = json.loads(job.events_json or '[]')
        events.append({'phase': phase, 'at': utcnow().isoformat() + 'Z'})
        job.events_json = json.dumps(events[-200:])
        if job.status in TERMINAL:
            job.finished_at = utcnow()
        self.audit(db, admin_user_id=job.created_by, action='deployment_worker_transition',
                   target_type='deployment', target_id=job.id, reason=job.reason,
                   metadata={'status_before': previous, 'status_after': job.status,
                             'error_code': error_code})
        db.commit()

    def recover_interrupted(self):
        with self.sessions() as db:
            jobs = db.query(self.Job).filter(self.Job.status.in_(['running', 'verifying'])).all()
            for job in jobs:
                self.event(db, job, 'manual_recovery', status='manual_recovery',
                           error_code='WORKER_INTERRUPTED')

    def run_once(self):
        with self.sessions() as db:
            try:
                settings = self._settings(db)
            except Exception:
                self.heartbeat('error', 'SETTINGS_UNAVAILABLE')
                return False
            if settings is not None and self._setting(settings, 'enabled', False) is not True:
                self.heartbeat('disabled')
                return False
            job = db.query(self.Job).filter(self.Job.status == 'queued').order_by(self.Job.created_at).first()
            if job is None:
                self.heartbeat('idle')
                return False
            # Manual recovery is a global stop, not permission to run the next deployment.
            if job.operation != 'restore' and db.query(self.Job).filter(self.Job.status == 'manual_recovery').first():
                self.heartbeat('idle')
                return False
            if (not self._operator_allowed(settings, job.created_by) or
                    not self.authorized(db, job.created_by)) or (
                    job.operation != 'preflight' and (
                        not job.approved_by or not self._operator_allowed(settings, job.approved_by) or
                        not self.authorized(db, job.approved_by))):
                self.event(db, job, 'permission_revoked', status='failed', error_code='DEPLOYMENT_FORBIDDEN')
                self.heartbeat('error', 'DEPLOYMENT_FORBIDDEN')
                return True
            changed = db.query(self.Job).filter(self.Job.id == job.id, self.Job.status == 'queued').update(
                {'status': 'running', 'started_at': utcnow()}, synchronize_session=False)
            if changed != 1:
                db.rollback()
                return True
            db.commit()
            db.refresh(job)
            self.heartbeat('running')
            self.event(db, job, 'preflight')
            artifact = db.get(self.Artifact, job.artifact_id)
            last_phase = 'preflight'
            try:
                if artifact is None:
                    raise ValueError('Artifact missing')
                directory = self.artifact_root / artifact.id
                publish.reject_link(directory)
                if directory.resolve().parent != self.artifact_root:
                    raise ValueError('Invalid artifact reference')
                manifest = json.loads(artifact.manifest_json)
                if manifest.get('bundle_sha256') != artifact.bundle_sha256:
                    raise ValueError('Artifact identity mismatch')
                def progress(phase):
                    nonlocal last_phase
                    if phase not in PHASES:
                        return
                    last_phase = phase
                    self.heartbeat('running')
                    self.event(db, job, phase, status='verifying' if phase in {'verifying', 'registering'} else None)
                if isinstance(self.executor, Executor):
                    self.executor.execute(job, directory, manifest, progress, settings)
                else:
                    self.executor.execute(job, directory, manifest, progress)
                job.result_json = json.dumps({'verified': True, 'registered': job.operation in {'deploy', 'register'},
                                              'restored': job.operation == 'restore'})
                if job.operation == 'restore':
                    unresolved = db.query(self.Job).filter(self.Job.artifact_id == job.artifact_id,
                                                          self.Job.status == 'manual_recovery').all()
                    for old in unresolved:
                        self.event(db, old, 'recovered_by_restore', status='failed', error_code='FILES_RESTORED')
                self.event(db, job, 'completed', status='succeeded')
                self.heartbeat('idle')
            except Exception:
                uncertain = job.operation in {'deploy', 'restore'} and last_phase not in {'preflight', 'verifying', 'registering', 'healthy', 'files_restored'}
                error = 'REGISTRATION_FAILED' if last_phase == 'registering' else 'DEPLOYMENT_EXECUTION_FAILED'
                self.event(db, job, 'manual_recovery' if uncertain else 'failed',
                           status='manual_recovery' if uncertain else 'failed', error_code=error)
                self.heartbeat('error', error)
            return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backend-root', required=True)
    parser.add_argument('--config', required=True)
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    backend = Path(args.backend_root).resolve()
    from dotenv import load_dotenv
    load_dotenv(backend / '.env')
    sys.path.insert(0, str(backend))
    os.chdir(backend)
    database = importlib.import_module('app.database')
    models = importlib.import_module('app.models.deployment')
    service = importlib.import_module('app.services.deployment_service')
    audit = importlib.import_module('app.services.admin_audit_service').record_required_admin_audit
    settings = service.get_deployment_config()
    artifacts = importlib.import_module('app.services.deployment_artifacts')
    def validate_artifact(bundle, manifest, current_settings):
        artifacts.validate_bundle(bundle, manifest, max_bytes=current_settings.max_bytes,
                                  max_expanded_bytes=current_settings.max_expanded_bytes,
                                  max_files=current_settings.max_files)
    def authorized(db, user_id):
        current_models = importlib.import_module('app.models.models')
        return db.query(current_models.User.id).join(
            current_models.UserRole, current_models.UserRole.user_id == current_models.User.id
        ).join(
            current_models.Role, current_models.Role.id == current_models.UserRole.role_id
        ).filter(
            current_models.User.id == user_id, current_models.User.is_active.is_(True),
            current_models.Role.name == 'admin'
        ).first() is not None
    executor = Executor(publish.config(args.config), validate_artifact)
    root = settings.artifact_dir.resolve()
    worker = Worker(database.SessionLocal, models.DeploymentJob, models.DeploymentArtifact,
                    root, executor, authorized, audit,
                    settings_loader=service.get_deployment_config,
                    heartbeat=getattr(service, 'worker_heartbeat', None))
    with process_lock(root / '.worker.lock'):
        worker.recover_interrupted()
        while True:
            worked = worker.run_once()
            if args.once:
                return
            if not worked:
                time.sleep(2)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Worker stopped: {type(error).__name__}; inspect private configuration and job status')
        raise SystemExit(1)
