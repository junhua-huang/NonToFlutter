# Nonto Edit Profile Phase 4D Design

## Goal
Modernize the edit-profile screen as the next Profile-area UI/UX slice while cleaning targeted analyzer issues in the touched file.

## Scope
This slice focuses on `lib/screens/profile/edit_profile_screen.dart` and one source regression test. It does not change upload APIs, auth state semantics, image crop behavior, database schema, or backend contracts.

## UX Direction
- Use Nonto-owned source wording for the edit-profile page.
- Keep the current lightweight inline editing model:
  - avatar and cover are changed through pick → crop → upload.
  - name and bio edit inline with save/cancel controls.
- Keep immediate local previews for avatar and cover uploads so users do not wait for remote image refresh.
- Keep optimistic updates for name and bio, with rollback on failure.
- Rename internal color helpers away from `_x...` naming to Nonto-neutral names.

## Source Health Requirements
- Remove unused imports from the edit-profile screen.
- Avoid using `BuildContext` across async gaps before crop navigation.
- Keep targeted analyzer clean for the touched screen and new test.

## Performance Requirements
- Keep the screen as a simple lazy-enough vertical `ListView`; the edit page is small and does not need heavier sliver structure.
- Keep image pick/crop/upload flows sequential and bounded.
- Do not add background polling, new network calls, or global refresh loops.

## Implementation Units
- `EditProfileScreen`: source wording, local helper naming, async-context guard, import cleanup.
- Regression test: guards Nonto wording, direct image-edit flow, immediate local preview, optimistic rollback, and targeted source hygiene.

## Non-Goals
- No new profile editing fields.
- No new cropping UI.
- No changes to `ImageCropScreen`.
- No change to `ProfileTab` routing decisions.
- No broad analyzer cleanup outside the edit-profile screen.

## Verification
- Run the new Phase 4D regression test.
- Run Profile Phase 4A and User Profile Phase 4C regression tests.
- Run targeted analyzer on touched files.
- Run recent UI/performance smoke tests.
- Run full Flutter tests with production dart-defines.
- Run full analyzer and report the remaining project-wide issue count honestly.
