import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String relativePath) =>
      File(relativePath).readAsStringSync().replaceAll('\r\n', '\n');

  group('Android push contracts', () {
    test('app and vendor push share the high-visibility message channel', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final activity = read(
        'android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt',
      );
      final receiver = read(
        'android/app/src/main/kotlin/com/nonto/nonto/'
        'NontoAliyunPushMessageReceiver.kt',
      );
      final localNotification =
          read('lib/services/local_notification_service.dart');

      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(
        manifest,
        contains(
          'com.huawei.hms.client.channel.androidNotificationChannelId',
        ),
      );
      expect(manifest, contains('android:value="nonto_message_alerts"'));

      expect(activity, contains('messageNotificationChannelId'));
      expect(activity, contains('nonto_message_alerts'));
      expect(activity, contains('NotificationManager.IMPORTANCE_HIGH'));
      expect(activity, contains('createMessageNotificationChannel'));

      expect(receiver, contains('hookNotificationBuild'));
      expect(receiver, contains('nonto_message_alerts'));
      expect(receiver, contains('NotificationCompat.PRIORITY_HIGH'));

      expect(localNotification, contains('showTestNotification'));
      expect(localNotification, contains('nonto_message_alerts'));
      expect(localNotification, contains('Importance.high'));
      expect(localNotification, contains('Priority.high'));
    });

    test('manifest registers the custom Aliyun receiver and vendor actions',
        () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final receiver = read(
        'android/app/src/main/kotlin/com/nonto/nonto/'
        'NontoAliyunPushMessageReceiver.kt',
      );
      final huaweiService = read(
        'android/app/src/main/kotlin/com/nonto/nonto/'
        'HuaweiPushDiagnosticsService.kt',
      );

      expect(
          manifest, contains('android:name=".NontoAliyunPushMessageReceiver"'));
      expect(
        manifest,
        contains('com.alibaba.push2.action.NOTIFICATION_OPENED'),
      );
      expect(
        manifest,
        contains('com.alibaba.push2.action.NOTIFICATION_REMOVED'),
      );
      expect(manifest, contains('com.alibaba.sdk.android.push.RECEIVE'));
      expect(
          manifest, contains('android:name=".HuaweiPushDiagnosticsService"'));
      expect(manifest, contains('com.huawei.push.action.MESSAGING_EVENT'));

      expect(receiver, contains('class NontoAliyunPushMessageReceiver'));
      expect(receiver, contains('override fun onNotificationOpened'));
      expect(
          receiver, contains('override fun onNotificationClickedWithNoAction'));
      expect(huaweiService, contains('class HuaweiPushDiagnosticsService'));
    });
  });
}
