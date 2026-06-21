# Nonto Create Post Phase 5A Design

## Context

The create-post screen is one of the highest-impact social UX surfaces. It already supports text, images, video, emoji, mentions, topics, upload progress, optimistic feed/profile refresh, and draft recovery. Phase 5A should improve source clarity and interaction reliability without changing backend contracts or introducing heavier media work.

Current behavior to preserve:

- Text posts, image posts, video posts, and mixed text/media posts are allowed.
- Images stay bounded to 9 and use `ReorderableListView.builder` for horizontal preview sorting.
- Video remains mutually exclusive with images.
- Upload progress remains visible while submitting.
- Drafts are saved on exit/failure and cleared on successful publish.
- Successful publish still notifies home feed and profile through existing notifiers.

## Goals

1. Give the composer Nonto-owned source wording and neutral helper names.
2. Centralize composer state (`has content`, `over limit`, `can submit`) so button behavior is easier to reason about.
3. Keep the submit button responsive and visually stable while publishing.
4. Keep the bottom composer toolbar lightweight and readable.
5. Add mounted guards around async draft/media flows.
6. Remove the known analyzer warning in `create_post_screen.dart`.
7. Add source regression tests to protect lazy media rendering and composer reliability.

## Non-goals

- No backend/API changes.
- No database migrations.
- No new media compression libraries.
- No changes to upload endpoints.
- No rewrite of media preview pages.
- No attempt to solve all project-wide analyzer issues in this slice.

## Design

### Naming and source wording

Replace the generic page comment with:

- `Nonto 创作页：文本、图片、视频、话题与草稿的一体化发布入口。`

Rename internal Twitter/X-style color helpers to Nonto-neutral names:

- `_xBlue` → `_accentColor`
- `_xBlack` → `_primaryTextColor`
- `_xDarkGrey` → `_secondaryTextColor`

### Composer state helpers

Add computed getters:

- `_hasComposerContent`
- `_isOverCharacterLimit`
- `_canSubmitPost`

Use these in `build` and submit-button construction instead of duplicating boolean logic inline.

### Submit button

Extract app-bar submit action into `_buildSubmitButton()`. It should:

- disable while submitting;
- disable when empty;
- disable when over character limit;
- show a compact spinner while publishing;
- keep the label `发布` for Nonto-owned copy.

Use `AnimatedSwitcher` for a small state transition without adding heavyweight animation.

### Toolbar and status

Extract the bottom toolbar into `_buildComposerToolbar({required bool isOverLimit})`. Keep it horizontally scrollable because labels may overflow on narrow screens. Preserve tool actions for images, video, mentions, topics, and emoji.

Keep character counter in the toolbar and highlight it red when over limit.

### Async reliability

Add `if (!mounted) return;` after async boundaries before mutating UI state in:

- `_restoreDraft()` after loading `SharedPreferences` and before restored media `setState`;
- `_pickImages()` after picker returns and after async byte reads;
- `_pickVideo()` after picker/compression/read/thumbnail work before `setState`;
- `_toggleVideoPlayback()` after video initialization before `setState`;
- successful submit after `_clearDraft()` before navigating back.

Remove the obsolete `picked == null` branch in `_pickImages()` because `pickMultiImage` returns a non-null list in the current package version. This removes the targeted analyzer warning.

## Testing

Create `test/nonto_create_post_phase5a_regression_test.dart` as a source regression suite. It should verify:

- Nonto-owned composer wording is present and old `_x...` helper names are absent;
- composer state helpers and submit-button helper exist;
- toolbar helper exists and preserves the same actions;
- async media/draft flows contain mounted guards;
- obsolete `picked == null` check is gone;
- media preview rendering remains lazy/bounded (`ReorderableListView.builder`, `PageView.builder`, `GridView.builder`).

Run RED before production changes, then GREEN after implementation.

## Verification

After implementation:

1. `flutter test test/nonto_create_post_phase5a_regression_test.dart`
2. `dart analyze lib/screens/post/create_post_screen.dart test/nonto_create_post_phase5a_regression_test.dart`
3. Adjacent UI regression tests:
   - `flutter test test/nonto_ui_phase1_regression_test.dart test/page_performance_regression_test.dart test/nonto_create_post_phase5a_regression_test.dart`
4. Full test suite with current API/WS defines.
5. Full `flutter analyze` for honest project-wide status.