# Nonto Explore/Search Phase 3B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Explore/Search interactions more reliable and polished by guarding stale search responses, removing the fake empty recommended-users search, and making live suggestions more resilient.

**Architecture:** Keep the changes in `SearchTab` and `SearchSuggestions`. Do not change backend contracts or introduce new services. Use source-level tests to lock behavior before editing production code.

**Tech Stack:** Flutter, Dart, Riverpod, existing Nonto search services, Flutter test.

---

## File Structure

- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`
  - Add `_searchGeneration` field.
  - Increment and check generation inside `_doSearch` before every async `setState` path.
  - Add `_focusSearch()` helper.
  - Replace recommended-users `查看全部` empty search with `_focusSearch`.

- Modify: `D:\FlutterProject\nonto\lib\widgets\search_suggestions.dart`
  - Change hard-coded `Colors.white` container background to `AppColors.background`.
  - Add per-request fallback with `.catchError((_) => null)`.
  - Use `Future.wait(futures, eagerError: false)`.
  - Parse dynamic nullable responses safely.

- Create: `D:\FlutterProject\nonto\test\nonto_explore_phase3b_regression_test.dart`
  - Source-level regression tests for the Phase 3B behavior.

## Tasks

### Task 1: Add failing Phase 3B regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\nonto_explore_phase3b_regression_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3B explore/search source regressions', () {
    late String searchTab;
    late String suggestions;

    setUpAll(() {
      searchTab = File('lib/screens/search/search_tab.dart').readAsStringSync();
      suggestions = File('lib/widgets/search_suggestions.dart').readAsStringSync();
    });

    test('submitted searches guard against stale async responses', () {
      expect(searchTab, contains('int _searchGeneration = 0;'));
      expect(searchTab, contains('final generation = ++_searchGeneration;'));
      expect(searchTab, contains('if (!mounted || generation != _searchGeneration) return;'));
      expect(searchTab, contains('if (mounted && generation == _searchGeneration)'));
    });

    test('recommended users view all focuses search instead of firing empty search', () {
      expect(searchTab, contains('void _focusSearch()'));
      expect(searchTab, contains('onAction: _focusSearch'));
      expect(searchTab, isNot(contains("_doSearch('');")));
    });

    test('search suggestions use Nonto themed surface and independent request settling', () {
      expect(suggestions, contains('color: AppColors.background'));
      expect(suggestions, isNot(contains('color: Colors.white')));
      expect(suggestions, contains('Future.wait(futures, eagerError: false)'));
      expect(suggestions, contains('.catchError((_) => null)'));
    });
  });
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3b_regression_test.dart
```

Expected: FAIL because stale search guards, `_focusSearch`, and suggestion independent fallback behavior are not implemented yet.

### Task 2: Add stale-response guard and focus-search action to SearchTab

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`

- [ ] **Step 1: Add search generation field**

Add below `_textNotEmpty`:

```dart
int _searchGeneration = 0;
```

- [ ] **Step 2: Add `_focusSearch` helper after `_exitSearchMode`**

```dart
void _focusSearch() {
  ref.read(barVisibleProvider.notifier).state = true;
  setState(() => _inSearchMode = true);
  _focusNode.requestFocus();
}
```

- [ ] **Step 3: Increment generation at start of `_doSearch`**

Add as the first line of `_doSearch`:

```dart
final generation = ++_searchGeneration;
```

- [ ] **Step 4: Guard async response after awaiting global search**

Immediately after:

```dart
final resp = await SearchService().globalSearch(query);
```

add:

```dart
if (!mounted || generation != _searchGeneration) return;
```

- [ ] **Step 5: Guard catch path**

At the start of the catch block, before logging or setting error, add:

```dart
if (!mounted || generation != _searchGeneration) return;
```

- [ ] **Step 6: Guard finally path**

Replace:

```dart
setState(() => _isLoading = false);
```

with:

```dart
if (mounted && generation == _searchGeneration) {
  setState(() => _isLoading = false);
}
```

- [ ] **Step 7: Replace recommended-users empty search action**

Change:

```dart
items.add(_DefaultItem.headerWithAction('推荐好友', '查看全部', () {
  _controller.text = '';
  _doSearch('');
}));
```

to:

```dart
items.add(_DefaultItem.headerWithAction('推荐好友', '查看全部', _focusSearch));
```

- [ ] **Step 8: Run checkpoint test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3b_regression_test.dart
```

Expected: still FAIL until `SearchSuggestions` is updated.

### Task 3: Harden SearchSuggestions request settling and themed background

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\widgets\search_suggestions.dart`

- [ ] **Step 1: Add independent fallback to suggest users request**

Change:

```dart
SearchService().suggestUsers(query, limit: 3),
```

to:

```dart
SearchService().suggestUsers(query, limit: 3).catchError((_) => null),
```

- [ ] **Step 2: Add independent fallback to global search and topics requests**

Change:

```dart
futures.add(SearchService().globalSearch(query));
futures.add(TopicService().getTopics(q: query, perPage: 3));
```

to:

```dart
futures.add(SearchService().globalSearch(query).catchError((_) => null));
futures.add(TopicService().getTopics(q: query, perPage: 3).catchError((_) => null));
```

- [ ] **Step 3: Use non-eager future settling**

Change:

```dart
final results = await Future.wait(futures);
```

to:

```dart
final results = await Future.wait(futures, eagerError: false);
```

- [ ] **Step 4: Parse nullable dynamic responses safely**

Change:

```dart
final userResp = results[0];
```

to:

```dart
final userResp = results[0] as dynamic;
```

Change:

```dart
final postResp = results[1];
```

to:

```dart
final postResp = results[1] as dynamic;
```

Change:

```dart
final topicResp = results[2];
```

to:

```dart
final topicResp = results[2] as dynamic;
```

- [ ] **Step 5: Replace hard-coded white background**

Change:

```dart
color: Colors.white,
```

to:

```dart
color: AppColors.background,
```

- [ ] **Step 6: Run GREEN test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3b_regression_test.dart
```

Expected: PASS.

### Task 4: Format and verify the slice

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`
- Modify: `D:\FlutterProject\nonto\lib\widgets\search_suggestions.dart`
- Test: `D:\FlutterProject\nonto\test\nonto_explore_phase3b_regression_test.dart`

- [ ] **Step 1: Format modified Dart files**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/search/search_tab.dart lib/widgets/search_suggestions.dart test/nonto_explore_phase3b_regression_test.dart
```

Expected: formatter completes successfully.

- [ ] **Step 2: Run Phase 3B regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3b_regression_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Phase 3A regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3a_regression_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run performance regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run full Flutter test suite**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

- [ ] **Step 6: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/search/search_tab.dart lib/widgets/search_suggestions.dart test/nonto_explore_phase3b_regression_test.dart
```

Expected: No issues found for modified files.

- [ ] **Step 7: Run full analyzer and report honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: May still FAIL due to known project-wide historical issues. Report the exact remaining count.

- [ ] **Step 8: Do not commit**

No commit should be made unless the user explicitly asks.

## Self-Review

- Spec coverage: Covers stale response protection, no fake empty recommended-user search, themed suggestions, independent suggestion request settling, and verification.
- Placeholder scan: No TBD/TODO placeholders are present.
- Type consistency: Helper names and source assertions match planned production edits.
