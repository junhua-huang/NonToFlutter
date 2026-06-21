# Nonto Dark Mode and Search Card Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make dark mode work consistently across all existing pages through centralized semantic color tokens, and make search-result post cards match the home feed card.

**Architecture:** Keep Nonto brand colors stable while turning legacy `AppColors` surface/text/border tokens into runtime theme-aware semantic colors. This gives broad page coverage without rewriting every screen at once, then explicitly unify search post rendering by reusing `PostCard` in search result paths.

**Tech Stack:** Flutter, Riverpod, Material 3 `ThemeData`, source regression tests with `flutter_test`.

---

## File Map

- Modify `lib/config/app_theme.dart`: add runtime brightness syncing and adaptive semantic colors.
- Modify `lib/main.dart`: sync `AppColors` with selected `ThemeMode`, centralize light/dark theme colors.
- Modify `lib/providers/theme_notifier.dart`: default unset preference to `ThemeMode.system`.
- Modify `lib/screens/search/search_tab.dart`: use `PostCard` for main search post results.
- Modify `lib/screens/search/search_results_screen.dart`: use `PostCard` for topic post results and remove compact `_PostTile`.
- Add/modify `test/nonto_dark_mode_search_parity_regression_test.dart`: source regressions for adaptive colors and card parity.

## Task 1: RED regression tests

- [ ] Add `test/nonto_dark_mode_search_parity_regression_test.dart` checking:
  - `AppColors` has brightness syncing and non-const adaptive semantic getters.
  - `theme_notifier.dart` defaults null saved theme to `ThemeMode.system`.
  - `search_tab.dart` `_buildPostTile` returns `PostCard` with `feedPosts: _postResults`.
  - `search_results_screen.dart` `ListView.builder` uses `PostCard` with `feedPosts: _posts` and no `_PostTile` class remains.
- [ ] Run `flutter test test/nonto_dark_mode_search_parity_regression_test.dart` and confirm it fails.

## Task 2: Adaptive color infrastructure

- [ ] Update `AppColors` to retain fixed brand colors and make semantic colors runtime-adaptive:
  - `background`, `backgroundSecondary`, `surface`
  - `textPrimary`, `textSecondary`, `textTertiary`
  - `borderLight`, `borderDivider`
  - `dragHandle`, `selectionHighlight`
- [ ] Add `AppColors.syncThemeMode(ThemeMode mode)` and compute system brightness for `ThemeMode.system`.
- [ ] Call `AppColors.syncThemeMode(themeMode)` in `lib/main.dart` before building `MaterialApp`.
- [ ] Update `theme_notifier.dart` so no saved value means `ThemeMode.system`.

## Task 3: Remove const contexts broken by adaptive colors

- [ ] Run targeted analyzer.
- [ ] Remove only the `const` markers that wrap adaptive `AppColors` getters.
- [ ] Keep lazy list rendering and existing widget structure unchanged.

## Task 4: Search card parity

- [ ] Replace `SearchTab._buildPostTile` compact implementation with shared `PostCard`.
- [ ] Replace topic search `_PostTile` usage with shared `PostCard` and delete unused compact tile/imports.
- [ ] Preserve navigation to `PostDetailScreen` and pass surrounding result lists as `feedPosts`.

## Task 5: Verification and commit

- [ ] Run `dart format` on changed files.
- [ ] Run focused tests.
- [ ] Run targeted analyzer for changed files.
- [ ] Run full tests with production dart-defines.
- [ ] Run full analyzer.
- [ ] Commit with message `Improve dark mode and search post card parity`.
