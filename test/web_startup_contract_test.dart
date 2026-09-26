import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('web startup contracts', () {
    test('index uses one Flutter bootstrap path and keeps overlay fallback',
        () {
      final source = read('web/index.html');

      expect(source, contains('id="loading-overlay"'));
      expect(source, contains('function hideLoading()'));
      expect(source, isNot(contains('数分钟')));
      expect(source, contains('function showLoadingError()'));
      expect(source, contains('flutter_bootstrap.js'));
      expect(source, contains('onerror="showLoadingError()"'));
      expect(source, contains('setTimeout(showLoadingError'));
      expect(source, isNot(contains('loadEntrypoint')));
      expect(source, isNot(contains('_waitCount')));
      expect(source, isNot(contains('setInterval(function()')));
    });

    test('cropper assets are not blocking first paint', () {
      final source = read('web/index.html');
      final head = source.substring(0, source.indexOf('</head>'));

      expect(head, isNot(contains('cropper.min.js')));
      expect(head, isNot(contains('cropper.min.css')));
      expect(source, contains('首屏不预加载裁剪库'));
    });

    test('main starts non-critical services after runApp', () {
      final source = read('lib/main.dart');
      final runAppIndex = source.indexOf('runApp(');
      final postStartupIndex =
          source.indexOf('unawaited(_startPostRunAppServices())');

      expect(source, contains('Future<void> _startPostRunAppServices() async'));
      expect(source, contains('unawaited(_startPostRunAppServices())'));
      expect(postStartupIndex, greaterThan(runAppIndex));
      expect(source, contains('LocalNotificationService().init()'));
      expect(source, contains('AliyunPushService().init()'));
      expect(source, contains('AppLifecycleKeepAliveService().start()'));
    });
  });
}
