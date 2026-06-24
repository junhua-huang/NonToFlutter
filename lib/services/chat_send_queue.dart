import 'dart:async';
import 'dart:collection';

import 'package:nonto/models/message.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:flutter/foundation.dart';

/// 聊天消息发送队列 — 保序 / 断线暂存 / 重试管控
///
/// 不替代 ReliableSender（后者负责协议层 ACK/持久化/重发），
/// 而是在应用层保证同一会话消息严格串行发送，避免并发导致的乱序。
///
/// ```
/// ChatSendQueue（本类）  →  WebSocketService.sendMessage  →  ReliableSender（协议层 ACK）
///     排队 & 串行               发送                           ACK/重发/持久化
/// ```
class ChatSendQueue {
  final int conversationId;
  final int senderId;
  final WebSocketService _ws;

  /// 内存等待队列（FIFO）
  final Queue<_SendEntry> _waiting = Queue();

  /// 当前正在处理的任务
  _SendEntry? _current;

  /// 当前任务的 ACK 等待定时器
  Timer? _ackTimer;

  /// 是否正在串行处理
  bool _draining = false;

  bool _disposed = false;

  /// 业务回调：当乐观消息被服务端 ACK 确认为真实消息时触发
  void Function(int optimisticMsgId, Message serverMsg)? onAck;

  /// 业务回调：消息最终发送失败
  void Function(int optimisticMsgId, String reason)? onFailed;

  /// 缓冲早到的协议 ACK — 当 handleProtocolAck 在 _processNext 设置
  /// msg.clientMsgId 之前被调用时，暂存于此，待 clientMsgId 设置后消费。
  final Map<String, int> _earlyAcks = {};

  // ── 配置 ──

  static const int maxRetries = 3;
  static const Duration ackTimeout = Duration(seconds: 15);
  static const Duration retryBaseDelay = Duration(seconds: 2);

  ChatSendQueue({
    required this.conversationId,
    required this.senderId,
    WebSocketService? ws,
  }) : _ws = ws ?? WebSocketService() {
    _ws.connectionStream.listen((connected) {
      if (connected &&
          !_draining &&
          (_waiting.isNotEmpty || _current != null)) {
        debugPrint(
            '[SendQ] WS reconnected, wait 2s for sync then drain ${_waiting.length + (_current != null ? 1 : 0)} pending');
        // 延迟 2s 让 sync 先走完，避免阻塞服务端消息循环
        Future.delayed(const Duration(seconds: 2), () {
          if (!_disposed &&
              !_draining &&
              (_waiting.isNotEmpty || _current != null)) {
            _drain();
          }
        });
      }
    });
  }

  /// 入队一条消息
  void enqueue(Message msg) {
    if (_disposed) return;
    _waiting.add(_SendEntry(msg, DateTime.now()));
    debugPrint(
        '[SendQ] enqueue msgId=${msg.id}, depth=${_waiting.length + (_current != null ? 1 : 0)}');
    if (!_draining) _drain();
  }

  /// 从本地 DB 加载「发送中」的消息重建队列
  Future<void> rebuildFromDb(List<Message> pendingMessages) async {
    if (pendingMessages.isEmpty) return;
    for (final msg in pendingMessages) {
      _waiting.add(_SendEntry(msg, msg.createdAt ?? DateTime.now()));
    }
    debugPrint('[SendQ] rebuilt ${pendingMessages.length} msgs from DB');
    if (!_draining) _drain();
  }

  /// 收到服务端回显 → 匹配并移除乐观消息
  /// 返回 true 表示匹配到了队列中的消息
  bool handleAck(Message serverMsg) {
    // 检查当前任务
    if (_current != null && _matches(_current!.message, serverMsg)) {
      debugPrint(
          '[SendQ] ACK current msgId=${_current!.message.id} → serverId=${serverMsg.id}');
      _completeCurrent(serverMsg);
      return true;
    }
    // 检查等待队列
    for (final entry in _waiting) {
      if (_matches(entry.message, serverMsg)) {
        debugPrint(
            '[SendQ] ACK waiting msgId=${entry.message.id} → serverId=${serverMsg.id}');
        _waiting.remove(entry);
        onAck?.call(entry.message.id, serverMsg.copyWith(status: 'sent'));
        return true;
      }
    }
    return false;
  }

  /// 收到协议层 ACK（服务端只返回 message_id，不回推完整 new_message 给发送者）
  /// 返回 true 表示匹配到了队列中的消息。
  /// 如果 clientMsgId 尚未设置（ACK 早于 _processNext 赋值），暂存到 _earlyAcks。
  bool handleProtocolAck(String clientMsgId, int messageId) {
    if (_current != null && _current!.message.clientMsgId == clientMsgId) {
      final msg = _current!.message;
      final serverMsg = msg.copyWith(
        id: messageId,
        clientMsgId: clientMsgId,
        status: 'sent',
      );
      debugPrint(
          '[SendQ] protocol ACK current msgId=${msg.id} → serverId=$messageId');
      _completeCurrent(serverMsg);
      return true;
    }

    for (final entry in _waiting) {
      if (entry.message.clientMsgId == clientMsgId) {
        final msg = entry.message;
        final serverMsg = msg.copyWith(
          id: messageId,
          clientMsgId: clientMsgId,
          status: 'sent',
        );
        debugPrint(
            '[SendQ] protocol ACK waiting msgId=${msg.id} → serverId=$messageId');
        _waiting.remove(entry);
        onAck?.call(msg.id, serverMsg);
        return true;
      }
    }

    // 当前消息的 clientMsgId 可能还未设置（ACK 在 _processNext 的 await 期间到达），
    // 暂存到 _earlyAcks，等 _processNext 设置 clientMsgId 后消费。
    if (_current != null && _current!.message.clientMsgId == null) {
      debugPrint(
          '[SendQ] early ACK buffered clientMsgId=$clientMsgId messageId=$messageId');
      _earlyAcks[clientMsgId] = messageId;
      return true; // 标记已处理，防止上层走 fallback 重复更新
    }

    return false;
  }

  /// 检查 _earlyAcks 中是否有匹配当前消息的早到 ACK，如有则消费
  void _consumeEarlyAck(_SendEntry entry) {
    final clientMsgId = entry.message.clientMsgId;
    if (clientMsgId == null) return;
    final messageId = _earlyAcks.remove(clientMsgId);
    if (messageId != null) {
      debugPrint(
          '[SendQ] consuming early ACK clientMsgId=$clientMsgId → serverId=$messageId');
      final serverMsg = entry.message.copyWith(
        id: messageId,
        clientMsgId: clientMsgId,
        status: 'sent',
      );
      _completeCurrent(serverMsg);
    }
  }

  /// 收到服务端 error 帧 → 匹配 clientMsgId 并立即标记失败
  /// 返回 true 表示匹配到了队列中的消息
  bool handleSendError(String clientMsgId, String error) {
    if (_current != null && _current!.message.clientMsgId == clientMsgId) {
      debugPrint(
          '[SendQ] server error for current msgId=${_current!.message.id}: $error');
      _failCurrent(error);
      return true;
    }

    for (final entry in _waiting) {
      if (entry.message.clientMsgId == clientMsgId) {
        debugPrint(
            '[SendQ] server error for waiting msgId=${entry.message.id}: $error');
        _waiting.remove(entry);
        final msg = entry.message;
        msg.status = 'failed';
        DataLayer().persistMessage(msg).catchError((_) {});
        onFailed?.call(msg.id, '发送失败：$error');
        return true;
      }
    }
    return false;
  }

  /// 将当前消息标记为失败并继续下一条
  void _failCurrent(String reason) {
    _ackTimer?.cancel();
    _ackTimer = null;
    final msg = _current!.message;
    msg.status = 'failed';
    DataLayer().persistMessage(msg).catchError((_) {});
    onFailed?.call(msg.id, '发送失败：$reason');
    _current = null;
    _draining = false; // 重置门闩，否则后续 _drain() 会被 if(_draining) 挡住
    _drain();
  }

  void _completeCurrent(Message serverMsg) {
    _ackTimer?.cancel();
    _ackTimer = null;
    onAck?.call(_current!.message.id, serverMsg.copyWith(status: 'sent'));
    _current = null;
    _draining = false; // 重置门闩，否则后续 _drain() 会被 if(_draining) 挡住
    _drain();
  }

  /// 匹配乐观消息与服务器回显
  bool _matches(Message optimistic, Message server) {
    if (optimistic.clientMsgId != null &&
        optimistic.clientMsgId == server.clientMsgId) {
      return true;
    }
    if (optimistic.requestId != null &&
        optimistic.requestId == server.requestId) {
      return true;
    }
    if (optimistic.id > 1000000000000 &&
        optimistic.senderId == server.senderId &&
        optimistic.content == server.content) {
      return true;
    }
    return false;
  }

  int get pendingCount => _waiting.length + (_current != null ? 1 : 0);

  // ═══════════════════════════════════════════════════════════
  // 串行发送引擎
  // ═══════════════════════════════════════════════════════════

  void _drain() {
    if (_disposed || _draining) return;
    _draining = true;
    _processNext();
  }

  Future<void> _processNext() async {
    while (!_disposed) {
      // 取下一个
      if (_current == null) {
        if (_waiting.isEmpty) {
          _draining = false;
          debugPrint('[SendQ] queue empty, done');
          return;
        }
        _current = _waiting.removeFirst();
      }

      // WS 断线 → 暂停，不把消息标失败；重连后继续 drain。
      if (!_ws.isConnected) {
        debugPrint(
            '[SendQ] WS disconnected, pause (${_waiting.length + 1} pending)');
        _draining = false;
        return;
      }

      // 发送
      final entry = _current!;
      final msg = entry.message;
      debugPrint(
          '[SendQ] → send msgId=${msg.id} retry=${entry.retries}/$maxRetries');

      try {
        final clientMsgId = await _ws
            .sendMessage(
              conversationId,
              msg.content ?? '',
              messageType: msg.messageType.name,
              mediaUrl: msg.mediaUrl,
              relatedId: msg.relatedId,
              quoteMessageId: msg.quoteMessageId,
              quotePreview: msg.quotePreview,
            )
            .timeout(ackTimeout);
        if (clientMsgId.isEmpty) {
          // WebSocketService 在断线/未认证时会返回空 ID。不要启动 ACK 计时器，
          // 保持 current，等待重连后继续发送，避免消息卡在 loading 或误判失败。
          debugPrint(
              '[SendQ] send skipped because WS not ready, pause msgId=${msg.id}');
          _draining = false;
          return;
        }
        msg.clientMsgId = clientMsgId;
        await DataLayer().persistMessage(msg);
        onAck?.call(
            msg.id, msg.copyWith(clientMsgId: clientMsgId, status: 'sending'));

        // 检查是否有早到的 ACK 在 clientMsgId 设置前就已缓存
        _consumeEarlyAck(entry);
        if (_current == null) {
          // 早到 ACK 已经完成当前消息，继续下一条
          return;
        }

        // 启动 ACK 等待定时器
        _startAckTimer(entry);
        return; // 等待 ACK 或超时来推进
      } catch (e) {
        debugPrint('[SendQ] send error msgId=${msg.id}: $e');
        _ackTimer?.cancel();
        _ackTimer = null;
        await _retryOrFail(entry);
      }
    }
  }

  void _startAckTimer(_SendEntry entry) {
    _ackTimer?.cancel();
    _ackTimer = Timer(ackTimeout, () {
      // ReliableSender owns protocol retransmission and must keep the same
      // clientMsgId. Do not call _ws.sendMessage() again from this queue timer,
      // otherwise the same logical message can be resent with a new clientMsgId.
      debugPrint(
          '[SendQ] still waiting for ReliableSender ACK msgId=${entry.message.id}');
    });
  }

  Future<void> _retryOrFail(_SendEntry entry) async {
    if (_disposed) return;
    if (!_ws.isConnected) {
      debugPrint(
          '[SendQ] retry paused because WS disconnected msgId=${entry.message.id}');
      _draining = false;
      return;
    }
    if (entry.retries < maxRetries) {
      entry.retries++;
      final delay = Duration(
          seconds: retryBaseDelay.inSeconds * (1 << (entry.retries - 1)));
      debugPrint(
          '[SendQ] retry msgId=${entry.message.id} in ${delay.inSeconds}s');
      await Future.delayed(delay);
      if (_disposed) return;
      // _current 不变，继续循环
      _processNext();
    } else {
      debugPrint('[SendQ] msgId=${entry.message.id} FAILED');
      final msg = entry.message;
      msg.status = 'failed';
      try {
        await DataLayer().persistMessage(msg);
      } catch (_) {}
      onFailed?.call(msg.id, '发送失败：已达最大重试次数');
      _current = null;
      _processNext();
    }
  }

  void dispose() {
    _disposed = true;
    _ackTimer?.cancel();
    _ackTimer = null;
    _waiting.clear();
    _current = null;
    _draining = false;
  }
}

class _SendEntry {
  final Message message;
  final DateTime enqueuedAt;
  int retries = 0;

  _SendEntry(this.message, this.enqueuedAt);
}
