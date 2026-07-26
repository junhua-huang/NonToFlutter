import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('splash startup contracts', () {
    test('logged-in startup only waits for HTTP token validation', () {
      final source = read('lib/screens/splash/splash_screen.dart');
      final validBranchStart = source.indexOf('if (valid) {');
      final validBranchEnd = source.indexOf('} else {', validBranchStart);
      final validBranch = source.substring(validBranchStart, validBranchEnd);

      expect(source,
          contains('void _startLoggedInBackgroundServices(String userId)'));
      expect(source, contains('unawaited(DataLayer().initDb(userId)'));
      expect(source, contains('unawaited(_connectWebSocketInBackground())'));
      expect(source, contains('unawaited(_warmHomeProvidersInBackground())'));
      expect(validBranch, contains('_startLoggedInBackgroundServices'));
      expect(validBranch, contains('_checkCookieAndGo(true)'));
      expect(validBranch, isNot(contains('await _verifyWsConnection()')));
      expect(validBranch, isNot(contains('await _controller.forward()')));
      expect(validBranch, isNot(contains('DataLayer().initDb(userId)')));
    });

    test('provider warmup is background-only and not part of navigation gate',
        () {
      final source = read('lib/screens/splash/splash_screen.dart');
      final validateStart =
          source.indexOf('Future<void> _validateAndNavigate()');
      final validateEnd =
          source.indexOf('/// 发一个 /auth/profile', validateStart);
      final validateBody = source.substring(validateStart, validateEnd);

      expect(source,
          contains('Future<void> _warmHomeProvidersInBackground() async'));
      expect(source, contains('ref.invalidate(feedProvider)'));
      expect(source, contains('ref.read(feedProvider)'));
      expect(validateBody, isNot(contains('_prewarmProviders()')));
      expect(validateBody, isNot(contains('ref.read(exploreProvider)')));
      expect(validateBody, isNot(contains('ref.read(conversationsProvider)')));
      expect(validateBody, isNot(contains('ref.read(notificationsProvider)')));
    });
  });
}
