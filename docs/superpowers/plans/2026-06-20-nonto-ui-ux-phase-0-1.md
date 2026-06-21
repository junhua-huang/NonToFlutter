# Nonto UI/UX Phase 0+1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the minimal Nonto UI foundation and modernize Home Feed/PostCard/Post Detail with cursor-aware pagination and shared post actions.

**Architecture:** Keep the current Flutter/Riverpod architecture and avoid a full app rewrite. Add focused Nonto shared widgets/helpers, upgrade the feed service/state/notifier to consume backend `cursor`/`next_cursor`, and incrementally replace duplicated post action UI in feed/detail with one shared component.

**Tech Stack:** Flutter, Dart, Riverpod `StateNotifier`, `pull_to_refresh_flutter3`, existing `ApiClient`, existing `PostCard`, existing `PostDetailScreen`, source-regression tests under `test/`.

**Commit policy:** Do not commit in this session unless the user explicitly asks. The skill template mentions commits, but the active user constraint overrides it.

---

## File Structure

### Create

- `lib/widgets/nonto/nonto_post_action_bar.dart`
  - Shared post action row for comment/like/view/share-ready UI.
  - Exposes `formatNontoCompactCount(int count)` for consistent count formatting.

- `test/nonto_ui_phase1_regression_test.dart`
  - Source and pure-function regression tests for cursor feed state/service and shared post action usage.

### Modify

- `lib/services/api/recommendation_service.dart`
  - Add optional `cursor` to `getFeed` and include it in request params only when non-empty.

- `lib/providers/feed_notifier.dart`
  - Add `nextCursor`, `feedStatus`, `isInitialLoading`, `isRefreshing`, `isLoadingMore`, and cursor-aware request flow.
  - Keep old posts during refresh failure.
  - Deduplicate appended posts.

- `lib/screens/home/home/feed_tab.dart`
  - Use new loading flags instead of single `isLoading` where visible.
  - Show friendlier load-more footer copy for exhausted feed.

- `lib/widgets/post_card.dart`
  - Replace private action row with `NontoPostActionBar`.
  - Keep existing media/header/menu behavior.

- `lib/screens/post/post_detail_screen.dart`
  - Replace private detail action row with `NontoPostActionBar`.
  - Keep existing post detail fetch/comment behavior.

---

## Task 1: Add shared post action bar and count formatting

**Files:**
- Create: `lib/widgets/nonto/nonto_post_action_bar.dart`
- Test: `test/nonto_ui_phase1_regression_test.dart`

- [ ] **Step 1: Write failing tests for count formatting and shared component presence**

Add this group to `test/nonto_ui_phase1_regression_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/widgets/nonto/nonto_post_action_bar.dart';

String readSource(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  group('Nonto post action bar', () {
    test('formats compact counts consistently', () {
      expect(formatNontoCompactCount(0), '');
      expect(formatNontoCompactCount(9), '9');
      expect(formatNontoCompactCount(999), '999');
      expect(formatNontoCompactCount(1000), '1K');
      expect(formatNontoCompactCount(1200), '1.2K');
      expect(formatNontoCompactCount(10000), '1万');
      expect(formatNontoCompactCount(34500), '3.4万');
    });

    test('post feed and detail use the shared action bar', () {
      final feedCard = readSource('lib/widgets/post_card.dart');
      final detail = readSource('lib/screens/post/post_detail_screen.dart');
      expect(feedCard, contains('NontoPostActionBar'));
      expect(detail, contains('NontoPostActionBar'));
    });
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart
```

Expected: fail because `nonto_post_action_bar.dart` does not exist and post files do not use `NontoPostActionBar`.

- [ ] **Step 3: Add the shared action bar**

Create `lib/widgets/nonto/nonto_post_action_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';

String formatNontoCompactCount(int count) {
  if (count <= 0) return '';
  if (count < 1000) return '$count';
  if (count < 10000) {
    final value = count / 1000;
    return value == value.truncateToDouble()
        ? '${value.toInt()}K'
        : '${value.toStringAsFixed(1)}K';
  }
  final value = count / 10000;
  return value == value.truncateToDouble()
      ? '${value.toInt()}万'
      : '${value.toStringAsFixed(1)}万';
}

class NontoPostActionBar extends StatelessWidget {
  final int commentCount;
  final int likeCount;
  final int viewCount;
  final bool isLiked;
  final VoidCallback onComment;
  final VoidCallback onLike;
  final VoidCallback onView;
  final VoidCallback? onShare;
  final EdgeInsetsGeometry padding;

  const NontoPostActionBar({
    super.key,
    required this.commentCount,
    required this.likeCount,
    required this.viewCount,
    required this.isLiked,
    required this.onComment,
    required this.onLike,
    required this.onView,
    this.onShare,
    this.padding = const EdgeInsets.fromLTRB(8, 8, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          NontoPostActionButton(
            icon: Icons.comment_outlined,
            count: commentCount,
            onTap: onComment,
          ),
          NontoPostActionButton(
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            count: likeCount,
            color: isLiked ? AppColors.likeRed : null,
            onTap: onLike,
          ),
          NontoPostActionButton(
            icon: Icons.bar_chart,
            count: viewCount,
            onTap: onView,
          ),
          if (onShare != null)
            NontoPostActionButton(
              icon: Icons.ios_share_outlined,
              count: 0,
              onTap: onShare!,
            ),
        ],
      ),
    );
  }
}

class NontoPostActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const NontoPostActionButton({
    super.key,
    required this.icon,
    required this.count,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;
    final label = formatNontoCompactCount(count);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: effectiveColor),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(color: effectiveColor, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the formatting portion again**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "formats compact counts consistently"
```

Expected: pass.

---

## Task 2: Add cursor support to recommendation feed service

**Files:**
- Modify: `lib/services/api/recommendation_service.dart`
- Test: `test/nonto_ui_phase1_regression_test.dart`

- [ ] **Step 1: Add failing source regression test**

Append this test inside `main()` in `test/nonto_ui_phase1_regression_test.dart`:

```dart
  group('cursor feed service', () {
    test('recommendation feed accepts optional cursor without sending empty cursor', () {
      final source = readSource('lib/services/api/recommendation_service.dart');
      expect(source, contains('String? cursor'));
      expect(source, contains("if (cursor != null && cursor.isNotEmpty) 'cursor': cursor"));
      expect(source, contains("'per_page': perPage"));
    });
  });
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "recommendation feed accepts optional cursor without sending empty cursor"
```

Expected: fail because `cursor` is not in `RecommendationService.getFeed`.

- [ ] **Step 3: Implement service cursor parameter**

Change `RecommendationService.getFeed` to:

```dart
  Future<ApiResponse> getFeed({int page = 1, int perPage = 20, String? cursor}) =>
      _api.getDeduped('/recommendations/feed', params: {
        'page': page,
        'per_page': perPage,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      });
```

- [ ] **Step 4: Re-run targeted test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "recommendation feed accepts optional cursor without sending empty cursor"
```

Expected: pass.

---

## Task 3: Upgrade FeedState and FeedNotifier to cursor-aware loading

**Files:**
- Modify: `lib/providers/feed_notifier.dart`
- Test: `test/nonto_ui_phase1_regression_test.dart`

- [ ] **Step 1: Add failing source regression tests**

Append this group to `test/nonto_ui_phase1_regression_test.dart`:

```dart
  group('cursor feed notifier', () {
    test('feed state tracks cursor and separated loading states', () {
      final source = readSource('lib/providers/feed_notifier.dart');
      expect(source, contains('final String? nextCursor;'));
      expect(source, contains('final String? feedStatus;'));
      expect(source, contains('final bool isInitialLoading;'));
      expect(source, contains('final bool isRefreshing;'));
      expect(source, contains('final bool isLoadingMore;'));
    });

    test('feed notifier sends cursor on load more and deduplicates appended posts', () {
      final source = readSource('lib/providers/feed_notifier.dart');
      expect(source, contains('cursor: state.page == 1 ? null : state.nextCursor'));
      expect(source, contains('_mergeUniquePosts'));
      expect(source, contains("data['next_cursor'] as String?"));
      expect(source, contains("data['feed_status'] as String?"));
    });
  });
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "feed state tracks cursor and separated loading states"
```

Expected: fail because the new fields do not exist.

- [ ] **Step 3: Replace `FeedState` with cursor-aware state**

In `lib/providers/feed_notifier.dart`, update `FeedState` to include:

```dart
class FeedState {
  final List<Post> posts;
  final int page;
  final String? nextCursor;
  final String? feedStatus;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? error;
  final DateTime? lastUpdatedAt;

  const FeedState({
    this.posts = const [],
    this.page = 1,
    this.nextCursor,
    this.feedStatus,
    this.hasMore = true,
    this.isInitialLoading = true,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.error,
    this.lastUpdatedAt,
  });

  bool get isLoading => isInitialLoading || isRefreshing || isLoadingMore;

  FeedState copyWith({
    List<Post>? posts,
    int? page,
    String? nextCursor,
    bool clearNextCursor = false,
    String? feedStatus,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    DateTime? lastUpdatedAt,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      page: page ?? this.page,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      feedStatus: feedStatus ?? this.feedStatus,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}
```

- [ ] **Step 4: Update feed response fetching and post application**

In `FeedNotifier`, update `_fetchFeedResponse`, add `_mergeUniquePosts`, and update `_applyPostsFromData`:

```dart
  List<Post> _mergeUniquePosts(List<Post> existing, List<Post> incoming) {
    final seen = existing.map((p) => p.id).toSet();
    final merged = List<Post>.from(existing);
    for (final post in incoming) {
      if (seen.add(post.id)) merged.add(post);
    }
    return merged;
  }

  void _applyPostsFromData(Map<String, dynamic> data, List postsJson) {
    final posts =
        postsJson.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    final isFirstPage = state.page == 1;
    final nextCursor = data['next_cursor'] as String?;
    final feedStatus = data['feed_status'] as String?;
    final newPosts = isFirstPage ? posts : _mergeUniquePosts(state.posts, posts);
    state = state.copyWith(
      posts: newPosts,
      hasMore: data['has_more'] == true || (nextCursor != null && nextCursor.isNotEmpty),
      nextCursor: nextCursor,
      feedStatus: feedStatus,
      page: state.page + 1,
      clearError: true,
      lastUpdatedAt: DateTime.now(),
    );
    _syncFeedToCache();
  }

  Future<Map<String, dynamic>?> _fetchFeedResponse() async {
    try {
      final resp = await RecommendationService().getFeed(
        page: state.page,
        cursor: state.page == 1 ? null : state.nextCursor,
      );
      if (resp.success && resp.data != null) {
        return resp.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('FeedNotifier recommendation error: $e');
    }
    try {
      final resp = await PostService().getFeed(page: state.page);
      if (resp.success && resp.data != null) {
        return resp.data as Map<String, dynamic>;
      }
    } catch (e2) {
      debugPrint('FeedNotifier fallback error: $e2');
    }
    return null;
  }
```

- [ ] **Step 5: Update refresh/load-more flags**

Use these bodies:

```dart
  Future<void> _fetchAndRefreshFeed() async {
    try {
      final data = await _fetchFeedResponse();
      if (data != null) {
        final List postsJson = data['posts'] ?? data['items'] ?? [];
        _applyPostsFromData(data, postsJson);
      } else {
        state = state.copyWith(
          error: state.posts.isEmpty ? '加载失败' : '刷新失败，正在显示上次内容',
        );
      }
    } catch (e) {
      debugPrint('FeedNotifier _fetchAndRefreshFeed error: $e');
      state = state.copyWith(
        error: state.posts.isEmpty ? '加载失败' : '刷新失败，正在显示上次内容',
      );
    } finally {
      state = state.copyWith(
        isInitialLoading: false,
        isRefreshing: false,
        isLoadingMore: false,
      );
    }
  }

  Future<void> refreshPosts() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    state = state.copyWith(
      isRefreshing: state.posts.isNotEmpty,
      isInitialLoading: state.posts.isEmpty,
      isLoadingMore: false,
      page: 1,
      hasMore: true,
      clearNextCursor: true,
      clearError: true,
    );
    await _fetchAndRefreshFeed();
    _loadInProgress = false;
  }

  Future<void> loadPosts() async {
    if (!state.hasMore) return;
    if (_loadInProgress) return;
    _loadInProgress = true;
    state = state.copyWith(isLoadingMore: true, clearError: true);
    await _fetchAndRefreshFeed();
    _loadInProgress = false;
  }
```

- [ ] **Step 6: Re-run feed notifier tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "feed notifier sends cursor on load more and deduplicates appended posts"
```

Expected: pass.

---

## Task 4: Update FeedTab for separated loading state and friendly footer copy

**Files:**
- Modify: `lib/screens/home/home/feed_tab.dart`
- Test: `test/nonto_ui_phase1_regression_test.dart`

- [ ] **Step 1: Add failing source test**

Append:

```dart
  group('feed tab cursor UX', () {
    test('feed tab uses initial loading and friendly exhausted copy', () {
      final source = readSource('lib/screens/home/home/feed_tab.dart');
      expect(source, contains('feedState.isInitialLoading'));
      expect(source, contains('你已经看完最近动态'));
      expect(source, contains('下面是更早一些的动态'));
    });
  });
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "feed tab uses initial loading and friendly exhausted copy"
```

Expected: fail.

- [ ] **Step 3: Update skeleton condition**

In `_buildFeedContent`, change the first condition to:

```dart
    if (feedState.isInitialLoading && feedState.posts.isEmpty) {
```

- [ ] **Step 4: Update footer copy**

In the `CustomFooter`, replace the `else` branch body text with status-aware copy:

```dart
                    final doneText = feedState.feedStatus == 'fallback'
                        ? '下面是更早一些的动态'
                        : '你已经看完最近动态';
                    body = Text(doneText,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13));
```

- [ ] **Step 5: Re-run targeted test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "feed tab uses initial loading and friendly exhausted copy"
```

Expected: pass.

---

## Task 5: Replace duplicated post action rows with `NontoPostActionBar`

**Files:**
- Modify: `lib/widgets/post_card.dart`
- Modify: `lib/screens/post/post_detail_screen.dart`
- Test: `test/nonto_ui_phase1_regression_test.dart`

- [ ] **Step 1: Update imports**

Add to both files:

```dart
import 'package:nonto/widgets/nonto/nonto_post_action_bar.dart';
```

- [ ] **Step 2: Replace `PostCard` action row**

In `lib/widgets/post_card.dart`, replace the action `Padding`/`Row` block with:

```dart
          NontoPostActionBar(
            commentCount: post.commentCount,
            likeCount: post.likeCount,
            viewCount: post.viewCount,
            isLiked: post.isLiked == true,
            onComment: onTap,
            onLike: onLike ?? () {},
            onView: () => _showPostStats(context, post),
          ),
```

- [ ] **Step 3: Replace detail action row**

In `lib/screens/post/post_detail_screen.dart`, replace the detail action `Padding`/`Row` block with:

```dart
        NontoPostActionBar(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
          commentCount: post.commentCount,
          likeCount: post.likeCount,
          viewCount: post.viewCount,
          isLiked: post.isLiked == true,
          onComment: () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          onLike: _toggleLike,
          onView: () => _showPostStatsDetail(post),
        ),
```

- [ ] **Step 4: Remove now-unused private action classes if analyzer reports them unused**

Delete `_ActionIcon` from `post_card.dart` if unused.
Delete `_Action` from `post_detail_screen.dart` if unused.

- [ ] **Step 5: Run shared action usage test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart --plain-name "post feed and detail use the shared action bar"
```

Expected: pass.

---

## Task 6: Run full Phase 1 regression tests and analyzer

**Files:**
- Test: `test/nonto_ui_phase1_regression_test.dart`

- [ ] **Step 1: Run the new regression test file**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_ui_phase1_regression_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run existing lightweight tests likely affected by source changes**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart test/image_utils_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: no new errors from modified files. If existing unrelated warnings appear, record them separately.

---

## Task 7: Manual smoke checklist

No code changes in this task.

- [ ] **Step 1: Home first load**

Expected:

- feed skeleton appears only when there are no cached posts
- existing cached posts remain visible during refresh

- [ ] **Step 2: Pull refresh**

Expected:

- refresh sends a first-page request without cursor
- old posts remain visible if refresh fails

- [ ] **Step 3: Load more**

Expected:

- load-more uses `next_cursor`
- duplicate posts are not appended
- exhausted footer shows `你已经看完最近动态`
- fallback footer shows `下面是更早一些的动态`

- [ ] **Step 4: Post actions**

Expected:

- feed post comment opens detail
- like toggles optimistically
- stats opens post stats
- detail post actions have the same formatting and touch sizing as feed

---

## Self-Review

- Spec coverage: This plan covers Phase 0 + Phase 1 only, as required. Messages, Explore, Profile, and Notifications are intentionally deferred.
- Placeholder scan: No implementation step uses unspecified placeholder code.
- Type consistency: `nextCursor`, `feedStatus`, `isInitialLoading`, `isRefreshing`, and `isLoadingMore` are consistently named across tasks.
- User constraint: No commit steps are included because the user did not explicitly request commits.
