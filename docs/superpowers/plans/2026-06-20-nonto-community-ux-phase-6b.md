# Nonto Community UX Phase 6B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the community discovery/detail/create/chat surfaces into a more mature Nonto social-product experience while preserving lazy rendering and bounded loading.

**Architecture:** Keep existing Riverpod/service boundaries and route behavior. Polish source-level UI structure in the community screens with small reusable helpers, builder-based lists, centralized empty/error states, and Nonto-owned labels. Do not introduce database migrations, eager post/message widget creation, or Twitter/X proprietary wording.

**Tech Stack:** Flutter, Riverpod, Material widgets, existing `CommunityApiService`, existing source regression tests, `flutter analyze`, `flutter test` with production dart-defines.

---

## File Structure

- Modify `test/nonto_community_phase6b_regression_test.dart`: source regression tests for community UX and performance constraints.
- Modify `lib/screens/community/community_list_screen.dart`: discovery hub polish, lazy list sections, stats chips, improved empty/error/loading states.
- Modify `lib/screens/community/community_detail_screen.dart`: hero/header extraction, member preview, announcement/rules cards, lazy post list rendering.
- Modify `lib/screens/community/community_create_screen.dart`: clearer creation wizard copy, progress indicator, safer submit affordances.
- Modify `lib/screens/community/community_chat_screen.dart`: chat empty state, composer affordance, bounded message list behavior, safer send state.
- Optionally modify `lib/providers/community_notifier.dart` only if needed to expose loading semantics without changing API contracts.

## Task 1: Source Regression Test

**Files:**
- Create: `test/nonto_community_phase6b_regression_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 6B community UX source regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('community surfaces use Nonto-owned product language', () {
      final list = read('lib/screens/community/community_list_screen.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');
      final create = read('lib/screens/community/community_create_screen.dart');
      final chat = read('lib/screens/community/community_chat_screen.dart');

      expect(list, contains('Nonto 社群广场'));
      expect(detail, contains('社群动态'));
      expect(create, contains('创建一个有温度的社群'));
      expect(chat, contains('在社群里开始第一句交流'));
      expect('$list$detail$create$chat', isNot(contains('推特')));
      expect('$list$detail$create$chat', isNot(contains('Twitter')));
      expect('$list$detail$create$chat', isNot(contains('X ')));
    });

    test('community discovery and detail keep lazy rendering', () {
      final list = read('lib/screens/community/community_list_screen.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');
      final chat = read('lib/screens/community/community_chat_screen.dart');

      expect(list, contains('ListView.builder'));
      expect(list, contains('_buildDiscoveryItem'));
      expect(detail, contains('SliverList.builder'));
      expect(detail, isNot(contains('...state.posts.map')));
      expect(chat, contains('ListView.builder'));
      expect(chat, contains('reverse: true'));
    });

    test('community screens have reusable loading empty and action helpers', () {
      final list = read('lib/screens/community/community_list_screen.dart');
      final detail = read('lib/screens/community/community_detail_screen.dart');
      final create = read('lib/screens/community/community_create_screen.dart');
      final chat = read('lib/screens/community/community_chat_screen.dart');

      expect(list, contains('_buildHeroHeader'));
      expect(list, contains('_buildEmptyDiscoveryState'));
      expect(detail, contains('_buildCommunityHeader'));
      expect(detail, contains('_buildPostEmptyState'));
      expect(create, contains('_buildStepProgress'));
      expect(chat, contains('_buildComposer'));
      expect(chat, contains('_buildEmptyMessagesState'));
    });
  });
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_community_phase6b_regression_test.dart
```

Expected: FAIL because the Phase 6B helper names and copy do not exist yet.

## Task 2: Community Discovery Hub Polish

**Files:**
- Modify: `lib/screens/community/community_list_screen.dart`
- Test: `test/nonto_community_phase6b_regression_test.dart`

- [ ] **Step 1: Implement discovery hub structure**

Add helpers:

```dart
Widget _buildHeroHeader(CommunityListState state)
Widget _buildMyCommunitiesSection(CommunityListState state)
Widget _buildDiscoverySection(CommunityListState state)
Widget _buildDiscoveryItem(Community community)
Widget _buildEmptyDiscoveryState()
Widget _buildCommunityAvatar(Community community, {double radius = 28})
String _formatCount(int value)
```

Keep `ListView.builder` for discovered communities and `ListView.separated` for my communities. Avoid converting discovery results to a spread list.

- [ ] **Step 2: Run focused test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_community_phase6b_regression_test.dart
```

Expected: still may fail on detail/create/chat until later tasks.

## Task 3: Community Detail Polish

**Files:**
- Modify: `lib/screens/community/community_detail_screen.dart`
- Test: `test/nonto_community_phase6b_regression_test.dart`

- [ ] **Step 1: Replace eager post spread with slivers**

Use `CustomScrollView` and `SliverList.builder` for posts. Extract:

```dart
Widget _buildCommunityHeader(Community c, CommunityDetailState state, ThemeData theme)
Widget _buildQuickStats(Community c)
Widget _buildRulesCard(Community c, ThemeData theme)
Widget _buildSortBar(CommunityDetailState state)
Widget _buildPostEmptyState()
Widget _buildPostTile(Post post)
```

Preserve join/leave/chat/post/manage behavior and existing providers.

- [ ] **Step 2: Run focused test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_community_phase6b_regression_test.dart
```

Expected: create/chat assertions may still fail until later tasks.

## Task 4: Create Community Wizard Polish

**Files:**
- Modify: `lib/screens/community/community_create_screen.dart`
- Test: `test/nonto_community_phase6b_regression_test.dart`

- [ ] **Step 1: Add clearer wizard chrome**

Extract:

```dart
Widget _buildStepProgress()
Widget _buildIntroCard()
Widget _buildCoverPlaceholder()
Widget _buildJoinPolicyCard(Map<String, String> option)
bool get _canContinue
```

Make the first step primary button disabled until the name is non-empty. Keep network submit unchanged.

- [ ] **Step 2: Run focused test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_community_phase6b_regression_test.dart
```

Expected: chat assertions may still fail until Task 5.

## Task 5: Community Chat Polish

**Files:**
- Modify: `lib/screens/community/community_chat_screen.dart`
- Test: `test/nonto_community_phase6b_regression_test.dart`

- [ ] **Step 1: Add mature chat empty/composer states**

Extract:

```dart
Widget _buildMessageList()
Widget _buildEmptyMessagesState()
Widget _buildComposer()
bool get _canSend
```

Keep `ListView.builder`, set `reverse: true`, and render messages by reversed index instead of creating a reversed list. Add local `_isSending` to disable duplicate sends while awaiting API.

- [ ] **Step 2: Run focused test**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_community_phase6b_regression_test.dart
```

Expected: PASS.

## Task 6: Verification

**Files:**
- All touched files.

- [ ] **Step 1: Format**

Run:

```bash
cd /d/FlutterProject/nonto && dart format test/nonto_community_phase6b_regression_test.dart lib/screens/community/community_list_screen.dart lib/screens/community/community_detail_screen.dart lib/screens/community/community_create_screen.dart lib/screens/community/community_chat_screen.dart
```

Expected: files formatted.

- [ ] **Step 2: Targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze test/nonto_community_phase6b_regression_test.dart lib/screens/community/community_list_screen.dart lib/screens/community/community_detail_screen.dart lib/screens/community/community_create_screen.dart lib/screens/community/community_chat_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Full tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: All tests pass.

- [ ] **Step 4: Full analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: No issues found.

- [ ] **Step 5: Commit**

Run:

```bash
cd /d/FlutterProject/nonto && git add test/nonto_community_phase6b_regression_test.dart lib/screens/community/community_list_screen.dart lib/screens/community/community_detail_screen.dart lib/screens/community/community_create_screen.dart lib/screens/community/community_chat_screen.dart docs/superpowers/plans/2026-06-20-nonto-community-ux-phase-6b.md && git commit -m "Polish Nonto community UX"
```

Expected: a follow-up commit on `nonto-ui-ux-analyzer-cleanup`.

## Self-Review

- Spec coverage: covers discovery, detail, creation, chat, performance, and verification.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: helper names match test assertions and implementation tasks.
