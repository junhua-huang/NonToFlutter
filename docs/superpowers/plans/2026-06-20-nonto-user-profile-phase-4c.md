# Nonto User Profile Phase 4C Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the other-user profile screen for Nonto-owned copy, shared profile state helpers, and consistency with Phase 4A Profile.

**Architecture:** Keep the existing `UserProfileScreen` stateful screen, friend/chat/report/block flows, `CustomScrollView`, `TabBarView`, and `ListView.builder`. Add small private helper methods for loading and empty tab states, clean source wording, and preserve lazy loading of liked posts.

**Tech Stack:** Flutter, Riverpod, existing Nonto theme/widgets, Flutter source regression tests.

---

## Files

- Create: `test/nonto_user_profile_phase4c_regression_test.dart`
  - Source regression tests for Nonto wording, helper states, lazy rendering, friendship/chat behavior, and online privacy.
- Modify: `lib/screens/profile/user_profile_screen.dart`
  - Replace Facebook/Twitter-adjacent comments/copy with Nonto-owned wording.
  - Add `_buildProfileLoadingState()` and `_buildProfileEmptyState(...)`.
  - Use helper states in posts/likes tab lists.
  - Preserve `CustomScrollView`, `SliverPersistentHeader`, `TabBarView`, and `ListView.builder`.

---

### Task 1: Add Phase 4C source regression test

**Files:**
- Create: `test/nonto_user_profile_phase4c_regression_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/nonto_user_profile_phase4c_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4C user profile source regressions', () {
    test('other-user profile uses Nonto-owned wording', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('Nonto 他人资料页'));
      expect(source, isNot(contains('Facebook 风格')));
      expect(source, isNot(contains('Twitter')));
      expect(source, isNot(contains('X-style')));
    });

    test('other-user profile has reusable loading and empty states', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('_buildProfileLoadingState()'));
      expect(source, contains('_buildProfileEmptyState('));
      expect(source, contains('还没有发布帖子'));
      expect(source, contains('还没有喜欢的帖子'));
    });

    test('other-user profile keeps lazy rendering and tab structure', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('CustomScrollView'));
      expect(source, contains('SliverPersistentHeader'));
      expect(source, contains('TabBarView'));
      expect(source, contains('ListView.builder'));
      expect(source, contains('_tabController.index == 1'));
      expect(source, contains('_loadLikedPosts()'));
    });

    test('other-user profile keeps relationship actions and chat behavior', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('FriendService().sendRequest'));
      expect(source, contains('FriendService().acceptRequest'));
      expect(source, contains('FriendService().deleteFriend'));
      expect(source, contains('ChatService().getOrCreateConversation'));
      expect(source, contains('ChatRoomScreen(conversation: conversation)'));
    });

    test('online indicator remains friends-only for privacy', () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(
        source,
        contains('_statusLoaded && _friendStatus == _FriendStatus.friends'),
      );
      expect(source, contains('user.isOnline == true'));
    });
  });
}
```

- [ ] **Step 2: Run RED test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_user_profile_phase4c_regression_test.dart
```

Expected: FAIL because `user_profile_screen.dart` still has `Facebook 风格`, may contain `Twitter`, and lacks the new helper states.

---

### Task 2: Implement low-risk other-user profile polish

**Files:**
- Modify: `lib/screens/profile/user_profile_screen.dart`

- [ ] **Step 1: Update page comment and option-menu comments**

Replace:

```dart
/// 查看其他用户的个人资料页（Facebook 风格）
```

with:

```dart
/// Nonto 他人资料页：资料、关系操作、内容列表与安全操作入口。
```

Replace this comment:

```dart
/// 统一更多选项菜单
```

with:

```dart
/// Nonto 资料页更多操作菜单
```

- [ ] **Step 2: Add shared tab-state helpers**

Add before `_buildPostsList(...)`:

```dart
Widget _buildProfileLoadingState() {
  return const Center(
    child: CircularProgressIndicator(color: AppColors.primary),
  );
}

Widget _buildProfileEmptyState({
  required IconData icon,
  required String title,
  String? subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
```

- [ ] **Step 3: Update posts/likes tab empty calls**

Replace:

```dart
_buildPostsList(_userPosts, _isLoadingPosts, '暂无帖子'),
_buildPostsList(_likedPosts, _isLoadingLikes, '暂无喜欢的帖子'),
```

with:

```dart
_buildPostsList(
  _userPosts,
  _isLoadingPosts,
  icon: Icons.article_outlined,
  emptyTitle: '还没有发布帖子',
  emptySubtitle: 'TA 的新动态会出现在这里',
),
_buildPostsList(
  _likedPosts,
  _isLoadingLikes,
  icon: Icons.favorite_border,
  emptyTitle: '还没有喜欢的帖子',
),
```

- [ ] **Step 4: Update `_buildPostsList` signature and body**

Replace the existing method:

```dart
Widget _buildPostsList(List<Post> posts, bool isLoading, String emptyText) {
  if (isLoading) {
    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
  }
  if (posts.isEmpty) {
    return Center(child: Text(emptyText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)));
  }
  return ListView.builder(
    padding: const EdgeInsets.only(top: 8),
    itemCount: posts.length,
    itemBuilder: (_, i) {
      final post = posts[i];
      return PostCard(
        post: post,
        onLike: () => _togglePostLike(post, i, posts),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PostDetailScreen(postId: post.id),
        )),
      );
    },
  );
}
```

with:

```dart
Widget _buildPostsList(
  List<Post> posts,
  bool isLoading, {
  required IconData icon,
  required String emptyTitle,
  String? emptySubtitle,
}) {
  if (isLoading) {
    return _buildProfileLoadingState();
  }
  if (posts.isEmpty) {
    return _buildProfileEmptyState(
      icon: icon,
      title: emptyTitle,
      subtitle: emptySubtitle,
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.only(top: 8),
    itemCount: posts.length,
    itemBuilder: (_, i) {
      final post = posts[i];
      return PostCard(
        post: post,
        onLike: () => _togglePostLike(post, i, posts),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: post.id),
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 5: Format and run Phase 4C test**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/profile/user_profile_screen.dart test/nonto_user_profile_phase4c_regression_test.dart
cd /d/FlutterProject/nonto && flutter test test/nonto_user_profile_phase4c_regression_test.dart
```

Expected: PASS.

---

### Task 3: Verify profile and full suite

**Files:**
- Test: `test/nonto_user_profile_phase4c_regression_test.dart`
- Existing profile test: `test/nonto_profile_phase4a_regression_test.dart`
- Analyze: `lib/screens/profile/user_profile_screen.dart`, `test/nonto_user_profile_phase4c_regression_test.dart`

- [ ] **Step 1: Run profile regression tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_profile_phase4a_regression_test.dart test/nonto_user_profile_phase4c_regression_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/profile/user_profile_screen.dart test/nonto_user_profile_phase4c_regression_test.dart
```

Expected: ideally no issues in touched files. If analyzer reports pre-existing issues in `user_profile_screen.dart`, fix low-risk source hygiene only if it does not change behavior.

- [ ] **Step 3: Run performance and recent UI smoke tests**

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

- Spec coverage: Plan covers Nonto wording, shared loading/empty states, lazy rendering, liked-post lazy loading, relationship/chat behaviors, online privacy, and verification.
- Placeholder scan: No placeholders remain; all code snippets and commands are concrete.
- Type consistency: Helper names and `_buildPostsList` named parameters match across test and implementation tasks.
