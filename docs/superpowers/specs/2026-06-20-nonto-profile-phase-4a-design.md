# Nonto Profile Phase 4A Design

**Date:** 2026-06-20

## Goal

Modernize the current user's Profile tab with Nonto-owned language, clearer reusable profile states, and small source hygiene improvements while keeping the existing data flow and scroll architecture stable.

## Scope

Included:

1. Replace Twitter/X-specific profile wording with Nonto profile wording.
2. Keep `NestedScrollView`, `SliverAppBar`, `TabBarView`, `ListView.builder`, and `GridView.builder` performance paths.
3. Add small reusable helpers for profile tab loading and empty states.
4. Apply those helpers to posts, likes, and photos tab content so the page feels consistent.
5. Remove unused profile imports/fields that are already analyzer noise and are not used by this screen.
6. Keep avatar/cover edit flow intact; do not rewrite upload/crop logic in this slice.

Out of scope:

- Backend API changes.
- DB migrations.
- Full profile architecture split.
- Editing flow rewrite.
- Other-user profile screen redesign.
- Notification/Profile global theme migration.

## Design

Phase 4A updates `ProfileTab` in place because the file is large but currently owns data loading, header, tabs, edit flow, and post interactions. This slice does not split the file yet; instead, it introduces a few private helpers that make the content states more consistent and easier to test.

`_buildProfileLoadingState()` returns an always-scrollable list with a compact centered spinner. `_buildProfileEmptyState(...)` returns an always-scrollable list with a consistent icon/title/subtitle pattern. Posts, likes, and photo grid empty/loading states use these helpers.

The profile comment changes from Twitter/X wording to Nonto wording. Obvious unused imports and unused local avatar preview fields are removed because they contribute to analyzer noise without changing behavior.

## Performance Rules

- Do not replace existing builder lists/grids with eager `Column`/`map` rendering.
- Do not add new network requests.
- Keep refresh behavior and post cache synchronization intact.
- Keep uploads/cropping untouched.

## Verification

Add source-level regression tests for the Phase 4A profile slice, run red/green, format modified files, run targeted tests, full Flutter tests with existing dart-defines, targeted analyzer, and full analyzer with honest remaining issue count.
