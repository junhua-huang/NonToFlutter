import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/config/layout_breakpoints.dart';

void main() {
  group('AppBreakpoints', () {
    test('uses the horizontal shell only for landscape dimensions', () {
      expect(AppBreakpoints.isLandscape(800, 1200), isFalse);
      expect(AppBreakpoints.isLandscape(1200, 800), isTrue);
      expect(AppBreakpoints.isLandscape(799, 900), isFalse);
      expect(AppBreakpoints.isLandscape(900, 500), isTrue);
      expect(AppBreakpoints.isLandscape(500, 500), isFalse);
    });

    test('keeps stable horizontal shell dimensions', () {
      expect(AppBreakpoints.navigationWidth, 224);
      expect(AppBreakpoints.contentMaxWidth, 960);
    });

    test('allows installed Web apps to follow device orientation', () {
      final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;

      expect(manifest['orientation'], 'any');
    });
  });
}
