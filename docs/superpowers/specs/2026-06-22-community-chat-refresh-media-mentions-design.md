# Community Chat Refresh, Media, Emoji, and Mentions Design

Date: 2026-06-22

## Context

Community chat is already partially integrated into the normal conversation list. The current gaps are frontend state synchronization and composer parity with direct chats:

- Creating a community and returning to Messages does not reliably show the new community conversation until the user manually refreshes.
- Sending a message inside `CommunityChatScreen` updates the chat page, but the conversation list preview/order is not updated immediately on return.
- `CommunityChatScreen` has a minimal composer with an `@` button, but it does not match the direct chat composer: emoji picker, media picker, image/video sending, and member mention selection are missing.

Relevant frontend files:

- `lib/screens/messages/messages_tab.dart`
- `lib/screens/community/community_chat_screen.dart`
- `lib/screens/community/community_create_screen.dart`
- `lib/providers/chat_notifiers.dart`
- `lib/services/api/community_service.dart`
- `lib/services/api/upload_service.dart`
- `lib/data/emoji_data.dart`

Relevant backend files:

- `app/routers/communities.py`
- `app/routers/upload.py`
- `app/models/models.py`

No database migration is part of this design. Existing `messages.message_type`, `messages.media_url`, and `messages.content` fields are sufficient for image/video group messages.

## Goals

1. Community conversations appear/update automatically without manual pull-to-refresh after creating a community or sending a group message.
2. Community chat composer supports:
   - emoji button and emoji picker matching direct chat behavior;
   - media button with a bottom sheet for image or video;
   - real image/video upload and send;
   - `@` typed mention picker;
   - long-pressing another member's avatar to mention them.
3. Group chat messages render text, image, and video message types correctly enough for production use.
4. Backend group chat contracts accept and broadcast media messages consistently.
5. Preserve existing direct chat behavior.

## Non-goals

- No DB migration.
- No full direct-chat refactor.
- No redesign of the whole conversation list.
- No advanced video editing/transcoding UI. Video send should use the existing upload infrastructure and render as a video message card/player entry.

## Approach

Use a focused community-chat implementation rather than forcing community chat through the direct-chat `messagesProvider`.

Direct chat already has mature logic for emoji, image upload, optimistic messages, and previews, but it is built around `conversationId` and direct-user assumptions. Community chat starts from `communityId`, has member mentions, and uses `CommunityApiService`. Reusing direct chat wholesale would increase coupling and risk direct chat regressions.

Instead, keep `CommunityChatScreen` as the community-specific surface and copy/extract only small reusable patterns where safe: emoji data insertion, media picker sheet styling, upload URL extraction, and media rendering conventions.

## Frontend Design

### Conversation list synchronization

`MessagesTab._openConversation` should refresh conversations when a pushed chat route returns. For community chats, this ensures that any messages sent while inside the room are reflected after pop.

`CommunityChatScreen` should also update conversations immediately on send/receive:

- After text/image/video send succeeds, update `conversationsProvider` with the group conversation id, preview text, message type, and timestamp.
- If the conversation is missing locally, call `loadConversations()`.
- On WS `new_message`, append to the local message list and update the conversation list preview/order.
- When a new community is created or entered from detail, invalidate/load the conversation list so the new community session can appear without manual refresh.

Preview rules:

- `text`: first 30 chars of content.
- `image`: `图片`.
- `video`: `视频`.

### Composer layout

Community composer should become:

```text
[emoji] [media] [text field................] [send]
```

Emoji button:

- Toggles a bottom emoji panel matching direct chat.
- Inserts selected emoji at the current cursor position.
- Hides keyboard while open; toggling back focuses the text field.

Media button:

- Opens a bottom sheet.
- Options: `图片`, `视频`.
- Image selection uses image picker and existing upload pipeline.
- Video selection uses image picker video selection and the same upload pipeline with video extension/content type.

Text field:

- Keeps normal send-on-submit behavior.
- Detects a newly typed `@` and opens a community member picker.

### Mention picker

A new community-specific member picker should be implemented instead of using the global friend/topic picker.

Bottom sheet layout:

```text
顶部拖拽圆角 sheet
搜索框
成员列表：头像 + display name + @username
```

Data source:

- `CommunityApiService.getMembers(communityId, limit: 50)` initially.
- Search filters the loaded member list locally for this first version.
- If later communities are large, backend search/pagination can be added separately.

Selection behavior:

- Tapping a member inserts `@displayName ` at the cursor.
- The member id is stored in a pending mention id set.
- Sending text includes `mention_user_ids`.
- Long-pressing another user's avatar in the message list performs the same insertion and mention-id tracking.
- The current user's own avatar should not trigger self-mention.

### Media sending

Community API service should support:

```dart
sendMessage(
  communityId,
  content: contentOrUrl,
  messageType: 'text' | 'image' | 'video',
  mediaUrl: optionalUrl,
  mentionUserIds: ids,
)
```

Image/video send flow:

1. User chooses media.
2. Frontend uploads through existing COS presign/confirm infrastructure with upload type `chat`.
3. Frontend receives public URL.
4. Frontend calls community send endpoint with:
   - image: `message_type=image`, `content=url`, `media_url=url`;
   - video: `message_type=video`, `content=url`, `media_url=url`.
5. Community chat appends/updates the local message list.
6. Conversation list preview updates to `图片` or `视频`.

Failure handling:

- If upload fails, show a SnackBar and keep composer usable.
- If send fails after upload, show a SnackBar and do not duplicate the message.
- Avoid adding durable local media queue changes in this phase to avoid database changes.

### Message rendering

Community message bubbles should render:

- text: current bubble text.
- image: thumbnail from `media_url` or `content` if URL-like; tap opens image preview.
- video: video card with thumbnail-like dark surface, play icon, and URL/open-player action. If an existing video player widget is available, use it; otherwise use a simple video card first.

Sender avatar/name behavior remains:

- Use authenticated current user id for alignment.
- Use message `sender` payload for display name, username, and avatar.
- Long press on non-self avatar inserts a mention.

## Backend Design

`app/routers/communities.py` group send endpoint should be tightened:

- Accept `message_type` values `text`, `image`, `video`.
- For text, require non-empty `content`.
- For image/video, require `media_url` or URL content.
- If image/video content is empty but `media_url` exists, set `content = media_url`.
- Save `media_url` to `Message.media_url`.
- Include `message_type`, `media_url`, `sender`, `community_id`, and `conversation_id` in returned and WS-broadcast message payloads.

No database migration is required.

Upload endpoints do not need new routes if the existing presign/confirm flow can handle upload type `chat` and image/video file extensions. If the frontend has path-specific helpers such as `/upload/chat/image`, they should continue to resolve to upload type `chat` through the existing `ApiClient` presign abstraction rather than requiring physical backend routes.

## Testing

Frontend source regression tests should cover:

- `CommunityChatScreen` has emoji and media buttons in the composer.
- Emoji insertion uses `EmojiData` and cursor-aware insertion.
- Media picker offers image and video choices.
- Community media send passes `message_type` and `media_url` to `CommunityApiService`.
- Typing `@` opens a community member picker.
- Member picker has search field and member list.
- Long-pressing a non-self avatar inserts a mention.
- Returning from community chat refreshes conversations.
- Sending/receiving community messages updates conversation preview/order without manual refresh.

Backend contract tests should cover:

- Community text message still works.
- Community image message accepts `media_url` and returns/broadcasts `message_type=image` and `media_url`.
- Community video message accepts `media_url` and returns/broadcasts `message_type=video` and `media_url`.
- Text messages without content are rejected.
- Media messages without URL are rejected.
- Sender profile remains present in group chat message payloads.

## Risks and Mitigations

- **Risk: direct chat regression.** Keep changes focused on community files and shared helpers only when clearly safe.
- **Risk: backend upload route confusion.** Use the existing presign/confirm upload abstraction and verify with tests/source checks.
- **Risk: large communities make local member filtering insufficient.** Use local filtering for the first version; add paginated server search later if needed.
- **Risk: video playback complexity.** Start with a video card/player entry using existing media conventions; do not add a large video subsystem in this phase.

## Acceptance Criteria

- Creating a community and returning to Messages shows the community conversation without manual pull-to-refresh.
- Sending a group text/image/video message updates the conversation list preview/order without manual pull-to-refresh.
- Group chat composer has emoji and media icons on the left.
- Emoji picker works like direct chat.
- Media sheet lets users choose image or video.
- Image and video group messages are uploaded, sent, returned from backend, broadcast over WS, and rendered in the group chat.
- Typing `@` opens the community member picker.
- Long-pressing another sender's avatar inserts a mention.
- Mention sends `mention_user_ids` to backend.
- No DB migration is run or required.
