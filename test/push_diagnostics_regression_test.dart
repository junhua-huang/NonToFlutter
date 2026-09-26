import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) => File('$projectRoot/$relativePath')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('push diagnostics', () {
    test('Dart diagnostics report vendor push and foreground Flutter WS only',
        () {
      final source = read('lib/services/push_diagnostics_service.dart');

      expect(source, contains('class PushDiagnosticsService'));
      expect(
          source, contains("MethodChannel('nonto/huawei_push_diagnostics')"));
      expect(source, contains('AliyunPushService().debugSnapshot()'));
      expect(source, contains('WebSocketService().debugSnapshot()'));
      expect(source, contains('LocalNotificationService().debugSnapshot()'));
      expect(source, contains('_aliyunPushKeys'));
      expect(source, contains('_webSocketKeys'));
      final compact = source.replaceAll(RegExp(r'\s+'), '');
      expect(compact, contains("result['aliyunPush']=_select("));
      expect(compact, contains("result['webSocket']=_select("));
      expect(source, isNot(contains('nonto/native_ws_diagnostics')));
      expect(source, isNot(contains('getNativeWsDiagnostics')));
      expect(source, isNot(contains('foregroundService')));
      expect(source, isNot(contains('native_ws_')));
      expect(source, isNot(contains('Native WebSocket')));
    });

    test('formatted diagnostics retain safe delivery health without content',
        () {
      final source = read('lib/services/push_diagnostics_service.dart');

      for (final requiredField in <String>[
        'packageName',
        'versionName',
        'versionCode',
        'signatureSha256',
        'notificationsEnabled',
        'postNotificationsGranted',
        'notificationChannelId',
        'notificationChannelImportance',
        'aliyun_push_initialized',
        'aliyun_push_device_id',
        'aliyun_push_backend_bind_status',
        'huawei_vendor_last_event',
        'aliyun_native_last_callback',
        'isConnected',
        'isAppInForeground',
      ]) {
        expect(source, contains(requiredField),
            reason: 'missing $requiredField');
      }

      for (final sensitiveField in <String>[
        'last payload',
        'payload summary',
        'local title',
        'local body',
        'local payload',
        'Huawei raw token',
        'token by app id',
        'token by sender id',
        'Huawei vendor title',
        'Huawei vendor body',
        'Huawei vendor data',
        'Aliyun native title',
        'Aliyun native summary',
        'Aliyun native content',
        'Aliyun native extra',
        'ws_last_payload_summary',
      ]) {
        expect(
          source,
          isNot(contains(sensitiveField)),
          reason: 'diagnostics expose content: $sensitiveField',
        );
      }
    });

    test('runtime diagnostics persist metadata only, never business payloads',
        () {
      final aliyun = read('lib/services/aliyun_push_service.dart');
      final websocket = read('lib/services/websocket_service.dart');

      expect(aliyun, isNot(contains("'aliyun_push_last_payload_summary':")));
      expect(aliyun, isNot(contains('_limit(message.toString())')));
      expect(websocket, isNot(contains("'ws_last_payload_summary':")));
      expect(websocket, isNot(contains('_payloadSummary(payload)')));
      expect(websocket,
          isNot(contains("'ws_last_local_notification_trigger_at':")));
      expect(websocket,
          isNot(contains("'ws_last_local_notification_trigger_type':")));
      expect(
          aliyun, contains("prefs.remove('aliyun_push_last_payload_summary')"));
      expect(websocket, contains("prefs.remove('ws_last_payload_summary')"));
    });

    test('diagnostics screen describes real foreground and vendor push roles',
        () {
      final source = read('lib/screens/profile/push_diagnostics_screen.dart');

      expect(source, contains('推送诊断'));
      expect(source, contains('设备与通知'));
      expect(source, contains('阿里云推送'));
      expect(source, contains('华为厂商推送'));
      expect(source, contains('阿里云原生回调'));
      expect(source, contains('Flutter WebSocket（仅前台）'));
      expect(source, contains('后台或被结束后由厂商推送送达'));
      expect(source, contains('发送通知测试'));
      expect(source, contains('刷新诊断'));
      expect(source, contains('复制诊断信息'));
      expect(source, isNot(contains('Native WebSocket')));
      expect(source, isNot(contains('后台消息服务')));
      expect(source, isNot(contains('service running')));
      expect(source, isNot(contains('native ws')));
      expect(source, isNot(contains('payload')));
      expect(source, isNot(contains('raw token')));
    });

    test('Android bridge exposes safe app and notification channel health', () {
      final source =
          read('android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt');

      expect(source, contains('nonto/huawei_push_diagnostics'));
      expect(source, contains('getHuaweiPushDiagnostics'));
      expect(source, contains('packageName'));
      expect(source, contains('versionName'));
      expect(source, contains('versionCode'));
      expect(source, contains('signatureSha256'));
      expect(source, contains('notificationsEnabled'));
      expect(source, contains('postNotificationsGranted'));
      expect(source, contains('notificationChannelId'));
      expect(source, contains('notificationChannelImportance'));
      expect(source, contains('nonto_message_alerts'));
      expect(source, contains('HuaweiPushDiagnosticsStore.snapshot'));
      expect(source, contains('AliyunNativePushDiagnosticsStore.snapshot'));
      expect(source, isNot(contains('HmsInstanceId')));
      expect(source, isNot(contains('huawei_raw_token')));
      expect(source, isNot(contains('huawei_token_by_')));
      expect(source, isNot(contains('nonto/native_ws_diagnostics')));
    });

    test('native callback diagnostics never persist message content or tokens',
        () {
      final store = read(
        'android/app/src/main/kotlin/com/nonto/nonto/NativePushDiagnosticsStore.kt',
      );
      final aliyunReceiver = read(
        'android/app/src/main/kotlin/com/nonto/nonto/NontoAliyunPushMessageReceiver.kt',
      );
      final huaweiReceiver = read(
        'android/app/src/main/kotlin/com/nonto/nonto/HuaweiPushDiagnosticsService.kt',
      );

      for (final forbidden in <String>[
        'vendor_token',
        'vendor_data',
        'vendor_title',
        'vendor_body',
        'native_title',
        'native_summary',
        'native_content',
        'native_extra',
        'raw_token',
      ]) {
        expect(store, isNot(contains(forbidden)), reason: 'stored $forbidden');
      }
      expect(
        aliyunReceiver,
        contains(
          'AliyunNativePushDiagnosticsStore.record(context, "onNotification")',
        ),
      );
      expect(
        aliyunReceiver,
        contains(
            'AliyunNativePushDiagnosticsStore.record(context, "onMessage")'),
      );
      expect(
          aliyunReceiver,
          isNot(contains(
              'record(\n            context,\n            "onMessage",')));
      expect(huaweiReceiver, isNot(contains('"token" to')));
      expect(huaweiReceiver, isNot(contains('"data" to')));
      expect(huaweiReceiver, isNot(contains('"title" to')));
      expect(huaweiReceiver, isNot(contains('"body" to')));
    });
  });
}
