import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readSource(String path) => File(path).readAsStringSync();

void main() {
  group('app update release contracts', () {
    test('visible and reported versions use runtime package metadata', () {
      final config = readSource('lib/config/app_config.dart');
      final splash = readSource('lib/screens/splash/splash_screen.dart');
      final settings = readSource('lib/screens/profile/settings_screen.dart');
      final push = readSource('lib/services/aliyun_push_service.dart');

      expect(config, isNot(contains('appVersion')));
      expect(splash, contains('AppRuntimeInfo.current.version'));
      expect(splash, isNot(contains('v0.2.8')));
      expect(settings, contains('AppRuntimeInfo.current.label'));
      expect(settings, contains("title: '检查更新'"));
      expect(push, contains('AppRuntimeInfo.current.version'));
    });

    test('automatic update checking stays outside the splash login gate', () {
      final main = readSource('lib/main.dart');
      final splash = readSource('lib/screens/splash/splash_screen.dart');
      final validateStart =
          splash.indexOf('Future<void> _validateAndNavigate()');
      final validateEnd =
          splash.indexOf('/// 发一个 /auth/profile', validateStart);
      final validateBody = splash.substring(validateStart, validateEnd);

      expect(main, contains('AppUpdateGate('));
      expect(validateBody, isNot(contains('appUpdateProvider')));
      expect(validateBody, isNot(contains('AppUpdateService')));
    });
  });
}
