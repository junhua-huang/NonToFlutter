import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/message.dart';

void main() {
  test('Drift schema declares the sole v1 to v2 failure metadata migration',
      () {
    final source =
        File('lib/services/database/app_database.dart').readAsStringSync();
    final generated =
        File('lib/services/database/app_database.g.dart').readAsStringSync();

    expect(source, contains('int get schemaVersion => 2;'));
    expect(source, contains('if (from < 2)'));
    expect(
        source,
        contains(
            'await m.addColumn(messagesTable, messagesTable.failureCode);'));
    expect(
        source,
        contains(
            'await m.addColumn(messagesTable, messagesTable.failureMessage);'));
    expect(source,
        contains('await m.addColumn(messagesTable, messagesTable.retryable);'));
    expect(source,
        contains("await _writeMeta(metaKeySchemaVersion, to.toString())"));

    final localDbSource =
        File('lib/services/local_db_service.dart').readAsStringSync();
    expect(localDbSource, contains('failureCode: Value(msg.failureCode)'));
    expect(
        localDbSource, contains('failureMessage: Value(msg.failureMessage)'));
    expect(localDbSource, contains('retryable: Value(msg.retryable)'));
    expect(localDbSource, contains('failureCode: row.failureCode'));
    expect(localDbSource, contains('failureMessage: row.failureMessage'));
    expect(localDbSource, contains('retryable: row.retryable'));

    expect(generated, contains("'failure_code'"));
    expect(generated, contains("'failure_message'"));
    expect(generated, contains("'retryable'"));
    expect(generated, contains('Value<String?> failureCode'));
    expect(generated, contains('Value<String?> failureMessage'));
    expect(generated, contains('Value<bool?> retryable'));
  });

  test('message failure metadata survives JSON round trip', () {
    final message = Message(
      id: 1000000000001,
      conversationId: 2,
      senderId: 3,
      content: 'blocked',
      status: 'failed',
      failureCode: 'CONTENT_REJECTED',
      failureMessage: '内容未通过审核',
      retryable: false,
    );

    final restored = Message.fromJson(message.toJson());

    expect(restored.failureCode, 'CONTENT_REJECTED');
    expect(restored.failureMessage, '内容未通过审核');
    expect(restored.retryable, isFalse);
    expect(restored.canRetry, isFalse);
  });

  test(
      'retryable moderation failures remain manually retryable after JSON parsing',
      () {
    final restored = Message.fromJson({
      'id': 1000000000002,
      'conversation_id': 2,
      'sender_id': 3,
      'content': 'retry later',
      'status': 'failed',
      'failure_code': 'MODERATION_UNAVAILABLE',
      'failure_message': '内容审核服务暂不可用，请稍后重试',
      'retryable': 1,
    });

    expect(restored.failureCode, 'MODERATION_UNAVAILABLE');
    expect(restored.failureMessage, '内容审核服务暂不可用，请稍后重试');
    expect(restored.retryable, isTrue);
    expect(restored.canRetry, isTrue);
  });
}
