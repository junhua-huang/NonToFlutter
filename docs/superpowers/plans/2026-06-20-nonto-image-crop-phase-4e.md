# Nonto Image Crop Phase 4E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the profile image crop screen so avatar/cover cropping stays lightweight while the touched file is analyzer-clean.

**Architecture:** Keep the existing single-screen crop architecture and gesture model. Replace source-health problem patterns in place: use Flutter-owned matrix helpers, remove deprecated transform calls and redundant null assertions, and guard post-async navigation with `context.mounted`.

**Tech Stack:** Flutter, Dart, `flutter_test`, source-regression tests.

---

## File Structure

- Create: `test/nonto_image_crop_phase4e_regression_test.dart`
  - Source regression coverage for crop-screen wording, matrix APIs, async navigation guard, and null-safety cleanup.
- Modify: `lib/screens/profile/image_crop_screen.dart`
  - Preserve crop behavior and gesture structure.
  - Remove direct `vector_math` import.
  - Replace `_toChild` implementation with `MatrixUtils.transformPoint`.
  - Replace deprecated `Matrix4.translate` / `Matrix4.scale` calls.
  - Remove analyzer-reported unnecessary `!` operators.
  - Use `context.mounted` before popping after `_doCrop()`.

Do not commit unless the user explicitly asks.

---

### Task 1: Add RED source regression coverage

**Files:**
- Create: `test/nonto_image_crop_phase4e_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_image_crop_phase4e_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4E image crop source regressions', () {
    test('crop screen uses Nonto-owned wording and keeps lightweight gestures', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(source, contains('Nonto 图片裁剪页'));
      expect(source, contains('拖动裁剪框 / 拖拽四角调整 / 双指缩放图片'));
      expect(source, contains('GestureDetector'));
      expect(source, contains('_buildCornerHandles'));
    });

    test('crop screen avoids undeclared vector_math dependency', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(source, isNot(contains('package:vector_math/vector_math_64.dart')));
      expect(source, contains('MatrixUtils.transformPoint'));
      expect(source, isNot(contains('transform3(Vector3')));
    });

    test('crop screen uses non-deprecated typed Matrix4 transforms', () {
      final source = read('lib/screens/profile/image_crop_screen.dart');

      expect(source, contains('translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)'));
      expect(source, contains('scaleByDouble(_imageScale, _imageScale, 1, 1)'));
      expect(source, isNot(contains('..translate(_imageOffset.dx, _imageOffset.dy)')));
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
      expect(source, isNot(contains('maxPx! - minPx!')));
      expect(source, isNot(contains('maxPy! - minPy!')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_image_crop_phase4e_regression_test.dart
```

Expected: FAIL because the crop screen still uses the older comment, direct `vector_math` import, deprecated matrix calls, `if (mounted) Navigator...`, and redundant null-assertion patterns.

---

### Task 2: Clean up `image_crop_screen.dart`

**Files:**
- Modify: `lib/screens/profile/image_crop_screen.dart`
- Test: `test/nonto_image_crop_phase4e_regression_test.dart`

- [ ] **Step 1: Update import and screen comment**

Change the top of `lib/screens/profile/image_crop_screen.dart` from:

```dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
```

to:

```dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
```

Change the class comment from:

```dart
/// Web 兼容的图片裁剪页面
```

to:

```dart
/// Nonto 图片裁剪页：头像与封面编辑时使用的轻量裁剪入口。
```

- [ ] **Step 2: Replace direct vector transform usage**

Change `_toChild` from:

```dart
Offset _toChild(Offset screenPoint, Matrix4 inverseMatrix) {
  final v =
      inverseMatrix.transform3(Vector3(screenPoint.dx, screenPoint.dy, 0));
  return Offset(v.x, v.y);
}
```

to:

```dart
Offset _toChild(Offset screenPoint, Matrix4 inverseMatrix) =>
    MatrixUtils.transformPoint(inverseMatrix, screenPoint);
```

- [ ] **Step 3: Replace deprecated Matrix4 transform calls**

Change both matrix construction sites from:

```dart
final matrix = Matrix4.identity()
  ..translate(_imageOffset.dx, _imageOffset.dy)
  ..scale(_imageScale);
```

and:

```dart
final imgMatrix = Matrix4.identity()
  ..translate(_imageOffset.dx, _imageOffset.dy)
  ..scale(_imageScale);
```

to:

```dart
final matrix = Matrix4.identity()
  ..translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)
  ..scaleByDouble(_imageScale, _imageScale, 1, 1);
```

and:

```dart
final imgMatrix = Matrix4.identity()
  ..translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)
  ..scaleByDouble(_imageScale, _imageScale, 1, 1);
```

- [ ] **Step 4: Remove redundant null assertions in crop math**

In `_cropCircle`, after `if (minPx == null) return null;`, change:

```dart
final srcW = maxPx! - minPx!;
final srcH = maxPy! - minPy!;
final srcSize = max(srcW, srcH);
final cx = (minPx! + maxPx!) / 2;
final cy = (minPy! + maxPy!) / 2;
```

to:

```dart
final srcW = maxPx - minPx;
final srcH = maxPy - minPy;
final srcSize = max(srcW, srcH);
final cx = (minPx + maxPx) / 2;
final cy = (minPy + maxPy) / 2;
```

In `_cropRectangle`, after `if (minPx == null) return null;`, change:

```dart
final srcLeft =
    minPx!.clamp(0, _image!.width.toDouble() - 1).toDouble();
final srcTop =
    minPy!.clamp(0, _image!.height.toDouble() - 1).toDouble();
final srcW = (maxPx! - minPx!)
    .clamp(1, _image!.width.toDouble() - srcLeft)
    .toDouble();
final srcH = (maxPy! - minPy!)
    .clamp(1, _image!.height.toDouble() - srcTop)
    .toDouble();
```

to:

```dart
final srcLeft = minPx.clamp(0, _image!.width.toDouble() - 1).toDouble();
final srcTop = minPy.clamp(0, _image!.height.toDouble() - 1).toDouble();
final srcW = (maxPx - minPx)
    .clamp(1, _image!.width.toDouble() - srcLeft)
    .toDouble();
final srcH = (maxPy - minPy)
    .clamp(1, _image!.height.toDouble() - srcTop)
    .toDouble();
```

- [ ] **Step 5: Guard post-async navigation with `context.mounted`**

Change the confirm button handler from:

```dart
onPressed: () async {
  final result = await _doCrop();
  if (mounted) Navigator.of(context).pop(result);
},
```

to:

```dart
onPressed: () async {
  final result = await _doCrop();
  if (!context.mounted) return;
  Navigator.of(context).pop(result);
},
```

- [ ] **Step 6: Run test to verify it passes**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_image_crop_phase4e_regression_test.dart
```

Expected: PASS.

---

### Task 3: Verify analyzer and adjacent profile coverage

**Files:**
- Verify: `lib/screens/profile/image_crop_screen.dart`
- Verify: `test/nonto_image_crop_phase4e_regression_test.dart`

- [ ] **Step 1: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/profile/image_crop_screen.dart test/nonto_image_crop_phase4e_regression_test.dart
```

Expected: `No issues found!`

- [ ] **Step 2: Run adjacent profile tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart test/nonto_edit_profile_phase4d_regression_test.dart test/nonto_image_crop_phase4e_regression_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run full test suite**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: all tests pass.

- [ ] **Step 4: Run full analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: may still fail on historical project-wide issues. Record the issue count honestly.

---

## Self-Review

- Spec coverage: plan covers all Phase 4E goals: source regression test, vector import removal, typed Matrix4 APIs, null assertion cleanup, async context guard, targeted/full verification.
- Placeholder scan: no placeholders or unresolved TODOs.
- Type consistency: all referenced methods and paths match the current Flutter/Dart source shape.