/// 可靠 WebSocket 客户端
///
/// 模块的主入口，组装所有子模块，对外暴露简洁 API。
///
/// 使用示例：
/// ```dart
/// final client = ReliableWebSocketClient(
///   url: 'wss://api.example.com/ws',
///   getToken: () async => 'your-jwt-token',
///   onMessage: (payload, seq) => print('Received: $payload @ $seq'),
///   onConnectionStateChange: (state) => print('State: $state'),
/// );
///
/// await client.connect();
/// await client.send({'type': 'chat', 'text': 'Hello'});
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import 'connection/connection_manager.dart';
import 'database/database.dart';
import 'models/connection_state.dart';
import 'outbox/outbox_manager.dart';
import 'protocol/codec.dart';
import 'protocol/message.dart';
import 'receiver/reliable_receiver.dart';
import 'sender/reliable_sender.dart';
import 'sync/sync_recovery.dart';

/// 获取认证 token 的回调
typedef TokenProvider = Future<String> Function();

/// 消息到达回调（按序）
typedef MessageHandler = void Function(Map<String, dynamic> payload, int seq);

/// 连接状态变化回调
typedef ConnectionStateHandler = void Function(ConnectionState state);

/// 消息发送成功回调
typedef MessageSentHandler = void Function(String clientMsgId);

/// 消息发送失败回调
typedef MessageFailedHandler = void Function(String clientMsgId, String error);

/// 服务端错误回调
typedef ErrorHandler = void Function(String message, String? clientMsgId);

/// 认证失败回调
typedef AuthFailedHandler = void Function(String? error);

/// 非序号自定义消息回调
typedef CustomMessageHandler = void Function(Map<String, dynamic> payload);

/// ACK 携带 message_id 回调
typedef AckMessageIdHandler = void Function(String clientMsgId, int messageId);

/// 可靠 WebSocket 客户端配置
class ReliableWebSocketConfig {
  /// WebSocket 服务器地址
  final String url;

  /// 认证 token 提供者
  final TokenProvider getToken;

  /// 消息处理回调
  final MessageHandler onMessage;

  /// 连接状态变化回调
  final ConnectionStateHandler onConnectionStateChange;

  /// 消息发送成功回调（可选）
  final MessageSentHandler? onMessageSent;

  /// 消息发送失败回调（可选）
  final MessageFailedHandler? onMessageFailed;

  /// 服务端错误回调（可选）
  final ErrorHandler? onError;

  /// 认证失败回调（可选）
  final AuthFailedHandler? onAuthFailed;
  /// 非序号消息回调（可选）
  final CustomMessageHandler? onCustomMessage;
  /// ACK message_id 回调（可选）
  final AckMessageIdHandler? onAckMessageId;
  final Duration connectTimeout;

  /// ACK 超时（默认 15 秒）
  final Duration ackTimeout;

  /// 心跳间隔（默认 30 秒）
  final Duration heartbeatInterval;

  /// 连续心跳丢失次数阈值（默认 2 次）
  final int maxPingMissCount;

  /// 消息最大重试次数（默认 3 次）
  final int maxRetries;

  /// 发件箱最大容量（默认 1000）
  final int maxOutboxSize;

  /// sync 补发请求超时（默认 30 秒）
  final Duration syncTimeout;

  /// sync 补发请求最大重试次数（默认 3）
  final int syncMaxRetries;

  /// 数据库（可选，用于注入测试数据库）
  final AppDatabase? database;

  const ReliableWebSocketConfig({
    required this.url,
    required this.getToken,
    required this.onMessage,
    required this.onConnectionStateChange,
    this.onMessageSent,
    this.onMessageFailed,
    this.onError,
    this.onAuthFailed,
    this.onCustomMessage,
    this.onAckMessageId,
    this.connectTimeout = const Duration(seconds: 15),
    this.ackTimeout = const Duration(seconds: 15),
    // 心跳 20s + 容忍 3 次未响应（~60s 判定死连接）。
    // 之前 30s/2 次：移动网络抖动时单次 pong 延迟即触发重连，造成「经常断开重连」。
    // 放宽到 3 次能吸收偶发延迟，同时 20s 间隔更快发现真死连接。
    this.heartbeatInterval = const Duration(seconds: 20),
    this.maxPingMissCount = 3,
    this.maxRetries = 3,
    this.maxOutboxSize = 1000,
    this.syncTimeout = const Duration(seconds: 30),
    this.syncMaxRetries = 3,
    this.database,
  });
}

/// 可靠 WebSocket 客户端
///
/// 提供消息确认、有序交付、发件箱持久化、自动重连等可靠性保障。
/// 与业务完全解耦，通过回调注入实现通信。
class ReliableWebSocketClient {
  final ReliableWebSocketConfig _config;
  final ProtocolCodec _codec;
  final Logger _log = Logger('ReliableWebSocketClient');

  late final AppDatabase _db;
  late final ConnectionManager _connection;
  late final OutboxManager _outbox;
  late final ReliableSender _sender;
  late final ReliableReceiver _receiver;
  late final SyncRecovery _sync;

  /// 当前连接状态
  ConnectionState get state => _connection.state;

  /// 是否已认证连接
  bool get isConnected => _connection.isConnected;

  /// 当前已交付的最大序号
  int get lastReceivedSeq => _receiver.lastReceivedSeq;

  ReliableWebSocketClient({
    required String url,
    required TokenProvider getToken,
    required MessageHandler onMessage,
    required ConnectionStateHandler onConnectionStateChange,
    MessageSentHandler? onMessageSent,
    MessageFailedHandler? onMessageFailed,
    ErrorHandler? onError,
    AuthFailedHandler? onAuthFailed,
    CustomMessageHandler? onCustomMessage,
    AckMessageIdHandler? onAckMessageId,
    AppDatabase? database,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration ackTimeout = const Duration(seconds: 15),
    Duration heartbeatInterval = const Duration(seconds: 20),
    int maxPingMissCount = 3,
    int maxRetries = 3,
    int maxOutboxSize = 1000,
    Duration syncTimeout = const Duration(seconds: 30),
    int syncMaxRetries = 3,
  }) : _config = ReliableWebSocketConfig(
          url: url,
          getToken: getToken,
          onMessage: onMessage,
          onConnectionStateChange: onConnectionStateChange,
          onMessageSent: onMessageSent,
          onMessageFailed: onMessageFailed,
          onError: onError,
          onAuthFailed: onAuthFailed,
          onCustomMessage: onCustomMessage,
          onAckMessageId: onAckMessageId,
          connectTimeout: connectTimeout,
          ackTimeout: ackTimeout,
          heartbeatInterval: heartbeatInterval,
          maxPingMissCount: maxPingMissCount,
          maxRetries: maxRetries,
          maxOutboxSize: maxOutboxSize,
          syncTimeout: syncTimeout,
          syncMaxRetries: syncMaxRetries,
          database: database,
        ),
        _codec = const ProtocolCodec() {
    _initModules();
  }

  /// 使用配置对象构造
  ReliableWebSocketClient.fromConfig(ReliableWebSocketConfig config)
      : _config = config,
        _codec = const ProtocolCodec() {
    _initModules();
  }

  void _initModules() {
    // 1. 数据库
    _db = _config.database ?? AppDatabase();

    // 2. 发件箱
    _outbox = OutboxManager(_db);

    // 3. 连接管理器
    _connection = ConnectionManager(
      url: _config.url,
      codec: _codec,
      connectTimeout: _config.connectTimeout,
      heartbeatInterval: _config.heartbeatInterval,
      maxPingMissCount: _config.maxPingMissCount,
      onStateChange: _config.onConnectionStateChange,
      onFrameReceived: _handleFrame,
      onSocketReady: _onSocketReady,   // 重连后也触发，自动重发 auth
      onSessionInvalid: (code, reason) {
        // 4001 = JWT 失效，1000 = 被踢下线
        _log.warning('Session invalid: code=$code reason=$reason');
        _config.onAuthFailed?.call('code=$code: $reason');
      },
    );

    // 4. 可靠发送器
    _sender = ReliableSender(
      connection: _connection,
      outbox: _outbox,
      ackTimeout: _config.ackTimeout,
      maxRetries: _config.maxRetries,
      maxOutboxSize: _config.maxOutboxSize,
      onSent: _config.onMessageSent,
      onFailed: _config.onMessageFailed,
    );

    // 5. 同步恢复（先建，receiver 后填）
    _sync = SyncRecovery(
      connection: _connection,
      db: _db,
      sender: _sender,
      syncTimeout: _config.syncTimeout,
      syncMaxRetries: _config.syncMaxRetries,
    );

    // 6. 可靠接收器（注入 sync 的补发能力）
    _receiver = ReliableReceiver(
      db: _db,
      onMessage: _config.onMessage,
      outOfOrderTimeout: _config.syncTimeout,
      requestSync: (fromSeq) => _sync.requestSync(fromSeq),
    );

    // 回填 receiver 到 sync
    _sync.setReceiver(_receiver);
  }

  // ========== 公开 API ==========

  /// 连接到服务器
  ///
  /// 建立 WebSocket 连接 → 自动发送 auth → 等待认证 → 执行同步恢复。
  Future<void> connect() async {
    _log.info('Connecting to ${_config.url}');

    // 加载本地序号状态（失败不阻塞连接）
    try {
      await _receiver.loadState();
    } catch (e) {
      _log.warning('Failed to load receiver state, starting with seq=0: $e');
    }

    // 建立物理连接（连接成功后会通过 onSocketReady 自动发送 auth）
    await _connection.connect();
  }

  /// 断开连接
  ///
  /// 关闭 WebSocket、停止心跳、取消重连，但不关闭数据库。
  Future<void> disconnect() async {
    _log.info('Disconnecting');
    _sender.cancelAllTimers();
    _receiver.dispose();
    _sync.dispose();
    await _connection.disconnect();
  }

  /// 强制重连：无视当前状态，断开现有连接并立即重建。
  ///
  /// 用于网络恢复、App 回前台等场景——旧连接可能已僵死（系统挂起 socket），
  /// 必须强制重建才能恢复实时通信。与 disconnect() 不同，这里不会进入
  /// disconnected 终态，而是直接重新连接，保证「有网就不断」。
  Future<void> forceReconnect() async {
    _log.info('Force reconnect');
    _sender.cancelAllTimers();
    await _connection.forceReconnect();
    // 重连成功后 onAuthenticated 会重新启动心跳；同步恢复由 _onAuthResult 触发。
  }

  /// 发送业务消息
  ///
  /// 返回 clientMsgId 用于追踪。
  /// 若发件箱满或超过最大容量，抛出 [StateError]。
  Future<String> send(Map<String, dynamic> payload) {
    return _sender.send(payload);
  }

  /// 发送原始协议帧（不经过发件箱/ACK，fire-and-forget）
  ///
  /// 用于 join / leave / typing / stop_typing / ping 等控制帧。
  /// [frame] 中的所有字段直接序列化为 JSON 发送，不做任何包装。
  /// 例: `{"type":"join","conversation_id":42}`
  void sendRaw(Map<String, dynamic> frame) {
    if (_connection.isConnected) {
      _connection.sendRawJson(jsonEncode(frame));
    }
  }

  /// 获取当前发件箱中 pending 消息数量
  Future<int> getPendingCount() {
    return _outbox.getPendingCount();
  }

  /// 清理已确认和失败的消息
  Future<void> cleanOutbox() async {
    await _outbox.cleanAcked();
    await _outbox.cleanFailed();
  }

  /// 应用进入后台
  void onAppBackground({bool disconnect = false}) {
    _connection.onAppBackground(disconnect: disconnect);
  }

  /// 应用回到前台
  void onAppForeground() {
    _connection.onAppForeground();
  }

  /// 释放所有资源
  void dispose() {
    _sender.dispose();
    _receiver.dispose();
    _sync.dispose();
    _connection.dispose();
  }

  // ========== 消息分发 ==========

  /// Socket 就绪回调（首次连接 + 每次重连成功后触发）
  Future<void> _onSocketReady() async {
    try {
      final token = await _config.getToken();
      _connection.sendFrame(ProtocolCodec.auth(token));
      _log.info('Auth sent via onSocketReady');
    } catch (e) {
      _log.severe('Failed to get token for auth: $e');
      await _connection.disconnect();
    }
  }

  /// 处理收到的协议帧
  void _handleFrame(ProtocolFrame frame) async {
    switch (frame.type) {
      case MessageType.authResult:
        await _onAuthResult(frame);
        break;

      case MessageType.ack:
        await _onAck(frame);
        break;

      case MessageType.message:
        await _onMessage(frame);
        break;

      case MessageType.syncResult:
        _onSyncResult(frame);
        break;

      case MessageType.pong:
        // 由 ConnectionManager 内部处理
        break;

      case MessageType.error:
        _config.onError?.call(
          frame.errorMsg ?? 'Unknown error',
          frame.ackClientMsgId,
        );
        break;

      case MessageType.typing:
      case MessageType.stopTyping:
        _config.onCustomMessage?.call(frame.payload ?? const <String, dynamic>{});
        break;

      default:
        _log.warning('Unhandled frame type: ${frame.type.name}');
    }
  }

  /// 处理认证结果（v1.0: 读 payload.success / payload.user_id）
  Future<void> _onAuthResult(ProtocolFrame frame) async {
    _log.info('[Auth] result: success=${frame.success}, userId=${frame.userId}, payload=${frame.payload}');
    if (frame.success == true) {
      _log.info('[Auth] ✅ Authenticated');
      _connection.onAuthenticated();
      await _sync.recover();
    } else {
      _log.warning('[Auth] ❌ Failed: ${frame.errorMsg}');
      _config.onAuthFailed?.call(frame.errorMsg);
      await _connection.disconnect();
    }
  }

  /// 处理 ACK 确认（v1.0: 读 payload.client_msg_id / payload.message_id）
  Future<void> _onAck(ProtocolFrame frame) async {
    final clientMsgId = frame.ackClientMsgId;
    if (clientMsgId != null) {
      await _sender.onAck(clientMsgId);
    }
    final msgId = frame.ackMessageId;
    if (msgId != null && clientMsgId != null) {
      _config.onAckMessageId?.call(clientMsgId, msgId);
    }
  }

  /// 处理服务端推送消息
  ///
  /// seq=0 表示非持久化事件（typing / stop_typing），
  /// 直接交付业务层，不进入序号跟踪逻辑。
  Future<void> _onMessage(ProtocolFrame frame) async {
    final seq = frame.seq ?? 0;
    if (seq == 0) {
      // 非持久化事件：直接交付，不记录 seq
      final payload = frame.payload;
      if (payload != null) {
        _config.onMessage(payload, 0);
      }
    } else {
      await _receiver.onMessage(frame);
    }
  }

  /// 处理 sync_result（v1.0: 读 payload.list）
  void _onSyncResult(ProtocolFrame frame) {
    final list = frame.syncList;
    final messages = <ProtocolFrame>[];
    if (list != null) {
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          messages.add(ProtocolFrame.fromJson(item));
        }
      }
    }
    _sync.onSyncResult(messages);
  }
}
