# Nonto Explore/Search Phase 3A Design

**Date:** 2026-06-20

## Goal

Modernize the Explore/Search surface with Nonto-owned language, clearer loading/empty states, and safer result tab behavior without changing backend APIs or adding heavier data flows.

## Scope

Phase 3A is a low-risk UI/UX and source-hygiene slice for `SearchTab`.

Included:

1. Replace Twitter/X-specific Explore wording with Nonto discovery/search wording.
2. Keep the discovery page fast by preserving builder-based list rendering.
3. Add explicit helper states for default discovery loading and empty content.
4. Fix automatic search result tab selection so special result types match the actual tab order: `全部`, `用户`, `漫展`, `帖子`.
5. Remove unused imports, dead private builders, and unused default item variants that currently create analyzer noise.

Out of scope:

- Backend/search API changes.
- Search result pagination.
- Stale-response generation guards.
- Shared `NontoSearchBar` extraction.
- Large file split or full Explore redesign.
- DB migrations.

## Design

`SearchTab` remains the owner of the existing interaction model: search focus enters search mode, text input shows suggestions, submit shows tabbed results, and the default view shows discovery sections from `ExploreNotifier`.

The default Explore content keeps its flattened `_DefaultItem` model and `ListView.builder` so long discovery lists remain lazy. A new `_hasExploreContent` helper determines whether any section has content. `_buildExploreLoadingState` and `_buildExploreEmptyState` make initial and all-empty states explicit and reusable inside `SmartRefresher`.

Search results keep the existing tab structure. The automatic tab selection is corrected to match the current order: hot posts route to the posts tab at index 3, comic events route to the comic events tab at index 2, and default searches route to all results at index 0.

## Performance Rules

- Do not replace `ListView.builder` in the default discovery surface.
- Do not introduce extra network requests.
- Do not block the page on optional sections; `ExploreNotifier` continues to allow modules to settle independently.
- Keep changes presentation-only except for the tab-index bug fix.

## Verification

Run targeted source regression tests for Phase 3A, existing page performance tests, relevant prior UI tests, the full Flutter test suite with existing dart-defines, targeted analyzer for modified files, and full `flutter analyze` to report remaining project-wide issues honestly.
