# Nonto Media Viewer Phase 5B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish `ImageViewerScreen` into a Nonto-owned, analyzer-clean full-screen media browsing experience while preserving lazy image paging, zoom, swipe navigation, author navigation, and expandable post context.

**Architecture:** Keep the existing single-screen implementation and avoid a broad refactor. Add small private helpers for chrome (`_buildCloseButton`, `_buildPageIndicator`) and info-bar visibility (`_hasInfoBarContent`) so the build tree is easier to scan without changing runtime behavior. Remove unused state and redundant null checks that currently block targeted analyzer cleanliness.

**Tech Stack:** Flutter, Dart, `CachedNetworkImage`, `PageView.builder`, `InteractiveViewer`, `Hero`, source-level Flutter regression tests.

---

## File Structure

- Create: `test/nonto_media_viewer_phase5b_regression_test.dart`
  - Source regression tests that protect Nonto-owned wording, helper extraction, lazy/zoom image rendering, author/content behavior, and analyzer cleanup.
- Modify: `lib/screens/post/image_viewer_screen.dart`
  - Update the screen doc comment.
  - Extract close button and page indicator helpers.
  - Add `_hasInfoBarContent` getter.
  - Remove `_isCurrentZoomed()` and `_verticalDragOffset`.
  - Remove redundant nested `author != null` checks inside already-promoted author blocks.
- Do not commit in this task unless the user explicitly asks.

---

### Task 1: Add RED source regression coverage

**Files:**
- Create: `test/nonto_media_viewer_phase5b_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_media_viewer_phase5b_regression_test.dart` with this content:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 5B media viewer source regressions', () {
    test('viewer uses Nonto-owned wording and keeps immersive behavior', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('Nonto 图片浏览页'));
      expect(source, contains('沉浸查看帖子图片、作者信息与正文上下文'));
      expect(source, contains('PageView.builder'));
      expect(source, contains('InteractiveViewer'));
      expect(source, contains('CachedNetworkImage'));
      expect(source, contains('Hero('));
    });

    test('top chrome is extracted without eager image creation', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('Widget _buildCloseButton()'));
      expect(source, contains('Widget _buildPageIndicator(int safeIndex, int total)'));
      expect(source, contains('if (resolved.length > 1) _buildPageIndicator'));
      expect(source, contains('itemBuilder: (context, index)'));
    });

    test('info bar visibility is centralized and keeps post context', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('bool get _hasInfoBarContent'));
      expect(source, contains('if (_hasInfoBarContent)'));
      expect(source, contains('UserProfileScreen(user: author)'));
      expect(source, contains('_ExpandablePostContent(content: content)'));
      expect(source, contains('AnimatedPositioned'));
    });

    test('targeted analyzer cleanup removes obsolete state and redundant checks', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, isNot(contains('bool _isCurrentZoomed()')));
      expect(source, isNot(contains('_verticalDragOffset')));
      expect(source, isNot(contains('if (author != null) {')));
    });

    test('empty and invalid media lists still close safely', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('if (urls.isEmpty) return;'));
      expect(source, contains('if (resolved.isEmpty)'));
      expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
      expect(source, contains('if (mounted) Navigator.pop(context);'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_media_viewer_phase5b_regression_test.dart
```

Expected: FAIL because `ImageViewerScreen` still has old generic wording, no extracted helper methods, no `_hasInfoBarContent` getter, `_isCurrentZoomed()`, `_verticalDragOffset`, and redundant nested `author != null` checks.

---

### Task 2: Implement media viewer polish and analyzer cleanup

**Files:**
- Modify: `lib/screens/post/image_viewer_screen.dart`
- Test: `test/nonto_media_viewer_phase5b_regression_test.dart`

- [ ] **Step 1: Update screen documentation**

Replace the current top screen comment:

```dart
/// 全屏图片浏览模式
///
/// 功能：
/// - 左右滑动在当前帖子图片之间切换
/// - 双指放大 / 双击恢复原始尺寸
/// - 上下滑动切换图片（原始尺寸时）
/// - 底部显示作者信息和帖子文字
/// - 点击空白区域切换底部信息栏显示/隐藏
```

with:

```dart
/// Nonto 图片浏览页：沉浸查看帖子图片、作者信息与正文上下文。
///
/// 保留轻量全屏浏览体验：左右翻页、缩放查看、竖向手势切图、
/// 作者资料入口以及可展开的帖子正文。
```

- [ ] **Step 2: Add centralized info-bar visibility getter**

Inside `_ImageViewerScreenState`, after `_showInfoBar`, add:

```dart
  bool get _hasInfoBarContent {
    return widget.author != null ||
        (widget.postContent != null && widget.postContent!.isNotEmpty);
  }
```

- [ ] **Step 3: Remove unused current zoom helper**

Delete this unused method:

```dart
  bool _isCurrentZoomed() {
    return _isZoomedMap[_currentIndex] ?? false;
  }
```

- [ ] **Step 4: Replace inline close button and page indicator in `build`**

In the `Stack(children: [...])` list, replace the inline close button `SafeArea(...)` block and inline page indicator `if (resolved.length > 1) SafeArea(...)` block with:

```dart
            _buildCloseButton(),

            if (resolved.length > 1) _buildPageIndicator(safeIndex, resolved.length),

            if (_hasInfoBarContent)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: _showInfoBar ? 0 : -200,
                child: _buildInfoBar(),
              ),
```

- [ ] **Step 5: Add `_buildCloseButton` helper**

Add this method before `_buildImagePages`:

```dart
  Widget _buildCloseButton() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 6: Add `_buildPageIndicator` helper**

Add this method after `_buildCloseButton`:

```dart
  Widget _buildPageIndicator(int safeIndex, int total) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${safeIndex + 1} / $total',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 7: Remove redundant nested author null checks**

Inside `_buildInfoBar`, keep the surrounding promoted `if (author != null) ...[` block, but replace both tap handlers that currently wrap navigation in `if (author != null) { ... }` with direct navigation:

```dart
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(user: author),
                      ),
                    );
                  },
```

and:

```dart
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(user: author),
                            ),
                          );
                        },
```

- [ ] **Step 8: Remove unused vertical drag offset field and writes**

Delete this field from `_ZoomableImageState`:

```dart
  double _verticalDragOffset = 0;
```

Replace the current `onVerticalDragUpdate` handler body:

```dart
          ? (details) {
              _verticalDragOffset += details.primaryDelta ?? 0;
            }
```

with a no-op handler that preserves gesture participation without unused state:

```dart
          ? (_) {}
```

Remove this line from `onVerticalDragEnd`:

```dart
              _verticalDragOffset = 0;
```

- [ ] **Step 9: Format changed files**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/post/image_viewer_screen.dart test/nonto_media_viewer_phase5b_regression_test.dart
```

Expected: formatter completes and reports the two formatted files or no changes.

- [ ] **Step 10: Run media viewer regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_media_viewer_phase5b_regression_test.dart
```

Expected: PASS.

- [ ] **Step 11: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/post/image_viewer_screen.dart test/nonto_media_viewer_phase5b_regression_test.dart
```

Expected: `No issues found!`.

---

### Task 3: Run adjacent and full verification

**Files:**
- Verify: `lib/screens/post/image_viewer_screen.dart`
- Verify: `test/nonto_media_viewer_phase5b_regression_test.dart`

- [ ] **Step 1: Run adjacent UI regression tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_create_post_phase5a_regression_test.dart test/nonto_ui_phase1_regression_test.dart test/nonto_media_viewer_phase5b_regression_test.dart
```

Expected: all selected tests pass.

- [ ] **Step 2: Run full Flutter test suite**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: full suite passes. Previous baseline was `+81`, `All tests passed!`; the total should increase by the new Phase 5B tests.

- [ ] **Step 3: Run full analyzer and record baseline honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: full analyzer may still fail from historical project-wide issues. Current baseline before Phase 5B is `76 issues found`; this slice should not add new issues, and the targeted analyzer for touched files must be clean.

---

## Self-Review

- Spec coverage:
  - Nonto-owned media viewer wording: Task 2 Step 1 and Task 1 first test.
  - Preserve lazy image browsing and zoom: Task 1 first/second tests protect `PageView.builder`, `itemBuilder`, `InteractiveViewer`, `CachedNetworkImage`, and `Hero`.
  - Preserve tap-toggle info bar, page indicator, author navigation, and expandable content: Task 1 second/third tests plus Task 2 Steps 4-7.
  - Analyzer cleanup: Task 1 cleanup test plus Task 2 Steps 3, 7, and 8.
  - Empty media safety: Task 1 fifth test.
- Placeholder scan: no TBD/fill-in-later steps; all code edits and commands are explicit.
- Type consistency: helper signatures match tests and implementation steps: `_buildCloseButton()`, `_buildPageIndicator(int safeIndex, int total)`, `_hasInfoBarContent`.
- User constraints: no commits, no migrations, no proprietary Twitter/X copying, and performance-preserving builders remain intact.
