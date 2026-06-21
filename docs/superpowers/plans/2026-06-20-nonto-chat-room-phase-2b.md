# Nonto Chat Room Phase 2B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the chat room UI/UX with Nonto-owned naming and a reactive message composer send button.

**Architecture:** Keep this slice low-risk and presentation-only. Do not modify WebSocket, send queue, message provider, sync, uploads, or backend contracts. Update `ChatRoomScreen` in place because the chat room is currently a single large screen, and add source-level regression tests to lock the intended behavior before changing production code.

**Tech Stack:** Flutter, Dart, Riverpod, existing chat room state/providers, Flutter test.

---

## File Structure

- Modify: `D:\FlutterProject\nonto\lib\screens\chat\chat_room_screen.dart`
  - Rename private color token class `_TwColors` to `_NontoChatColors`.
  - Update comments so the screen no longer describes itself as Twitter/X DM.
  - Change `_buildInputBar` so the send button is driven by `ValueListenableBuilder<TextEditingValue>` on `_messageController`.
  - Add `AnimatedSwitcher` around the send/progress affordance so the composer reacts smoothly without rebuilding the whole screen.

- Test: `D:\FlutterProject\nonto\test\nonto_chat_phase2b_regression_test.dart`
  - Assert the chat room source no longer contains `_TwColors` or Twitter/X DM labels.
  - Assert composer source uses `ValueListenableBuilder<TextEditingValue>` and no longer computes stale `hasText` once per parent build.
  - Assert composer has animated keyed send/sending states.

## Tasks

### Task 1: Add failing Phase 2B regression tests

**Files:**
- Create: `D:\FlutterProject\nonto\test\nonto_chat_phase2b_regression_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 2B chat room source regressions', () {
    test('chat room uses Nonto-owned naming instead of Twitter/X labels', () {
      final source = File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('class _NontoChatColors'));
      expect(source, isNot(contains('_TwColors')));
      expect(source, isNot(contains('Twitter/X DM')));
      expect(source, isNot(contains('Twitter DM')));
    });

    test('composer send affordance reacts to text changes locally', () {
      final source = File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('ValueListenableBuilder<TextEditingValue>'));
      expect(source, contains('valueListenable: _messageController'));
      expect(source, isNot(contains('final hasText = _messageController.text.trim().isNotEmpty;')));
    });

    test('composer uses animated keyed send and sending states', () {
      final source = File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('AnimatedSwitcher'));
      expect(source, contains("ValueKey('chat-send-progress')"));
      expect(source, contains("ValueKey('chat-send-button')"));
    });
  });
}
```

- [ ] **Step 2: Run RED**

```bash
flutter test test/nonto_chat_phase2b_regression_test.dart
```

Expected: FAIL because `ChatRoomScreen` still uses `_TwColors`, Twitter/X comments, and the composer does not use `ValueListenableBuilder`.

### Task 2: Rename chat UI tokens to Nonto naming

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\chat\chat_room_screen.dart`

- [ ] **Step 1: Replace private color token naming**

Replace all `_TwColors` references with `_NontoChatColors`.

- [ ] **Step 2: Update comments**

Change:

```dart
// ── Twitter DM 颜色常量 ──
/// Twitter/X DM 风格聊天室页面
```

to:

```dart
// ── Nonto 聊天颜色常量 ──
/// Nonto 聊天室页面
```

- [ ] **Step 3: Run RED/GREEN checkpoint**

```bash
flutter test test/nonto_chat_phase2b_regression_test.dart
```

Expected: still FAIL until composer behavior is updated.

### Task 3: Make composer send affordance reactive

**Files:**
- Modify: `D:\FlutterProject\nonto\lib\screens\chat\chat_room_screen.dart`

- [ ] **Step 1: Remove stale parent-build hasText**

Delete this line from `_buildInputBar`:

```dart
final hasText = _messageController.text.trim().isNotEmpty;
```

- [ ] **Step 2: Replace send button conditional with local value-listenable builder**

Replace:

```dart
if (hasText || isSending)
  isSending
      ? const Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                color: _NontoChatColors.selfBubble, strokeWidth: 2),
          ),
        )
      : IconButton(
          icon: const Icon(Icons.send_rounded,
              color: _NontoChatColors.selfBubble, size: 22),
          onPressed: _sendMessage,
          padding: EdgeInsets.zero,
          constraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
```

with:

```dart
ValueListenableBuilder<TextEditingValue>(
  valueListenable: _messageController,
  builder: (context, value, _) {
    final hasText = value.text.trim().isNotEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isSending
          ? const Padding(
              key: ValueKey('chat-send-progress'),
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: _NontoChatColors.selfBubble,
                  strokeWidth: 2,
                ),
              ),
            )
          : hasText
              ? IconButton(
                  key: const ValueKey('chat-send-button'),
                  icon: const Icon(
                    Icons.send_rounded,
                    color: _NontoChatColors.selfBubble,
                    size: 22,
                  ),
                  onPressed: _sendMessage,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                )
              : const SizedBox(
                  key: ValueKey('chat-send-empty'),
                  width: 36,
                  height: 36,
                ),
    );
  },
),
```

- [ ] **Step 3: Run Phase 2B tests**

```bash
flutter test test/nonto_chat_phase2b_regression_test.dart
```

Expected: PASS.

### Task 4: Format and verify

**Files:**
- Modify/Test all Phase 2B files.

- [ ] **Step 1: Format**

```bash
dart format lib/screens/chat/chat_room_screen.dart test/nonto_chat_phase2b_regression_test.dart
```

- [ ] **Step 2: Run targeted Phase 2B tests**

```bash
flutter test test/nonto_chat_phase2b_regression_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Phase 2A and Phase 1 regressions**

```bash
flutter test test/nonto_messages_phase2a_regression_test.dart test/nonto_ui_phase1_regression_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full suite with required dart-defines**

```bash
flutter test --dart-define=API_BASE_URL=https://www.nonto.online/api --dart-define=WS_URL=wss://www.nonto.online/ws
```

Expected: PASS.

- [ ] **Step 5: Run analyzer on modified files**

```bash
dart analyze lib/screens/chat/chat_room_screen.dart test/nonto_chat_phase2b_regression_test.dart
```

Expected: no issues in Phase 2B files.

- [ ] **Step 6: Run full analyzer**

```bash
flutter analyze
```

Expected: may still fail with existing project analyzer issues; report actual output honestly.

## Self-Review

- Spec coverage: low-risk chat room UI/UX modernization, Nonto naming, and composer responsiveness are covered.
- Placeholder scan: no placeholders remain.
- Type consistency: `ValueListenableBuilder<TextEditingValue>` works with `TextEditingController`, and `_NontoChatColors` remains private to `ChatRoomScreen`.
