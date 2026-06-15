/// 连接管理模块
///
/// 基于 web_socket_channel 管理 WebSocket 物理连接，
/// 包含状态机、心跳保活、指数退避重连。
library;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/connection_state.dart';
import '../protocol/codec.dart';
import '../protocol/message.dart';

/// 连接状态变化回调
typedef OnStateChange = void Function(ConnectionState state);

/// 消息到达回调（原始协议帧）
typedef OnFrameReceived = void Function(ProtocolFrame frame);

/// 物理连接就绪回调
typedef OnSocketReady = Future<void> Function();

/// JWT 失效/被踢下线回调（关闭码 4001/1000）
typedef OnSessionInvalid = void Function(int closeCode, String reason);

/// 连接管理器
///
/// 负责 WebSocket 物理连接的生命周期管理。
class ConnectionManager {
  final String _url;
  final ProtocolCodec _codec;
  final OnStateChange _onStateChange;
  final OnFrameReceived _onFrameReceived;
  final OnSocketReady? _onSocketReady;
  final OnSessionInvalid? _onSessionInvalid;
  final Duration _connectTimeout;
  final Duration _heartbeatInterval;
  final int _maxPingMissCount;

  final Logger _log = Logger('ConnectionManager');

  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;

  Timer? _heartbeatTimer;
  Timer? _connectTimer;
  Timer? _reconnectTimer;

  int _pingMissCount = 0;
  int _reconnectAttempt = 0;

  /// 重连策略：指数退避
  static const _reconnectBaseDelay = Duration(seconds: 1);
  static const _reconnectMaxDelay = Duration(seconds: 60);

  /// 当前连接状态
  ConnectionState get state => _state;

  /// 是否已连接
  bool get isConnected => _state == ConnectionState.authenticated;

  ConnectionManager({
    required String url,
    ProtocolCodec? codec,
    required OnStateChange onStateChange,
    required OnFrameReceived onFrameReceived,
    OnSocketReady? onSocketReady,
    OnSessionInvalid? onSessionInvalid,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration heartbeatInterval = const Duration(seconds: 30),
    int maxPingMissCount = 2,
  })  : _url = url,
        _codec = codec ?? const ProtocolCodec(),
        _onStateChange = onStateChange,
        _onFrameReceived = onFrameReceived,
        _onSocketReady = onSocketReady,
        _onSessionInvalid = onSessionInvalid,
        _connectTimeout = connectTimeout,
        _heartbeatInterval = heartbeatInterval,
        _maxPingMissCount = maxPingMissCount;

  // ========== 状态管理 ==========

  void _setState(ConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _log.info('State changed → ${newState.name}');
      _onStateChange(newState);
    }
  }

  // ========== 连接与断开 ==========

  /// 建立连接
  Future<void> connect() async {
    if (_state == ConnectionState.connecting ||
        _state == ConnectionState.authenticated) {
      _log.info('connect() called but already in state ${_state.name}, skip');
      return;
    }

    final isFirstConnect = _state == ConnectionState.disconnected;
    _setState(ConnectionState.connecting);
    if (isFirstConnect) {
      _reconnectAttempt = 0;
    }

    try {
      _log.info('Opening WebSocket to $_url');
      final channel = WebSocketChannel.connect(Uri.parse(_url));
      _channel = channel;

      _connectTimer = Timer(_connectTimeout, () {
        if (_state == ConnectionState.connecting) {
          _log.warning('Connect timeout after ${_connectTimeout.inSeconds}s');
          _closeChannel();
          _startReconnect();
        }
      });

      await channel.ready;

      _connectTimer?.cancel();
      _connectTimer = null;

      _log.info('WebSocket connected to $_url');

      // 必须先监听再发 auth，避免服务端极快返回 auth_result/session_list 时监听尚未建立而丢帧。
      channel.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      await _onSocketReady?.call();
    } catch (e, _) {
      _log.severe('Connect failed: $e');
      _closeChannel();
      _startReconnect();
    }
  }

  /// 标记认证成功
  void onAuthenticated() {
    _setState(ConnectionState.authenticated);
    _reconnectAttempt = 0;
    _pingMissCount = 0;
    _startHeartbeat();
  }

  /// 断开连接
  Future<void> disconnect() async {
    _log.info('Disconnecting...');
    _cancelTimers();
    // 必须先设状态再关 channel，否则 _onDone 检测到 _state != disconnected 会触发重连
    _setState(ConnectionState.disconnected);
    _closeChannel();
  }

  // ========== 消息收发 ==========

  /// 发送原始帧（直接写入 WebSocket）
  void sendFrame(ProtocolFrame frame) {
    final data = _codec.encode(frame);
    if (frame.type != MessageType.ping) {
      _log.info('→ ${frame.type.name}: $data');
    }
    _channel?.sink.add(data);
  }

  /// 发送原始 JSON 字符串（用于控制帧等不需要 ProtocolFrame 包装的消息）
  void sendRawJson(String json) {
    _channel?.sink.add(json);
  }

  void _onData(dynamic data) {
    try {
      final rawStr = data as String;
      final frame = _codec.decode(rawStr);
      // 接收的所有 WS 帧完整打印原始 JSON
      if (frame.type == MessageType.pong) {
        _log.fine('← pong');
        _pingMissCount = 0;
        return;
      }
      _log.info('← ${frame.type.name}: $rawStr');

      _onFrameReceived(frame);
    } catch (e) {
      _log.warning('Failed to decode message: $e');
    }
  }

  void _onError(dynamic error) {
    _log.warning('WebSocket error: $error');
    // Stream 错误不直接触发重连，由 onDone 统一处理
  }

  void _onDone() {
    // 在关闭 channel 前读取关闭码
    final channel = _channel;  // 局部变量防止异步竞态
    final closeCode = channel?.closeCode;
    final closeReason = channel?.closeReason ?? '';
    _log.warning('WebSocket closed: code=$closeCode reason=$closeReason');
    _closeChannel();

    // 4001 = JWT 无效/过期/用户不存在 → 不重连，需重新登录
    // 1000 = 同用户新连接替换旧连接 → 不重连
    if (closeCode == 4001 || closeCode == 1000) {
      _setState(ConnectionState.disconnected);
      _onSessionInvalid?.call(closeCode!, closeReason);
      return;
    }

    if (_state != ConnectionState.disconnected) {
      _startReconnect();
    }
  }

  // ========== 心跳 ==========

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _pingMissCount = 0;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_state == ConnectionState.authenticated) {
        sendFrame(ProtocolCodec.ping);
        _pingMissCount++;

        if (_pingMissCount > _maxPingMissCount) {
          _log.warning('Heartbeat timeout ($_pingMissCount missed)');
          _closeChannel();
          _startReconnect();
        }
      }
    });
  }

  // ========== 重连 ==========

  void _startReconnect() {
    if (_state == ConnectionState.disconnected) return;

    _setState(ConnectionState.reconnecting);

    // 指数退避：1s → 2s → 4s → 8s → ... → 60s
    final delay = _reconnectBaseDelay * (1 << _reconnectAttempt);
    final clamped = delay > _reconnectMaxDelay ? _reconnectMaxDelay : delay;

    _reconnectAttempt++;
    _log.info('Reconnecting in ${clamped.inSeconds}s (attempt $_reconnectAttempt)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(clamped, () {
      connect();
    });
  }

  // ========== 资源释放 ==========

  void _closeChannel() {
    _channel?.sink.close();
    _channel = null;
  }

  void _cancelTimers() {
    _connectTimer?.cancel();
    _connectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// 应用进入后台时调用：暂停心跳，可选断开连接
  void onAppBackground({bool disconnect = false}) {
    _heartbeatTimer?.cancel();
    if (disconnect) {
      this.disconnect();
    }
  }

  /// 应用回到前台时调用：恢复心跳，必要时重连
  void onAppForeground() {
    if (_state == ConnectionState.disconnected) {
      connect();
    } else if (_state == ConnectionState.authenticated) {
      _pingMissCount = 0;
      _startHeartbeat();
    }
  }

  /// 释放所有资源
  void dispose() {
    _cancelTimers();
    _closeChannel();
  }
}
