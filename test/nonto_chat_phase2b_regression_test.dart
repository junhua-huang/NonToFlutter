import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 2B chat room source regressions', () {
    test('chat room uses Nonto-owned naming instead of Twitter/X labels', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('class _NontoChatColors'));
      expect(source, isNot(contains('_TwColors')));
      expect(source, isNot(contains('Twitter/X DM')));
      expect(source, isNot(contains('Twitter DM')));
    });

    test('composer send affordance reacts to text changes locally', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('ValueListenableBuilder<TextEditingValue>'));
      expect(source, contains('valueListenable: _messageController'));
      expect(
          source,
          isNot(contains(
              'final hasText = _messageController.text.trim().isNotEmpty;')));
    });

    test('initial chat entry forces latest-message scroll once', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('bool _didInitialScrollToLatest = false;'));
      expect(source, contains('_scrollToBottom(animate: false, force: true)'));
      expect(source, contains('if (!force && distance > 800) return;'));
    });

    test('dark chat chrome uses neutral Nonto semantic colors', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('AppColors.background'));
      expect(source, contains('AppColors.surface'));
      expect(source, contains('AppColors.textPrimary'));
      expect(source, isNot(contains('0xFF15202B')));
      expect(source, isNot(contains('0xFF1E2732')));
    });

    test('composer uses animated keyed send and sending states', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('AnimatedSwitcher'));
      expect(source, contains("ValueKey('chat-send-progress')"));
      expect(source, contains("ValueKey('chat-send-button')"));
    });
  });
}
