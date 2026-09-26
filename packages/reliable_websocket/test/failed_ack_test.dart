import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reliable_websocket/reliable_websocket.dart';
import 'package:reliable_websocket/src/connection/connection_manager.dart';
import 'package:reliable_websocket/src/database/database.dart';
import 'package:reliable_websocket/src/outbox/outbox_manager.dart';
import 'package:reliable_websocket/src/sender/reliable_sender.dart';

void main() {
  group('failed ACK parsing', () {
    test('decodes flattened non-200 ACK as typed terminal failure', () {
      final frame = ProtocolFrame.fromJson({
        'type': 'ack',
        'request_id': 'req-1',
        'clientMsgId': 'client-1',
        'status': 422,
        'code': 'CONTENT_REJECTED',
        'retryable': false,
        'message': '内容未通过审核',
      });

      final failure = frame.ackFailure;

      expect(frame.ackClientMsgId, 'client-1');
      expect(frame.ackStatus, 422);
      expect(frame.ackMessageId, isNull);
      expect(failure, isNotNull);
      expect(failure!.clientMsgId, 'client-1');
      expect(failure.status, 422);
      expect(failure.code, 'CONTENT_REJECTED');
      expect(failure.retryable, isFalse);
      expect(failure.message, '内容未通过审核');
    });

    test('decodes payload-wrapped non-200 ACK as typed terminal failure', () {
      final frame = ProtocolFrame.fromJson({
        'type': 'ack',
        'request_id': 'req-2',
        'payload': {
          'client_msg_id': 'client-2',
          'status': '503',
          'code': 'MODERATION_UNAVAILABLE',
          'retryable': true,
          'msg': '内容审核服务暂不可用，请稍后重试',
        },
      });

      final failure = frame.ackFailure;

      expect(frame.ackClientMsgId, 'client-2');
      expect(frame.ackStatus, 503);
      expect(frame.ackMessageId, isNull);
      expect(failure, isNotNull);
      expect(failure!.clientMsgId, 'client-2');
      expect(failure.status, 503);
      expect(failure.code, 'MODERATION_UNAVAILABLE');
      expect(failure.retryable, isTrue);
      expect(failure.message, '内容审核服务暂不可用，请稍后重试');
    });

    test('keeps successful ACK out of failed settlement path', () {
      final frame = ProtocolFrame.fromJson({
        'type': 'ack',
        'payload': {
          'client_msg_id': 'client-ok',
          'status': 200,
          'message_id': 123,
        },
      });

      expect(frame.ackFailure, isNull);
      expect(frame.ackMessageId, 123);
    });
  });

  group('failed ACK settlement', () {
    late AppDatabase db;
    late OutboxManager outbox;
    late ReliableSender sender;
    late List<String> sent;
    late List<SendFailure> failures;

    setUp(() async {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
      outbox = OutboxManager(db);
      sent = <String>[];
      failures = <SendFailure>[];
      sender = ReliableSender(
        connection: ConnectionManager(
          url: 'ws://localhost/ws',
          onStateChange: (_) {},
          onFrameReceived: (_) {},
        ),
        outbox: outbox,
        onSent: sent.add,
        onFailed: failures.add,
        ackTimeout: const Duration(minutes: 1),
      );
      await outbox.insertPending(
        clientMsgId: 'client-terminal',
        payload: '{"content":"hello"}',
        timestamp: 1,
      );
    });

    tearDown(() async {
      sender.dispose();
      await db.close();
    });

    test('marks pending outbox row failed and invokes typed callback once',
        () async {
      const failure = SendFailure(
        clientMsgId: 'client-terminal',
        status: 422,
        code: 'CONTENT_REJECTED',
        retryable: false,
        message: '内容未通过审核',
      );

      await sender.onFailedAck(failure);
      await sender.onFailedAck(failure);

      final row = await db.customSelect(
        'SELECT status FROM outbox WHERE client_msg_id = ?',
        variables: [const Variable<String>('client-terminal')],
      ).getSingle();

      expect(row.read<String>('status'), 'failed');
      expect(await outbox.getPendingCount(), 0);
      expect(failures, hasLength(1));
      expect(failures.single, failure);

      await sender.resendPending();
      expect(await outbox.getPendingCount(), 0);
      expect(failures, hasLength(1));
    });

    test('ignores later success ACK after terminal failed ACK', () async {
      const failure = SendFailure(
        clientMsgId: 'client-terminal',
        status: 422,
        code: 'CONTENT_REJECTED',
        retryable: false,
        message: '内容未通过审核',
      );

      await sender.onFailedAck(failure);
      await sender.onAck('client-terminal');

      final row = await db.customSelect(
        'SELECT status FROM outbox WHERE client_msg_id = ?',
        variables: [const Variable<String>('client-terminal')],
      ).getSingle();

      expect(row.read<String>('status'), 'failed');
      expect(sent, isEmpty);
      expect(failures, hasLength(1));
    });
  });
}
