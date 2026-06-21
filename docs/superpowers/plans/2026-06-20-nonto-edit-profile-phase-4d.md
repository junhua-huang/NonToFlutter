# Nonto Edit Profile Phase 4D Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the edit-profile screen with Nonto-owned wording, responsive inline edit states, and targeted analyzer cleanup.

**Architecture:** Keep the current single `EditProfileScreen` and its direct pick → crop → upload and inline save/cancel flows. Make low-risk source hygiene changes: remove unused imports, rename `_x...` color aliases to Nonto-neutral names, guard crop navigation context usage, and keep local previews/optimistic update behavior intact.

**Tech Stack:** Flutter, Riverpod, `image_picker`, existing Nonto auth/upload/image crop services, Flutter source regression tests.

---

## Files

- Create: `test/nonto_edit_profile_phase4d_regression_test.dart`
  - Guards source wording, image-edit flow, local previews, optimistic rollback, and analyzer hygiene.
- Modify: `lib/screens/profile/edit_profile_screen.dart`
  - Nonto-owned source comment and neutral helper naming.
  - Remove unused imports.
  - Guard `BuildContext` use before crop navigation after async image picking.
  - Keep existing upload, cache, auth state, and inline edit behavior.

---

### Task 1: Add Phase 4D source regression test

**Files:**
- Create: `test/nonto_edit_profile_phase4d_regression_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/nonto_edit_profile_phase4d_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4D edit profile source regressions', () {
    test('edit profile uses Nonto-owned wording and neutral helper names', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, contains('Nonto 个人资料编辑页'));
      expect(source, isNot(contains('按需编辑模式')));
      expect(source, isNot(contains('_xBlack')));
      expect(source, isNot(contains('_xDarkGrey')));
      expect(source, isNot(contains('_xBlue')));
      expect(source, contains('_primaryTextColor'));
      expect(source, contains('_secondaryTextColor'));
      expect(source, contains('_accentColor'));
    });

    test('edit profile keeps direct image crop upload flow and previews', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, contains('_picker.pickImage'));
      expect(source, contains('ImageCropScreen'));
      expect(source, contains('UploadService().uploadAvatar'));
      expect(source, contains('UploadService().uploadCoverPhoto'));
      expect(source, contains('_localAvatarBytes = finalBytes'));
      expect(source, contains('_localCoverBytes = finalBytes'));
    });

    test('edit profile guards context usage after async image picking', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, contains('if (!mounted) return;\n\n      // 裁剪'));
      expect(source, contains('Navigator.of(context).push<Uint8List>'));
    });

    test('edit profile keeps optimistic text updates with rollback', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, contains('final optimistic = user.copyWith(displayName: newName)'));
      expect(source, contains('final optimistic = user.copyWith(bio: newBio)'));
      expect(source, contains('updateUser(user.copyWith(displayName: originalName))'));
      expect(source, contains('updateUser(user.copyWith(bio: originalBio))'));
    });

    test('edit profile removes known unused imports', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, isNot(contains("import 'dart:io';")));
      expect(source, isNot(contains("import 'package:cross_file/cross_file.dart';")));
    });
  });
}
```

- [ ] **Step 2: Run RED test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_edit_profile_phase4d_regression_test.dart
```

Expected: FAIL because edit profile still has old source wording, `_x...` helper names, unused imports, and context guard is missing before crop navigation.

---

### Task 2: Implement edit-profile polish and analyzer cleanup

**Files:**
- Modify: `lib/screens/profile/edit_profile_screen.dart`

- [ ] **Step 1: Remove unused imports**

Remove:

```dart
import 'dart:io';
import 'package:cross_file/cross_file.dart';
```

Keep `dart:typed_data`, because `Uint8List` is used.

- [ ] **Step 2: Update page source comment**

Replace:

```dart
/// 个人资料编辑页面 —— 按需编辑模式
///
/// 每个字段（头像、背景、名字、简介）独立编辑、独立保存。
/// 头像/背景：点击 → 选择图片 → 裁剪 → 立即上传
/// 名字/简介：点击进入编辑态 → 修改 → 保存/取消
```

with:

```dart
/// Nonto 个人资料编辑页：头像、封面、昵称与简介的轻量编辑入口。
///
/// 每个字段独立编辑、独立保存：图片选择后裁剪并上传，文字字段支持保存/取消。
```

- [ ] **Step 3: Rename internal color helpers**

Replace:

```dart
Color get _xBlack => AppColors.textPrimary;
Color get _xDarkGrey => AppColors.textSecondary;
Color get _xBlue => AppColors.primary;
```

with:

```dart
Color get _primaryTextColor => AppColors.textPrimary;
Color get _secondaryTextColor => AppColors.textSecondary;
Color get _accentColor => AppColors.primary;
```

Then replace every usage:

```dart
_xBlack -> _primaryTextColor
_xDarkGrey -> _secondaryTextColor
_xBlue -> _accentColor
```

- [ ] **Step 4: Guard crop navigation context after image picking**

In `_changeAvatar()`, after:

```dart
final originalBytes = await picked.readAsBytes();
```

insert:

```dart
if (!mounted) return;
```

In `_changeCoverPhoto()`, after:

```dart
final originalBytes = await picked.readAsBytes();
```

insert:

```dart
if (!mounted) return;
```

This ensures `Navigator.of(context)` is not used after async image-picking/read work without a mounted check.

- [ ] **Step 5: Format and run Phase 4D test**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/profile/edit_profile_screen.dart test/nonto_edit_profile_phase4d_regression_test.dart
cd /d/FlutterProject/nonto && flutter test test/nonto_edit_profile_phase4d_regression_test.dart
```

Expected: PASS.

---

### Task 3: Verify profile area and full suite

**Files:**
- Test: `test/nonto_edit_profile_phase4d_regression_test.dart`
- Existing profile tests: `test/nonto_profile_phase4a_regression_test.dart`, `test/nonto_user_profile_phase4c_regression_test.dart`
- Analyze: `lib/screens/profile/edit_profile_screen.dart`, `test/nonto_edit_profile_phase4d_regression_test.dart`

- [ ] **Step 1: Run profile regression tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart test/nonto_user_profile_phase4c_regression_test.dart test/nonto_edit_profile_phase4d_regression_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/profile/edit_profile_screen.dart test/nonto_edit_profile_phase4d_regression_test.dart
```

Expected: No issues found.

- [ ] **Step 3: Run recent UI/performance smoke tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart test/nonto_explore_phase3a_regression_test.dart test/nonto_explore_phase3b_regression_test.dart test/nonto_notifications_phase4b_regression_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full Flutter tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

- [ ] **Step 5: Run full analyzer and report honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: may still fail with project-wide historical issues. Report exact issue count and whether touched files are clean.

---

## Self-Review

- Spec coverage: Plan covers Nonto wording, inline edit model preservation, image preview/upload flow, optimistic updates, analyzer cleanup, and verification.
- Placeholder scan: No placeholders remain; every step has concrete code or commands.
- Type consistency: Helper names and test assertions match the implementation steps.
