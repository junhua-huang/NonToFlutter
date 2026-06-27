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

    test('websocket normalization does not replace missing server timestamps with current time', () {
      final source = read('lib/services/websocket_service.dart');
      final newMessageStart = source.indexOf("case 'new_message':");
      final notifierComment = source.indexOf('// Notifier 需要 event 字段', newMessageStart);
      expect(newMessageStart, greaterThanOrEqualTo(0));
      expect(notifierComment, greaterThan(newMessageStart));
      final newMessageSource = source.substring(newMessageStart, notifierComment);

      expect(newMessageSource, isNot(contains('DateTime.now().toIso8601String()')));
      expect(newMessageSource, isNot(contains("normalized['created_at'] =")));
    });
  });

  group('private chat ordering and optimistic de-duplication', () {
    test('private chat merges server refresh with pending optimistic messages by client_msg_id', () {
      final source = read('lib/providers/chat_notifiers.dart');
      final mergeStart = source.indexOf('final serverIds = serverMessages.map((m) => m.id).toSet();');
      final persistStart = source.indexOf('await DataLayer().persistMessages(serverMessages);', mergeStart);
      expect(mergeStart, greaterThanOrEqualTo(0));
      expect(persistStart, greaterThan(mergeStart));
      final mergeSource = source.substring(mergeStart, persistStart);

      expect(mergeSource, contains('serverClientMsgIds'));
      expect(mergeSource, contains('m.clientMsgId'));
      expect(mergeSource, contains('!serverClientMsgIds.contains(m.clientMsgId)'));
      expect(mergeSource, contains('_compareMessagesForTimeline'));
    });

    test('private chat uses a single timeline comparator with seq, createdAt, and id fallback', () {
      final source = read('lib/providers/chat_notifiers.dart');
      final helperStart = source.indexOf('int _compareMessagesForTimeline');
      expect(helperStart, greaterThanOrEqualTo(0));
      final classEnd = source.indexOf('class _ChatService', helperStart);
      final helperSource = source.substring(
        helperStart,
        classEnd > helperStart ? classEnd : source.length,
      );

      expect(helperSource, contains('a.seq != null && b.seq != null'));
      expect(helperSource, contains('a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)'));
      expect(helperSource, contains('return a.id.compareTo(b.id);'));
    });

    test('private sqlite fallback keeps timeline order instead of reversing twice', () {
      final source = read('lib/providers/chat_notifiers.dart');
      final sqliteStart = source.indexOf('// Step 2: SQLite 持久层');
      final networkStart = source.indexOf('// Step 3: DataLayer 标准缓存', sqliteStart);
      expect(sqliteStart, greaterThanOrEqualTo(0));
      expect(networkStart, greaterThan(sqliteStart));
      final sqliteSource = source.substring(sqliteStart, networkStart);

      expect(sqliteSource, isNot(contains('localMessages.reversed.toList()')));
      expect(sqliteSource, contains('localTimeline.sort(_compareMessagesForTimeline)'));
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

    test('community deduplicates by normalized id when merging and loading history', () {
      final source = read('lib/screens/community/community_chat_screen.dart');
      final mergeStart = source.indexOf('List<Map<String, dynamic>> _mergeServerMessages');
      final cacheStart = source.indexOf('Future<void> _writeMessagesCache', mergeStart);
      final loadMoreStart = source.indexOf('Future<void> _loadMoreHistory()');
      final quoteStart = source.indexOf('/// 点击引用预览条', loadMoreStart);
      expect(mergeStart, greaterThanOrEqualTo(0));
      expect(cacheStart, greaterThan(mergeStart));
      expect(loadMoreStart, greaterThanOrEqualTo(0));
      expect(quoteStart, greaterThan(loadMoreStart));
      final mergeSource = source.substring(mergeStart, cacheStart);
      final loadMoreSource = source.substring(loadMoreStart, quoteStart);

      expect(source, contains('String? _messageIdentity'));
      expect(mergeSource, contains('_messageIdentity(message)'));
      expect(loadMoreSource, contains('existingIds'));
      expect(loadMoreSource, contains('_messageIdentity(message)'));
      expect(loadMoreSource, isNot(contains('_messages.insertAll(0, older);')));
    });

    test('community media sends carry stable client message ids', () {
      final source = read('lib/screens/community/community_chat_screen.dart');
      final mediaStart = source.indexOf('Future<void> _sendMediaMessage');
      final previewStart = source.indexOf('void _syncConversationPreview', mediaStart);
      expect(mediaStart, greaterThanOrEqualTo(0));
      expect(previewStart, greaterThan(mediaStart));
      final mediaSource = source.substring(mediaStart, previewStart);

      expect(mediaSource, contains('final clientMsgId = _newClientMsgId();'));
      expect(mediaSource, contains('clientMsgId: clientMsgId'));
      expect(mediaSource, contains('clientMsgId: clientMsgId'));
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
