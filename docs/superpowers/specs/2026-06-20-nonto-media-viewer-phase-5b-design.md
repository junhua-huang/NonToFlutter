# Nonto Media Viewer Phase 5B Design

## Context

The full-screen image viewer is a core social browsing surface. It already supports horizontal paging, zoom, hero transitions, author/content context, and cached network images. Phase 5B should polish the source and remove known analyzer issues while preserving lightweight, lazy media rendering.

Current behavior to preserve:

- Empty image lists close without rendering a broken viewer.
- `PageView.builder` lazily renders image pages.
- `CachedNetworkImage` handles network image loading and error states.
- Tapping toggles the info bar.
- Multi-image posts show a page indicator.
- Author row can navigate to the user profile.
- Text content can expand/collapse.

## Goals

1. Give the image viewer Nonto-owned source wording.
2. Remove current targeted analyzer warnings in `image_viewer_screen.dart`.
3. Keep lazy media rendering and cache-backed image loading.
4. Make overlay visibility logic easier to read with small helper widgets.
5. Preserve author/profile navigation and post context display.
6. Keep gesture behavior simple: tap toggles overlay, double tap resets zoom, vertical swipe changes image only when not zoomed.
7. Add source regression tests for lazy rendering, overlay structure, author navigation, and analyzer cleanup patterns.

## Non-goals

- No replacement with a new image-viewer package.
- No changes to backend image URL storage.
- No database migrations.
- No new download/share feature in this slice.
- No broad refactor of `lib/widgets/media_viewer.dart` or enhanced media viewer widgets.

## Design

### Source wording

Replace the top comment with:

- `Nonto 图片浏览页：沉浸查看帖子图片、作者信息与正文上下文。`

This keeps the product identity without copying another app’s naming.

### Analyzer cleanup

Remove the unused `_isCurrentZoomed()` method. It is redundant because current zoom state is already read directly from `_isZoomedMap` when constructing `_ZoomableImage`.

Remove the unused `_verticalDragOffset` field and its updates. Current vertical navigation behavior depends on gesture velocity, not accumulated offset.

Remove unnecessary author null checks inside `if (author != null)` blocks. Dart promotes `author` after that guard, so nested `if (author != null)` branches are redundant.

### Overlay helpers

Extract small helpers for readability:

- `_buildCloseButton()`
- `_buildPageIndicator(int safeIndex, int total)`
- `_hasInfoBarContent`

The main `Stack` should read as: image pages, close button, optional page indicator, optional info bar.

### Lazy rendering and performance

Keep `PageView.builder` and `CachedNetworkImage`. Do not pre-cache all images in this slice. The screen must continue resolving URLs into a small list of strings and let the builder instantiate only visible pages.

### Gesture behavior

Keep:

- single tap toggles info bar;
- double tap resets zoom when zoomed;
- vertical swipe changes image only when not zoomed;
- `InteractiveViewer` remains the zoom mechanism.

## Testing

Create `test/nonto_media_viewer_phase5b_regression_test.dart` as a source regression suite. It should verify:

- Nonto-owned image viewer wording;
- helper structure for close button, page indicator, and info-bar content;
- lazy/cached rendering with `PageView.builder`, `InteractiveViewer`, and `CachedNetworkImage`;
- author navigation to `UserProfileScreen` remains present;
- known analyzer-warning patterns are absent (`_isCurrentZoomed`, `_verticalDragOffset`, nested `if (author != null)`).

Run RED before production changes, then GREEN after implementation.

## Verification

After implementation:

1. `flutter test test/nonto_media_viewer_phase5b_regression_test.dart`
2. `dart analyze lib/screens/post/image_viewer_screen.dart test/nonto_media_viewer_phase5b_regression_test.dart`
3. Adjacent media/post tests:
   - `flutter test test/nonto_create_post_phase5a_regression_test.dart test/nonto_ui_phase1_regression_test.dart test/nonto_media_viewer_phase5b_regression_test.dart`
4. Full test suite with current API/WS defines.
5. Full `flutter analyze` for honest project-wide status.