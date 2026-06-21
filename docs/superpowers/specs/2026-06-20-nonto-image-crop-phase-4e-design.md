# Nonto Image Crop Phase 4E Design

## Context

Phase 4D improved the edit-profile entry points for avatar and cover updates. The next profile-adjacent slice is the crop screen used by those flows: `lib/screens/profile/image_crop_screen.dart`.

Current crop behavior is already useful and should be preserved:

- Image bytes are decoded only for the active crop screen.
- The user can drag the crop box, resize corners, and pinch-zoom the image.
- Circle crop is used for avatar-style images.
- Rectangle crop supports a locked aspect ratio for cover-style images.
- The crop action returns PNG bytes to the caller.

The current targeted analyzer reports source-health issues in this file: an undeclared transitive package import, deprecated `Matrix4` transform calls, unnecessary null assertions, and an async-context lint after crop completion.

## Goals

1. Keep the crop screen behavior intact for avatar and cover editing.
2. Remove analyzer issues from `image_crop_screen.dart` without adding new runtime dependencies.
3. Keep the implementation lightweight: no extra image libraries, no eager work outside the active crop screen, no backend/API changes.
4. Keep copy Nonto-owned and functional rather than imitating any other product.
5. Add a source regression test so future UI polish does not reintroduce the known analyzer patterns.

## Non-goals

- No database migrations.
- No upload/service changes.
- No new crop package integration.
- No visual redesign of the crop gestures beyond source-health and small wording cleanup.
- No broad analyzer cleanup outside the touched crop file and new regression test.

## Design

### Source cleanup

`image_crop_screen.dart` should stop importing `package:vector_math/vector_math_64.dart` directly. Flutter already provides `Matrix4`, and the point transformation can use `MatrixUtils.transformPoint`, avoiding reliance on an undeclared transitive dependency.

Deprecated matrix calls should be replaced with the typed alternatives:

- `translateByDouble(_imageOffset.dx, _imageOffset.dy, 0, 1)`
- `scaleByDouble(_imageScale, _imageScale, 1, 1)`

This keeps the same 2D transform semantics while satisfying the current analyzer.

### Null-safety cleanup

The crop routines already return early when no sampled crop coordinate exists. After that guard, promoted local values should be used without redundant `!` operators. This is a source-health cleanup only and should not change crop math.

### Async navigation safety

The confirm button awaits `_doCrop()`, then pops the route with the result. The context use after the async gap should be guarded with `context.mounted` before calling `Navigator.of(context).pop(result)`.

### UX copy

The existing instruction copy is concise and Nonto-owned: `拖动裁剪框 / 拖拽四角调整 / 双指缩放图片`. Keep it unless implementation work reveals a concrete issue.

## Testing

Add `test/nonto_image_crop_phase4e_regression_test.dart` as a source regression test. It should verify:

- the crop screen comment remains Nonto-owned;
- `vector_math` is not imported directly;
- point transforms use `MatrixUtils.transformPoint`;
- matrix transforms use `translateByDouble` and `scaleByDouble` rather than deprecated cascade calls;
- crop completion checks `context.mounted` before popping;
- known redundant null-assertion patterns are absent.

Run the new test RED before production changes, then GREEN after implementation.

## Verification

After implementation:

1. `flutter test test/nonto_image_crop_phase4e_regression_test.dart`
2. `dart analyze lib/screens/profile/image_crop_screen.dart test/nonto_image_crop_phase4e_regression_test.dart`
3. Existing adjacent profile tests:
   - `flutter test test/nonto_profile_phase4a_regression_test.dart test/nonto_edit_profile_phase4d_regression_test.dart test/nonto_image_crop_phase4e_regression_test.dart`
4. Full test suite with the current API/WS defines.
5. Full `flutter analyze` for honest project-wide status. It is expected to still fail on historical issues unless this slice happens to reduce all remaining warnings.