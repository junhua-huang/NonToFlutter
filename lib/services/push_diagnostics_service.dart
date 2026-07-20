import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:nonto/services/aliyun_push_service.dart';
import 'package:nonto/services/local_notification_service.dart';
import 'package:nonto/services/websocket_service.dart';

/// Read-only diagnostics for vendor push, Android notification health, and the
/// foreground-only Flutter WebSocket.
class PushDiagnosticsService {
  PushDiagnosticsService._();
  static final PushDiagnosticsService _instance = PushDiagnosticsService._();
  factory PushDiagnosticsService() => _instance;

  static const MethodChannel _huaweiPushChannel =
      MethodChannel('nonto/huawei_push_diagnostics');

  static const _deviceKeys = <String>{
    'packageName',
    'versionName',
    'versionCode',
    'signatureSha256',
    'manufacturer',
    'model',
    'sdkInt',
    'notificationsEnabled',
    'postNotificationsGranted',
    'notificationChannelId',
    'notificationChannelImportance',
    'huawei_app_id_configured',
  };
  static const _aliyunPushKeys = <String>{
    'supported',
    'initialized',
    'aliyun_push_initialized',
    'aliyun_push_init_at',
    'aliyun_push_init_code',
    'aliyun_push_init_error',
    'aliyun_push_third_init_at',
    'aliyun_push_third_init_code',
    'aliyun_push_third_init_error',
    'aliyun_push_device_id',
    'aliyun_push_backend_bind_status',
    'aliyun_push_backend_bind_at',
    'aliyun_push_backend_bind_error',
    'aliyun_push_backend_unbind_at',
    'aliyun_push_backend_unbind_error',
    'aliyun_push_backend_state_status',
    'aliyun_push_backend_state_at',
    'aliyun_push_backend_state_error',
    'aliyun_push_huawei_configured',
    'aliyun_push_oppo_configured',
    'aliyun_push_vivo_configured',
    'aliyun_push_last_callback_type',
    'aliyun_push_last_callback_at',
    'aliyun_push_last_error',
    'aliyun_push_debug_error',
  };
  static const _webSocketKeys = <String>{
    'isConnected',
    'isAppInForeground',
    'ws_last_event',
    'ws_last_event_at',
    'ws_last_seq',
    'ws_is_app_in_foreground',
    'ws_is_connected',
    'ws_last_notification_decision',
    'ws_diagnostic_error',
  };

  Future<Map<String, dynamic>> collect() async {
    final aliyunPush = await AliyunPushService().debugSnapshot();
    final webSocket = await WebSocketService().debugSnapshot();
    final result = <String, dynamic>{
      'collectedAt': DateTime.now().toIso8601String(),
      'device': <String, dynamic>{},
      'localNotification': await LocalNotificationService().debugSnapshot(),
      'aliyunPush': <String, dynamic>{},
      'huaweiVendor': <String, dynamic>{},
      'aliyunNative': <String, dynamic>{},
      'webSocket': <String, dynamic>{},
    };
    result['aliyunPush'] =
        _select(aliyunPush, (key) => _aliyunPushKeys.contains(key));
    result['webSocket'] =
        _select(webSocket, (key) => _webSocketKeys.contains(key));

    if (kIsWeb || !Platform.isAndroid) {
      final skipped = <String, dynamic>{
        'skipped': true,
        'reason': 'Android diagnostics are unavailable on this platform',
      };
      result['device'] = skipped;
      result['huaweiVendor'] = skipped;
      result['aliyunNative'] = skipped;
      return result;
    }

    try {
      final snapshot = await _huaweiPushChannel
              .invokeMapMethod<String, dynamic>('getHuaweiPushDiagnostics')
              .timeout(const Duration(seconds: 5)) ??
          <String, dynamic>{};
      result['device'] = _select(snapshot, (key) => _deviceKeys.contains(key));
      result['huaweiVendor'] =
          _select(snapshot, (key) => key.startsWith('huawei_vendor_'));
      result['aliyunNative'] =
          _select(snapshot, (key) => key.startsWith('aliyun_native_'));
    } catch (e) {
      result['device'] = <String, dynamic>{'nativeError': e.toString()};
    }
    return result;
  }

  Map<String, dynamic> _select(
    Map<String, dynamic> source,
    bool Function(String key) include,
  ) {
    return Map<String, dynamic>.fromEntries(
      source.entries.where((entry) => include(entry.key)),
    );
  }

  String format(Map<String, dynamic> diagnostics) {
    final buffer = StringBuffer()
      ..writeln('南图推送诊断')
      ..writeln('============')
      ..writeln('采集时间: ${diagnostics['collectedAt'] ?? ''}')
      ..writeln();

    final device = diagnostics['device'];
    if (device is Map) {
      buffer
        ..writeln('[设备与通知]')
        ..writeln('packageName: ${device['packageName'] ?? ''}')
        ..writeln('versionName: ${device['versionName'] ?? ''}')
        ..writeln('versionCode: ${device['versionCode'] ?? ''}')
        ..writeln('签名 SHA-256: ${device['signatureSha256'] ?? ''}')
        ..writeln('manufacturer: ${device['manufacturer'] ?? ''}')
        ..writeln('model: ${device['model'] ?? ''}')
        ..writeln('sdkInt: ${device['sdkInt'] ?? ''}')
        ..writeln(
          'notificationsEnabled: ${device['notificationsEnabled'] ?? ''}',
        )
        ..writeln(
          'postNotificationsGranted: ${device['postNotificationsGranted'] ?? ''}',
        )
        ..writeln(
          'notificationChannelId: ${device['notificationChannelId'] ?? ''}',
        )
        ..writeln(
          'notificationChannelImportance: ${device['notificationChannelImportance'] ?? ''}',
        )
        ..writeln(
          'Huawei configured: ${device['huawei_app_id_configured'] ?? ''}',
        )
        ..writeln('nativeError: ${device['nativeError'] ?? ''}')
        ..writeln();
    }

    final aliyunPush = diagnostics['aliyunPush'];
    if (aliyunPush is Map) {
      buffer
        ..writeln('[阿里云推送]')
        ..writeln('supported: ${aliyunPush['supported'] ?? ''}')
        ..writeln('initialized: ${aliyunPush['initialized'] ?? ''}')
        ..writeln(
          'stored initialized: ${aliyunPush['aliyun_push_initialized'] ?? ''}',
        )
        ..writeln('init at: ${aliyunPush['aliyun_push_init_at'] ?? ''}')
        ..writeln('init code: ${aliyunPush['aliyun_push_init_code'] ?? ''}')
        ..writeln('init error: ${aliyunPush['aliyun_push_init_error'] ?? ''}')
        ..writeln(
          'third init at: ${aliyunPush['aliyun_push_third_init_at'] ?? ''}',
        )
        ..writeln(
          'third init code: ${aliyunPush['aliyun_push_third_init_code'] ?? ''}',
        )
        ..writeln(
          'third init error: ${aliyunPush['aliyun_push_third_init_error'] ?? ''}',
        )
        ..writeln('device id: ${aliyunPush['aliyun_push_device_id'] ?? ''}')
        ..writeln(
          'backend bind status: ${aliyunPush['aliyun_push_backend_bind_status'] ?? ''}',
        )
        ..writeln(
          'backend bind at: ${aliyunPush['aliyun_push_backend_bind_at'] ?? ''}',
        )
        ..writeln(
          'backend bind error: ${aliyunPush['aliyun_push_backend_bind_error'] ?? ''}',
        )
        ..writeln(
          'backend state: ${aliyunPush['aliyun_push_backend_state_status'] ?? ''}',
        )
        ..writeln(
          'last callback type: ${aliyunPush['aliyun_push_last_callback_type'] ?? ''}',
        )
        ..writeln(
          'last callback at: ${aliyunPush['aliyun_push_last_callback_at'] ?? ''}',
        )
        ..writeln('last error: ${aliyunPush['aliyun_push_last_error'] ?? ''}')
        ..writeln();
    }

    final huaweiVendor = diagnostics['huaweiVendor'];
    if (huaweiVendor is Map) {
      buffer
        ..writeln('[华为厂商推送]')
        ..writeln(
          'last event: ${huaweiVendor['huawei_vendor_last_event'] ?? ''}',
        )
        ..writeln(
          'last event at: ${huaweiVendor['huawei_vendor_last_event_at'] ?? ''}',
        )
        ..writeln();
    }

    final aliyunNative = diagnostics['aliyunNative'];
    if (aliyunNative is Map) {
      buffer
        ..writeln('[阿里云原生回调]')
        ..writeln(
          'last callback: ${aliyunNative['aliyun_native_last_callback'] ?? ''}',
        )
        ..writeln(
          'last callback at: ${aliyunNative['aliyun_native_last_callback_at'] ?? ''}',
        )
        ..writeln(
          'last display decision: ${aliyunNative['aliyun_native_last_display_decision'] ?? ''}',
        )
        ..writeln(
          'last display decision at: ${aliyunNative['aliyun_native_last_display_decision_at'] ?? ''}',
        )
        ..writeln();
    }

    final webSocket = diagnostics['webSocket'];
    if (webSocket is Map) {
      buffer
        ..writeln('[Flutter WebSocket（仅前台）]')
        ..writeln('isConnected: ${webSocket['isConnected'] ?? ''}')
        ..writeln(
          'isAppInForeground: ${webSocket['isAppInForeground'] ?? ''}',
        )
        ..writeln('last event: ${webSocket['ws_last_event'] ?? ''}')
        ..writeln('last event at: ${webSocket['ws_last_event_at'] ?? ''}')
        ..writeln('last seq: ${webSocket['ws_last_seq'] ?? ''}')
        ..writeln(
          'foreground flag: ${webSocket['ws_is_app_in_foreground'] ?? ''}',
        )
        ..writeln(
          'connected flag: ${webSocket['ws_is_connected'] ?? ''}',
        )
        ..writeln(
          'last alert decision: ${webSocket['ws_last_notification_decision'] ?? ''}',
        )
        ..writeln();
    }

    final localNotification = diagnostics['localNotification'];
    if (localNotification is Map) {
      buffer
        ..writeln('[通知权限测试]')
        ..writeln('supported: ${localNotification['supported'] ?? ''}')
        ..writeln('initialized: ${localNotification['initialized'] ?? ''}')
        ..writeln(
          'init at: ${localNotification['local_notification_last_init_at'] ?? ''}',
        )
        ..writeln(
          'attempt at: ${localNotification['local_notification_last_attempt_at'] ?? ''}',
        )
        ..writeln(
          'attempt type: ${localNotification['local_notification_last_attempt_type'] ?? ''}',
        )
        ..writeln(
          'success at: ${localNotification['local_notification_last_success_at'] ?? ''}',
        )
        ..writeln(
          'error: ${localNotification['local_notification_last_error'] ?? ''}',
        );
    }

    return buffer.toString();
  }
}
