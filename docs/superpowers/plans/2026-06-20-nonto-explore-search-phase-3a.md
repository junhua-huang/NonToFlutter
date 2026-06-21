# Nonto Explore/Search Phase 3A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the Explore/Search UI with Nonto-owned naming, explicit discovery loading/empty states, and correct search result tab routing.

**Architecture:** Keep this slice focused inside `SearchTab`. Preserve existing provider/API behavior and lazy builder rendering. Use source-level regression tests before production edits to lock naming, state helpers, tab index mapping, and dead-code cleanup.

**Tech Stack:** Flutter, Dart, Riverpod, Pull-to-refresh, existing Nonto search/explore services, Flutter test.

---

## File Structure

- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`
  - Replace Twitter/X-specific screen comment with Nonto-owned discovery wording.
  - Change visible app-bar title from `Explore` to a Nonto-branded Chinese discovery label.
  - Add `_hasExploreContent(ExploreState)`, `_buildExploreLoadingState()`, and `_buildExploreEmptyState()` helpers.
  - Use those helpers inside default `SmartRefresher` content selection.
  - Fix special search result tab mapping to match current tab order: `全部` index 0, `用户` index 1, `漫展` index 2, `帖子` index 3.
  - Remove unused imports: `app_config.dart`, `comic_detail_page.dart`, and `recommendation_service.dart`.
  - Remove unused `_buildFriendRow`, `_buildTrendingPostCard`, `_DefaultItemType.historyItem`, `_DefaultItem.history`, and `historyIndex` field if no longer needed.

- Create: `D:\FlutterProject\nonto\test\nonto_explore_phase3a_regression_test.dart`
  - Source-level regression coverage for the low-risk UI/UX slice.

## Tasks

### Task 1: Add failing Phase 3A regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\nonto_explore_phase3a_regression_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3A explore/search source regressions', () {
    late String source;

    setUpAll(() {
      source = File('lib/screens/search/search_tab.dart').readAsStringSync();
    });

    test('uses Nonto-owned discovery language instead of Twitter/X labels', () {
      expect(source, isNot(contains('Twitter/X Explore')));
      expect(source, contains('Nonto 发现'));
      expect(source, contains("title: const Text('发现'"));
    });

    test('default discovery state has explicit loading and empty helpers', () {
      expect(source, contains('bool _hasExploreContent(ExploreState s)'));
      expect(source, contains('Widget _buildExploreLoadingState()'));
      expect(source, contains('Widget _buildExploreEmptyState()'));
      expect(source, contains('_buildExploreLoadingState()'));
      expect(source, contains('_buildExploreEmptyState()'));
    });

    test('special search result tab routing matches actual tab order', () {
      expect(source, contains('_tabController.index = 3; // 帖子'));
      expect(source, contains('_tabController.index = 2; // 漫展'));
      expect(source, contains('_tabController.index = 0; // 全部'));
      expect(source, isNot(contains('_tabController.index = 1; // 帖子')));
      expect(source, isNot(contains('_tabController.index = 3; // 漫展')));
    });

    test('keeps lazy rendering for discovery and result lists', () {
      expect(source, contains('return ListView.builder('));
      expect(source, contains('Widget _buildUsersList()'));
      expect(source, contains('Widget _buildPostsList()'));
      expect(source, contains('Widget _buildComicEventsList()'));
    });

    test('removes known dead search-tab source noise', () {
      expect(source, isNot(contains("package:nonto/config/app_config.dart")));
      expect(source, isNot(contains("package:nonto/screens/comic/comic_detail_page.dart")));
      expect(source, isNot(contains("package:nonto/services/api/recommendation_service.dart")));
      expect(source, isNot(contains('Widget _buildFriendRow')));
      expect(source, isNot(contains('Widget _buildTrendingPostCard')));
      expect(source, isNot(contains('_DefaultItemType.historyItem')));
      expect(source, isNot(contains('factory _DefaultItem.history')));
    });
  });
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3a_regression_test.dart
```

Expected: FAIL because `SearchTab` still contains `Twitter/X Explore`, lacks the new helper methods, has wrong special tab indexes, and still contains the unused imports/dead private builders.

### Task 2: Apply Nonto naming and fix result tab routing

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`

- [ ] **Step 1: Remove unused imports**

Delete these imports:

```dart
import 'package:nonto/config/app_config.dart';
import 'package:nonto/screens/comic/comic_detail_page.dart';
import 'package:nonto/services/api/recommendation_service.dart';
```

- [ ] **Step 2: Replace screen comment**

Change:

```dart
/// Twitter/X Explore 风格搜索页（带实时搜索建议）
```

to:

```dart
/// Nonto 发现页：融合探索内容、搜索记录、实时建议与结果页。
```

- [ ] **Step 3: Change app-bar title**

Change:

```dart
title: const Text('Explore',
```

to:

```dart
title: const Text('发现',
```

- [ ] **Step 4: Fix special search result tab indexes**

Change the special tab routing block to:

```dart
final specialType = data['type'] as String?;
if (specialType == 'hot_posts' || specialType == 'trending_topics') {
  _tabController.index = 3; // 帖子
} else if (specialType == 'comic_events') {
  _tabController.index = 2; // 漫展
} else {
  _tabController.index = 0; // 全部
}
```

- [ ] **Step 5: Run checkpoint test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3a_regression_test.dart
```

Expected: still FAIL until loading/empty helpers and dead-code cleanup are completed.

### Task 3: Add explicit default Explore loading and empty states

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`

- [ ] **Step 1: Add content helper above `_buildContentArea`**

Add:

```dart
bool _hasExploreContent(ExploreState s) {
  return s.trendingTopics.isNotEmpty ||
      s.trendingPosts.isNotEmpty ||
      s.recentComicEvents.isNotEmpty ||
      s.followedComicEvents.isNotEmpty ||
      s.suggestedUsers.isNotEmpty;
}
```

- [ ] **Step 2: Replace inline loading conditional inside `SmartRefresher` child**

Change:

```dart
child: exploreState.isLoading &&
        exploreState.trendingTopics.isEmpty &&
        exploreState.trendingPosts.isEmpty &&
        !_isRefreshing
    ? const Center(
        child: CircularProgressIndicator(color: AppColors.primary))
    : _buildDefaultView(exploreState),
```

to:

```dart
child: exploreState.isLoading && !_hasExploreContent(exploreState) && !_isRefreshing
    ? _buildExploreLoadingState()
    : !_hasExploreContent(exploreState)
        ? _buildExploreEmptyState()
        : _buildDefaultView(exploreState),
```

- [ ] **Step 3: Add the loading helper before `_buildSearchHistoryFull`**

Add:

```dart
Widget _buildExploreLoadingState() {
  return const Center(
    child: CircularProgressIndicator(color: AppColors.primary),
  );
}
```

- [ ] **Step 4: Add the empty helper after loading helper**

Add:

```dart
Widget _buildExploreEmptyState() {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore_outlined,
            size: 52,
            color: AppColors.textTertiary.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 14),
          const Text(
            '暂时没有发现内容',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '下拉刷新，或试试搜索你感兴趣的话题、帖子和漫展。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 5: Run checkpoint test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3a_regression_test.dart
```

Expected: still FAIL until dead-code cleanup is completed.

### Task 4: Remove known dead source noise in SearchTab

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`

- [ ] **Step 1: Remove unused `_buildFriendRow` method**

Delete the entire method:

```dart
Widget _buildFriendRow(List<User> friends) {
  return SizedBox(
    height: 170,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final user = friends[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => UserProfileScreen(user: user),
              ));
            },
            child: _FriendCard(user: user),
          ),
        );
      },
    ),
  );
}
```

- [ ] **Step 2: Remove unused `_buildTrendingPostCard` method**

Delete the entire `Widget _buildTrendingPostCard(Post post)` method.

- [ ] **Step 3: Remove unused default-item history variant**

In `_DefaultItemType`, delete:

```dart
historyItem,
```

In `_DefaultItem`, delete:

```dart
final int? historyIndex;
```

Delete constructor argument:

```dart
this.historyIndex,
```

Delete factory:

```dart
factory _DefaultItem.history(int index) =>
    _DefaultItem._(type: _DefaultItemType.historyItem, historyIndex: index);
```

Delete the switch case:

```dart
case _DefaultItemType.historyItem:
  return _buildCompactHistoryItem(item.historyIndex!);
```

- [ ] **Step 4: Run GREEN test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3a_regression_test.dart
```

Expected: PASS.

### Task 5: Format and verify the slice

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\search\search_tab.dart`
- Test: `D:\FlutterProject\nonto\test\nonto_explore_phase3a_regression_test.dart`

- [ ] **Step 1: Format modified Dart files**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/search/search_tab.dart test/nonto_explore_phase3a_regression_test.dart
```

Expected: formatter completes successfully.

- [ ] **Step 2: Run Phase 3A regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_explore_phase3a_regression_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run performance regression test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run relevant UI regression tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_messages_phase2a_regression_test.dart test/nonto_chat_phase2b_regression_test.dart test/nonto_ui_phase1_regression_test.dart
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
cd /d/FlutterProject/nonto && dart analyze lib/screens/search/search_tab.dart test/nonto_explore_phase3a_regression_test.dart
```

Expected: No issues found for modified files.

- [ ] **Step 7: Run full analyzer and report honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: May still FAIL due to known project-wide historical issues. Report the exact remaining count and do not claim full analyzer is clean unless it is.

- [ ] **Step 8: Do not commit**

No commit should be made unless the user explicitly asks.

## Self-Review

- Spec coverage: This plan covers Nonto naming, explicit default loading/empty states, result tab mapping, lazy rendering preservation, dead-source cleanup, and verification.
- Placeholder scan: No TBD/TODO placeholders are present.
- Type consistency: Helper names and file paths match the planned tests and implementation steps.
