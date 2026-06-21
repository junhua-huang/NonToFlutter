# Nonto UI/UX Modernization Design

**Date:** 2026-06-20

## Goal

Modernize the Flutter client so Nonto feels like a mature social app while keeping its own brand identity. The target is not to copy Twitter/X visuals or branding, but to approach mature social-app quality in information hierarchy, interaction speed, feed density, loading/error states, media handling, messaging reliability, and page consistency.

## Chosen Approach

Use **component system + home-first modernization + critical performance fixes**.

- Build a lightweight Nonto design/component system.
- First modernize Home Feed, PostCard, post detail, and comments.
- Connect Home Feed to the backend cursor/seen-post feed instead of deep page pagination.
- Then modernize messages/chat, explore/search, profile, notifications, and global consistency in later phases.

## Existing Strengths

- `FeedTab` already uses `SmartRefresher` and `ListView.builder`.
- Feed has skeleton, empty, and error states.
- `PostCard` already has avatar, author info, content, media, actions, and more menu.
- `PostDetailScreen` already integrates `CommentSection`.
- Comments support replies, likes, delete, emoji, send state, and auto load more.
- Messages already have WebSocket, optimistic send, image upload progress, local cache, read/delivery status, reconnect banner, quote reply, emoji, and recall state.
- Explore has search box, history, suggestions, trending topics/posts, suggested users, and events.
- Light/dark themes and reusable empty/error/skeleton widgets exist.

## Main Problems Found

### Feed and posts

- Frontend feed still calls `/recommendations/feed` with `page/per_page`; it does not use backend `cursor/next_cursor/feed_status` yet.
- Feed state uses one `isLoading` flag for initial load, refresh, and load-more.
- `PostCard` and `PostDetailScreen` duplicate action/media/menu implementations.
- Media handling is split across several widgets; web video cover images can use raw `Image.network`.
- Action bars are duplicated and do not have a shared formatting/feedback policy.

### Messages and chat

- Conversation list is basic and lacks search/filtering/long-press actions.
- `MessagesTab` and `ConversationsTab` overlap as separate conversation UIs.
- `ChatRoomScreen` is monolithic and mixes app bar, list, bubbles, composer, emoji, media, actions, grouping, and state.
- Message sorting/grouping is in a build hot path and can become expensive for long histories.
- Composer send-button reactivity should be controller/listener driven like comments.
- Some message actions appear present but are not fully implemented.

### Explore/search

- Explore is closer to a static search landing page than a true discovery surface.
- “View all” actions can use fake searches or empty searches.
- Search result tab routing can mismatch the actual tab order.
- Search results do not have robust pagination.
- Submitted searches need stale-response protection.
- Event images should use cached, size-limited image loading.

### Profile/notifications/global

- `ProfileTab` has too many responsibilities and contains duplicated avatar/cover edit logic.
- Profile post interaction stream subscriptions need careful dispose handling.
- Notifications can eagerly build many tiles.
- Theme setup is split between `main.dart`, `AppColors`, and direct static color usage.
- Empty, error, skeleton, snackbar, refresh, and bottom-sheet patterns are inconsistent.

## Design System

Create a lightweight Nonto UI foundation under `lib/design` and `lib/widgets/nonto`.

### Theme/tokens

Define semantic tokens for:

- colors: `background`, `surface`, `surfaceMuted`, `surfaceElevated`, `border`, `borderSubtle`, `textPrimary`, `textSecondary`, `textTertiary`, `primary`, `primarySoft`, `like`, `danger`, `success`, `warning`
- spacing: `gap4`, `gap8`, `gap12`, `gap16`, `gap20`, `gap24`
- radius: `xs`, `sm`, `md`, `lg`, `xl`
- typography: title, body, meta, action

New components should prefer `Theme.of(context)`, color scheme, or Nonto theme extensions over static `AppColors`.

### Core components

Phase 0/1 should introduce only the components needed by Home Feed and post detail:

- `NontoActionBar`
- `NontoMediaGrid`
- `NontoPostCard`
- `NontoBottomSheet` or a branded wrapper around existing `TwitterBottomSheet`
- `NontoFeedback`
- unified empty/error/skeleton wrappers where useful

Later phases can add:

- `NontoConversationTile`
- `NontoMessageBubble`
- `ChatComposer`
- `NontoSearchBar`
- `TopicCard`
- `UserSuggestCard`
- `EventCard`
- `NontoNotificationTile`
- `ProfileHeader`

## Phase 0: Minimal Design Foundation

Build the smallest shared UI foundation needed for Phase 1.

Scope:

1. Add Nonto token helpers.
2. Add shared post action bar.
3. Add shared post media grid wrapper.
4. Add feedback helper for success/error/info/login-required snackbars.
5. Keep old pages functional; do not migrate the entire app at once.

Out of scope:

- full app theme rewrite
- all-page color migration
- animation system
- complete visual redesign of chat/explore/profile/notifications

## Phase 1: Home Feed, PostCard, Post Detail, Comments

### Feed data flow

Upgrade frontend feed state from page-only pagination to cursor-aware pagination.

State should include:

- `posts`
- `nextCursor`
- `feedStatus`
- `hasMore`
- `isInitialLoading`
- `isRefreshing`
- `isLoadingMore`
- `error`
- `lastUpdatedAt`

Behavior:

- initial load: `cursor = null`
- refresh: keep old posts, clear cursor, replace posts on success
- load more: pass `nextCursor`, append unique posts
- failure with existing posts: keep old posts and show light feedback
- exhausted feed: show friendly “you have seen recent posts” footer
- fallback feed: explain that older posts are being shown

### Feed UI

Keep `ListView.builder` and `SmartRefresher`. Do not replace the feed with eager `Column`/`map` rendering.

Home feed card layout:

```text
avatar  displayName  @username · time      more
        content
        media
        comment   like   view   share/copy
```

Visual principles:

- no heavy card shadow
- dense social-feed spacing
- stable separators
- consistent touch targets
- low-contrast inactive actions and semantic active colors
- cached media and lazy video initialization

### Post detail

Use the same post component in `detail` mode instead of duplicating post UI in `PostDetailScreen`.

Detail structure:

```text
Detail app bar
NontoPostCard.detail
interaction summary/action area
CommentSection
```

Detail mode should use slightly larger body text and more vertical space than feed mode.

### Comments

Keep existing `CommentSection` architecture. First phase only polishes integration and consistency:

- align comment item text/spacing with post detail
- keep composer behavior stable
- keep reply chip and emoji support
- keep auto-load-more behavior
- avoid a large comment architecture rewrite

## Phase 2: Messages and Chat

Scope after Phase 1:

1. Consolidate `MessagesTab` and `ConversationsTab` into one main conversation UI.
2. Add `NontoConversationTile`.
3. Change conversation list to builder/sliver rendering.
4. Add local conversation search.
5. Extract `ChatComposer` and fix send-button reactivity.
6. Extract or standardize `NontoMessageBubble`.
7. Hide or implement incomplete message menu actions.
8. Make typing status higher priority than online status.
9. Move message grouping out of build hot paths.
10. Add clear retry UI for failed text messages.

Out of scope for this UI modernization round:

- group chat
- voice messages
- file messages
- full reaction backend sync
- Discord-style channels

## Phase 3: Explore and Search

Scope after messages:

1. Fix search tab index mapping.
2. Replace fake “view all” searches with real destination behavior.
3. Add shared `NontoSearchBar`.
4. Reorganize Explore home sections.
5. Add shared topic/user/event cards.
6. Add search result pagination.
7. Add stale-response generation guards.
8. Add section-level loading/error/empty states.
9. Use cached, size-limited images for events.
10. Avoid Explore loading competing with Home first paint.

Explore should become a discovery surface, not just a search page.

## Phase 4: Profile, Notifications, and Global Consistency

Scope after Explore:

1. Fix profile stream subscription lifecycle.
2. Stop duplicating avatar/cover edit flows in `ProfileTab` and `EditProfileScreen`.
3. Add `NontoNotificationTile`.
4. Change notifications to builder/sliver rendering.
5. Standardize notification empty/error/skeleton states.
6. Move common snackbars to `NontoFeedback`.
7. Gradually move theme setup out of `main.dart` and toward `NontoTheme`.
8. Migrate new/reworked components away from direct static `AppColors` usage.

## Performance Rules

### Feed

- Use cursor/next_cursor; do not rely on deep pages.
- Limit page size to 20.
- Prevent request re-entry.
- Deduplicate appends on the client.
- Keep old posts during refresh.
- Use builder lists.
- Cache and size-limit images.
- Lazy-load videos and pause when hidden.

### Chat

- Do not sort/group messages repeatedly inside build for long histories.
- Use builder lists.
- Use cached thumbnails and load full images only in viewer.
- Keep provider/subscription lifecycle controlled.
- Do not break WebSocket, send queue, or retry behavior.

### Explore

- Debounce suggestions.
- Avoid heavy remote suggestions for very short input.
- Drop stale search responses.
- Paginate results.
- Make section failures local.

### Profile/notifications

- Dispose stream subscriptions.
- Use builder/sliver for potentially long notification lists.
- Plan pagination for profile posts/likes/media.

## Testing and Verification

Each implementation phase should run:

- `flutter analyze`
- relevant Flutter tests if present
- targeted widget/unit tests for new state logic and components
- manual smoke checks on feed refresh/load-more, post detail, comments, media, and dark mode

Phase 1 test focus:

- feed first load does not pass cursor
- load more passes `nextCursor`
- refresh clears cursor and preserves old posts during loading
- append deduplicates posts
- `hasMore == false` prevents additional requests
- like optimistic update rolls back on failure
- post action counts format consistently

## First Implementation Round

Only implement **Phase 0 + Phase 1** first.

Do not implement messages, explore, profile, or notifications in the first code round except for shared components that Phase 1 needs.

Phase 0 + Phase 1 deliverables:

1. minimal Nonto design/token helpers
2. cursor-aware frontend feed service/state/notifier
3. shared action bar
4. shared media grid wrapper
5. shared post card with feed/detail modes
6. post detail reusing shared post card
7. comment visual micro-polish only where needed
8. updated feed empty/error/footer messages
9. tests and verification

## Success Criteria

- Home feed loads with backend cursor support.
- Users do not see repeated posts due to frontend append/cache races.
- Home refresh does not white-screen.
- Feed footer explains fallback/exhausted states naturally.
- Feed and post detail share the same post presentation logic.
- Media and action UI are consistent.
- Image/video handling does not regress scrolling performance.
- No large app-wide migration is done before the Home phase proves stable.
