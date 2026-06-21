# Nonto Notifications Phase 4B Design

## Goal
Modernize the Notifications tab as the next low-risk Phase 4 UI/UX slice while preserving Nonto branding, existing notification semantics, and fast list performance.

## Scope
This slice focuses on `lib/screens/notifications/notifications_tab.dart` only, plus a source regression test. It does not change notification APIs, database schema, routing contracts, provider state semantics, or push/websocket behavior.

## UX Direction
- Keep the page title as `通知`, with Nonto-owned copy rather than Twitter/X wording.
- Present notifications as a lightweight activity feed with clear sections:
  - `新的互动` for unread items.
  - `稍早动态` for read items behind a collapsible row.
- Keep existing tap behavior:
  - post-related notifications open post detail.
  - friend requests open the request screen.
  - accepted friends/message notifications open chat through existing paths.
  - system notifications remain local/read-only.
- Keep empty, error, refresh, and initial loading states explicit and friendly.

## Performance Requirements
- Preserve pull-to-refresh and load-more behavior through `SmartRefresher`.
- Replace eager notification widget creation with `ListView.builder`.
- Do not build read notification tiles while the read section is collapsed.
- Keep provider pagination unchanged; this slice only reduces client-side widget work.

## Implementation Units
- `NotificationsTab`: build a small feed-entry list from current provider state and render entries lazily.
- `_NotificationTile`: keep a compact readable row, with unread visual affordance and existing avatar/icon logic.
- Regression test: guard Nonto wording, lazy rendering, read-section collapse behavior, and source hygiene.

## Non-Goals
- No mark-all-read feature.
- No new backend fields or migrations.
- No notification filtering tabs.
- No broad analyzer cleanup outside touched files.

## Verification
- Run the new Phase 4B regression test.
- Run existing notification UX regression tests.
- Run the targeted analyzer on touched files.
- Run full Flutter tests with production dart-defines.
- Run full analyzer and report remaining global issues honestly if existing warnings remain.
