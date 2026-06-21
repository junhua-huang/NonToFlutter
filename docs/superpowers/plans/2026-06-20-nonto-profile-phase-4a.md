# Nonto Profile Phase 4A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the current user's Profile tab with Nonto-owned naming, consistent loading/empty states, and low-risk source hygiene.

**Architecture:** Keep `ProfileTab` in place and preserve its existing data loading, edit, upload, refresh, and post interaction flows. Add small private helpers for repeated content states and remove unused profile source noise. Use source-level regression tests before modifying production code.

**Tech Stack:** Flutter, Dart, Riverpod, existing profile/auth/post services, Flutter test.

---

## File Structure

- Modify: `D:\FlutterProject\nonto\lib\screens\profile\profile_tab.dart`
  - Replace Twitter/X profile comment with Nonto wording.
  - Add `_buildProfileLoadingState()` and `_buildProfileEmptyState(...)` helpers.
  - Use helpers in posts, likes, and photos tab states.
  - Preserve `NestedScrollView`, `SliverAppBar`, `TabBarView`, `ListView.builder`, and `GridView.builder`.
  - Remove unused imports: `cross_file.dart`, `app_config.dart`, and `core_providers.dart`.
  - Remove unused local avatar preview fields and assignments: `_localAvatarPreview`, `_localAvatarBytes`.

- Create: `D:\FlutterProject\nonto\test\nonto_profile_phase4a_regression_test.dart`
  - Source-level regression tests for this low-risk UI/UX slice.

## Tasks

### Task 1: Add failing Phase 4A regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\nonto_profile_phase4a_regression_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4A profile source regressions', () {
    late String source;

    setUpAll(() {
      source = File('lib/screens/profile/profile_tab.dart').readAsStringSync();
    });

    test('profile tab uses Nonto-owned naming instead of Twitter/X labels', () {
      expect(source, contains('Nonto 个人资料页'));
      expect(source, isNot(contains('Twitter/X 风格个人资料页')));
    });

    test('profile tab has reusable loading and empty states', () {
      expect(source, contains('Widget _buildProfileLoadingState()'));
      expect(source, contains('Widget _buildProfileEmptyState({'));
      expect(source, contains("_buildProfileEmptyState(\n        icon: Icons.article_outlined"));
      expect(source, contains("_buildProfileEmptyState(\n        icon: Icons.favorite_border"));
      expect(source, contains("_buildProfileEmptyState(\n        icon: Icons.photo_library_outlined"));
    });

    test('profile tab keeps lazy rendering and nested profile scroll structure', () {
      expect(source, contains('NestedScrollView('));
      expect(source, contains('SliverAppBar('));
      expect(source, contains('TabBarView('));
      expect(source, contains('return ListView.builder('));
      expect(source, contains('return GridView.builder('));
    });

    test('profile tab removes known unused imports and unused avatar preview fields', () {
      expect(source, isNot(contains("package:cross_file/cross_file.dart")));
      expect(source, isNot(contains("package:nonto/config/app_config.dart")));
      expect(source, isNot(contains("package:nonto/providers/core_providers.dart")));
      expect(source, isNot(contains('String? _localAvatarPreview')));
      expect(source, isNot(contains('Uint8List? _localAvatarBytes')));
    });
  });
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart
```

Expected: FAIL because the profile tab still has Twitter/X wording, lacks the new helpers, and still contains known unused imports/fields.

### Task 2: Apply Nonto naming and source hygiene

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\profile_tab.dart`

- [ ] **Step 1: Remove unused imports**

Delete these imports:

```dart
import 'package:cross_file/cross_file.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/providers/core_providers.dart';
```

- [ ] **Step 2: Replace profile comment**

Change:

```dart
/// Twitter/X 风格个人资料页（头像半覆盖背景、可编辑、照片墙Tab）
```

to:

```dart
/// Nonto 个人资料页：封面、头像、简介、统计与内容 Tab。
```

- [ ] **Step 3: Remove unused avatar preview fields**

Delete:

```dart
String? _localAvatarPreview;
Uint8List? _localAvatarBytes;
```

- [ ] **Step 4: Remove unused avatar preview assignments**

Delete these assignments from `_changeAvatar`:

```dart
_localAvatarPreview = picked!.path;
_localAvatarBytes = avatarBytes;
```

Delete the unused local variable:

```dart
final avatarBytes = await picked!.readAsBytes();
```

Delete these cropped-avatar preview assignments:

```dart
_localAvatarPreview = finalPath;
_localAvatarBytes = croppedBytes;
```

Delete these finally assignments:

```dart
_localAvatarPreview = null;
_localAvatarBytes = null;
```

- [ ] **Step 5: Run checkpoint test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart
```

Expected: still FAIL until reusable profile state helpers are added and applied.

### Task 3: Add reusable profile content states

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\profile_tab.dart`

- [ ] **Step 1: Add loading helper before `_buildPostsContent`**

```dart
Widget _buildProfileLoadingState() {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      SizedBox(height: 200),
      Center(child: CircularProgressIndicator(color: AppColors.primary)),
    ],
  );
}
```

- [ ] **Step 2: Add empty helper after loading helper**

```dart
Widget _buildProfileEmptyState({
  required IconData icon,
  required String title,
  String? subtitle,
}) {
  return ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 120),
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary.withValues(alpha: 0.45)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ],
        ],
      ),
    ],
  );
}
```

- [ ] **Step 3: Use loading helper in posts and likes**

Replace the posts loading `ListView(children: const [...])` with:

```dart
return _buildProfileLoadingState();
```

Replace the likes loading `ListView(children: const [...])` with:

```dart
return _buildProfileLoadingState();
```

- [ ] **Step 4: Use empty helper in posts**

Replace the posts empty `ListView` block with:

```dart
return _buildProfileEmptyState(
  icon: Icons.article_outlined,
  title: '还没有发布帖子',
  subtitle: '发一条帖子让大家了解你吧',
);
```

- [ ] **Step 5: Use empty helper in likes**

Replace the likes empty `ListView` block with:

```dart
return _buildProfileEmptyState(
  icon: Icons.favorite_border,
  title: '还没有喜欢的帖子',
);
```

- [ ] **Step 6: Use empty helper in photos**

Replace the photos empty `ListView` block with:

```dart
return _buildProfileEmptyState(
  icon: Icons.photo_library_outlined,
  title: '还没有照片',
);
```

- [ ] **Step 7: Run GREEN test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart
```

Expected: PASS.

### Task 4: Format and verify the slice

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\profile\profile_tab.dart`
- Test: `D:\FlutterProject\nonto\test\nonto_profile_phase4a_regression_test.dart`

- [ ] **Step 1: Format modified Dart files**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/profile/profile_tab.dart test/nonto_profile_phase4a_regression_test.dart
```

Expected: formatter completes successfully.

- [ ] **Step 2: Run Phase 4A regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run existing profile/performance related tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart test/nonto_explore_phase3a_regression_test.dart test/nonto_explore_phase3b_regression_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full Flutter test suite**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

- [ ] **Step 5: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/profile/profile_tab.dart test/nonto_profile_phase4a_regression_test.dart
```

Expected: No issues found for modified files.

- [ ] **Step 6: Run full analyzer and report honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: May still FAIL due to known project-wide historical issues. Report exact remaining count.

- [ ] **Step 7: Do not commit**

No commit should be made unless the user explicitly asks.

## Self-Review

- Spec coverage: Covers Nonto naming, reusable profile states, preserved lazy rendering, low-risk hygiene, and verification.
- Placeholder scan: No TBD/TODO placeholders are present.
- Type consistency: Helper names and source assertions match planned implementation.
