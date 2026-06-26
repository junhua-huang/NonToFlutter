import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android push contracts', () {
    test('MainActivity creates the JPush manufacturer notification channel', () {
      final source = File(
              'android/app/src/main/kotlin/com/nonto/nonto/MainActivity.kt')
          .readAsStringSync();

      expect(source, contains('nonto_message'));
      expect(source, contains('NotificationChannel'));
      expect(source, contains('createNotificationChannel'));
      expect(source, contains('IMPORTANCE_DEFAULT'));
    });
  });
}
