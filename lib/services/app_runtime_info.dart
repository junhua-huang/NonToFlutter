import 'package:package_info_plus/package_info_plus.dart';

/// Runtime application identity shared by version display, telemetry and updates.
class AppRuntimeInfo {
  const AppRuntimeInfo({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;

  static AppRuntimeInfo current = const AppRuntimeInfo(
    version: '1.0.1',
    buildNumber: 2,
  );

  static Future<AppRuntimeInfo> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final buildNumber = int.tryParse(info.buildNumber) ?? current.buildNumber;
      current = AppRuntimeInfo(
        version: info.version.trim().isEmpty ? current.version : info.version,
        buildNumber: buildNumber,
      );
    } catch (_) {
      // Package metadata is unavailable in a few test/sandbox environments.
    }
    return current;
  }

  String get label => '$version ($buildNumber)';
}
