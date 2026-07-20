import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) => File('$projectRoot/$relativePath')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('Aliyun Android vendor push validation', () {
    test('pubspec depends on Aliyun Push and local diagnostics notifications',
        () {
      final pubspec = read('pubspec.yaml');

      expect(pubspec, contains('aliyun_push_flutter'));
      expect(pubspec, contains('flutter_local_notifications'));
      expect(pubspec, isNot(contains('jpush_flutter')));
    });

    test('Gradle injects vendor configuration only through placeholders', () {
      final source = read('android/app/build.gradle.kts');

      for (final placeholder in <String>[
        'ALIYUN_PUSH_APP_KEY',
        'ALIYUN_PUSH_APP_SECRET',
        'HUAWEI_PUSH_APP_ID',
        'OPPO_PUSH_APP_KEY',
        'OPPO_PUSH_APP_SECRET',
        'VIVO_PUSH_APP_ID',
        'VIVO_PUSH_APP_KEY',
      ]) {
        expect(source, contains(placeholder), reason: 'missing $placeholder');
      }
      expect(source, contains('aliyunPushProperty'));
      expect(source, contains('manifestPlaceholders'));
      expect(source, contains('buildConfigField'));
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'''implementation\s*\(\s*["']com\.squareup\.okhttp3:okhttp:''',
            ),
          ),
        ),
      );
      expect(source, isNot(contains('cn.jiguang')));
      expect(source, isNot(contains('JPUSH_APPKEY')));
    });

    test('root Gradle retains required Aliyun and vendor repositories', () {
      final source = read('android/build.gradle.kts');

      expect(
        source,
        contains('maven.aliyun.com/nexus/content/repositories/releases'),
      );
      expect(source, contains('developer.huawei.com/repo'));
      expect(source, contains('developer.hihonor.com/repo'));
    });

    test('manifest uses custom receiver, actions, and vendor placeholders', () {
      final source = read('android/app/src/main/AndroidManifest.xml');

      expect(source, contains('android.permission.POST_NOTIFICATIONS'));
      expect(
          source, contains('android:name=".NontoAliyunPushMessageReceiver"'));
      expect(
        source,
        contains('com.alibaba.push2.action.NOTIFICATION_OPENED'),
      );
      expect(
        source,
        contains('com.alibaba.push2.action.NOTIFICATION_REMOVED'),
      );
      expect(source, contains('com.alibaba.sdk.android.push.RECEIVE'));
      expect(source, contains('com.aliyun.ams.push.PushPopupActivity'));
      expect(source, contains(r'android:value="${ALIYUN_PUSH_APP_KEY}"'));
      expect(source, contains(r'android:value="${ALIYUN_PUSH_APP_SECRET}"'));
      expect(source, contains(r'android:value="${HUAWEI_PUSH_APP_ID}"'));
      expect(source, contains(r'android:value="${OPPO_PUSH_APP_KEY}"'));
      expect(source, contains(r'android:value="${OPPO_PUSH_APP_SECRET}"'));
      expect(source, contains(r'android:value="${VIVO_PUSH_APP_ID}"'));
      expect(source, contains(r'android:value="${VIVO_PUSH_APP_KEY}"'));
      expect(
        source,
        isNot(
          contains(
            'android:name="com.aliyun.ams.push.AliyunPushMessageReceiver"',
          ),
        ),
      );
    });

    test('MainActivity exposes safe vendor configuration and open handling',
        () {
      final source =
          read('android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt');

      expect(source, contains('nonto/aliyun_push_config'));
      expect(source, contains('getAliyunPushConfig'));
      expect(source, contains('BuildConfig.ALIYUN_PUSH_APP_KEY'));
      expect(source, contains('BuildConfig.ALIYUN_PUSH_APP_SECRET'));
      expect(source, contains('override fun shouldHandleDeeplinking'));
      expect(source, contains('return false'));
      expect(source, isNot(contains('JPush')));
    });
  });
}
