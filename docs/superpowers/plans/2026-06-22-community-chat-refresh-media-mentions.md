# Community Chat Refresh Media Mentions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make community chat sessions refresh automatically and add real emoji, image/video sending, and member mention support to `CommunityChatScreen`.

**Architecture:** Keep community chat as a community-specific screen and service path, while reusing direct chat patterns for emoji insertion, media picker affordances, upload flow, and message previews. Backend changes are limited to validating/saving community media message payloads using existing `messages.message_type` and `messages.media_url` fields, with no database migration.

**Tech Stack:** Flutter, Dart, Riverpod, `image_picker`, existing COS presign upload flow, FastAPI, SQLAlchemy models, Python unittest source contract tests, Flutter source regression tests.

---

## File Structure

### Frontend repo: `D:\FlutterProject\nonto`

- Modify: `lib/services/api/community_service.dart`
  - Extend `sendMessage` with `messageType` and `mediaUrl` parameters.
  - Keep `mentionUserIds` behavior.

- Modify: `lib/providers/chat_notifiers.dart`
  - Add a public conversation-list update method that can update an existing community conversation preview or trigger `loadConversations()` when missing.
  - Preserve community metadata when rebuilding `Conversation` instances.

- Modify: `lib/screens/messages/messages_tab.dart`
  - Refresh conversations when returning from a community or direct chat route.

- Modify: `lib/screens/community/community_create_screen.dart`
  - Invalidate/refresh the conversations cache after a community is created.

- Modify: `lib/screens/community/community_chat_screen.dart`
  - Convert the composer to emoji + media + text + send.
  - Add emoji panel using `EmojiData`.
  - Add image/video media sheet and upload/send flow.
  - Add member mention picker on typed `@` and long-press on non-self avatars.
  - Render image and video community messages.
  - Update conversation list on successful send and WS receive.

- Test: `test/nonto_community_chat_media_mentions_regression_test.dart`
  - Source regressions for refresh, composer, media send, mentions, and media rendering.

### Backend repo: `D:\NanTuPy`

- Modify: `app/routers/communities.py`
  - Add a small payload normalization helper for community chat messages.
  - Require text content for text messages.
  - Require `media_url` or URL content for image/video messages.
  - Ensure returned/WS payload carries `message_type`, `media_url`, `sender`, `community_id`, and `conversation_id`.

- Test: `tests/test_community_chat_contracts.py`
  - Extend source contract tests for community image/video payload support and validation.

## Tasks

### Task 1: Backend RED — add community media message contract tests

**Files:**
- Modify: `D:\NanTuPy\tests\test_community_chat_contracts.py`

- [ ] **Step 1: Write the failing backend contract test**

Append this test method inside `CommunityChatContractsTest`, after `test_community_chat_messages_include_sender_profile_for_ui`:

```python
    def test_community_chat_accepts_image_and_video_media_payloads(self):
        with open('app/routers/communities.py', 'r', encoding='utf-8') as f:
            source = f.read()

        self.assertIn('def _normalize_community_message_payload', source)
        self.assertIn("allowed_types = {'text', 'image', 'video'}", source)
        self.assertIn("message_type == 'text'", source)
        self.assertIn("message_type in {'image', 'video'}", source)
        self.assertIn('media_url or content', source)
        self.assertIn('raise HTTPException(status_code=400, detail="媒体消息不能为空")', source)
        self.assertIn('content = media_url', source)
        self.assertIn('message_type=message_type', source)
        self.assertIn('media_url=media_url', source)
        self.assertIn('"media_url"', source)
        self.assertIn('"message_type"', source)
```

- [ ] **Step 2: Run RED**

```bash
cd 'D:\NanTuPy' && './.venv/Scripts/python.exe' -m unittest tests.test_community_chat_contracts -v
```

Expected: FAIL because `communities.py` does not yet contain `_normalize_community_message_payload`, image/video validation strings, or explicit media payload contract strings.

### Task 2: Backend GREEN — normalize and save community media messages

**Files:**
- Modify: `D:\NanTuPy\app\routers\communities.py`
- Test: `D:\NanTuPy\tests\test_community_chat_contracts.py`

- [ ] **Step 1: Add the normalization helper**

Insert this helper after `_community_message_to_dict`:

```python
def _normalize_community_message_payload(payload: dict):
    content = (payload.get("content") or "").strip()
    message_type = (payload.get("message_type") or "text").strip().lower()
    media_url = (payload.get("media_url") or "").strip()
    mention_user_ids = payload.get("mention_user_ids", [])
    allowed_types = {'text', 'image', 'video'}

    if message_type not in allowed_types:
        raise HTTPException(status_code=400, detail="不支持的消息类型")

    if message_type == 'text' and not content:
        raise HTTPException(status_code=400, detail="消息内容不能为空")

    if message_type in {'image', 'video'}:
        if not (media_url or content):
            raise HTTPException(status_code=400, detail="媒体消息不能为空")
        if not media_url:
            media_url = content
        if not content:
            content = media_url

    if not isinstance(mention_user_ids, list):
        mention_user_ids = []

    return content, message_type, media_url or None, mention_user_ids
```

- [ ] **Step 2: Use the helper in `send_community_message`**

Replace the current payload extraction and empty-content guard:

```python
    content = (payload.get("content") or "").strip()
    message_type = payload.get("message_type", "text")
    media_url = payload.get("media_url")
    mention_user_ids = payload.get("mention_user_ids", [])  # @提及的用户 ID 列表

    if not content and not media_url:
        raise HTTPException(status_code=400, detail="消息内容不能为空")
```

with:

```python
    content, message_type, media_url, mention_user_ids = _normalize_community_message_payload(payload)
```

Keep the existing `Message(...)` construction, ensuring these two assignments are present:

```python
        message_type=message_type,
        media_url=media_url,
```

- [ ] **Step 3: Run backend GREEN**

```bash
cd 'D:\NanTuPy' && './.venv/Scripts/python.exe' -m unittest tests.test_community_chat_contracts -v
```

Expected: `Ran 6 tests ... OK`.

- [ ] **Step 4: Compile backend files**

```bash
cd 'D:\NanTuPy' && './.venv/Scripts/python.exe' -m py_compile app/routers/communities.py
```

Expected: exit code 0 with no syntax errors.

- [ ] **Step 5: Commit backend contract and implementation**

```bash
git -C 'D:\NanTuPy' add app/routers/communities.py tests/test_community_chat_contracts.py
git -C 'D:\NanTuPy' commit -m "Support community chat media messages"
```

Expected: a backend commit containing only `communities.py` and `test_community_chat_contracts.py`.

### Task 3: Frontend RED — add community chat source regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\nonto_community_chat_media_mentions_regression_test.dart`

- [ ] **Step 1: Write failing Flutter source tests**

Create the test file with this content:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('community chat media mentions regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('messages tab refreshes conversations after returning from chats', () {
      final source = read('lib/screens/messages/messages_tab.dart');

      expect(source, contains('Future<void> _openConversation'));
      expect(source, contains('await Navigator.push'));
      expect(source, contains('ref.read(conversationsProvider.notifier).loadConversations()'));
    });

    test('community service sends message type and media url', () {
      final source = read('lib/services/api/community_service.dart');

      expect(source, contains('String messageType = \'text\''));
      expect(source, contains('String? mediaUrl'));
      expect(source, contains("'message_type': messageType"));
      expect(source, contains("data['media_url'] = mediaUrl"));
      expect(source, contains("data['mention_user_ids'] = mentionUserIds"));
    });

    test('conversation notifier exposes community preview update hook', () {
      final source = read('lib/providers/chat_notifiers.dart');

      expect(source, contains('void upsertCommunityConversationPreview'));
      expect(source, contains("msgType == 'image'"));
      expect(source, contains("msgType == 'video'"));
      expect(source, contains('communityId: conv.communityId'));
      expect(source, contains('loadConversations();'));
    });

    test('community chat composer has emoji media and mention member affordances', () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains("import 'package:nonto/data/emoji_data.dart';"));
      expect(source, contains("import 'package:image_picker/image_picker.dart';"));
      expect(source, contains('bool _showEmojiPicker = false;'));
      expect(source, contains('final FocusNode _msgFocusNode = FocusNode();'));
      expect(source, contains('_toggleEmojiPicker'));
      expect(source, contains('_buildEmojiPicker'));
      expect(source, contains('Icons.emoji_emotions_outlined'));
      expect(source, contains('Icons.image_outlined'));
      expect(source, contains('_showMediaPicker'));
      expect(source, contains('_showMentionMemberPicker'));
      expect(source, contains('_onTextChanged'));
    });

    test('community chat sends real image and video messages', () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains('_pickAndSendImage'));
      expect(source, contains('_pickAndSendVideo'));
      expect(source, contains('UploadService().uploadImage'));
      expect(source, contains('UploadService().uploadVideo'));
      expect(source, contains("messageType: 'image'"));
      expect(source, contains("messageType: 'video'"));
      expect(source, contains('mediaUrl: url'));
    });

    test('community chat mentions members from typed at and avatar long press', () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains('final Set<int> _mentionUserIds = {};'));
      expect(source, contains('List<CommunityMember> _members = [];'));
      expect(source, contains('CommunityApiService().getMembers'));
      expect(source, contains('_insertMention(CommunityMember member)'));
      expect(source, contains('onAvatarLongPress'));
      expect(source, contains('mentionUserIds: _mentionUserIds.toList()'));
    });

    test('community chat renders image and video messages', () {
      final source = read('lib/screens/community/community_chat_screen.dart');

      expect(source, contains("message['message_type']?.toString()"));
      expect(source, contains("messageType == 'image'"));
      expect(source, contains("messageType == 'video'"));
      expect(source, contains('_buildImageMessage'));
      expect(source, contains('_buildVideoMessage'));
      expect(source, contains('Icons.play_circle_fill'));
    });
  });
}
```

- [ ] **Step 2: Run RED**

```bash
cd 'D:\FlutterProject\nonto' && flutter test test/nonto_community_chat_media_mentions_regression_test.dart
```

Expected: FAIL because the community service and chat screen do not yet expose the required media/emoji/mention/refresh source markers.

### Task 4: Frontend GREEN part 1 — service and conversation list refresh hooks

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\services\api\community_service.dart`
- Modify: `D:\FlutterProject\nonto\lib\providers\chat_notifiers.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\messages\messages_tab.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\community\community_create_screen.dart`
- Test: `D:\FlutterProject\nonto\test\nonto_community_chat_media_mentions_regression_test.dart`

- [ ] **Step 1: Extend `CommunityApiService.sendMessage`**

Replace the current method with:

```dart
  /// 发送群聊消息
  Future<ApiResponse> sendMessage(
    int communityId, {
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    List<int>? mentionUserIds,
  }) {
    final data = <String, dynamic>{
      'content': content,
      'message_type': messageType,
    };
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      data['media_url'] = mediaUrl;
    }
    if (mentionUserIds != null && mentionUserIds.isNotEmpty) {
      data['mention_user_ids'] = mentionUserIds;
    }
    return _api.post('/communities/$communityId/chat/messages', data: data);
  }
```

- [ ] **Step 2: Add a community preview update hook to `ConversationsNotifier`**

Add this method near `onMessageSent`:

```dart
  void upsertCommunityConversationPreview({
    required int conversationId,
    required int communityId,
    required String content,
    required String msgType,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    final preview = _formatPreview(content, msgType);
    final lastMsg = Message(
      id: 0,
      conversationId: conversationId,
      senderId: _currentUserId ?? 0,
      content: content,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == msgType,
        orElse: () => MessageType.text,
      ),
      mediaUrl: msgType == 'image' || msgType == 'video' ? content : null,
      createdAt: now,
    );

    final existingIdx = state.conversations.indexWhere((c) => c.id == conversationId);
    if (existingIdx < 0) {
      loadConversations();
      return;
    }

    final conv = state.conversations[existingIdx];
    final updatedConv = Conversation(
      id: conv.id,
      user1Id: conv.user1Id,
      user2Id: conv.user2Id,
      otherUser: conv.otherUser,
      lastMessage: lastMsg,
      lastMessageAt: now,
      unreadCount: conv.unreadCount,
      type: conv.type,
      communityId: conv.communityId,
      communityName: conv.communityName,
      communityAvatar: conv.communityAvatar,
    );
    final updated = List<Conversation>.from(state.conversations)
      ..removeAt(existingIdx)
      ..insert(0, updatedConv);
    state = state.copyWith(conversations: updated);
    DataLayer().invalidate(CacheKeys.convPattern);
  }
```

- [ ] **Step 3: Refresh conversations after returning from chat routes**

Change `_openConversation` in `messages_tab.dart` from `void` to `Future<void>` and use `await Navigator.push`:

```dart
  Future<void> _openConversation(Conversation conv) async {
    if (conv.isCommunity && conv.communityId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityChatScreen(
            communityId: conv.communityId!,
            communityName: conv.communityName,
          ),
        ),
      );
      if (mounted) {
        await ref.read(conversationsProvider.notifier).loadConversations();
      }
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conv)),
    );
    if (mounted) {
      await ref.read(conversationsProvider.notifier).loadConversations();
    }
  }
```

Keep the tile callback as:

```dart
onTap: () => _openConversation(conversation),
```

- [ ] **Step 4: Refresh conversations after community creation**

Convert `CommunityCreateScreen` to a `ConsumerStatefulWidget` if it is still a `StatefulWidget`:

```dart
class CommunityCreateScreen extends ConsumerStatefulWidget {
  const CommunityCreateScreen({super.key});

  @override
  ConsumerState<CommunityCreateScreen> createState() => _CommunityCreateScreenState();
}

class _CommunityCreateScreenState extends ConsumerState<CommunityCreateScreen> {
```

Add imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/providers/chat_notifiers.dart';
```

Before `Navigator.pushReplacement(...)` in `_submit`, insert:

```dart
          ref.read(conversationsProvider.notifier).loadConversations();
```

- [ ] **Step 5: Run focused Flutter test**

```bash
cd 'D:\FlutterProject\nonto' && flutter test test/nonto_community_chat_media_mentions_regression_test.dart
```

Expected: still FAIL until composer/media/mention implementation is added; service and refresh-related expectations should no longer be the failing assertions.

### Task 5: Frontend GREEN part 2 — community chat emoji, media, mentions, and rendering

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\community\community_chat_screen.dart`
- Test: `D:\FlutterProject\nonto\test\nonto_community_chat_media_mentions_regression_test.dart`

- [ ] **Step 1: Add imports and state**

Add imports:

```dart
import 'package:image_picker/image_picker.dart';
import 'package:nonto/data/emoji_data.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/services/api/upload_service.dart';
```

Add fields to `_CommunityChatScreenState`:

```dart
  final FocusNode _msgFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final Set<int> _mentionUserIds = {};
  List<CommunityMember> _members = [];
  bool _showEmojiPicker = false;
  int _emojiTabIndex = 0;
```

Dispose the focus node:

```dart
    _msgFocusNode.dispose();
```

- [ ] **Step 2: Add text, emoji, and mention helpers**

Add these methods inside `_CommunityChatScreenState`:

```dart
  void _onTextChanged(String text) {
    final selection = _msgCtrl.selection;
    if (!selection.isValid || selection.baseOffset <= 0) return;
    if (text[selection.baseOffset - 1] == '@') {
      _showMentionMemberPicker();
    }
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
    if (_showEmojiPicker) {
      _msgFocusNode.unfocus();
    } else {
      _msgFocusNode.requestFocus();
    }
  }

  void _insertTextAtCursor(String value) {
    final text = _msgCtrl.text;
    final cursorPos = _msgCtrl.selection.baseOffset;
    final before = cursorPos >= 0 ? text.substring(0, cursorPos) : text;
    final after = cursorPos >= 0 ? text.substring(cursorPos) : '';
    _msgCtrl.text = '$before$value$after';
    _msgCtrl.selection = TextSelection.collapsed(offset: before.length + value.length);
  }

  void _insertEmoji(String emoji) {
    _insertTextAtCursor(emoji);
  }

  void _insertMention(CommunityMember member) {
    final user = member.user;
    final label = (user?.displayName?.trim().isNotEmpty == true)
        ? user!.displayName!
        : (user?.username?.trim().isNotEmpty == true ? user!.username : '用户${member.userId}');
    final mentionText = '@$label ';
    final text = _msgCtrl.text;
    final cursorPos = _msgCtrl.selection.baseOffset;
    if (cursorPos > 0 && cursorPos <= text.length && text[cursorPos - 1] == '@') {
      final before = text.substring(0, cursorPos - 1);
      final after = text.substring(cursorPos);
      _msgCtrl.text = '$before$mentionText$after';
      _msgCtrl.selection = TextSelection.collapsed(offset: before.length + mentionText.length);
    } else {
      _insertTextAtCursor(mentionText);
    }
    _mentionUserIds.add(member.userId);
    _msgFocusNode.requestFocus();
  }
```

- [ ] **Step 3: Add member loading and member picker sheet**

Add:

```dart
  Future<void> _ensureMembersLoaded() async {
    if (_members.isNotEmpty) return;
    final resp = await CommunityApiService().getMembers(widget.communityId, limit: 50);
    if (resp.data is Map && (resp.data as Map)['members'] is List) {
      final members = ((resp.data as Map)['members'] as List)
          .whereType<Map>()
          .map((e) => CommunityMember.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (mounted) setState(() => _members = members);
    }
  }

  Future<void> _showMentionMemberPicker() async {
    await _ensureMembersLoaded();
    if (!mounted) return;
    final searchCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final visible = _members.where((member) {
              final user = member.user;
              final haystack = '${user?.displayName ?? ''} ${user?.username ?? ''} ${member.userId}'.toLowerCase();
              return haystack.contains(query.toLowerCase());
            }).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.65,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(2))),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: searchCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索社群成员'),
                          onChanged: (value) => setSheetState(() => query = value),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, index) {
                            final member = visible[index];
                            final user = member.user;
                            final title = user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : user?.username ?? '用户${member.userId}';
                            return ListTile(
                              leading: ImageUtils.buildAvatar(user, radius: 18),
                              title: Text(title),
                              subtitle: Text('@${user?.username ?? member.userId}'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _insertMention(member);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
  }
```

- [ ] **Step 4: Add media picker and send helpers**

Add:

```dart
  Future<void> _showMediaPicker() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('图片'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('视频'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (action == 'image') await _pickAndSendImage();
    if (action == 'video') await _pickAndSendVideo();
  }

  String? _extractUploadUrl(dynamic data) {
    if (data is Map) {
      return data['url']?.toString() ?? data['image_url']?.toString() ?? data['media_url']?.toString();
    }
    return data?.toString();
  }

  Future<void> _pickAndSendImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90);
    if (picked == null) return;
    final upload = await UploadService().uploadImage(picked);
    final url = _extractUploadUrl(upload.data);
    if (!upload.success || url == null || url.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(upload.message ?? '图片上传失败')));
      return;
    }
    await _sendMediaMessage(url, 'image');
  }

  Future<void> _pickAndSendVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final upload = await UploadService().uploadVideo(picked);
    final url = _extractUploadUrl(upload.data);
    if (!upload.success || url == null || url.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(upload.message ?? '视频上传失败')));
      return;
    }
    await _sendMediaMessage(url, 'video');
  }

  Future<void> _sendMediaMessage(String url, String messageType) async {
    final resp = await CommunityApiService().sendMessage(
      widget.communityId,
      content: url,
      messageType: messageType,
      mediaUrl: url,
      mentionUserIds: _mentionUserIds.toList(),
    );
    if (!resp.success) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp.message ?? '发送失败')));
      return;
    }
    _mentionUserIds.clear();
    await _loadMessages();
    _syncConversationPreview(url, messageType);
  }
```

- [ ] **Step 5: Update text send to include mentions and sync preview**

Change `_sendMessage` to call the extended service:

```dart
      await CommunityApiService().sendMessage(
        widget.communityId,
        content: content,
        messageType: 'text',
        mentionUserIds: _mentionUserIds.toList(),
      );
      _mentionUserIds.clear();
      await _loadMessages();
      _syncConversationPreview(content, 'text');
```

Add:

```dart
  void _syncConversationPreview(String content, String messageType) {
    final conversationId = _conversationId;
    if (conversationId == null) {
      ref.read(conversationsProvider.notifier).loadConversations();
      return;
    }
    ref.read(conversationsProvider.notifier).upsertCommunityConversationPreview(
      conversationId: conversationId,
      communityId: widget.communityId,
      content: content,
      msgType: messageType,
      createdAt: DateTime.now(),
    );
  }
```

- [ ] **Step 6: Update WS append to sync conversation preview**

At the end of `_appendRealtimeMessage`, after adding the message, call:

```dart
    final content = messageMap['media_url']?.toString().isNotEmpty == true
        ? messageMap['media_url'].toString()
        : messageMap['content']?.toString() ?? '';
    final messageType = messageMap['message_type']?.toString() ?? 'text';
    _syncConversationPreview(content, messageType);
```

- [ ] **Step 7: Replace composer and include emoji picker in build**

Change the body column to:

```dart
          Expanded(child: _buildMessages()),
          _buildComposer(),
          if (_showEmojiPicker) _buildEmojiPicker(),
```

Replace `_buildComposer` with:

```dart
  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -1))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              tooltip: '表情',
              icon: Icon(_showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined, size: 24),
              onPressed: _toggleEmojiPicker,
            ),
            IconButton(
              tooltip: '图片或视频',
              icon: const Icon(Icons.image_outlined, size: 24),
              onPressed: _showMediaPicker,
            ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                focusNode: _msgFocusNode,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '说点有用、有温度的话...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: _isSending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              color: Colors.white,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
```

Add emoji picker:

```dart
  Widget _buildEmojiPicker() {
    final categories = EmojiData.categories;
    final emojis = categories[_emojiTabIndex].value;
    return Container(
      height: 300,
      color: AppColors.surface,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (_, index) => IconButton(
                icon: Text(categories[index].icon, style: const TextStyle(fontSize: 20)),
                onPressed: () => setState(() => _emojiTabIndex = index),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
              itemCount: emojis.length,
              itemBuilder: (_, index) => InkWell(
                onTap: () => _insertEmoji(emojis[index]),
                child: Center(child: Text(emojis[index], style: const TextStyle(fontSize: 24))),
              ),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 8: Pass avatar long-press callback into message bubbles**

Update `_MessageBubble` constructor fields:

```dart
  final void Function(Map<String, dynamic> sender)? onAvatarLongPress;
```

When building bubbles, pass:

```dart
          onAvatarLongPress: isMine
              ? null
              : (sender) {
                  final rawId = sender['id'];
                  final userId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
                  if (userId == null) return;
                  final member = _members.firstWhere(
                    (m) => m.userId == userId,
                    orElse: () => CommunityMember(id: 0, communityId: widget.communityId, userId: userId, user: null),
                  );
                  _insertMention(member);
                },
```

Wrap non-self avatar with long press:

```dart
            GestureDetector(
              onLongPress: onAvatarLongPress == null ? null : () => onAvatarLongPress!(sender),
              child: _buildSenderAvatar(senderName, senderAvatar),
            ),
```

- [ ] **Step 9: Render image and video message types**

Inside `_MessageBubble.build`, compute:

```dart
    final messageType = message['message_type']?.toString() ?? 'text';
    final mediaUrl = (message['media_url'] ?? message['content'])?.toString() ?? '';
```

Replace the plain content `Text(...)` with:

```dart
                    if (messageType == 'image')
                      _buildImageMessage(mediaUrl)
                    else if (messageType == 'video')
                      _buildVideoMessage(mediaUrl)
                    else
                      Text(
                        content.toString(),
                        style: TextStyle(color: isMine ? Colors.white : AppColors.textPrimary),
                      ),
```

Add helper widgets to `_MessageBubble`:

```dart
  Widget _buildImageMessage(String url) {
    final resolved = ImageUtils.resolveUrl(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: resolved,
        width: 220,
        height: 220,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => const SizedBox(
          width: 220,
          height: 120,
          child: Center(child: Icon(Icons.broken_image)),
        ),
      ),
    );
  }

  Widget _buildVideoMessage(String url) {
    return Container(
      width: 220,
      height: 132,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
      ),
    );
  }
```

- [ ] **Step 10: Run Flutter GREEN**

```bash
cd 'D:\FlutterProject\nonto' && flutter test test/nonto_community_chat_media_mentions_regression_test.dart
```

Expected: all tests in this file pass.

### Task 6: Full verification and final commits

**Files:**
- Frontend modified files from Tasks 3-5.
- Backend modified files from Tasks 1-2 if not committed yet.

- [ ] **Step 1: Run frontend focused community tests**

```bash
cd 'D:\FlutterProject\nonto' && flutter test test/nonto_community_chat_phase9_regression_test.dart test/nonto_community_chat_media_mentions_regression_test.dart
```

Expected: all focused community chat tests pass.

- [ ] **Step 2: Run frontend analyzer**

```bash
cd 'D:\FlutterProject\nonto' && flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 3: Run backend community contracts**

```bash
cd 'D:\NanTuPy' && './.venv/Scripts/python.exe' -m unittest tests.test_community_chat_contracts -v
```

Expected: all community chat contract tests pass.

- [ ] **Step 4: Run backend compile check**

```bash
cd 'D:\NanTuPy' && './.venv/Scripts/python.exe' -m py_compile app/routers/communities.py
```

Expected: exit code 0 with no syntax errors.

- [ ] **Step 5: Confirm no migration files are staged**

```bash
git -C 'D:\NanTuPy' status --short
git -C 'D:\FlutterProject\nonto' status --short
```

Expected: no new migration files. Frontend may still show the pre-existing `M lib/config/app_config.dart`; do not stage it unless the user explicitly asks.

- [ ] **Step 6: Commit frontend implementation only**

```bash
git -C 'D:\FlutterProject\nonto' add \
  lib/services/api/community_service.dart \
  lib/providers/chat_notifiers.dart \
  lib/screens/messages/messages_tab.dart \
  lib/screens/community/community_create_screen.dart \
  lib/screens/community/community_chat_screen.dart \
  test/nonto_community_chat_media_mentions_regression_test.dart

git -C 'D:\FlutterProject\nonto' commit -m "Polish community chat media and mentions"
```

Expected: commit excludes `lib/config/app_config.dart` unless it was intentionally part of a separate user-approved change.

- [ ] **Step 7: Report evidence**

Report:

```text
Backend:
- tests.test_community_chat_contracts: OK
- py_compile app/routers/communities.py: OK

Frontend:
- nonto_community_chat_phase9_regression_test + nonto_community_chat_media_mentions_regression_test: OK
- flutter analyze: No issues found

DB migrations: not run, not created, not staged
Commits: <backend commit>, <frontend commit>
```
