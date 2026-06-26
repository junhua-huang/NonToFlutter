import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/utils/date_utils.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('server chat timestamp parsing', () {
    test('timezone-less server timestamps are treated as UTC', () {
      final parsed = AppDateUtils.parseServerTime('2026-06-26T13:00:00');

      expect(parsed, DateTime.parse('2026-06-26T13:00:00Z').toLocal());
    });

    test('explicit timezone offsets keep their original instant', () {
      final parsed = AppDateUtils.parseServerTime('2026-06-26T13:00:00+08:00');

      expect(parsed, DateTime.parse('2026-06-26T13:00:00+08:00').toLocal());
    });

    test('invalid server timestamps return null instead of current time', () {
      expect(AppDateUtils.parseServerTime('not-a-date'), isNull);

      final message = Message.fromJson({
        'id': 1,
        'conversation_id': 2,
        'sender_id': 3,
        'content': 'old malformed message',
        'created_at': 'not-a-date',
      });
      expect(message.createdAt, isNull);
    });
  });

  group('community chat optimistic de-duplication', () {
    test('community send payload carries a stable client message id', () {
      final service = read('lib/services/api/community_service.dart');
      final sendStart = service.indexOf('Future<ApiResponse> sendMessage');
      final recallStart = service.indexOf('/// 撤回消息', sendStart);
      expect(sendStart, greaterThanOrEqualTo(0));
      expect(recallStart, greaterThan(sendStart));
      final sendSource = service.substring(sendStart, recallStart);

      expect(sendSource, contains('String? clientMsgId'));
      expect(sendSource, contains("data['client_msg_id'] = clientMsgId"));
    });

    test(
        'community optimistic, HTTP response, and websocket echo merge by client_msg_id',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');
      final sendStart = source.indexOf('Future<void> _sendMessage()');
      final retryStart = source.indexOf('void _retryMessage', sendStart);
      final matchStart = source.indexOf('bool _isMatchingOptimistic');
      final timeStart = source.indexOf('DateTime _messageTime', matchStart);
      expect(sendStart, greaterThanOrEqualTo(0));
      expect(retryStart, greaterThan(sendStart));
      expect(matchStart, greaterThan(retryStart));
      expect(timeStart, greaterThan(matchStart));
      final sendSource = source.substring(sendStart, retryStart);
      final matchSource = source.substring(matchStart, timeStart);

      expect(source, contains('String _newClientMsgId()'));
      expect(sendSource, contains('final clientMsgId = _newClientMsgId();'));
      expect(sendSource, contains('clientMsgId: clientMsgId'));
      expect(sendSource, contains("client_msg_id"));
      expect(sendSource, contains('clientMsgId: clientMsgId'));
      expect(matchSource, contains("existing['client_msg_id']"));
      expect(matchSource, contains("incoming['client_msg_id']"));
      expect(matchSource, contains('return true;'));
    });

    test(
        'community message sorting uses server time parser, not raw DateTime.tryParse',
        () {
      final source = read('lib/screens/community/community_chat_screen.dart');
      final timeStart = source.indexOf('DateTime _messageTime');
      final textStart = source.indexOf('void _onTextChanged', timeStart);
      expect(timeStart, greaterThanOrEqualTo(0));
      expect(textStart, greaterThan(timeStart));
      final timeSource = source.substring(timeStart, textStart);

      expect(timeSource, contains('AppDateUtils.parseServerTime'));
      expect(timeSource, isNot(contains('DateTime.tryParse')));
    });
  });
}
