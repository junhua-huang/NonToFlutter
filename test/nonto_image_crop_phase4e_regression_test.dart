import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4E image crop source regressions', () {
    test('crop screen uses Nonto-owned wording and keeps lightweight gestures',
        () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(source, contains('Nonto 图片裁剪页'));
      expect(source, contains('拖动裁剪框 / 拖拽四角调整 / 双指缩放图片'));
      expect(source, contains('GestureDetector'));
      expect(source, contains('_buildCornerHandles'));
    });

    test('crop screen avoids undeclared vector_math dependency', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(
          source, isNot(contains('package:vector_math/vector_math_64.dart')));
      expect(source, contains('MatrixUtils.transformPoint'));
      expect(source, isNot(contains('transform3(Vector3')));
    });

    test('crop screen uses non-deprecated typed Matrix4 transforms', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(
        source,
        contains('translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)'),
      );
      expect(source, contains('scaleByDouble(_imageScale, _imageScale, 1, 1)'));
      expect(
        source,
        isNot(contains('..translate(_imageOffset.dx, _imageOffset.dy)')),
      );
      expect(source, isNot(contains('..scale(_imageScale)')));
    });

    test('crop completion guards context after async crop work', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(source, contains('final result = await _doCrop();'));
      expect(source, contains('if (!context.mounted) return;'));
      expect(source, contains('Navigator.of(context).pop(result);'));
    });

    test('crop math removes known redundant null assertions', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(source, isNot(contains('maxPx! - minPx!')));
      expect(source, isNot(contains('minPx! + maxPx!')));
      expect(source, isNot(contains('minPy! + maxPy!')));
      expect(source, isNot(contains('minPx!.clamp')));
      expect(source, isNot(contains('maxPy! - minPy!')));
    });
  });
}
