# Nonto Messages Phase 2A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the main Messages tab conversation list with local search, builder-based rendering, and a reusable safe-avatar conversation tile.

**Architecture:** Keep Phase 2A intentionally low-risk: only touch the conversation list surface, not WebSocket delivery, send queues, chat room reliability, or backend contracts. Add pure filtering logic for testability, extract tile UI into a reusable Nonto widget, and refactor `MessagesTab` to render with `ListView.builder` so large conversation lists do not eagerly allocate every row.

**Tech Stack:** Flutter, Dart, Riverpod, pull_to_refresh_flutter3, existing Nonto `ImageUtils` avatar/cache helper.

---

## File Structure

- Create: `lib/widgets/nonto/nonto_conversation_helpers.dart`
  - Pure helper `filterNontoConversations(List<Conversation>, String)`.
  - Pure helper `nontoConversationPreview(Conversation)`.
  - No Flutter dependency beyond model imports; easy to unit test.

- Create: `lib/widgets/nonto/nonto_conversation_tile.dart`
  - Reusable conversation row widget.
  - Uses `ImageUtils.buildAvatar(otherUser, radius: 24)` instead of raw `NetworkImage`.
  - Owns unread visual styling and compact unread badge.

- Modify: `lib/screens/messages/messages_tab.dart`
  - Add `TextEditingController` and `_searchQuery` state.
  - Dispose search controller.
  - Filter conversations locally with `filterNontoConversations`.
  - Replace eager `ListView(children: [...conversations.map(...)])` with `ListView.builder`.
  - Use `NontoConversationTile` for conversation rows.
  - Keep notification entry and pull-to-refresh behavior unchanged.

- Test: `test/nonto_messages_phase2a_regression_test.dart`
  - Pure tests for filtering by display name, username, and last message content.
  - Source-level regression tests for builder rendering and safe reusable tile usage.

## Tasks

### Task 1: Add failing Phase 2A regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\nonto_messages_phase2a_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create tests that assert the desired Phase 2A behavior before production code exists:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';

void main() {
  group('Phase 2A conversation filtering', () {
    test('matches display name, username, and last message content', () {
      final conversations = [
        _conversation(
          id: 1,
          displayName: '林小南',
          username: 'lin_nan',
          message: '今天去看展吗',
        ),
        _conversation(
          id: 2,
          displayName: 'Ocean Studio',
          username: 'ocean_daily',
          message: '新的摄影路线发你了',
        ),
        _conversation(
          id: 3,
          displayName: null,
          username: 'quiet_reader',
          message: '晚点回复',
        ),
      ];

      expect(filterNontoConversations(conversations, '小南'), [conversations[0]]);
      expect(filterNontoConversations(conversations, 'ocean'), [conversations[1]]);
      expect(filterNontoConversations(conversations, '摄影'), [conversations[1]]);
      expect(filterNontoConversations(conversations, 'reader'), [conversations[2]]);
    });

    test('empty or whitespace query returns the original conversation order', () {
      final conversations = [
        _conversation(id: 1, displayName: 'A', username: 'a', message: 'one'),
        _conversation(id: 2, displayName: 'B', username: 'b', message: 'two'),
      ];

      expect(filterNontoConversations(conversations, ''), conversations);
      expect(filterNontoConversations(conversations, '   '), conversations);
    });

    test('conversation preview handles recalled and empty messages', () {
      expect(nontoConversationPreview(_conversation(message: 'hello')), 'hello');
      expect(
        nontoConversationPreview(_conversation(message: 'removed', isRecalled: true)),
        '消息已撤回',
      );
      expect(nontoConversationPreview(_conversation(message: '')), '暂无消息');
    });
  });

  group('Phase 2A MessagesTab source regressions', () {
    test('messages tab uses builder rendering and local search state', () {
      final source = File('lib/screens/messages/messages_tab.dart').readAsStringSync();

      expect(source, contains('TextEditingController'));
      expect(source, contains('filterNontoConversations'));
      expect(source, contains('ListView.builder'));
      expect(source, isNot(contains('...conversations.map(_buildConversationItem)')));
    });

    test('shared conversation tile uses cached safe avatar rendering', () {
      final source = File('lib/widgets/nonto/nonto_conversation_tile.dart').readAsStringSync();

      expect(source, contains('class NontoConversationTile'));
      expect(source, contains('ImageUtils.buildAvatar'));
      expect(source, isNot(contains('NetworkImage')));
    });
  });
}

Conversation _conversation({
  int id = 1,
  String? displayName = 'User',
  String username = 'user',
  String? message = 'hello',
  bool isRecalled = false,
}) {
  return Conversation(
    id: id,
    user1Id: 1,
    user2Id: 2,
    lastMessageAt: DateTime(2026, 6, 20, 12),
    otherUser: User(
      id: id,
      username: username,
      email: '$username@example.com',
      displayName: displayName,
    ),
    lastMessage: Message(
      id: id,
      conversationId: id,
      senderId: 2,
      content: message,
      isRecalled: isRecalled,
    ),
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
flutter test test/nonto_messages_phase2a_regression_test.dart
```

Expected: FAIL because `nonto_conversation_helpers.dart` and `nonto_conversation_tile.dart` do not exist yet.

### Task 2: Implement pure conversation helpers

**Files:**
- Create: `D:\FlutterProject\nonto\lib\widgets\nonto\nonto_conversation_helpers.dart`
- Test: `D:\FlutterProject\nonto\test\nonto_messages_phase2a_regression_test.dart`

- [ ] **Step 1: Implement helper functions**

```dart
import 'package:nonto/models/conversation.dart';

List<Conversation> filterNontoConversations(
  List<Conversation> conversations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return conversations;

  return conversations.where((conversation) {
    final other = conversation.otherUser;
    final fields = <String?>[
      other?.displayName,
      other?.username,
      conversation.lastMessage?.content,
    ];

    return fields.any(
      (field) => field != null && field.toLowerCase().contains(normalizedQuery),
    );
  }).toList(growable: false);
}

String nontoConversationPreview(Conversation conversation) {
  final lastMessage = conversation.lastMessage;
  if (lastMessage?.isRecalled == true) return '消息已撤回';

  final content = lastMessage?.content?.trim() ?? '';
  if (content.isEmpty) return '暂无消息';

  return content;
}
```

- [ ] **Step 2: Run helper tests**

Run:

```bash
flutter test test/nonto_messages_phase2a_regression_test.dart
```

Expected: still FAIL because shared tile and MessagesTab refactor are not implemented yet.

### Task 3: Extract reusable conversation tile

**Files:**
- Create: `D:\FlutterProject\nonto\lib\widgets\nonto\nonto_conversation_tile.dart`

- [ ] **Step 1: Create shared tile widget**

```dart
import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';

class NontoConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const NontoConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    final hasUnread = conversation.unreadCount > 0;
    final name = other?.displayName?.trim().isNotEmpty == true
        ? other!.displayName!.trim()
        : (other?.username.trim().isNotEmpty == true ? other!.username.trim() : '未知用户');

    return Material(
      color: hasUnread ? AppColors.primary.withValues(alpha: 0.03) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ImageUtils.buildAvatar(other, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.lastMessageAt != null)
                          Text(
                            AppDateUtils.formatTimeAgo(conversation.lastMessageAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: hasUnread ? AppColors.primary : AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nontoConversationPreview(conversation),
                            style: TextStyle(
                              fontSize: 14,
                              color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: conversation.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: AppColors.likeRed,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run test**

Run:

```bash
flutter test test/nonto_messages_phase2a_regression_test.dart
```

Expected: still FAIL until `MessagesTab` uses builder/search.

### Task 4: Refactor MessagesTab list to search + builder rendering

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\messages\messages_tab.dart`

- [ ] **Step 1: Add imports**

Add:

```dart
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_tile.dart';
```

- [ ] **Step 2: Add search state and dispose**

Inside `_MessagesTabState` add:

```dart
final TextEditingController _searchController = TextEditingController();
String _searchQuery = '';
```

In `dispose()` add before `super.dispose()`:

```dart
_searchController.dispose();
```

- [ ] **Step 3: Update build content call**

Change:

```dart
: _buildContent(conversations),
```

to:

```dart
: _buildContent(conversations),
```

The call signature remains the same; filtering happens inside `_buildContent`.

- [ ] **Step 4: Replace eager content list with builder**

Replace `_buildContent` and `_buildConversationItem` with builder-based rendering:

```dart
Widget _buildContent(List<Conversation> conversations) {
  final visibleConversations = filterNontoConversations(conversations, _searchQuery);
  final showEmpty = conversations.isEmpty;
  final showSearchEmpty = conversations.isNotEmpty && visibleConversations.isEmpty;
  final itemCount = 3 + (showEmpty || showSearchEmpty ? 1 : visibleConversations.length);

  return ListView.builder(
    padding: EdgeInsets.zero,
    itemCount: itemCount,
    itemBuilder: (context, index) {
      if (index == 0) return _buildNotificationEntry();
      if (index == 1) return const Divider(height: 1, indent: 72);
      if (index == 2) return _buildSearchBox();

      if (showEmpty) return _buildEmpty();
      if (showSearchEmpty) return _buildSearchEmpty();

      final conversation = visibleConversations[index - 3];
      return NontoConversationTile(
        conversation: conversation,
        onTap: () => _openConversation(conversation),
      );
    },
  );
}
```

- [ ] **Step 5: Add search and search-empty widgets**

Add methods:

```dart
Widget _buildSearchBox() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: '搜索会话',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: AppColors.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
      ),
    ),
  );
}

Widget _buildSearchEmpty() {
  return const Padding(
    padding: EdgeInsets.only(top: 72),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.search_off, size: 44, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('没有找到相关会话', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          SizedBox(height: 4),
          Text('换个关键词试试', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 6: Remove obsolete `_formatTime` if unused**

Delete `_formatTime` from `MessagesTab` after tile owns time formatting.

- [ ] **Step 7: Run Phase 2A tests**

Run:

```bash
flutter test test/nonto_messages_phase2a_regression_test.dart
```

Expected: PASS.

### Task 5: Regression verification

**Files:**
- Verify all modified code.

- [ ] **Step 1: Run Phase 2A targeted tests**

```bash
flutter test test/nonto_messages_phase2a_regression_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run Phase 1 regression tests**

```bash
flutter test test/nonto_ui_phase1_regression_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run full suite with required production URL dart-defines**

```bash
flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

- [ ] **Step 4: Run analyzer on modified files**

```bash
dart analyze lib/widgets/nonto/nonto_conversation_helpers.dart lib/widgets/nonto/nonto_conversation_tile.dart lib/screens/messages/messages_tab.dart test/nonto_messages_phase2a_regression_test.dart
```

Expected: no new analyzer errors in Phase 2A files. Existing global analyzer issues may remain outside this slice.

## Self-Review

- Spec coverage: Phase 2A search, builder rendering, reusable tile, safe cached avatar usage, and low-risk boundary are covered.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: helpers use existing `Conversation`, `Message`, and `User` model APIs; tile uses existing `AppDateUtils.formatTimeAgo` and `ImageUtils.buildAvatar` APIs.
