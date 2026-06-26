# Post Share Target Cache Sort Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cached, mixed post-share target list that orders friends and communities by the existing conversation list order.

**Architecture:** Add a focused `PostShareTargetResolver` service that owns cache reads/writes, API fallback, target normalization, and conversation-order sorting. Keep `PostShareToChatSheet` responsible only for rendering targets and sending the selected post to the chosen target.

**Tech Stack:** Flutter/Dart, existing `DataLayer`, `CacheKeys`, `CacheManifest`, `FriendService`, `CommunityApiService`, and Flutter unit/contract tests.

---

## Files

- Create: `lib/services/post_share_target_resolver.dart`
  - Defines `PostShareTargetType`, `PostShareTarget`, parsing helpers, sorting helper, and `PostShareTargetResolver.loadTargets()`.
- Modify: `lib/services/cache_keys.dart`
  - Add `communityMyList` key.
- Modify: `lib/services/cache_manifest.dart`
  - Register `community:my:list` cache metadata.
- Modify: `lib/widgets/post_share_to_chat_sheet.dart`
  - Use resolver output instead of directly loading friend/community APIs.
- Modify: `test/chat_message_types_contract_test.dart`
  - Add failing tests for cache key, manifest registration, mixed sorting, and widget/resolver responsibility split.

## Task 1: Cache key and resolver contract tests

- [ ] Add tests to `test/chat_message_types_contract_test.dart` that expect `CacheKeys.communityMyList`, `PostShareTargetResolver`, `PostShareTargetType.friend`, `PostShareTargetType.community`, and `sortPostShareTargetsByConversationOrder` to exist.
- [ ] Run `flutter test test/chat_message_types_contract_test.dart` and verify the tests fail because the new cache key/service are missing.
- [ ] Add `communityMyList` to `CacheKeys`.
- [ ] Create `lib/services/post_share_target_resolver.dart` with the public model and pure sorting helper.
- [ ] Run the focused test and verify this task passes.

## Task 2: Conversation-order mixed sorting

- [ ] Add a test that builds two friends, two communities, and a mixed `Conversation` list where a community conversation appears before a friend conversation.
- [ ] Assert the sorted target IDs are ordered by conversation list first, then stable fallback order.
- [ ] Run the focused test and verify it fails if sorting is not implemented.
- [ ] Implement the sorting helper using private conversation keys for friends and community keys for groups.
- [ ] Run the focused test and verify it passes.

## Task 3: Cache manifest registration

- [ ] Add a test that reads `lib/services/cache_manifest.dart` and expects `community:my:list` and a `community` domain entry.
- [ ] Run the focused test and verify it fails before implementation.
- [ ] Register `community:my:list` in `CacheManifest.entries` with TTL 300 seconds and `List<Map>` shape.
- [ ] Run the focused test and verify it passes.

## Task 4: Share sheet integration

- [ ] Add a test that reads `lib/widgets/post_share_to_chat_sheet.dart` and expects `PostShareTargetResolver().loadTargets()` usage.
- [ ] Add expectations that the widget renders target type subtitles and no longer performs `Future.wait([FriendService().getFriends(), CommunityApiService().getMy()])` directly.
- [ ] Run the focused test and verify it fails before integration.
- [ ] Modify `PostShareToChatSheet` to use `Future<List<PostShareTarget>>` and switch on target type for rendering/sending.
- [ ] Run the focused test and verify it passes.

## Task 5: Final verification

- [ ] Run `flutter test test/chat_message_types_contract_test.dart test/chat_reliability_regression_test.dart test/permissions_and_unread_regression_test.dart`.
- [ ] Run `git diff --check`.
- [ ] Review `git status --short` and report changed files.
