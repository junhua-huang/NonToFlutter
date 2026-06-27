import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Android vendor push channel configuration', () {
    test('vendor credentials are read from Gradle properties or environment', () {
      final source = read('android/app/build.gradle.kts');

      expect(source, contains('fun gradleOrEnv(name: String): String'));
      expect(
        source,
        contains('providers.gradleProperty(name)\n    .orElse(providers.environmentVariable(name))'),
      );
      for (final key in [
        'HUAWEI_APPID',
        'XIAOMI_APPID',
        'XIAOMI_APPKEY',
        'OPPO_APPID',
        'OPPO_APPKEY',
        'OPPO_APPSECRET',
        'VIVO_APPID',
        'VIVO_APPKEY',
        'MEIZU_APPID',
        'MEIZU_APPKEY',
      ]) {
        expect(source, contains('manifestPlaceholders["$key"] = gradleOrEnv("$key")'));
      }
    });

    test('JPush vendor channel plugin dependencies are packaged into Android app', () {
      final source = read('android/app/build.gradle.kts');

      for (final artifact in [
        'cn.jiguang.sdk.plugin:huawei',
        'cn.jiguang.sdk.plugin:xiaomi',
        'cn.jiguang.sdk.plugin:oppo',
        'cn.jiguang.sdk.plugin:vivo',
        'cn.jiguang.sdk.plugin:meizu',
      ]) {
        expect(source, contains('implementation("$artifact:'));
      }
    });

    test('release build prefers release signing instead of hard-coded debug signing', () {
      final source = read('android/app/build.gradle.kts');
      final releaseStart = source.indexOf('release {');
      final androidEnd = source.indexOf('\n}\n\nflutter {', releaseStart);
      expect(releaseStart, greaterThanOrEqualTo(0));
      expect(androidEnd, greaterThan(releaseStart));
      final releaseSource = source.substring(releaseStart, androidEnd);

      expect(releaseSource, isNot(contains('signingConfig = signingConfigs.getByName("debug")')));
      expect(
        releaseSource,
        contains('signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")'),
      );
    });

    test('MainActivity disables Flutter automatic deep link handling for vendor notification clicks', () {
      final source = read('android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt');

      expect(source, contains('override fun shouldHandleDeeplinking(): Boolean'));
      expect(source, contains('return false'));
    });
  });
}
