/// 同步恢复模块
///
/// 连接重建后，从 Drift 读取最后序号，发起 sync 请求补发离线消息，
/// 并重发发件箱中未确认消息。
library;

import 'dart:async';

import 'package:logging/logging.dart';

import '../connection/connection_manager.dart';
import '../database/database.dart';
import '../protocol/codec.dart';
import '../protocol/message.dart';
import '../receiver/reliable_receiver.dart';
import '../sender/reliable_sender.dart';

/// 同步恢复结果
enum SyncResult {
  /// 同步成功
  success,

  /// 同步失败（补发请求超时）
  failure,
}

/// 同步完成回调
typedef OnSyncComplete = void Function(SyncResult result);

/// 同步恢复管理器
///
/// 重连认证成功后自动执行：序号同步 + 发件箱重发。
class SyncRecovery {
  final ConnectionManager _connection;
  final AppDatabase _db;
  ReliableReceiver? _receiver;
  final ReliableSender _sender;

  final OnSyncComplete? _onSyncComplete;

  final Logger _log = Logger('SyncRecovery');

  /// 补发请求超时
  final Duration syncTimeout;

  /// 补发请求最大重试次数
  final int syncMaxRetries;

  /// 待处理的 sync_result Completer
  Completer<List<ProtocolFrame>>? _syncCompleter;

  SyncRecovery({
    required ConnectionManager connection,
    required AppDatabase db,
    ReliableReceiver? receiver,
    required ReliableSender sender,
    OnSyncComplete? onSyncComplete,
    this.syncTimeout = const Duration(seconds: 30),
    this.syncMaxRetries = 3,
  })  : _connection = connection,
        _db = db,
        _receiver = receiver,
        _sender = sender,
        _onSyncComplete = onSyncComplete;

  /// 设置接收器（解决循环依赖）
  void setReceiver(ReliableReceiver receiver) {
    _receiver = receiver;
  }

  /// 执行同步恢复
  ///
  /// 1. 序号同步：发送 sync 请求补发离线消息
  /// 2. 发件箱重发：重发所有 pending 消息
  Future<void> recover() async {
    _log.info('Starting sync recovery');

    try {
      // Step 1: 序号同步
      await _syncSequence();

      // Step 2: 发件箱重发
      await _sender.resendPending();

      // 更新同步时间
      await _db.updateLastSyncTime(
        DateTime.now().millisecondsSinceEpoch,
      );

      _log.info('Sync recovery complete');
      _onSyncComplete?.call(SyncResult.success);
    } catch (e, stack) {
      _log.severe('Sync recovery failed', e, stack);
      _onSyncComplete?.call(SyncResult.failure);
    }
  }

  /// 序号同步：请求补发丢失的消息
  Future<void> _syncSequence() async {
    final receiver = _receiver;
    if (receiver == null) {
      _log.warning('Receiver not set, skipping seq sync');
      return;
    }
    final lastSeq = receiver.lastReceivedSeq;
    _log.info('Requesting sync from seq=${lastSeq + 1}');

    final messages = await _requestSyncWithRetry(lastSeq + 1);

    if (messages.isNotEmpty) {
      await receiver.onSyncMessages(messages);
    } else {
      _log.info('No missing messages');
    }
  }

  /// 带重试的 sync 请求
  Future<List<ProtocolFrame>> _requestSyncWithRetry(int fromSeq) async {
    for (int attempt = 0; attempt < syncMaxRetries; attempt++) {
      try {
        final messages = await _doSyncRequest(fromSeq);
        return messages;
      } catch (e) {
        _log.warning('Sync attempt ${attempt + 1} failed: $e');
        if (attempt == syncMaxRetries - 1) rethrow;
        // 等待短暂间隔再重试
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return [];
  }

  /// 发送 sync 请求并等待 sync_result
  Future<List<ProtocolFrame>> _doSyncRequest(int fromSeq) {
    final completer = Completer<List<ProtocolFrame>>();
    _syncCompleter = completer;

    // 发送 sync 帧
    final frame = ProtocolCodec.sync(fromSeq);
    _connection.sendFrame(frame);

    // 超时处理
    return completer.future.timeout(syncTimeout, onTimeout: () {
      _syncCompleter = null;
      throw TimeoutException('Sync request timed out');
    });
  }

  /// 收到 sync_result 时调用
  void onSyncResult(List<ProtocolFrame> messages) {
    _syncCompleter?.complete(messages);
    _syncCompleter = null;
  }

  /// 发送 sync 请求（供 ReliableReceiver 乱序补发调用）
  Future<List<ProtocolFrame>> requestSync(int fromSeq) {
    return _requestSyncWithRetry(fromSeq);
  }

  /// 释放资源
  void dispose() {
    _syncCompleter?.complete([]);
    _syncCompleter = null;
  }
}
