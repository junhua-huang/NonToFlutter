/// Drift 数据库定义
///
/// 跨平台数据库支持：移动端/桌面端使用 NativeDatabase，Web 端使用 WebDatabase。
/// dart:io / drift/native.dart 仅在 database_io.dart（native）中导入，
/// database_web.dart（web）不引入这些依赖，保证 Web 编译通过。
library;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'tables.dart';

// 条件导入：Web 平台加载 database_web.dart（drift/web.dart），
// Native 平台加载 database_io.dart（drift/native.dart）。
import 'database_io.dart'
    if (dart.library.js_interop) 'database_web.dart';

part 'database.g.dart';

/// 应用数据库
@DriftDatabase(tables: [Outbox, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    if (kIsWeb) {
      return LazyDatabase(() => openWebDatabase('websocket_cache'));
    }
    return openNativeDatabase('ws_cache');
  }

  // ========== 发件箱操作 ==========

  /// 插入一条 pending 消息
  Future<void> insertPending({
    required String clientMsgId,
    required String payload,
    required int timestamp,
  }) {
    return customStatement(
      'INSERT OR IGNORE INTO outbox '
      '(client_msg_id, payload, timestamp, retry_count, status) '
      'VALUES (?, ?, ?, 0, \'pending\')',
      [clientMsgId, payload, timestamp],
    );
  }

  /// 查询所有 pending 消息（按时间升序）
  Future<List<QueryRow>> getPendingMessages() {
    return customSelect(
      'SELECT * FROM outbox WHERE status = ? ORDER BY timestamp ASC',
      variables: [const Variable<String>('pending')],
    ).get();
  }

  /// 查询 pending 消息数量
  Future<int> getPendingCount() async {
    final rows = await customSelect(
      'SELECT COUNT(*) AS cnt FROM outbox WHERE status = ?',
      variables: [const Variable<String>('pending')],
    ).get();
    return rows.first.read<int>('cnt');
  }

  /// 将消息状态更新为 acked
  Future<void> ackMessage(String clientMsgId) {
    return customStatement(
      'UPDATE outbox SET status = \'acked\' WHERE client_msg_id = ?',
      [clientMsgId],
    );
  }

  /// 删除 acked 消息
  Future<void> deleteAckedMessage(String clientMsgId) {
    return customStatement(
      'DELETE FROM outbox WHERE client_msg_id = ? AND status = \'acked\'',
      [clientMsgId],
    );
  }

  /// 增加重试计数
  Future<void> incrementRetry(String clientMsgId) {
    return customStatement(
      'UPDATE outbox SET retry_count = retry_count + 1 WHERE client_msg_id = ?',
      [clientMsgId],
    );
  }

  /// 标记消息为 failed
  Future<void> markFailed(String clientMsgId) {
    return customStatement(
      'UPDATE outbox SET status = \'failed\' WHERE client_msg_id = ?',
      [clientMsgId],
    );
  }

  /// 获取某条消息的重试计数
  Future<int> getRetryCount(String clientMsgId) async {
    final rows = await customSelect(
      'SELECT retry_count FROM outbox WHERE client_msg_id = ?',
      variables: [Variable<String>(clientMsgId)],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('retry_count');
  }

  /// 清理已确认的消息
  Future<void> cleanAckedMessages() {
    return customStatement(
      'DELETE FROM outbox WHERE status = \'acked\'',
      [],
    );
  }

  /// 清理失败的消息
  Future<void> cleanFailedMessages() {
    return customStatement(
      'DELETE FROM outbox WHERE status = \'failed\'',
      [],
    );
  }

  // ========== 同步状态操作 ==========

  /// 读取 last_received_seq
  Future<int> getLastReceivedSeq() async {
    final rows = await customSelect(
      'SELECT last_received_seq FROM sync_state WHERE id = 1',
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('last_received_seq');
  }

  /// 更新 last_received_seq（仅当新值 > 当前值）
  Future<void> updateLastReceivedSeq(int newSeq) {
    return customStatement(
      'INSERT INTO sync_state (id, last_received_seq) VALUES (1, ?) '
      'ON CONFLICT(id) DO UPDATE SET last_received_seq = ? '
      'WHERE last_received_seq < ?',
      [newSeq, newSeq, newSeq],
    );
  }

  /// 更新同步时间
  Future<void> updateLastSyncTime(int timestamp) {
    return customStatement(
      'INSERT INTO sync_state (id, last_received_seq, last_sync_time) VALUES (1, 0, ?) '
      'ON CONFLICT(id) DO UPDATE SET last_sync_time = ?',
      [timestamp, timestamp],
    );
  }
}
