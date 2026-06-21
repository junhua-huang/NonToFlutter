# Nonto Create Post Phase 5A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the Nonto create-post composer with clearer source structure, safer async media flows, and clean targeted analyzer output.

**Architecture:** Keep the existing single-screen composer and media upload flow. Add small computed helpers and widget extraction inside `create_post_screen.dart`, preserving lazy media builders and existing service calls.

**Tech Stack:** Flutter, Riverpod, ImagePicker, VideoPlayer, SharedPreferences, `flutter_test`, source-regression tests.

---

## File Structure

- Create: `test/nonto_create_post_phase5a_regression_test.dart`
  - Source regression checks for Nonto wording, neutral color helper names, composer-state helpers, submit button extraction, toolbar extraction, mounted guards, analyzer cleanup, and lazy media rendering.
- Modify: `lib/screens/post/create_post_screen.dart`
  - Rename `_x...` color helpers.
  - Add `_hasComposerContent`, `_isOverCharacterLimit`, `_canSubmitPost` getters.
  - Extract `_buildSubmitButton()` and `_buildComposerToolbar({required bool isOverLimit})`.
  - Add mounted guards around async draft/media/navigation boundaries.
  - Remove obsolete `picked == null` check for `pickMultiImage`.
  - Keep existing upload/service contracts.

Do not commit unless the user explicitly asks.

---

### Task 1: Add RED source regression coverage

**Files:**
- Create: `test/nonto_create_post_phase5a_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_create_post_phase5a_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 5A create post source regressions', () {
    test('composer uses Nonto-owned wording and neutral helper names', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('Nonto 创作页'));
      expect(source, contains('文本、图片、视频、话题与草稿'));
      expect(source, isNot(contains('_xBlue')));
      expect(source, isNot(contains('_xBlack')));
      expect(source, isNot(contains('_xDarkGrey')));
      expect(source, contains('_accentColor'));
      expect(source, contains('_primaryTextColor'));
      expect(source, contains('_secondaryTextColor'));
    });

    test('composer state is centralized for submit behavior', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('bool get _hasComposerContent'));
      expect(source, contains('bool get _isOverCharacterLimit'));
      expect(source, contains('bool get _canSubmitPost'));
      expect(source, contains('Widget _buildSubmitButton()'));
      expect(source, contains('AnimatedSwitcher'));
      expect(source, contains('onPressed: _canSubmitPost ? _submitPost : null'));
    });

    test('composer toolbar is extracted and keeps existing actions', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('Widget _buildComposerToolbar({required bool isOverLimit})'));
      expect(source, contains("label: '图片 (\${_selectedImages.length}/\$_maxImages)'"));
      expect(source, contains("label: '视频'"));
      expect(source, contains("label: '@好友'"));
      expect(source, contains("label: '#话题'"));
      expect(source, contains("label: '表情'"));
      expect(source, contains('SingleChildScrollView'));
    });

    test('async draft and media flows guard mounted before UI work', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('if (!mounted) return;'));
      expect(source, contains('final picked = await _picker.pickMultiImage'));
      expect(source, contains('final bytes = await videoFile.readAsBytes();'));
      expect(source, contains('await _videoController!.initialize();'));
      expect(source, contains('await _clearDraft();'));
    });

    test('obsolete multi-image null check is removed', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, isNot(contains('picked == null')));
      expect(source, contains('if (picked.isEmpty) return;'));
    });

    test('media preview rendering remains lazy and bounded', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('ReorderableListView.builder'));
      expect(source, contains('PageView.builder'));
      expect(source, contains('GridView.builder'));
      expect(source, contains('static const int _maxImages = 9'));
    });
  });
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_create_post_phase5a_regression_test.dart
```

Expected: FAIL because current source still has old wording, `_x...` names, inline submit/toolbar logic, and the obsolete `picked == null` check.

---

### Task 2: Implement composer polish

**Files:**
- Modify: `lib/screens/post/create_post_screen.dart`
- Test: `test/nonto_create_post_phase5a_regression_test.dart`

- [ ] **Step 1: Update comment and color helper names**

Change the screen comment to:

```dart
/// Nonto 创作页：文本、图片、视频、话题与草稿的一体化发布入口。
```

Rename getters:

```dart
Color get _accentColor => AppColors.primary;
Color get _primaryTextColor => AppColors.textPrimary;
Color get _secondaryTextColor => AppColors.textSecondary;
```

Replace all usages of `_xBlue`, `_xBlack`, and `_xDarkGrey` with the new names.

- [ ] **Step 2: Add composer state getters**

Add near the color helpers:

```dart
bool get _hasComposerContent =>
    _controller.text.trim().isNotEmpty ||
    _selectedImages.isNotEmpty ||
    _selectedVideo != null;

bool get _isOverCharacterLimit => _charCount > _maxChars;

bool get _canSubmitPost =>
    _hasComposerContent && !_isSubmitting && !_isOverCharacterLimit;
```

- [ ] **Step 3: Remove obsolete image null check and add mounted guards**

In `_pickImages()`, change:

```dart
if (picked == null || picked.isEmpty) return;
```

to:

```dart
if (picked.isEmpty) return;
```

Add `if (!mounted) return;` after image byte reads and before `setState`.

In `_restoreDraft()`, add `if (!mounted) return;` after `SharedPreferences.getInstance()` and after restored byte reads before UI mutation.

In `_pickVideo()`, add `if (!mounted) return;` before its `setState` after async read/thumbnail work.

In `_toggleVideoPlayback()`, add `if (!mounted) return;` after `await _videoController!.initialize();` before `play()`/`setState`.

In successful submit, change:

```dart
await _clearDraft();
if (mounted) Navigator.of(context).pop(true);
```

to:

```dart
await _clearDraft();
if (!mounted) return;
Navigator.of(context).pop(true);
```

- [ ] **Step 4: Extract `_buildSubmitButton()`**

Add:

```dart
Widget _buildSubmitButton() {
  return TextButton(
    onPressed: _canSubmitPost ? _submitPost : null,
    style: TextButton.styleFrom(
      backgroundColor: _canSubmitPost ? _accentColor : Colors.grey[300],
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      disabledBackgroundColor: Colors.grey[300],
    ),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: _isSubmitting
          ? const SizedBox(
              key: ValueKey('submitting'),
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Text(
              '发布',
              key: ValueKey('publish'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
    ),
  );
}
```

Replace the app-bar `TextButton` action with `_buildSubmitButton()`.

- [ ] **Step 5: Extract `_buildComposerToolbar`**

Move the bottom toolbar container into:

```dart
Widget _buildComposerToolbar({required bool isOverLimit}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.borderLight)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.image_outlined,
            label: '图片 (${_selectedImages.length}/$_maxImages)',
            onTap: _selectedImages.length >= _maxImages ? null : _pickImages,
          ),
          const SizedBox(width: 4),
          _ToolbarButton(
            icon: Icons.videocam_outlined,
            label: '视频',
            onTap: _selectedImages.isNotEmpty ? null : _pickVideo,
          ),
          const SizedBox(width: 4),
          _ToolbarButton(
            icon: Icons.alternate_email,
            label: '@好友',
            onTap: _showMentionPicker,
          ),
          const SizedBox(width: 4),
          _ToolbarButton(
            icon: Icons.tag,
            label: '#话题',
            onTap: _showTopicPicker,
          ),
          const SizedBox(width: 4),
          _ToolbarButton(
            icon: Icons.emoji_emotions_outlined,
            label: '表情',
            onTap: _showEmojiPicker,
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_charCount/$_maxChars',
              style: TextStyle(
                color: isOverLimit ? Colors.red : _secondaryTextColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

Replace the inline bottom toolbar with:

```dart
_buildComposerToolbar(isOverLimit: _isOverCharacterLimit),
```

- [ ] **Step 6: Simplify build state locals**

Remove local `hasContent`, `canPost`, and `isOverLimit` calculations from `build`. Use getters instead:

```dart
final user = auth.user;
```

Use `_isOverCharacterLimit` for progress/counter state and `_buildSubmitButton()` for the app-bar action.

- [ ] **Step 7: Format and run GREEN**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/post/create_post_screen.dart test/nonto_create_post_phase5a_regression_test.dart
cd /d/FlutterProject/nonto && flutter test test/nonto_create_post_phase5a_regression_test.dart
```

Expected: format succeeds and test passes.

---

### Task 3: Verify analyzer and adjacent coverage

**Files:**
- Verify: `lib/screens/post/create_post_screen.dart`
- Verify: `test/nonto_create_post_phase5a_regression_test.dart`

- [ ] **Step 1: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/post/create_post_screen.dart test/nonto_create_post_phase5a_regression_test.dart
```

Expected: `No issues found!`

- [ ] **Step 2: Run adjacent UI/performance tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart test/page_performance_regression_test.dart test/nonto_create_post_phase5a_regression_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run full suite**

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

- Spec coverage: covers Nonto wording, neutral names, state helper extraction, submit/toolbar helpers, mounted guards, analyzer cleanup, lazy media rendering, and verification.
- Placeholder scan: no placeholders or unresolved TODOs.
- Type consistency: method names and helper names match the planned source changes.