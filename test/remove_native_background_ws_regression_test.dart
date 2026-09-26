import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;

  String read(String relativePath) => File('$projectRoot/$relativePath')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('native background WebSocket removal', () {
    test('Flutter foreground service facade is absent', () {
      final service = File(
        '$projectRoot/lib/services/foreground_service_manager.dart',
      );

      expect(service.existsSync(), isFalse);
    });

    test('auth and lifecycle have no native foreground service dependency', () {
      for (final relativePath in <String>[
        'lib/providers/auth_notifier.dart',
        'lib/services/app_lifecycle_keepalive_service.dart',
      ]) {
        final source = read(relativePath);
        expect(source, isNot(contains('foreground_service_manager.dart')));
        expect(source, isNot(contains('ForegroundServiceManager')));
        expect(source, isNot(contains('startMessageKeepAlive')));
        expect(source, isNot(contains('stopMessageKeepAlive')));
        expect(source, isNot(contains('clearNativeState')));
      }
    });

    test('Flutter WebSocket never creates local system notifications', () {
      final webSocket = read('lib/services/websocket_service.dart');
      final localNotification =
          read('lib/services/local_notification_service.dart');

      expect(webSocket, isNot(contains('local_notification_service.dart')));
      expect(webSocket, isNot(contains('LocalNotificationService')));
      expect(webSocket, isNot(contains('showMessageNotification')));
      expect(webSocket, isNot(contains('showInteractionNotification')));
      expect(webSocket, contains('SoundService().playNotificationSound()'));
      expect(webSocket, contains('HapticFeedback.lightImpact()'));
      expect(localNotification, contains('showTestNotification'));
      expect(localNotification, isNot(contains('showMessageNotification')));
      expect(localNotification, isNot(contains('showInteractionNotification')));
      expect(localNotification, contains('用户主动触发'));
      expect(localNotification, isNot(contains('WebSocket 后台消息')));
      expect(localNotification, isNot(contains('前台服务')));
    });

    test('app-owned MessageKeepAliveService source is absent', () {
      final service = File(
        '$projectRoot/android/app/src/main/kotlin/com/nonto/nonto/MessageKeepAliveService.kt',
      );

      expect(service.existsSync(), isFalse);
    });

    test('source manifest removes only the app-owned foreground service', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');

      expect(manifest, isNot(contains('.MessageKeepAliveService')));
      expect(
        manifest,
        isNot(contains('android.permission.FOREGROUND_SERVICE"')),
      );
      expect(
        manifest,
        isNot(contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC')),
      );
      expect(manifest, isNot(contains('nonto_keepalive')));

      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('.NontoAliyunPushMessageReceiver'));
      expect(
        manifest,
        contains('com.alibaba.push2.action.NOTIFICATION_OPENED'),
      );
      expect(
        manifest,
        contains('com.alibaba.push2.action.NOTIFICATION_REMOVED'),
      );
      expect(manifest, contains('com.alibaba.sdk.android.push.RECEIVE'));
      expect(manifest, contains('com.aliyun.ams.push.PushPopupActivity'));
      expect(manifest, contains('com.alibaba.app.appkey'));
      expect(manifest, contains('com.alibaba.app.appsecret'));
      expect(manifest, contains('com.huawei.hms.client.appid'));
      expect(manifest, contains('com.oppo.push.key'));
      expect(manifest, contains('com.oppo.push.secret'));
      expect(manifest, contains('com.vivo.push.app_id'));
      expect(manifest, contains('com.vivo.push.api_key'));
      expect(manifest, contains('.HuaweiPushDiagnosticsService'));
      expect(
        manifest,
        contains('com.huawei.push.action.MESSAGING_EVENT'),
      );
    });

    test('settings and diagnostics remove native keepalive product claims', () {
      for (final relativePath in <String>[
        'lib/screens/profile/settings_screen.dart',
        'lib/screens/profile/background_permission_guide_screen.dart',
        'lib/services/push_diagnostics_service.dart',
        'lib/screens/profile/push_diagnostics_screen.dart',
        'lib/main.dart',
        'lib/services/local_notification_service.dart',
        'pubspec.yaml',
      ]) {
        final source = read(relativePath);
        for (final obsoleteClaim in <String>[
          'foreground_keepalive_enabled',
          '后台消息保活',
          'Native WebSocket',
          'nonto/native_ws_diagnostics',
          'getNativeWsDiagnostics',
          'MessageKeepAliveService',
          'WebSocket 后台消息',
        ]) {
          expect(
            source,
            isNot(contains(obsoleteClaim)),
            reason: '$relativePath retains $obsoleteClaim',
          );
        }
      }
    });

    test('MainActivity removes native WS and foreground-service bridges', () {
      final source = read(
        'android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt',
      );

      for (final obsoleteSymbol in <String>[
        'nonto/foreground_service',
        'nonto/native_ws_diagnostics',
        'startMessageKeepAlive',
        'stopMessageKeepAlive',
        'startForegroundService',
        'MessageKeepAliveService',
        'native_ws_',
        'nativeWsDiagnosticsChannel',
        'foregroundServiceChannel',
        'collectNativeWsDiagnostics',
        'getNativeWsDiagnostics',
        'nonto_keepalive',
      ]) {
        expect(
          source,
          isNot(contains(obsoleteSymbol)),
          reason: 'obsolete native bridge remains: $obsoleteSymbol',
        );
      }

      expect(source, contains('nonto/aliyun_push_config'));
      expect(source, contains('nonto/huawei_push_diagnostics'));
      expect(source, contains('shouldHandleDeeplinking'));
      expect(source, contains('return false'));
      expect(source, contains('nonto_message_alerts'));
      expect(source, contains('createMessageNotificationChannel'));
      expect(source, contains('createNotificationChannel'));
    });

    test('app no longer directly depends on OkHttp', () {
      final gradle = read('android/app/build.gradle.kts');
      final kotlinRoot = Directory(
        '$projectRoot/android/app/src/main/kotlin',
      );
      final kotlinSources = kotlinRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.kt'));

      expect(
        gradle,
        isNot(
          matches(
            RegExp(
              r'''implementation\s*\(\s*["']com\.squareup\.okhttp3:okhttp:''',
            ),
          ),
        ),
      );
      for (final sourceFile in kotlinSources) {
        final source = sourceFile.readAsStringSync();
        expect(source, isNot(matches(RegExp(r'import\s+okhttp3\.'))));
        expect(source, isNot(matches(RegExp(r'import\s+okio\.'))));
      }

      expect(
        gradle,
        contains('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:'),
      );
      expect(gradle, contains('testImplementation("junit:junit:'));
      expect(gradle, contains('manifestPlaceholders'));
      expect(gradle, contains('ALIYUN_PUSH_APP_KEY'));
      expect(gradle, contains('HUAWEI_PUSH_APP_ID'));
      expect(gradle, contains('OPPO_PUSH_APP_KEY'));
      expect(gradle, contains('VIVO_PUSH_APP_ID'));
    });
  });
}
