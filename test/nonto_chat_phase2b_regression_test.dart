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

    test('initial chat entry starts at the latest-message origin', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('reverse: true'));
      expect(source, contains('void _scrollToLatest'));
      expect(source, contains('_scrollController.jumpTo(0)'));
      expect(
          source, isNot(contains('bool _didInitialScrollToLatest = false;')));
      expect(source,
          isNot(contains('_scrollToBottom(animate: false, force: true)')));
    });

    test('chat provider startup is deferred until after the first frame', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      final callbackStart =
          source.indexOf('WidgetsBinding.instance.addPostFrameCallback((_) {');
      final initCall = source.indexOf('.init(currentUserId', callbackStart);

      expect(callbackStart, greaterThanOrEqualTo(0));
      expect(initCall, greaterThan(callbackStart));
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

    test('composer uses animated keyed send and empty states', () {
      final source =
          File('lib/screens/chat/chat_room_screen.dart').readAsStringSync();

      expect(source, contains('AnimatedSwitcher'));
      expect(source, contains("ValueKey('chat-send-empty')"));
      expect(source, contains("ValueKey('chat-send-button')"));
    });
  });
}
