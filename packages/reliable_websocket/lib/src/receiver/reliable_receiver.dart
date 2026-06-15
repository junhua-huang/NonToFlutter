/// 可靠接收模块
///
/// 维护本地序号状态，检测乱序，请求补发，按顺序交付业务层。
library;

import 'dart:async';

import 'package:logging/logging.dart';

import '../database/database.dart';
import '../protocol/message.dart';

/// 消息到达回调（按序）
typedef OnMessageDelivered = void Function(Map<String, dynamic> payload, int seq);

/// 可靠接收器
class ReliableReceiver {
  final AppDatabase _db;
  final OnMessageDelivered _onMessage;

  /// 请求补发的回调（由上层注入，连接模块发送 sync 帧）
  final Future<List<ProtocolFrame>> Function(int fromSeq) _requestSync;

  final Logger _log = Logger('ReliableReceiver');

  /// 当前已交付给业务层的最大序号
  int _lastReceivedSeq = 0;

  /// 乱序缓冲：seq → ProtocolFrame
  final Map<int, ProtocolFrame> _pendingSeqMap = {};

  /// 乱序超时计时器
  Timer? _outOfOrderTimer;

  /// 乱序超时
  final Duration outOfOrderTimeout;

  /// 最大乱序缓冲数
  final int maxPendingCount;

  ReliableReceiver({
    required AppDatabase db,
    required OnMessageDelivered onMessage,
    required Future<List<ProtocolFrame>> Function(int fromSeq) requestSync,
    this.outOfOrderTimeout = const Duration(seconds: 5),
    this.maxPendingCount = 500,
  })  : _db = db,
        _onMessage = onMessage,
        _requestSync = requestSync;

  /// 当前已交付的最大序号
  int get lastReceivedSeq => _lastReceivedSeq;

  /// 从数据库加载初始序号
  Future<void> loadState() async {
    _lastReceivedSeq = await _db.getLastReceivedSeq();
    _log.info('Loaded lastReceivedSeq = $_lastReceivedSeq');
  }

  /// 处理收到的消息帧
  Future<void> onMessage(ProtocolFrame frame) async {
    final seq = frame.seq;
    if (seq == null) {
      _log.warning('Received message without seq');
      return;
    }

    _log.fine('Received message seq=$seq');

    if (seq <= _lastReceivedSeq) {
      // 重复消息，丢弃
      _log.fine('Duplicate message seq=$seq (last=$_lastReceivedSeq), dropped');
      return;
    }

    if (seq == _lastReceivedSeq + 1) {
      // 正常按序到达
      _deliver(frame);
    } else if (seq > _lastReceivedSeq + 1) {
      // 乱序到达：sync 可能返回空跳过了历史，直接跳到 seq
      // 不放入缓冲等待，因为那些"缺失"的序号可能已被清理
      _log.warning('Out of order: expected ${_lastReceivedSeq + 1}, got $seq, jumping');
      _lastReceivedSeq = seq - 1;
      _db.updateLastReceivedSeq(_lastReceivedSeq);
      _deliver(frame);
    }
  }

  /// 交付消息给业务层
  void _deliver(ProtocolFrame frame) {
    final payload = frame.payload;
    final seq = frame.seq!;

    if (payload != null) {
      _onMessage(payload, seq);
    }

    _lastReceivedSeq = seq;

    // 持久化序号
    _db.updateLastReceivedSeq(_lastReceivedSeq);

    // 检查乱序缓冲中是否有下一序号的消息
    _drainPending();
  }

  /// 消费乱序缓冲中的连续消息
  void _drainPending() {
    while (true) {
      final nextSeq = _lastReceivedSeq + 1;
      final frame = _pendingSeqMap.remove(nextSeq);
      if (frame == null) break;

      _log.fine('Delivering buffered message seq=$nextSeq');
      final payload = frame.payload;
      if (payload != null) {
        _onMessage(payload, nextSeq);
      }
      _lastReceivedSeq = nextSeq;
      _db.updateLastReceivedSeq(_lastReceivedSeq);
    }
  }

  /// 请求补发缺失消息
  Future<void> _requestMissing() async {
    final fromSeq = _lastReceivedSeq + 1;
    _log.info('Requesting missing messages from seq=$fromSeq');

    try {
      final messages = await _requestSync(fromSeq);

      // 按序号升序排序
      messages.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));

      // 重新投喂给接收逻辑
      for (final msg in messages) {
        final seq = msg.seq;
        if (seq != null && seq > _lastReceivedSeq) {
          if (seq == _lastReceivedSeq + 1) {
            _deliver(msg);
          } else {
            _pendingSeqMap[seq] = msg;
          }
        }
      }

      // 再次尝试消费缓冲
      _drainPending();
    } catch (e) {
      _log.warning('Failed to request missing messages: $e');
    }
  }

  /// 处理批量补发消息（sync_result）
  Future<void> onSyncMessages(List<ProtocolFrame> messages) async {
    if (messages.isEmpty) return;

    _log.info('Processing ${messages.length} sync messages');

    // 清空已有乱序缓冲（新消息覆盖）
    _pendingSeqMap.clear();

    // 按序号升序排序
    messages.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));

    // 逐个处理
    for (final msg in messages) {
      final seq = msg.seq;
      if (seq == null) continue;

      if (seq <= _lastReceivedSeq) continue; // 重复

      if (seq == _lastReceivedSeq + 1) {
        _deliver(msg);
      } else {
        _pendingSeqMap[seq] = msg;
      }
    }

    // 消费缓冲中的连续消息
    _drainPending();
  }

  /// 释放资源
  void dispose() {
    _outOfOrderTimer?.cancel();
    _outOfOrderTimer = null;
    _pendingSeqMap.clear();
  }
}
