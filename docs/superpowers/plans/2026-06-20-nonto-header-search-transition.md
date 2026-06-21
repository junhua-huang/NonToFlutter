# Nonto Header Search Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move message and discover search into the header with an animated avatar-to-expanded-search transition.

**Architecture:** Add a small reusable header widget that owns only layout, focus animation, avatar visibility, and text-field chrome. Keep each page's search business logic in its current screen so message filtering remains local and discover global search/suggestions keep their existing state flow.

**Tech Stack:** Flutter, Riverpod, existing `AppColors`, existing `ImageUtils.buildAvatar`, existing `barVisibleProvider`, existing source-regression tests under `test/`.

---

## File Structure

- Create: `lib/widgets/nonto_header_search_bar.dart`
  - Reusable header row: current-user avatar, animated search field, optional trailing action, and focus-driven expand/collapse.
  - Does not know about message filtering or discover API calls.
- Modify: `lib/screens/messages/messages_tab.dart`
  - Replace title AppBar with header search bar.
  - Remove search row from the list and keep local filtering via `_searchQuery`.
  - Add tap-to-unfocus around the body.
- Modify: `lib/screens/search/search_tab.dart`
  - Replace separate “发现” AppBar + below-header search row with header search bar.
  - Keep existing `_inSearchMode`, suggestions, history, `_doSearch`, and right button behavior.
  - Add tap-to-unfocus around content without breaking list gestures.
- Modify: `test/nonto_header_search_regression_test.dart`
  - Source-level regression tests for header search placement, animation primitives, title removal, avatar behavior, and lazy list preservation.

---

### Task 1: Add header search source regression tests

**Files:**
- Create: `test/nonto_header_search_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_header_search_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('header search transition regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('shared header search animates avatar and field focus state', () {
      final source = read('lib/widgets/nonto_header_search_bar.dart');

      expect(source, contains('class NontoHeaderSearchBar'));
      expect(source, contains('AnimatedSize'));
      expect(source, contains('AnimatedOpacity'));
      expect(source, contains('FocusNode'));
      expect(source, contains('ImageUtils.buildAvatar'));
      expect(source, contains('onTapOutside'));
      expect(source, contains('showAvatar'));
    });

    test('messages search lives in the app bar and title text is removed', () {
      final source = read('lib/screens/messages/messages_tab.dart');

      expect(source, contains('NontoHeaderSearchBar('));
      expect(source, contains("hintText: '搜索会话'"));
      expect(source, isNot(contains("title: const Text('消息'")));
      expect(source, isNot(contains('Widget _buildSearchBox()')));
      expect(source, isNot(contains('if (index == 2) return _buildSearchBox();')));
      expect(source, contains('filterNontoConversations(conversations, _searchQuery)'));
      expect(source, contains('return ListView.builder('));
    });

    test('discover search lives in the header and keeps existing search flow', () {
      final source = read('lib/screens/search/search_tab.dart');

      expect(source, contains('NontoHeaderSearchBar('));
      expect(source, contains("hintText: '搜索'"));
      expect(source, isNot(contains("title: Text('发现'")));
      expect(source, contains('_buildRightButton()'));
      expect(source, contains('_showSuggestions'));
      expect(source, contains('onSubmitted: _doSearch'));
      expect(source, contains('return ListView.builder('));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter test test/nonto_header_search_regression_test.dart --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: FAIL because `lib/widgets/nonto_header_search_bar.dart` does not exist and both pages still use old search placement.

---

### Task 2: Create reusable header search widget

**Files:**
- Create: `lib/widgets/nonto_header_search_bar.dart`
- Test: `test/nonto_header_search_regression_test.dart`

- [ ] **Step 1: Implement the reusable widget**

Create `lib/widgets/nonto_header_search_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/utils/image_utils.dart';

class NontoHeaderSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final User? user;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final Widget? trailing;
  final bool keepExpandedWhenNotEmpty;

  const NontoHeaderSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.user,
    this.onChanged,
    this.onSubmitted,
    this.suffixIcon,
    this.trailing,
    this.keepExpandedWhenNotEmpty = true,
  });

  @override
  State<NontoHeaderSearchBar> createState() => _NontoHeaderSearchBarState();
}

class _NontoHeaderSearchBarState extends State<NontoHeaderSearchBar> {
  late final FocusNode _ownedFocusNode;
  late final FocusNode _focusNode;
  bool _hasFocus = false;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;
  bool get showAvatar => !_hasFocus && !(widget.keepExpandedWhenNotEmpty && _hasText);

  @override
  void initState() {
    super.initState();
    _ownedFocusNode = FocusNode();
    _focusNode = widget.focusNode ?? _ownedFocusNode;
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_syncFocus);
    widget.controller.addListener(_syncText);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_syncFocus);
    widget.controller.removeListener(_syncText);
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _syncFocus() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  void _syncText() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: showAvatar
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: showAvatar ? 1 : 0,
                        child: ImageUtils.buildAvatar(widget.user, radius: 18),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  onTapOutside: (_) => _focusNode.unfocus(),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: Icon(Icons.search,
                        color: AppColors.textSecondary, size: 20),
                    suffixIcon: widget.suffixIcon,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter test test/nonto_header_search_regression_test.dart --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: still FAIL because pages have not been wired to `NontoHeaderSearchBar` yet.

---

### Task 3: Move message search into the title bar

**Files:**
- Modify: `lib/screens/messages/messages_tab.dart`
- Test: `test/nonto_header_search_regression_test.dart`

- [ ] **Step 1: Add state and imports**

In `lib/screens/messages/messages_tab.dart`, add:

```dart
import 'package:nonto/widgets/nonto_header_search_bar.dart';
```

Add a focus node beside the search controller:

```dart
final FocusNode _searchFocusNode = FocusNode();
```

Dispose it:

```dart
_searchFocusNode.dispose();
```

- [ ] **Step 2: Replace the AppBar title with header search**

Replace the old `AppBar(title: const Text('消息'...))` block with:

```dart
child: barVisible
    ? Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: NontoHeaderSearchBar(
          controller: _searchController,
          focusNode: _searchFocusNode,
          user: ref.watch(authProvider).user,
          hintText: '搜索会话',
          onChanged: (value) => setState(() => _searchQuery = value),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
        ),
      )
    : const SizedBox.shrink(),
```

- [ ] **Step 3: Remove the in-list search row**

Change item count in `_buildContent` from:

```dart
final itemCount =
    3 + (showEmpty || showSearchEmpty ? 1 : visibleConversations.length);
```

To:

```dart
final itemCount =
    2 + (showEmpty || showSearchEmpty ? 1 : visibleConversations.length);
```

Change builder index handling from:

```dart
if (index == 0) return _buildNotificationEntry();
if (index == 1) return const Divider(height: 1, indent: 72);
if (index == 2) return _buildSearchBox();

if (showEmpty) return _buildEmpty();
if (showSearchEmpty) return _buildSearchEmpty();

final conversation = visibleConversations[index - 3];
```

To:

```dart
if (index == 0) return _buildNotificationEntry();
if (index == 1) return const Divider(height: 1, indent: 72);

if (showEmpty) return _buildEmpty();
if (showSearchEmpty) return _buildSearchEmpty();

final conversation = visibleConversations[index - 2];
```

Delete the entire `_buildSearchBox()` method.

- [ ] **Step 4: Add tap-to-unfocus without breaking scrolling**

Wrap the body `NotificationListener<ScrollUpdateNotification>` in:

```dart
GestureDetector(
  behavior: HitTestBehavior.translucent,
  onTap: () => _searchFocusNode.unfocus(),
  child: NotificationListener<ScrollUpdateNotification>(
    onNotification: (notif) {
      handleBarScrollNotification(notif, ref);
      return false;
    },
    child: Consumer(...),
  ),
)
```

- [ ] **Step 5: Run focused test**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter test test/nonto_header_search_regression_test.dart --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: messages assertions PASS, discover assertions still FAIL.

---

### Task 4: Move discover search into the title bar

**Files:**
- Modify: `lib/screens/search/search_tab.dart`
- Test: `test/nonto_header_search_regression_test.dart`

- [ ] **Step 1: Add import**

In `lib/screens/search/search_tab.dart`, add:

```dart
import 'package:nonto/widgets/nonto_header_search_bar.dart';
```

- [ ] **Step 2: Replace old title AppBar with header search**

Replace the old title-only header block with a header that stays visible when `_inSearchMode` is true:

```dart
final hideHeader = !_inSearchMode && !barVisible;
return AnimatedSize(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeInOut,
  child: SizedBox(
    height: hideHeader ? topPadding : (kToolbarHeight + topPadding),
    child: hideHeader
        ? const SizedBox.shrink()
        : Material(
            color: AppColors.background,
            child: NontoHeaderSearchBar(
              controller: _controller,
              focusNode: _focusNode,
              user: ref.watch(authProvider).user,
              hintText: '搜索',
              onChanged: (_) => _onTextChanged(),
              onSubmitted: _doSearch,
              suffixIcon: ValueListenableBuilder<bool>(
                valueListenable: _textNotEmpty,
                builder: (_, notEmpty, __) {
                  if (!notEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      _controller.clear();
                      _textNotEmpty.value = false;
                    },
                  );
                },
              ),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: _buildRightButton(),
              ),
            ),
          ),
  ),
);
```

- [ ] **Step 3: Remove the old below-header search row**

Delete the `Padding` block that starts with the comment:

```dart
// (b) 搜索框行 + 右侧按钮（AnimatedSwitcher 切换形态）
```

Keep the content `Expanded(AnimatedSwitcher(...))` immediately after the header.

- [ ] **Step 4: Keep focus state and outside tap behavior stable**

Wrap the returned root `Column` in:

```dart
GestureDetector(
  behavior: HitTestBehavior.translucent,
  onTap: () {
    if (_focusNode.hasFocus) _focusNode.unfocus();
  },
  child: Column(
    children: [...],
  ),
)
```

Ensure taps inside the text field are not blocked; `TextField` handles its own gestures first.

- [ ] **Step 5: Run focused test**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter test test/nonto_header_search_regression_test.dart --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

---

### Task 5: Analyzer, full tests, and commit

**Files:**
- All modified files from Tasks 1-4

- [ ] **Step 1: Run formatter on touched Dart files**

Run:

```bash
cd "D:/FlutterProject/nonto" && dart format lib/widgets/nonto_header_search_bar.dart lib/screens/messages/messages_tab.dart lib/screens/search/search_tab.dart test/nonto_header_search_regression_test.dart
```

Expected: formatter exits 0.

- [ ] **Step 2: Run focused regression**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter test test/nonto_header_search_regression_test.dart --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: `All tests passed!`

- [ ] **Step 3: Run full analyzer**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Run full tests with production dart-defines**

Run:

```bash
cd "D:/FlutterProject/nonto" && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

Run:

```bash
cd "D:/FlutterProject/nonto" && git status --short
cd "D:/FlutterProject/nonto" && git add lib/widgets/nonto_header_search_bar.dart lib/screens/messages/messages_tab.dart lib/screens/search/search_tab.dart test/nonto_header_search_regression_test.dart docs/superpowers/plans/2026-06-20-nonto-header-search-transition.md
cd "D:/FlutterProject/nonto" && git commit -m "Add animated header search transitions"
cd "D:/FlutterProject/nonto" && git log -1 --oneline
cd "D:/FlutterProject/nonto" && git status --short
```

Expected: latest commit is `Add animated header search transitions`; final status is clean.

---

## Self-Review

- Spec coverage: The plan moves message and discover search into headers, removes the message/discover title text, animates avatar collapse/restore, unfocuses on outside tap, and preserves lazy list rendering.
- Placeholder scan: No placeholder steps remain.
- Type consistency: `NontoHeaderSearchBar`, `showAvatar`, `FocusNode`, and page wiring names are consistent across tasks.
