import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android notification permission and user-triggered diagnostic notification.
///
/// This service does not display WebSocket business events. Background and
/// killed-state delivery is handled by Aliyun and vendor push channels.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService _instance =
      LocalNotificationService._();
  factory LocalNotificationService() => _instance;

  static const _diagnosticKeys = <String>[
    'local_notification_last_init_at',
    'local_notification_last_attempt_at',
    'local_notification_last_attempt_type',
    'local_notification_last_success_at',
    'local_notification_last_error',
  ];

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationId = 2000;

  Future<void> init() async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _initialized = true;
      await _recordDiagnostic({
        'local_notification_last_init_at': DateTime.now().toIso8601String(),
        'local_notification_last_error': '',
      });
    } catch (e) {
      await _recordDiagnostic({
        'local_notification_last_error': 'init_failed: $e',
      });
      debugPrint('[LocalNotification] init failed: $e');
    }
  }

  /// Sends a notification only after the user actively requests a diagnostics
  /// check (用户主动触发); it is never called for message business events.
  Future<bool> showTestNotification() async {
    if (!_initialized) {
      await init();
    }
    if (!_canShow()) {
      await _recordSkipped();
      return false;
    }

    await _recordDiagnostic({
      'local_notification_last_attempt_at': DateTime.now().toIso8601String(),
      'local_notification_last_attempt_type': 'test',
      'local_notification_last_error': '',
    });
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'nonto_message_alerts',
        '南图消息提醒',
        channelDescription: '南图消息与互动提醒',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    try {
      await _plugin.show(
        _notificationId++,
        '南图通知测试',
        '如果你看到这条，说明系统通知权限和通知分类可用',
        details,
      );
      await _recordDiagnostic({
        'local_notification_last_success_at': DateTime.now().toIso8601String(),
        'local_notification_last_error': '',
      });
      return true;
    } catch (e) {
      await _recordDiagnostic({
        'local_notification_last_error': 'show_failed: $e',
      });
      debugPrint('[LocalNotification] test failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> debugSnapshot() async {
    final supported = !kIsWeb && Platform.isAndroid;
    final result = <String, dynamic>{
      'supported': supported,
      'initialized': _initialized,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _diagnosticKeys) {
        result[key] = prefs.getString(key) ?? '';
      }
    } catch (e) {
      result['local_notification_debug_error'] = e.toString();
    }
    return result;
  }

  bool _canShow() => _initialized && !kIsWeb && Platform.isAndroid;

  Future<void> _recordSkipped() async {
    await _recordDiagnostic({
      'local_notification_last_attempt_at': DateTime.now().toIso8601String(),
      'local_notification_last_attempt_type': 'test',
      'local_notification_last_error':
          'skipped: initialized=$_initialized supported=${!kIsWeb && Platform.isAndroid}',
    });
  }

  Future<void> _recordDiagnostic(Map<String, Object?> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in values.entries) {
        final value = entry.value;
        if (value == null) {
          await prefs.remove(entry.key);
        } else {
          await prefs.setString(entry.key, value.toString());
        }
      }
    } catch (e) {
      debugPrint('[LocalNotification] diagnostic write failed: $e');
    }
  }
}
