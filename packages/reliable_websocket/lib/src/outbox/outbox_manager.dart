/// 发件箱管理器
///
/// 封装 Drift 发件箱的 CRUD 操作，提供事务支持。
library;

import 'package:logging/logging.dart';

import '../database/database.dart';

/// 发件箱状态
enum OutboxStatus {
  pending,
  acked,
  failed,
}

/// 发件箱条目
class OutboxItem {
  final String clientMsgId;
  final String payload;
  final int timestamp;
  final int retryCount;
  final OutboxStatus status;

  const OutboxItem({
    required this.clientMsgId,
    required this.payload,
    required this.timestamp,
    required this.retryCount,
    required this.status,
  });

  factory OutboxItem.fromMap(Map<String, Object?> map) => OutboxItem(
        clientMsgId: map['client_msg_id'] as String,
        payload: map['payload'] as String,
        timestamp: map['timestamp'] as int,
        retryCount: map['retry_count'] as int? ?? 0,
        status: OutboxStatus.values.firstWhere(
          (s) => s.name == (map['status'] as String),
          orElse: () => OutboxStatus.pending,
        ),
      );
}

/// 发件箱管理器
///
/// 管理客户端已发送但未确认消息的持久化存储。
class OutboxManager {
  final AppDatabase _db;
  final Logger _log = Logger('OutboxManager');

  OutboxManager(this._db);

  /// 插入一条待发送消息（状态 = pending）
  Future<void> insertPending({
    required String clientMsgId,
    required String payload,
    int? timestamp,
  }) async {
    await _db.insertPending(
      clientMsgId: clientMsgId,
      payload: payload,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );
    _log.fine('Inserted pending: $clientMsgId');
  }

  /// 获取所有 pending 消息（按时间升序，用于重连重发）
  Future<List<OutboxItem>> getPendingMessages() async {
    final rows = await _db.getPendingMessages();
    return rows
        .map((r) => OutboxItem(
            clientMsgId: r.read<String>('client_msg_id'),
            payload: r.read<String>('payload'),
            timestamp: r.read<int>('timestamp'),
            retryCount: r.read<int>('retry_count'),
            status: _parseStatus(r.read<String>('status')),
            ))
        .toList();
  }

  static OutboxStatus _parseStatus(String s) {
    return OutboxStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => OutboxStatus.pending,
    );
  }

  /// 获取 pending 消息数量（用于堆积检测）
  Future<int> getPendingCount() async {
    return _db.getPendingCount();
  }

  /// 标记消息为已确认（收到 ACK）
  Future<void> markAcked(String clientMsgId) async {
    await _db.ackMessage(clientMsgId);
    _log.fine('Marked acked: $clientMsgId');
    // 立即删除，节省空间
    await _db.deleteAckedMessage(clientMsgId);
  }

  /// 增加重试计数，返回新的计数值
  Future<int> incrementRetry(String clientMsgId) async {
    await _db.incrementRetry(clientMsgId);
    return _db.getRetryCount(clientMsgId);
  }

  /// 标记消息为发送失败（超最大重试次数）
  Future<void> markFailed(String clientMsgId) async {
    await _db.markFailed(clientMsgId);
    _log.warning('Marked failed: $clientMsgId');
  }

  /// 获取消息的重试计数
  Future<int> getRetryCount(String clientMsgId) async {
    return _db.getRetryCount(clientMsgId);
  }

  /// 清理已确认的消息
  Future<void> cleanAcked() => _db.cleanAckedMessages();

  /// 清理失败的消息
  Future<void> cleanFailed() => _db.cleanFailedMessages();
}
