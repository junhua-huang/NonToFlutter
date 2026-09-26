# Critical Chat Unread Bugs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix chat/notification unread badge separation, unread badge color consistency, server-time parsing, and community-chat duplicate message merging.

**Architecture:** Keep unread domains separate: bottom navigation reads only conversation unread state, while the notification entry reads the notifications provider. Normalize server timestamps through one client utility and one backend UTC-Z serializer. Add `client_msg_id` to community HTTP chat send so optimistic messages, HTTP responses, and WebSocket echoes can be matched deterministically.

**Tech Stack:** Flutter/Dart with Riverpod (`D:\FlutterProject\nonto`), FastAPI/Python with pytest (`D:\NanTuPy`).

---

## Scope and repositories

- Client repo: `D:\FlutterProject\nonto`
- Backend repo: `D:\NanTuPy`
- Design spec: `C:\Users\25318\ZCodeProject\docs\superpowers\specs\2026-06-26-critical-chat-unread-bugs-design.md`

This plan covers only:

1. Notification/chat unread badge separation.
2. Bottom navigation unread badge color matching conversation list unread badge color.
3. Client-side server timestamp parsing for chat/conversation/community-chat paths.
4. Backend UTC timestamp contract for `Message` and `Conversation` chat fields.
5. Community chat `client_msg_id` propagation and merge/de-dupe rules.

It does not cover avatar UI, identity verification, or search-back-button work.

---

## File structure

### Client files

- Create: `D:\FlutterProject\nonto\test\unread_badge_regression_test.dart`
  - Source-level regression tests for unread badge separation and color token usage.
- Create: `D:\FlutterProject\nonto\test\chat_time_and_dedupe_regression_test.dart`
  - Unit/source-level regression tests for server time parsing and community chat client message ID de-dupe hooks.
- Modify: `D:\FlutterProject\nonto\lib\config\app_theme.dart`
  - Add semantic unread badge color token.
- Modify: `D:\FlutterProject\nonto\lib\screens\home\home_screen.dart`
  - Bottom navigation message badge reads only `unreadMessagesCountProvider`; badge uses `AppColors.unreadBadge`.
- Modify: `D:\FlutterProject\nonto\lib\screens\messages\messages_tab.dart`
  - Notification entry reads `unreadNotificationsCountProvider` instead of maintaining a local `_unreadNotifications` counter.
- Modify: `D:\FlutterProject\nonto\lib\widgets\nonto\nonto_conversation_tile.dart`
  - Conversation unread badge uses `AppColors.unreadBadge`.
- Modify: `D:\FlutterProject\nonto\lib\utils\date_utils.dart`
  - Add nullable `parseServerTime` that never falls back to current time for invalid server values.
- Modify: `D:\FlutterProject\nonto\lib\models\message.dart`
  - Parse chat message timestamps with `parseServerTime`.
- Modify: `D:\FlutterProject\nonto\lib\models\conversation.dart`
  - Parse last-message timestamps with `parseServerTime`.
- Modify: `D:\FlutterProject\nonto\lib\services\api\community_service.dart`
  - Accept and send optional `clientMsgId` as `client_msg_id`.
- Modify: `D:\FlutterProject\nonto\lib\screens\community\community_chat_screen.dart`
  - Generate community `client_msg_id`, store it in optimistic messages, send it to backend, and merge incoming messages by `client_msg_id` before fuzzy matching.

### Backend files

- Create: `D:\NanTuPy\app\utils\time_utils.py`
  - Serialize naive UTC datetimes as ISO-8601 UTC strings with `Z`.
- Create: `D:\NanTuPy\tests\test_critical_chat_unread_contracts.py`
  - Contract tests for UTC-Z serialization and community `client_msg_id` propagation.
- Modify: `D:\NanTuPy\app\models\models.py`
  - Use UTC-Z serialization for `Conversation.to_dict()` and `Message.to_dict()` chat fields.
- Modify: `D:\NanTuPy\app\routers\communities.py`
  - Accept `client_msg_id` in community chat send and include it in HTTP response and WS broadcast.
- Modify: `D:\NanTuPy\app\routers\ws.py`
  - Use UTC-Z serialization in direct-message session/message payloads that are manually built.

---

## Task 1: Add unread badge regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\unread_badge_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unread_badge_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('unread badge regressions', () {
    test('bottom message tab badge counts only conversation unread messages', () {
      final source = read('lib/screens/home/home_screen.dart');

      expect(source, contains('final totalBadge = ref.watch(unreadMessagesCountProvider).toInt();'));
      expect(source, isNot(contains('ref.watch(unreadNotificationsCountProvider) +')));
      expect(source, isNot(contains('+\n            ref.watch(unreadMessagesCountProvider)')));
    });

    test('notification entry uses notification provider count, not local fetch state', () {
      final source = read('lib/screens/messages/messages_tab.dart');

      expect(source, contains('final unreadNotifications = ref.watch(unreadNotificationsCountProvider);'));
      expect(source, isNot(contains('int _unreadNotifications = 0;')));
      expect(source, isNot(contains('_fetchUnreadNotifications')));
      expect(source, isNot(contains('NotificationService _notifService')));
      expect(source, isNot(contains('CacheKeys.notifUnreadCount')));
    });

    test('bottom nav and conversation unread badges share the unreadBadge color token', () {
      final theme = read('lib/config/app_theme.dart');
      final home = read('lib/screens/home/home_screen.dart');
      final tile = read('lib/widgets/nonto/nonto_conversation_tile.dart');

      expect(theme, contains('static const Color unreadBadge = likeRed;'));
      expect(home, contains('backgroundColor: AppColors.unreadBadge'));
      expect(tile, contains('color: AppColors.unreadBadge'));
    });
  });
}
```

- [ ] **Step 2: Run the failing test**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/unread_badge_regression_test.dart
```

Expected: FAIL because `home_screen.dart` currently adds notification unread into `totalBadge`, `messages_tab.dart` has local `_unreadNotifications`, and `AppColors.unreadBadge` does not exist.

---

## Task 2: Implement unread badge separation and color token

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\config\app_theme.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\home\home_screen.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\messages\messages_tab.dart`
- Modify: `D:\FlutterProject\nonto\lib\widgets\nonto\nonto_conversation_tile.dart`

- [ ] **Step 1: Add the semantic unread badge color**

In `lib/config/app_theme.dart`, change the functional color section to:

```dart
  // 功能色
  static const Color likeRed = Color(0xFFF91880);
  static const Color unreadBadge = likeRed;
  static const Color successGreen = Color(0xFF00BA7C);
```

- [ ] **Step 2: Fix bottom navigation count and badge color**

In `lib/screens/home/home_screen.dart`, replace the current `totalBadge` block in `build()`:

```dart
    final totalBadge = (ref.watch(unreadNotificationsCountProvider) +
            ref.watch(unreadMessagesCountProvider))
        .toInt();
```

with:

```dart
    final totalBadge = ref.watch(unreadMessagesCountProvider).toInt();
```

Then replace `_buildNavIcon` badge creation:

```dart
    return Badge(
      label: Text(_formatBadgeCount(badgeCount)),
      child: icon,
    );
```

with:

```dart
    return Badge(
      backgroundColor: AppColors.unreadBadge,
      label: Text(_formatBadgeCount(badgeCount)),
      child: icon,
    );
```

- [ ] **Step 3: Remove local notification count state from messages tab**

In `lib/screens/messages/messages_tab.dart`, remove these imports because notification unread count will come from `notificationsProvider` through `unreadNotificationsCountProvider`:

```dart
import 'package:nonto/services/api/notification_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/websocket_service.dart';
```

Remove these fields:

```dart
  final WebSocketService _wsService = WebSocketService();
  final NotificationService _notifService = NotificationService();

  int _unreadNotifications = 0;
  String _searchQuery = '';

  StreamSubscription? _wsNotifSub;
```

Replace them with:

```dart
  String _searchQuery = '';
```

Remove this from `initState()`:

```dart
    _wsNotifSub = _wsService.notificationStream.listen(_onWsNotification);
    _fetchUnreadNotifications();
```

Remove this from `dispose()`:

```dart
    _wsNotifSub?.cancel();
```

Delete the entire `void _onWsNotification(Map<String, dynamic> data)` method whose body starts with:

```dart
    if (!mounted) return;
    final event = data['event'] as String?;
```

and ends after:

```dart
      setState(() => _unreadNotifications = count);
    }
  }
```

Delete the entire `Future<void> _fetchUnreadNotifications() async` method whose body starts with:

```dart
    try {
      final result = await DataLayer().query(
```

and ends after:

```dart
    } catch (_) {}
  }
```

In `_onRefresh()`, replace:

```dart
    _fetchUnreadNotifications();
```

with:

```dart
    await ref.read(notificationsProvider.notifier).loadNotifications(refresh: true);
```

- [ ] **Step 4: Use provider count in the notification entry**

At the start of `_buildNotificationEntry()` in `lib/screens/messages/messages_tab.dart`, add:

```dart
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);
```

Then replace every `_unreadNotifications` in `_buildNotificationEntry()` with `unreadNotifications`.

The count block should become:

```dart
                      if (unreadNotifications > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: const BoxDecoration(
                            color: AppColors.unreadBadge,
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          child: Text(
                            unreadNotifications > 99
                                ? '99+'
                                : '$unreadNotifications',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
```

- [ ] **Step 5: Update conversation tile unread badge color**

In `lib/widgets/nonto/nonto_conversation_tile.dart`, replace:

```dart
      decoration: const BoxDecoration(
        color: AppColors.likeRed,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
```

with:

```dart
      decoration: const BoxDecoration(
        color: AppColors.unreadBadge,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
```

- [ ] **Step 6: Verify unread badge tests pass**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/unread_badge_regression_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit client unread fix**

Run from `D:\FlutterProject\nonto`:

```bash
git add test/unread_badge_regression_test.dart lib/config/app_theme.dart lib/screens/home/home_screen.dart lib/screens/messages/messages_tab.dart lib/widgets/nonto/nonto_conversation_tile.dart
git commit -m "fix: separate chat and notification unread badges"
```

Expected: commit succeeds.

---

## Task 3: Add client time parsing and community de-dupe regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\chat_time_and_dedupe_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/chat_time_and_dedupe_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/utils/date_utils.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('server time parsing regressions', () {
    test('server timestamps without timezone are parsed as UTC instants', () {
      final parsed = AppDateUtils.parseServerTime('2026-06-26T13:00:00');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc().toIso8601String(), '2026-06-26T13:00:00.000Z');
    });

    test('server timestamps with Z keep the same UTC instant', () {
      final parsed = AppDateUtils.parseServerTime('2026-06-26T13:00:00Z');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc().toIso8601String(), '2026-06-26T13:00:00.000Z');
    });

    test('invalid server timestamps return null instead of current time', () {
      expect(AppDateUtils.parseServerTime(null), isNull);
      expect(AppDateUtils.parseServerTime(''), isNull);
      expect(AppDateUtils.parseServerTime('not-a-time'), isNull);
    });

    test('chat models use parseServerTime for server chat fields', () {
      final message = read('lib/models/message.dart');
      final conversation = read('lib/models/conversation.dart');
      final communityChat = read('lib/screens/community/community_chat_screen.dart');

      expect(message, contains('AppDateUtils.parseServerTime'));
      expect(conversation, contains('AppDateUtils.parseServerTime'));
      expect(communityChat, contains('AppDateUtils.parseServerTime'));
      expect(communityChat, isNot(contains('DateTime.tryParse(raw.toString())')));
      expect(communityChat, isNot(contains('DateTime.tryParse(time)')));
    });
  });

  group('community chat client_msg_id regressions', () {
    test('community optimistic messages and send payload include client_msg_id', () {
      final screen = read('lib/screens/community/community_chat_screen.dart');
      final service = read('lib/services/api/community_service.dart');

      expect(screen, contains("'client_msg_id': clientMsgId"));
      expect(screen, contains('_nextCommunityClientMsgId'));
      expect(screen, contains('clientMsgId: clientMsgId'));
      expect(service, contains('String? clientMsgId'));
      expect(service, contains("data['client_msg_id'] = clientMsgId"));
    });

    test('community merge prioritizes client_msg_id before fuzzy matching', () {
      final screen = read('lib/screens/community/community_chat_screen.dart');
      final replaceStart = screen.indexOf('void _replaceOptimisticOrAppend');
      final fuzzyStart = screen.indexOf('bool _isMatchingOptimistic', replaceStart);
      expect(replaceStart, greaterThanOrEqualTo(0));
      expect(fuzzyStart, greaterThan(replaceStart));
      final replaceSource = screen.substring(replaceStart, fuzzyStart);

      expect(replaceSource, contains('_clientMsgIdOf(messageMap)'));
      expect(replaceSource, contains('_findMessageIndexByClientMsgId(clientMsgId)'));
      expect(replaceSource, contains('_removeDuplicateClientMessages(clientMsgId'));
      expect(replaceSource.indexOf('_findMessageIndexByClientMsgId(clientMsgId)'),
          lessThan(replaceSource.indexOf('_isMatchingOptimistic')));
    });
  });
}
```

- [ ] **Step 2: Run the failing test**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/chat_time_and_dedupe_regression_test.dart
```

Expected: FAIL because `parseServerTime` does not exist, community chat still parses some server times with `DateTime.tryParse`, and community send does not propagate `client_msg_id`.

---

## Task 4: Implement client server-time parsing

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\utils\date_utils.dart`
- Modify: `D:\FlutterProject\nonto\lib\models\message.dart`
- Modify: `D:\FlutterProject\nonto\lib\models\conversation.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\community\community_chat_screen.dart`

- [ ] **Step 1: Add nullable server-time parser**

In `lib/utils/date_utils.dart`, add this method above `parseBeijingTime`:

```dart
  /// Parse a backend timestamp into the local display timezone.
  ///
  /// Backend chat fields are stored as UTC. Older responses may serialize them
  /// without a timezone suffix, e.g. `2026-06-26T13:00:00`; treat those values
  /// as UTC instead of local time. Invalid values return null so callers do not
  /// accidentally sort old messages as `DateTime.now()`.
  static DateTime? parseServerTime(String? dateString) {
    final value = dateString?.trim();
    if (value == null || value.isEmpty) return null;

    final hasTimezone = RegExp(r'(Z|[+-]\\d{2}:?\\d{2})$').hasMatch(value);
    final normalized = hasTimezone ? value : '${value}Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }
```

Then replace `parseBeijingTime` with this compatibility wrapper:

```dart
  static DateTime parseBeijingTime(String? dateString) {
    return parseServerTime(dateString) ?? _nowLocalBeijing();
  }
```

Do not remove `_nowLocalBeijing()` because `formatTimeAgo()` and existing non-chat callers still use it.

- [ ] **Step 2: Update message model parsing**

In `lib/models/message.dart`, replace:

```dart
    createdAt: json['created_at'] != null ? AppDateUtils.parseBeijingTime(json['created_at'].toString()) : null,
```

with:

```dart
    createdAt: AppDateUtils.parseServerTime(json['created_at']?.toString()),
```

- [ ] **Step 3: Update conversation model parsing**

In `lib/models/conversation.dart`, replace:

```dart
        lastMessageAt: json['last_message_at'] != null
            ? AppDateUtils.parseBeijingTime(json['last_message_at'].toString())
            : null,
```

with:

```dart
        lastMessageAt: AppDateUtils.parseServerTime(json['last_message_at']?.toString()),
```

Keep non-chat model date parsing unchanged in this task.

- [ ] **Step 4: Update community chat time parsing**

In `lib/screens/community/community_chat_screen.dart`, add this import near the other `nonto/utils` imports:

```dart
import 'package:nonto/utils/date_utils.dart';
```

Replace `_messageTime` with:

```dart
  DateTime _messageTime(Map<String, dynamic> message) {
    return AppDateUtils.parseServerTime(message['created_at']?.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
```

Replace `_formatTime(dynamic time)` with:

```dart
  String _formatTime(dynamic time) {
    final dt = AppDateUtils.parseServerTime(time?.toString());
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
```

- [ ] **Step 5: Verify time tests still fail only on client_msg_id expectations**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/chat_time_and_dedupe_regression_test.dart
```

Expected: server-time parsing tests PASS; community `client_msg_id` tests still FAIL.

---

## Task 5: Add backend UTC-Z and community client_msg_id contract tests

**Files:**
- Create: `D:\NanTuPy\tests\test_critical_chat_unread_contracts.py`

- [ ] **Step 1: Write the failing backend tests**

Create `tests/test_critical_chat_unread_contracts.py` with:

```python
from datetime import datetime, timezone, timedelta


def test_isoformat_utc_z_serializes_naive_datetime_as_utc_z():
    from app.utils.time_utils import isoformat_utc_z

    assert isoformat_utc_z(datetime(2026, 6, 26, 13, 0, 0)) == "2026-06-26T13:00:00Z"


def test_isoformat_utc_z_converts_aware_datetime_to_utc_z():
    from app.utils.time_utils import isoformat_utc_z

    aware = datetime(2026, 6, 26, 21, 0, 0, tzinfo=timezone(timedelta(hours=8)))
    assert isoformat_utc_z(aware) == "2026-06-26T13:00:00Z"


def test_chat_models_use_utc_z_serializer_for_chat_timestamps():
    with open("app/models/models.py", "r", encoding="utf-8") as f:
        source = f.read()

    conversation_source = source.split("class Conversation")[1].split("class ConversationParticipant")[0]
    message_source = source.split("class Message")[1].split("class Notification")[0]

    assert "isoformat_utc_z" in conversation_source
    assert "isoformat_utc_z" in message_source
    assert "self.created_at.isoformat() if self.created_at else None" not in message_source
    assert "self.last_message_at.isoformat() if self.last_message_at else None" not in conversation_source


def test_community_chat_accepts_and_broadcasts_client_msg_id():
    with open("app/routers/communities.py", "r", encoding="utf-8") as f:
        source = f.read()

    send_source = source.split('async def send_community_message')[1].split('@router.delete("/{community_id}/chat/messages/{message_id}"')[0]

    assert 'client_msg_id = payload.get("client_msg_id")' in send_source
    assert 'msg_dict["client_msg_id"] = client_msg_id' in send_source
    assert '"message": msg_dict' in send_source
```

- [ ] **Step 2: Run the failing backend tests**

Run from `D:\NanTuPy`:

```bash
python -m pytest tests/test_critical_chat_unread_contracts.py -q
```

Expected: FAIL because `app.utils.time_utils` does not exist and community chat does not propagate `client_msg_id`.

---

## Task 6: Implement backend UTC-Z serialization and community client_msg_id propagation

**Files:**
- Create: `D:\NanTuPy\app\utils\time_utils.py`
- Modify: `D:\NanTuPy\app\models\models.py`
- Modify: `D:\NanTuPy\app\routers\communities.py`
- Modify: `D:\NanTuPy\app\routers\ws.py`

- [ ] **Step 1: Add UTC-Z serializer**

Create `app/utils/time_utils.py` with:

```python
from datetime import datetime, timezone


def isoformat_utc_z(value: datetime | None) -> str | None:
    """Serialize backend UTC datetimes as ISO-8601 strings with a Z suffix.

    SQLAlchemy models currently store naive UTC datetimes via datetime.utcnow().
    Treat naive values as UTC, convert aware values to UTC, and replace the
    Python '+00:00' suffix with 'Z' for a stable API contract.
    """
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    else:
        value = value.astimezone(timezone.utc)
    return value.isoformat().replace('+00:00', 'Z')
```

- [ ] **Step 2: Use serializer in chat model dictionaries**

In `app/models/models.py`, add near the imports:

```python
from app.utils.time_utils import isoformat_utc_z
```

In `Conversation.to_dict()`, replace:

```python
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
            'last_message_at': self.last_message_at.isoformat() if self.last_message_at else None,
```

with:

```python
            'created_at': isoformat_utc_z(self.created_at),
            'updated_at': isoformat_utc_z(self.updated_at),
            'last_message_at': isoformat_utc_z(self.last_message_at),
```

In `Message.to_dict()`, replace:

```python
            'recalled_at': self.recalled_at.isoformat() if self.recalled_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
```

with:

```python
            'recalled_at': isoformat_utc_z(self.recalled_at),
            'created_at': isoformat_utc_z(self.created_at),
```

- [ ] **Step 3: Propagate community client message ID**

In `app/routers/communities.py`, in `send_community_message`, add after payload normalization:

```python
    client_msg_id = payload.get("client_msg_id")
```

After this block:

```python
    msg_dict = inject_quote_preview(db, _community_message_to_dict(msg))
    msg_dict["community_id"] = community_id
    msg_dict["community_name"] = c.name
```

add:

```python
    if client_msg_id:
        msg_dict["client_msg_id"] = client_msg_id
```

Do not persist `client_msg_id` in the `Message` table in this task; community chat uses HTTP POST once, and the field only needs to let the current client match optimistic UI to the HTTP/WS result.

- [ ] **Step 4: Use UTC-Z serializer in manual WebSocket payloads**

In `app/routers/ws.py`, add near imports:

```python
from app.utils.time_utils import isoformat_utc_z
```

Replace manual `created_at` / `updated_at` serializations that produce chat/session payloads. The key replacements are:

```python
'created_at': msg.created_at.isoformat() if msg.created_at else None,
```

becomes:

```python
'created_at': isoformat_utc_z(msg.created_at),
```

and:

```python
'created_at': conv.created_at.isoformat() if conv.created_at else None,
'updated_at': conv.updated_at.isoformat() if conv.updated_at else None,
```

becomes:

```python
'created_at': isoformat_utc_z(conv.created_at),
'updated_at': isoformat_utc_z(conv.updated_at),
```

Also replace the manual send-message response field inside `_handle_send_message`:

```python
"created_at": msg.created_at.isoformat() if msg.created_at else None,
```

with:

```python
"created_at": isoformat_utc_z(msg.created_at),
```

- [ ] **Step 5: Verify backend contract tests pass**

Run from `D:\NanTuPy`:

```bash
python -m pytest tests/test_critical_chat_unread_contracts.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit backend contract fix**

Run from `D:\NanTuPy`:

```bash
git add app/utils/time_utils.py app/models/models.py app/routers/communities.py app/routers/ws.py tests/test_critical_chat_unread_contracts.py
git commit -m "fix: normalize chat timestamps and echo community client ids"
```

Expected: commit succeeds.

---

## Task 7: Implement community chat client_msg_id send path

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\services\api\community_service.dart`
- Modify: `D:\FlutterProject\nonto\lib\screens\community\community_chat_screen.dart`

- [ ] **Step 1: Extend community send API**

In `lib/services/api/community_service.dart`, update `sendMessage` signature from:

```dart
  Future<ApiResponse> sendMessage(
    int communityId, {
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    int? relatedId,
    List<int>? mentionUserIds,
    int? quoteMessageId,
  }) {
```

 to:

```dart
  Future<ApiResponse> sendMessage(
    int communityId, {
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    int? relatedId,
    List<int>? mentionUserIds,
    int? quoteMessageId,
    String? clientMsgId,
  }) {
```

Before `return _api.post(...)`, add:

```dart
    if (clientMsgId != null && clientMsgId.isNotEmpty) {
      data['client_msg_id'] = clientMsgId;
    }
```

- [ ] **Step 2: Add community client message ID generator**

In `lib/screens/community/community_chat_screen.dart`, add a field near `_highlightMessageId`:

```dart
  int _clientMsgSeq = 0;
```

Add this method before `_sendMessage()`:

```dart
  String _nextCommunityClientMsgId() {
    final user = ref.read(authProvider).user;
    final userId = user == null ? 'anon' : user.id.toString();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final seq = _clientMsgSeq++;
    return 'community_${widget.communityId}_${userId}_${timestamp}_$seq';
  }
```

- [ ] **Step 3: Store client_msg_id in optimistic messages**

Change `_buildOptimisticMessage` signature from:

```dart
  Map<String, dynamic> _buildOptimisticMessage({
    required String content,
    required String messageType,
    String? mediaUrl,
    List<int>? mentionUserIds,
    int? quoteMessageId,
    String? quotePreview,
  }) {
```

 to:

```dart
  Map<String, dynamic> _buildOptimisticMessage({
    required String content,
    required String messageType,
    required String clientMsgId,
    String? mediaUrl,
    List<int>? mentionUserIds,
    int? quoteMessageId,
    String? quotePreview,
  }) {
```

Inside the returned map, add:

```dart
      'client_msg_id': clientMsgId,
```

right before:

```dart
      'status': 'sending',
```

- [ ] **Step 4: Pass clientMsgId for text send**

In `_sendMessage()`, before `_buildOptimisticMessage(...)`, add:

```dart
    final clientMsgId = _nextCommunityClientMsgId();
```

Pass it into the optimistic message:

```dart
      clientMsgId: clientMsgId,
```

Pass it into `CommunityApiService().sendMessage(...)`:

```dart
        clientMsgId: clientMsgId,
```

- [ ] **Step 5: Pass clientMsgId for retry send**

In `_retryMessage(...)`, before `_buildOptimisticMessage(...)`, add:

```dart
    final clientMsgId = _nextCommunityClientMsgId();
```

Pass it into the retry `_buildOptimisticMessage(...)` call:

```dart
      clientMsgId: clientMsgId,
```

Pass it into the retry `CommunityApiService().sendMessage(...)` call:

```dart
          clientMsgId: clientMsgId,
```

- [ ] **Step 6: Pass clientMsgId for media send**

In `_sendMediaMessage(...)`, before `_buildOptimisticMessage(...)`, add:

```dart
      final clientMsgId = _nextCommunityClientMsgId();
```

Pass it into `_buildOptimisticMessage(...)`:

```dart
        clientMsgId: clientMsgId,
```

Pass it into `CommunityApiService().sendMessage(...)`:

```dart
        clientMsgId: clientMsgId,
```

- [ ] **Step 7: Run client de-dupe tests and confirm remaining merge failure**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/chat_time_and_dedupe_regression_test.dart
```

Expected: time parsing tests PASS, send-path `client_msg_id` checks PASS, merge-priority checks still FAIL.

---

## Task 8: Implement deterministic community chat merge/de-dupe

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\community\community_chat_screen.dart`

- [ ] **Step 1: Add helper methods before `_replaceOptimisticOrAppend`**

Add these helpers immediately before `void _replaceOptimisticOrAppend(...)`:

```dart
  String? _clientMsgIdOf(Map<String, dynamic> message) {
    final raw = message['client_msg_id'] ?? message['clientMsgId'];
    final value = raw?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  int _findMessageIndexByClientMsgId(String? clientMsgId) {
    if (clientMsgId == null || clientMsgId.isEmpty) return -1;
    return _messages.indexWhere(
      (existing) => _clientMsgIdOf(existing) == clientMsgId,
    );
  }

  int _findMessageIndexByServerId(dynamic messageId) {
    if (messageId == null) return -1;
    return _messages.indexWhere((existing) => existing['id'] == messageId);
  }

  void _removeDuplicateClientMessages(String? clientMsgId, int keepIndex) {
    if (clientMsgId == null || clientMsgId.isEmpty) return;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (i != keepIndex && _clientMsgIdOf(_messages[i]) == clientMsgId) {
        _messages.removeAt(i);
        if (i < keepIndex) keepIndex--;
      }
    }
  }
```

- [ ] **Step 2: Replace `_replaceOptimisticOrAppend`**

Replace the whole method with:

```dart
  void _replaceOptimisticOrAppend(Map<String, dynamic> messageMap,
      {dynamic optimisticId}) {
    final clientMsgId = _clientMsgIdOf(messageMap);
    final messageId = messageMap['id'];
    final existingServerIdx = _findMessageIndexByServerId(messageId);
    final optimisticByIdIdx = optimisticId == null
        ? -1
        : _messages.indexWhere((existing) => existing['id'] == optimisticId);
    final optimisticByClientIdx = _findMessageIndexByClientMsgId(clientMsgId);
    final fuzzyOptimisticIdx = _messages.indexWhere(
      (existing) => _isMatchingOptimistic(existing, messageMap),
    );

    setState(() {
      var keepIndex = -1;
      if (existingServerIdx >= 0) {
        _messages[existingServerIdx] = {
          ..._messages[existingServerIdx],
          ...messageMap,
          if (clientMsgId != null) 'client_msg_id': clientMsgId,
        };
        keepIndex = existingServerIdx;
      } else if (optimisticByIdIdx >= 0) {
        _messages[optimisticByIdIdx] = messageMap;
        keepIndex = optimisticByIdIdx;
      } else if (optimisticByClientIdx >= 0) {
        _messages[optimisticByClientIdx] = messageMap;
        keepIndex = optimisticByClientIdx;
      } else if (fuzzyOptimisticIdx >= 0) {
        _messages[fuzzyOptimisticIdx] = messageMap;
        keepIndex = fuzzyOptimisticIdx;
      } else {
        _messages.add(messageMap);
        keepIndex = _messages.length - 1;
      }

      _removeDuplicateClientMessages(clientMsgId, keepIndex);
      _messages.sort((a, b) => _messageTime(a).compareTo(_messageTime(b)));
    });
  }
```

- [ ] **Step 3: Make fuzzy matching prefer client ID when available**

At the top of `_isMatchingOptimistic(...)`, add:

```dart
    final incomingClientMsgId = _clientMsgIdOf(incoming);
    final existingClientMsgId = _clientMsgIdOf(existing);
    if (incomingClientMsgId != null && existingClientMsgId != null) {
      return incomingClientMsgId == existingClientMsgId;
    }
```

Keep the existing sender/content/type/media/time fallback after this block.

- [ ] **Step 4: Verify client chat time and de-dupe tests pass**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/chat_time_and_dedupe_regression_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit client time and de-dupe fix**

Run from `D:\FlutterProject\nonto`:

```bash
git add test/chat_time_and_dedupe_regression_test.dart lib/utils/date_utils.dart lib/models/message.dart lib/models/conversation.dart lib/services/api/community_service.dart lib/screens/community/community_chat_screen.dart
git commit -m "fix: stabilize chat times and community message dedupe"
```

Expected: commit succeeds.

---

## Task 9: Full verification

**Files:**
- No source changes expected unless verification reveals failures.

- [ ] **Step 1: Run focused client regression tests**

Run from `D:\FlutterProject\nonto`:

```bash
flutter test test/unread_badge_regression_test.dart test/chat_time_and_dedupe_regression_test.dart test/chat_reliability_regression_test.dart
```

Expected: all tests PASS.

- [ ] **Step 2: Run client analyzer**

Run from `D:\FlutterProject\nonto`:

```bash
flutter analyze
```

Expected: exits 0. If existing unrelated analyzer warnings appear, capture them and do not claim analyzer clean.

- [ ] **Step 3: Run focused backend tests**

Run from `D:\NanTuPy`:

```bash
python -m pytest tests/test_critical_chat_unread_contracts.py tests/test_community_chat_contracts.py tests/test_chat_message_type_contracts.py -q
```

Expected: all selected tests PASS.

- [ ] **Step 4: Check git status in both repos**

Run:

```bash
git -C /d/FlutterProject/nonto status --short
git -C /d/NanTuPy status --short
```

Expected: no unexpected untracked or modified files except intentional work if commits were skipped by the executor.

---

## Requirement coverage checklist

- Bottom navigation message badge only counts conversations: Task 1, Task 2.
- Notification entry uses notification count source: Task 1, Task 2.
- Badge color matches conversation list: Task 1, Task 2.
- Server time parsing does not treat UTC as local time: Task 3, Task 4, Task 6.
- Invalid timestamps do not become `DateTime.now()` in chat sorting: Task 3, Task 4.
- Community optimistic message can be matched to HTTP/WS result: Task 3, Task 7, Task 8.
- Community HTTP response and WS broadcast include `client_msg_id`: Task 5, Task 6.
- Backend chat timestamps use UTC `Z` format: Task 5, Task 6.

## Notes for implementers

- Keep `parseBeijingTime` as a compatibility wrapper because many non-chat models still call it.
- Do not add a `client_msg_id` database column for community messages in this phase.
- Do not include notification unread in `unreadMessagesCountProvider`; that provider already sums `Conversation.unreadCount`.
- If `flutter analyze` reports unrelated pre-existing issues, document the exact output and continue only with focused test evidence.
