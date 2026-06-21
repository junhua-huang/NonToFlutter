# Nonto Notifications Phase 4B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the Notifications tab into a Nonto-owned, lazy-rendered activity feed with clearer unread/read sections.

**Architecture:** Keep `NotificationsNotifier` and API behavior unchanged. Add a tiny private feed-entry model inside `notifications_tab.dart` so the tab can render headers, the read-toggle row, and notification tiles with `ListView.builder` instead of eagerly expanding every widget.

**Tech Stack:** Flutter, Riverpod, `pull_to_refresh_flutter3`, existing Nonto theme/components, Flutter source regression tests.

---

## Files

- Create: `test/nonto_notifications_phase4b_regression_test.dart`
  - Source regression tests for Nonto wording, lazy rendering, collapsed read behavior, and unchanged reliability semantics.
- Modify: `lib/screens/notifications/notifications_tab.dart`
  - Replace eager `ListView(children: [...])` with lazy `ListView.builder` backed by `_NotificationFeedEntry`.
  - Add reusable loading/empty helpers for this tab.
  - Keep existing routes and provider calls.
- Existing verification: `test/notification_ux_regression_test.dart`
  - Must keep passing.

---

### Task 1: Add Phase 4B source regression test

**Files:**
- Create: `test/nonto_notifications_phase4b_regression_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/nonto_notifications_phase4b_regression_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4B notifications source regressions', () {
    test('notifications tab uses Nonto-owned activity wording', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains('Nonto 通知页'));
      expect(source, contains('新的互动'));
      expect(source, contains('稍早动态'));
      expect(source, isNot(contains('Twitter')));
      expect(source, isNot(contains('X-style')));
    });

    test('notifications feed renders lazily with builder', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains('ListView.builder'));
      expect(source, contains('_buildNotificationEntries('));
      expect(source, contains('itemBuilder: (context, index)'));
      expect(source, isNot(contains('children: [\n                          ...unread.map')));
      expect(source, isNot(contains('read.map(_buildNotificationTile).toList()')));
    });

    test('collapsed read notifications are not built as tiles', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains("_NotificationFeedEntry.readToggle(read.length)"));
      expect(source, contains('if (_showReadNotifications)'));
      expect(source, contains("_NotificationFeedEntry.notification(n)"));
    });

    test('notifications tab keeps reliability semantics', () {
      final source = read('lib/screens/notifications/notifications_tab.dart');

      expect(source, contains('notificationsProvider.notifier).markAsRead(id)'));
      expect(source, contains('SmartRefresher'));
      expect(source, isNot(contains('NotificationService().markAllRead()')));
      expect(source, isNot(contains('id: 0,')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/nonto_notifications_phase4b_regression_test.dart
```

Expected: FAIL because `notifications_tab.dart` still uses eager mapped children and lacks Phase 4B wording/feed-entry structure.

---

### Task 2: Implement lazy notification feed entries

**Files:**
- Modify: `lib/screens/notifications/notifications_tab.dart`

- [ ] **Step 1: Add Nonto page comment**

Above `class NotificationsTab`, add:

```dart
/// Nonto 通知页：聚合互动、好友、消息与系统动态。
class NotificationsTab extends ConsumerStatefulWidget {
```

- [ ] **Step 2: Add private feed-entry model near the bottom of the file**

Add before `_NotificationTile`:

```dart
enum _NotificationFeedEntryType { sectionHeader, readToggle, notification }

class _NotificationFeedEntry {
  final _NotificationFeedEntryType type;
  final String? title;
  final int? count;
  final app_notif.AppNotification? notification;

  const _NotificationFeedEntry._({
    required this.type,
    this.title,
    this.count,
    this.notification,
  });

  const _NotificationFeedEntry.sectionHeader(String title, int count)
      : this._(
          type: _NotificationFeedEntryType.sectionHeader,
          title: title,
          count: count,
        );

  const _NotificationFeedEntry.readToggle(int count)
      : this._(
          type: _NotificationFeedEntryType.readToggle,
          count: count,
        );

  const _NotificationFeedEntry.notification(app_notif.AppNotification notification)
      : this._(
          type: _NotificationFeedEntryType.notification,
          notification: notification,
        );
}
```

- [ ] **Step 3: Add entry builder helper inside `_NotificationsTabState`**

Add after `_read(...)`:

```dart
List<_NotificationFeedEntry> _buildNotificationEntries(
  List<app_notif.AppNotification> unread,
  List<app_notif.AppNotification> read,
) {
  final entries = <_NotificationFeedEntry>[];
  if (unread.isNotEmpty) {
    entries.add(_NotificationFeedEntry.sectionHeader('新的互动', unread.length));
    entries.addAll(unread.map(_NotificationFeedEntry.notification));
  }
  if (read.isNotEmpty) {
    entries.add(_NotificationFeedEntry.readToggle(read.length));
    if (_showReadNotifications) {
      entries.add(_NotificationFeedEntry.sectionHeader('稍早动态', read.length));
      entries.addAll(read.map(_NotificationFeedEntry.notification));
    }
  }
  return entries;
}
```

- [ ] **Step 4: Add row builders inside `_NotificationsTabState`**

Add after `_buildNotificationTile(...)`:

```dart
Widget _buildSectionHeader(String title, int count) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildReadToggle(int count) {
  return InkWell(
    onTap: () => setState(() =>
        _showReadNotifications = !_showReadNotifications),
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          const Icon(Icons.done_all,
              color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Text(
            '稍早动态 ($count)',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          AnimatedRotation(
            turns: _showReadNotifications ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: const Icon(Icons.expand_more,
                color: AppColors.textSecondary, size: 20),
          ),
        ],
      ),
    ),
  );
}

Widget _buildNotificationEntry(_NotificationFeedEntry entry) {
  switch (entry.type) {
    case _NotificationFeedEntryType.sectionHeader:
      return _buildSectionHeader(entry.title!, entry.count!);
    case _NotificationFeedEntryType.readToggle:
      return _buildReadToggle(entry.count!);
    case _NotificationFeedEntryType.notification:
      return _buildNotificationTile(entry.notification!);
  }
}
```

- [ ] **Step 5: Replace eager `ListView` body branch with `ListView.builder`**

In `build`, after `final read = _read(state.notifications);`, add:

```dart
final entries = _buildNotificationEntries(unread, read);
```

Replace the existing non-empty branch:

```dart
: ListView(
    children: [
      ...unread.map(_buildNotificationTile),
      if (read.isNotEmpty) ...[
        InkWell(
          ...
        ),
        AnimatedSize(
          ...
        ),
      ],
    ],
  ),
```

with:

```dart
: ListView.builder(
    itemCount: entries.length,
    itemBuilder: (context, index) =>
        _buildNotificationEntry(entries[index]),
  ),
```

- [ ] **Step 6: Format and run Phase 4B test**

Run:

```bash
cd /d/FlutterProject/nonto && dart format lib/screens/notifications/notifications_tab.dart test/nonto_notifications_phase4b_regression_test.dart
cd /d/FlutterProject/nonto && flutter test test/nonto_notifications_phase4b_regression_test.dart
```

Expected: PASS.

---

### Task 3: Verify existing notification behavior and analyzer

**Files:**
- Test: `test/notification_ux_regression_test.dart`
- Analyze: `lib/screens/notifications/notifications_tab.dart`, `test/nonto_notifications_phase4b_regression_test.dart`

- [ ] **Step 1: Run existing notification regression tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/notification_ux_regression_test.dart test/nonto_notifications_phase4b_regression_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run targeted analyzer**

Run:

```bash
cd /d/FlutterProject/nonto && dart analyze lib/screens/notifications/notifications_tab.dart test/nonto_notifications_phase4b_regression_test.dart
```

Expected: ideally no issues in touched files. If analyzer reports an issue in these files, fix it before continuing.

- [ ] **Step 3: Run performance/explore/profile smoke regressions**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test test/page_performance_regression_test.dart test/nonto_explore_phase3a_regression_test.dart test/nonto_explore_phase3b_regression_test.dart test/nonto_profile_phase4a_regression_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full Flutter tests**

Run:

```bash
cd /d/FlutterProject/nonto && flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

- [ ] **Step 5: Run full analyzer and report honestly**

Run:

```bash
cd /d/FlutterProject/nonto && flutter analyze
```

Expected: may still fail with pre-existing project-wide issues. Report exact issue count and whether touched files remain clean.

---

## Self-Review

- Spec coverage: The plan covers Nonto wording, unread/read sections, lazy rendering, collapsed read behavior, unchanged routing/provider semantics, and verification.
- Placeholder scan: No placeholders remain; every code step includes concrete code and commands.
- Type consistency: `_NotificationFeedEntry`, `_NotificationFeedEntryType`, and helper names match across tasks.
