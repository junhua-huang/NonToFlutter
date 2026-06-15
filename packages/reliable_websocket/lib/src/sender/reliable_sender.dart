/// 可靠发送模块
///
/// 为业务消息生成唯一 ID，写入发件箱，启动 ACK 超时计时器，
/// 处理重传和确认。
library;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../connection/connection_manager.dart';
import '../outbox/outbox_manager.dart';
import '../protocol/codec.dart';

/// 发送结果
enum SendResult {
  /// 发送成功（已收到 ACK）
  success,

  /// 发送失败（超过最大重试次数或存储满）
  failure,
}

/// 发送成功回调
typedef OnMessageSent = void Function(String clientMsgId);

/// 发送失败回调
typedef OnMessageFailed = void Function(String clientMsgId, String error);

/// 可靠发送器
///
/// 负责消息的可靠发送：生成 ID → 写入发件箱 → 发送 → 等待 ACK → 重试。
class ReliableSender {
  final ConnectionManager _connection;
  final OutboxManager _outbox;
  final OnMessageSent? _onSent;
  final OnMessageFailed? _onFailed;

  final Logger _log = Logger('ReliableSender');

  /// ACK 超时时间
  final Duration ackTimeout;

  /// 最大重试次数
  final int maxRetries;

  /// 发件箱最大容量
  final int maxOutboxSize;

  static const _uuid = Uuid();

  /// 活跃的 ACK 计时器：clientMsgId → Timer
  final Map<String, Timer> _ackTimers = {};

  ReliableSender({
    required ConnectionManager connection,
    required OutboxManager outbox,
    OnMessageSent? onSent,
    OnMessageFailed? onFailed,
    this.ackTimeout = const Duration(seconds: 15),
    this.maxRetries = 3,
    this.maxOutboxSize = 1000,
  })  : _connection = connection,
        _outbox = outbox,
        _onSent = onSent,
        _onFailed = onFailed;

  /// 发送业务消息
  ///
  /// 生成 clientMsgId → 写入发件箱 → 发送帧 → 启动 ACK 计时器。
  /// 返回 clientMsgId，业务层可用于追踪。
  Future<String> send(Map<String, dynamic> payload) async {
    // 检查发件箱容量
    final count = await _outbox.getPendingCount();
    if (count >= maxOutboxSize) {
      const error = 'Outbox full, rejected';
      _log.warning(error);
      throw StateError(error);
    }

    final clientMsgId = _uuid.v4();
    final payloadJson = jsonEncode(payload);

    // 写入发件箱
    await _outbox.insertPending(
      clientMsgId: clientMsgId,
      payload: payloadJson,
    );

    // 发送帧
    _sendFrame(clientMsgId, payload);

    // 启动 ACK 计时器
    _startAckTimer(clientMsgId, payloadJson, 0);

    return clientMsgId;
  }

  /// 发送 WebSocket 帧
  void _sendFrame(String clientMsgId, Map<String, dynamic> payload) {
    if (_connection.isConnected) {
      final frame = ProtocolCodec.sendMessage(clientMsgId, payload);
      _connection.sendFrame(frame);
      _log.fine('Sent: $clientMsgId');
    }
    // 如果未连接，消息已在发件箱中，重连后统一重发
  }

  /// 启动 ACK 超时计时器
  void _startAckTimer(
    String clientMsgId,
    String payloadJson,
    int retryCount,
  ) {
    _ackTimers[clientMsgId]?.cancel();
    _ackTimers[clientMsgId] = Timer(ackTimeout, () async {
      await _onAckTimeout(clientMsgId, payloadJson, retryCount);
    });
  }

  /// ACK 超时处理
  Future<void> _onAckTimeout(
    String clientMsgId,
    String payloadJson,
    int previousRetry,
  ) async {
    // 检查连接状态
    if (!_connection.isConnected) {
      _log.info('ACK timeout for $clientMsgId but not connected, will retry on reconnect');
      return;
    }

    // 获取当前重试计数
    final currentRetry = await _outbox.getRetryCount(clientMsgId);

    if (currentRetry >= maxRetries) {
      // 超过最大重试，标记失败
      await _outbox.markFailed(clientMsgId);
      _ackTimers.remove(clientMsgId);
      _log.warning('Max retries exceeded: $clientMsgId');
      _onFailed?.call(clientMsgId, 'Max retries exceeded');
      return;
    }

    // 增加重试计数
    final newCount = await _outbox.incrementRetry(clientMsgId);
    _log.info('Retry $clientMsgId (attempt $newCount)');

    // 重新发送
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    _sendFrame(clientMsgId, payload);

    // 重启计时器
    _startAckTimer(clientMsgId, payloadJson, newCount);
  }

  /// 收到 ACK 确认
  Future<void> onAck(String clientMsgId) async {
    _ackTimers[clientMsgId]?.cancel();
    _ackTimers.remove(clientMsgId);

    await _outbox.markAcked(clientMsgId);
    _log.fine('Acked: $clientMsgId');
    _onSent?.call(clientMsgId);
  }

  /// 重连后重发所有 pending 消息
  Future<void> resendPending() async {
    if (!_connection.isConnected) return;

    final pending = await _outbox.getPendingMessages();
    if (pending.isEmpty) return;

    _log.info('Resending ${pending.length} pending messages');

    for (final item in pending) {
      if (item.retryCount >= maxRetries) {
        await _outbox.markFailed(item.clientMsgId);
        _onFailed?.call(item.clientMsgId, 'Max retries exceeded on reconnect');
        continue;
      }

      final payload = jsonDecode(item.payload) as Map<String, dynamic>;
      _sendFrame(item.clientMsgId, payload);
      _startAckTimer(item.clientMsgId, item.payload, item.retryCount);
    }
  }

  /// 取消所有 ACK 计时器（断开连接时调用）
  void cancelAllTimers() {
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    _ackTimers.clear();
  }

  /// 释放资源
  void dispose() {
    cancelAllTimers();
  }
}
