# Nonto User Profile Phase 4C Design

## Goal
Modernize the other-user profile screen so it feels consistent with the current-user Profile tab and the rest of the Nonto social experience, while preserving existing friend, chat, report, block, and post navigation behavior.

## Scope
This slice focuses on `lib/screens/profile/user_profile_screen.dart` plus a source regression test. It does not change backend APIs, persistence, friendship semantics, chat creation, notification semantics, or database schema.

## UX Direction
- Use Nonto-owned profile wording instead of Facebook/Twitter/X labels in source comments and visible copy.
- Align the other-user profile with the current-user profile patterns from Phase 4A:
  - cover + avatar hero remains at the top.
  - display name, username, bio, join date, and friend count stay visible.
  - actions remain prominent and state-aware.
  - posts/likes tabs keep lazy rendering.
- Improve tab content states:
  - shared loading helper for posts and likes.
  - shared empty helper with icon, title, and optional subtitle.
  - friendly empty copy: no posts / no liked posts.
- Keep privacy behavior: online indicator only appears for friends.

## Performance Requirements
- Keep `CustomScrollView` with slivers and `TabBarView`.
- Keep `ListView.builder` for post lists.
- Keep liked posts lazy-loading only when the likes tab is opened.
- Do not introduce eager post widget creation or global refresh loops.

## Implementation Units
- `UserProfileScreen`: low-risk copy/source hygiene and shared profile state helpers.
- Regression test: guard Nonto-owned wording, lazy rendering, friend/chat behavior, online privacy, and helper states.

## Non-Goals
- No redesign of friendship backend model.
- No follow/follower model migration.
- No new API endpoints.
- No new image upload/edit behavior.
- No broad analyzer cleanup outside touched files unless directly caused by this screen.

## Verification
- Run the new Phase 4C regression test.
- Run Phase 4A profile regression tests.
- Run targeted analyzer on touched files.
- Run performance/profile/explore smoke tests.
- Run full Flutter tests with production dart-defines.
- Run full analyzer and report any existing project-wide issues honestly.
