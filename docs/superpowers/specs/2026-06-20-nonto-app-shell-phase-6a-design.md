# Nonto App Shell Phase 6A Design

## Goal

Modernize the main app shell around `HomeScreen` so the core social navigation feels more intentional and mature while preserving Nonto branding, existing tab behavior, lazy-enough tab retention, and startup performance.

## Current State

`HomeScreen` owns the four primary tabs with an `IndexedStack`: feed, search, messages, and profile. The bottom navigation is icon-only and already animates with the shared `barVisibleProvider`. It also shows a combined unread badge on the messages tab, keeps a floating compose button on the feed tab, and provides a profile drawer for secondary destinations.

Targeted analyzer currently reports six issues in `lib/screens/home/home_screen.dart`:

- unused `app_config.dart` import
- unused `chat_notifiers.dart` import
- unused `authState` local in `build`
- unused `_buildBadgeIcon`
- unused `_buildBadgeIcon.isActive`
- unused `_buildAvatar`

## Design

### Navigation Shell

Keep the existing `IndexedStack` to preserve tab state and avoid reloading feed/search/messages/profile on every switch. Keep four primary tabs and keep the current index in `currentTabIndexProvider`, so deep links and route generator behavior remain compatible.

The bottom navigation should become easier to read and test by extracting helpers:

- `_buildBottomNavigationBar(...)` wraps the animated hide/show behavior and themed `BottomNavigationBar`.
- `_buildNavigationItems(...)` returns the four `BottomNavigationBarItem`s.
- `_buildNavItem(...)` builds each icon pair with a stable label.
- `_buildNavIcon(...)` centralizes selected/unselected SVG rendering.
- `_formatBadgeCount(int count)` keeps the `99+` cap in one place.

Labels should stay concise and Nonto-owned: `首页`, `发现`, `消息`, `我的`. To preserve the current minimalist visual style, labels can remain visually hidden with zero font sizes, but the item labels must exist for semantics and regression protection.

### Compose Button

Keep the floating compose button only on the feed tab. Extract it into `_buildComposeButton(bool barVisible)` so the build method stays focused on layout. Preserve the existing animation, `CreatePostScreen` navigation, and feed-only behavior.

No new post refresh logic is added here; create-post already notifies the relevant feed/profile notifiers.

### Drawer

Keep the profile drawer structure and all destinations:

- edit profile
- friend requests
- topics
- community
- comic timeline
- my comic events
- settings
- logout

The drawer can remain functionally unchanged in this slice. This avoids mixing shell navigation cleanup with broader account-menu redesign.

### Analyzer Cleanup

Remove the unused imports, unused `authState` local, unused `_buildBadgeIcon`, and unused `_buildAvatar`. Do not replace them with equivalent dead helpers.

### Performance Constraints

- Preserve `IndexedStack` and the existing constant tab list.
- Do not introduce eager creation of drawer destination screens.
- Do not add network calls, startup waits, or tab preload logic.
- Keep badge calculation derived from providers only.
- Keep SVG icon rendering bounded to four nav items.

## Testing

Add a source regression test `test/nonto_app_shell_phase6a_regression_test.dart` that verifies:

- HomeScreen uses Nonto-owned shell wording/commentary.
- The app shell still uses `IndexedStack` and the same four tab widgets.
- Bottom navigation is extracted into helper methods.
- The four tab labels are stable: `首页`, `发现`, `消息`, `我的`.
- Compose remains feed-only and routes to `CreatePostScreen`.
- The unread badge remains provider-derived and capped at `99+`.
- Known HomeScreen analyzer noise is removed.

Run targeted analyzer on `home_screen.dart` and the new test. Run adjacent shell/performance tests and the full suite. Full analyzer may still fail on historical project-wide issues, but touched files must be clean.

## Out of Scope

- Replacing `BottomNavigationBar` with Material 3 `NavigationBar`.
- Changing route/deep-link tab indices.
- Redesigning the drawer visuals.
- Adding new network/data loading behavior.
- Database migrations.
