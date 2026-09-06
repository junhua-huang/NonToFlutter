class AppUpdateInfo {
  const AppUpdateInfo({
    required this.platform,
    required this.channel,
    required this.releaseId,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.minimumSupportedBuildNumber,
    required this.updateAvailable,
    required this.forceUpdate,
    required this.updateAction,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.sha256,
    required this.fileSize,
  });

  final String platform;
  final String channel;
  final int? releaseId;
  final String? latestVersion;
  final int? latestBuildNumber;
  final int? minimumSupportedBuildNumber;
  final bool updateAvailable;
  final bool forceUpdate;
  final String? updateAction;
  final String? downloadUrl;
  final List<String> releaseNotes;
  final DateTime? publishedAt;
  final String? sha256;
  final int? fileSize;

  static const none = AppUpdateInfo(
    platform: 'unknown',
    channel: 'stable',
    releaseId: null,
    latestVersion: null,
    latestBuildNumber: null,
    minimumSupportedBuildNumber: null,
    updateAvailable: false,
    forceUpdate: false,
    updateAction: null,
    downloadUrl: null,
    releaseNotes: <String>[],
    publishedAt: null,
    sha256: null,
    fileSize: null,
  );

  bool get isOptional => updateAvailable && !forceUpdate;
  bool get isRequired => updateAvailable && forceUpdate;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    if (json['update_available'] is! bool) {
      throw const FormatException('update_available must be a boolean');
    }

    String? stringValue(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    int? intValue(String key) {
      final value = json[key];
      return value is int
          ? value
          : value is num
              ? value.toInt()
              : null;
    }

    final notes = json['release_notes'];
    final releaseNotes = notes is List
        ? notes
            .whereType<String>()
            .map((note) => note.trim())
            .where((note) => note.isNotEmpty)
            .toList()
        : <String>[];
    final updateAvailable = json['update_available'] == true;
    final forceUpdate = updateAvailable && json['force_update'] == true;
    final published = stringValue('published_at');

    return AppUpdateInfo(
      platform: stringValue('platform') ?? 'unknown',
      channel: stringValue('channel') ?? 'stable',
      releaseId: intValue('release_id'),
      latestVersion: stringValue('latest_version'),
      latestBuildNumber: intValue('latest_build_number'),
      minimumSupportedBuildNumber: intValue('minimum_supported_build_number'),
      updateAvailable: updateAvailable,
      forceUpdate: forceUpdate,
      updateAction: stringValue('update_action'),
      downloadUrl: stringValue('download_url'),
      releaseNotes: List.unmodifiable(releaseNotes),
      publishedAt: published == null ? null : DateTime.tryParse(published),
      sha256: stringValue('sha256'),
      fileSize: intValue('file_size'),
    );
  }
}
