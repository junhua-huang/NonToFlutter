# Nonto Explore/Search Phase 3B Design

**Date:** 2026-06-20

## Goal

Improve Explore/Search interaction reliability and perceived polish without changing backend contracts: avoid stale search responses, stop fake empty searches from discovery actions, and make live suggestions match Nonto theme surfaces.

## Scope

Included:

1. Add stale-response generation protection to `SearchTab._doSearch` so slower old searches cannot overwrite newer search results.
2. Replace the recommended-users `查看全部` empty-search action with a local search-focus action that opens the search affordance without making a backend request.
3. Keep trending topics/posts actions as intentional searches because they already map to meaningful backend special result types.
4. Make `SearchSuggestions` use app theme surface colors instead of hard-coded white and allow suggestion modules to settle independently with `Future.wait(..., eagerError: false)` and per-request fallbacks.
5. Preserve lazy rendering and existing debounce behavior.

Out of scope:

- Backend API changes.
- Full search result pagination inside `SearchTab`.
- Shared `NontoSearchBar` extraction.
- Profile/notification UI work.
- DB migrations.

## Design

`SearchTab` gets a private `_searchGeneration` integer. Every submitted search increments it and stores a local generation token. Any async response, error, or finally block checks that token before calling `setState`. This prevents old network responses from replacing newer user intent.

The recommended-users discovery section no longer calls `_doSearch('')`. Instead, it calls a small `_focusSearch()` helper that enters search mode and focuses the search box. This avoids a confusing no-op/empty request path while still giving the user a clear next action.

`SearchSuggestions` keeps its current debounce and generation guard. Phase 3B only hardens its concurrent loading: individual suggestion requests return `null` on failure, `Future.wait` uses `eagerError: false`, and the UI parses whichever modules succeed. Its container uses `AppColors.background` instead of a hard-coded white so it does not clash with the rest of Nonto's themed surfaces.

## Performance Rules

- Do not add extra requests.
- Keep the existing 300ms suggestion debounce.
- Keep short-query behavior that avoids `globalSearch` for one-character input.
- Do not replace existing builder-based lists.

## Verification

Add source-level regression tests, run them red/green, then run existing Phase 3A, performance, prior UI, full test suite, targeted analyzer, and full analyzer.
