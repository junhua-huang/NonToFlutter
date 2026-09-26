import 'package:flutter/foundation.dart';
import 'package:nonto/models/app_update.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/app_runtime_info.dart';

class AppUpdateCheckException implements Exception {
  const AppUpdateCheckException({this.message, this.statusCode});

  final String? message;
  final int? statusCode;

  @override
  String toString() => message ?? 'Unable to check for updates';
}

class AppUpdateService {
  AppUpdateService(
      {ApiClient? api, AppRuntimeInfo? runtimeInfo, String? platform})
      : _api = api ?? ApiClient(),
        _runtimeInfo = runtimeInfo ?? AppRuntimeInfo.current,
        _platformOverride = platform;

  final ApiClient _api;
  final AppRuntimeInfo _runtimeInfo;
  final String? _platformOverride;

  String get platform {
    if (_platformOverride != null) return _platformOverride!;
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      _ => 'web',
    };
  }

  Future<AppUpdateInfo> check({String channel = 'stable'}) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/app/version',
      params: {
        'platform': platform,
        'channel': channel,
        'current_version': _runtimeInfo.version,
        'current_build_number': _runtimeInfo.buildNumber,
      },
    ).timeout(const Duration(seconds: 8));
    if (!response.success) {
      throw AppUpdateCheckException(
        message: response.message,
        statusCode: response.statusCode,
      );
    }
    final data = response.data;
    if (data == null) {
      throw const FormatException('Update response data is missing');
    }
    return AppUpdateInfo.fromJson(data);
  }
}
