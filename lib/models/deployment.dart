class DeploymentCapabilities {
  final bool enabled;
  final bool canDeploy;
  const DeploymentCapabilities(
      {required this.enabled, required this.canDeploy});
  bool get allowed => enabled && canDeploy;
  factory DeploymentCapabilities.fromJson(Map<String, dynamic> json) =>
      DeploymentCapabilities(
          enabled: json['enabled'] == true,
          canDeploy: json['can_deploy'] == true);
}

List<String> _components(dynamic value) => value is List
    ? value.map((e) => e.toString()).toList()
    : value is Map
        ? value.keys.map((e) => e.toString()).toList()
        : [];

class DeploymentArtifact {
  final String id;
  final String releaseId;
  final String version;
  final String buildNumber;
  final List<String> components;
  final String? createdAt;
  const DeploymentArtifact(
      {required this.id,
      required this.releaseId,
      required this.version,
      required this.buildNumber,
      required this.components,
      this.createdAt});
  String get label => '$version ($buildNumber) · $releaseId';
  factory DeploymentArtifact.fromJson(Map<String, dynamic> json) =>
      DeploymentArtifact(
        id: '${json['id'] ?? ''}',
        releaseId: '${json['release_id'] ?? ''}',
        version: '${json['version'] ?? ''}',
        buildNumber: '${json['build_number'] ?? ''}',
        components: _components(json['components']),
        createdAt: json['created_at'] as String?,
      );
}

class DeploymentEvent {
  final String phase;
  final String? message;
  final String? at;
  const DeploymentEvent({required this.phase, this.message, this.at});
  factory DeploymentEvent.fromJson(Map<String, dynamic> json) =>
      DeploymentEvent(
        phase: '${json['phase'] ?? ''}',
        message: json['message'] as String?,
        at: json['at'] as String?,
      );
}

class DeploymentJob {
  final String id;
  final String artifactId;
  final String operation;
  final String status;
  final String phase;
  final String? createdAt;
  final String? startedAt;
  final String? finishedAt;
  final String? errorCode;
  final String? version;
  final String? buildNumber;
  final List<String> components;
  final List<DeploymentEvent> events;
  const DeploymentJob(
      {required this.id,
      required this.artifactId,
      required this.operation,
      required this.status,
      required this.phase,
      this.createdAt,
      this.startedAt,
      this.finishedAt,
      this.errorCode,
      this.version,
      this.buildNumber,
      this.components = const [],
      this.events = const []});
  bool get active => const [
        'awaiting_approval',
        'queued',
        'running',
        'verifying'
      ].contains(status);
  factory DeploymentJob.fromJson(Map<String, dynamic> json) => DeploymentJob(
        id: json['id'].toString(),
        artifactId: json['artifact_id'].toString(),
        operation: '${json['operation'] ?? ''}',
        status: '${json['status'] ?? ''}',
        phase: '${json['phase'] ?? ''}',
        createdAt: json['created_at'] as String?,
        startedAt: json['started_at'] as String?,
        finishedAt: json['finished_at'] as String?,
        errorCode: json['error_code'] as String?,
        version: json['version']?.toString(),
        buildNumber: json['build_number']?.toString(),
        components: _components(json['components']),
        events: (json['events'] as List? ?? [])
            .map((e) =>
                DeploymentEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class DeploymentPage<T> {
  final List<T> items;
  final int total;
  const DeploymentPage(this.items, this.total);
}

class DeploymentActive {
  final DeploymentJob? job;
  final DeploymentArtifact? release;
  const DeploymentActive({this.job, this.release});
  factory DeploymentActive.fromJson(Map<String, dynamic> json) =>
      DeploymentActive(
        job: json['job'] == null
            ? null
            : DeploymentJob.fromJson(
                Map<String, dynamic>.from(json['job'] as Map)),
        release: json['release'] == null
            ? null
            : DeploymentArtifact.fromJson(
                Map<String, dynamic>.from(json['release'] as Map)),
      );
}
