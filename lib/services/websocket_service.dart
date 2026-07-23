import 'dart:async';
import 'dart:collection';

import 'package:nonto/config/app_config.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/connectivity_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/local_db_service.dart';
import 'package:nonto/services/sound_service.dart';
import 'package:nonto/providers/chat_room_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:reliable_websocket/reliable_websocket.dart';

typedef WebSocketClientFactory = WebSocketClientAdapter Function({
  required String url,
  required WebSocketClientCallbacks callbacks,
});

typedef WebSocketConnectionCoordinatorFactory = WebSocketConnectionCoordinator
    Function(
  WebSocketClientCallbacks callbacks,
);

class ChatSendFailure {
  final String clientMsgId;
  final String code;
  final String message;
  final bool retryable;

  const ChatSendFailure({
    required this.clientMsgId,
    required this.code,
    required this.message,
    required this.retryable,
  });

  factory ChatSendFailure.fromReliable(SendFailure failure) {
    return ChatSendFailure(
      clientMsgId: failure.clientMsgId,
      code: failure.code ?? 'SEND_FAILED',
      message: failure.message.trim().isNotEmpty ? failure.message : '发送失败',
      retryable: failure.retryable,
    );
  }
}

abstract interface class WebSocketClientAdapter {
  Future<void> connect();
  Future<void> disconnect();
  Future<void> forceReconnect();
  Future<String> send(Map<String, dynamic> payload);
  void sendRaw(Map<String, dynamic> frame);
}

class WebSocketClientCallbacks {
  const WebSocketClientCallbacks({
    this.onMessage,
    this.onAckMessageId,
    this.onMessageFailed,
    this.onConnectionStateChange,
    this.onError,
    this.onAuthFailed,
  });

  final void Function(Map<String, dynamic> payload, int seq)? onMessage;
  final void Function(String clientMsgId, int messageId)? onAckMessageId;
  final void Function(SendFailure failure)? onMessageFailed;
  final void Function(ConnectionState state)? onConnectionStateChange;
  final void Function(String message, String? clientMsgId)? onError;
  final void Function(String? error)? onAuthFailed;
}

class _DisconnectOnceWebSocketClientAdapter implements WebSocketClientAdapter {
  _DisconnectOnceWebSocketClientAdapter(this._delegate);

  final WebSocketClientAdapter _delegate;
  Future<void>? _disconnecting;
  bool _disconnected = false;

  @override
  Future<void> connect() => _delegate.connect();

  @override
  Future<void> disconnect() {
    if (_disconnected) return Future<void>.value();
    return _disconnecting ??= _disconnect();
  }

  Future<void> _disconnect() async {
    try {
      await _delegate.disconnect();
      _disconnected = true;
    } finally {
      _disconnecting = null;
    }
  }

  @override
  Future<void> forceReconnect() => _delegate.forceReconnect();

  @override
  Future<String> send(Map<String, dynamic> payload) => _delegate.send(payload);

  @override
  void sendRaw(Map<String, dynamic> frame) => _delegate.sendRaw(frame);
}

class _ReliableWebSocketClientAdapter implements WebSocketClientAdapter {
  _ReliableWebSocketClientAdapter({
    required String url,
    required WebSocketClientCallbacks callbacks,
  }) : _client = ReliableWebSocketClient(
          url: url,
          getToken: () async => ApiClient.token ?? '',
          onMessage: callbacks.onMessage ?? (_, __) {},
          onAckMessageId: callbacks.onAckMessageId,
          onMessageFailed: callbacks.onMessageFailed,
          onConnectionStateChange: callbacks.onConnectionStateChange ?? (_) {},
          onError: callbacks.onError,
          onAuthFailed: callbacks.onAuthFailed,
        );

  final ReliableWebSocketClient _client;

  @override
  Future<void> connect() => _client.connect();

  @override
  Future<void> disconnect() => _client.disconnect();

  @override
  Future<void> forceReconnect() => _client.forceReconnect();

  @override
  Future<String> send(Map<String, dynamic> payload) => _client.send(payload);

  @override
  void sendRaw(Map<String, dynamic> frame) => _client.sendRaw(frame);
}

enum _WebSocketClientCallbackScope {
  active,
  backgroundRetiring,
  invalidated,
}

/// Owns foreground/token gating and invalidates stale asynchronous clients.
class WebSocketConnectionCoordinator {
  WebSocketConnectionCoordinator({
    required String? Function() tokenProvider,
    required String Function(String token) uriForToken,
    required WebSocketClientCallbacks callbacks,
    Duration transportShutdownTimeout = const Duration(seconds: 2),
  }) : this.forTesting(
          tokenProvider: tokenProvider,
          uriForToken: uriForToken,
          clientFactory: ({required url, required callbacks}) =>
              _ReliableWebSocketClientAdapter(
            url: url,
            callbacks: callbacks,
          ),
          callbacks: callbacks,
          transportShutdownTimeout: transportShutdownTimeout,
        );

  WebSocketConnectionCoordinator.forTesting({
    required String? Function() tokenProvider,
    required String Function(String token) uriForToken,
    required WebSocketClientFactory clientFactory,
    required WebSocketClientCallbacks callbacks,
    Duration transportShutdownTimeout = const Duration(seconds: 2),
  })  : _tokenProvider = tokenProvider,
        _uriForToken = uriForToken,
        _clientFactory = clientFactory,
        _callbacks = callbacks,
        _transportShutdownTimeout = transportShutdownTimeout;

  final String? Function() _tokenProvider;
  final String Function(String token) _uriForToken;
  final WebSocketClientFactory _clientFactory;
  final WebSocketClientCallbacks _callbacks;
  final Duration _transportShutdownTimeout;
  final Set<WebSocketClientAdapter> _retiredClients =
      HashSet<WebSocketClientAdapter>.identity();
  final Map<WebSocketClientAdapter, Future<void>> _clientOperations =
      HashMap<WebSocketClientAdapter, Future<void>>.identity();
  final Map<WebSocketClientAdapter, _WebSocketClientCallbackScope>
      _callbackScopes =
      HashMap<WebSocketClientAdapter, _WebSocketClientCallbackScope>.identity();
  final Map<WebSocketClientAdapter, Future<void>> _disconnectingClients =
      HashMap<WebSocketClientAdapter, Future<void>>.identity();

  WebSocketClientAdapter? _client;
  int? _clientGeneration;
  String? _clientToken;
  bool _isAppInForeground = true;
  bool _isConnected = false;
  int _generation = 0;
  int? _connectingGeneration;
  Future<void>? _connecting;
  DateTime _lastFrameAt = DateTime.now();

  bool get isConnected => _isConnected;
  bool get isAppInForeground => _isAppInForeground;
  WebSocketClientAdapter? get client => _client;

  void setAppForeground(bool foreground) {
    final changed = _isAppInForeground != foreground;
    _isAppInForeground = foreground;
    if (changed || !foreground) {
      _generation++;
    }
    if (!foreground) {
      final client = _client;
      if (client != null) _markClientBackgroundRetiring(client);
      _setConnected(false);
    }
  }

  void _markClientBackgroundRetiring(WebSocketClientAdapter client) {
    if (_callbackScopes[client] == _WebSocketClientCallbackScope.active) {
      _callbackScopes[client] =
          _WebSocketClientCallbackScope.backgroundRetiring;
    }
  }

  void _invalidateClientCallbacks(WebSocketClientAdapter client) {
    if (_callbackScopes.containsKey(client)) {
      _callbackScopes[client] = _WebSocketClientCallbackScope.invalidated;
    }
  }

  void _removeClientCallbacks(WebSocketClientAdapter client) {
    _callbackScopes.remove(client);
  }

  bool _hasToken([String? expectedToken]) {
    final token = _tokenProvider();
    return token != null &&
        token.trim().isNotEmpty &&
        (expectedToken == null || token == expectedToken);
  }

  bool _isCurrent(int generation, String token) {
    return generation == _generation && _isAppInForeground && _hasToken(token);
  }

  void _invalidateChangedToken(String token) {
    if (_clientToken != null && _clientToken != token) {
      _generation++;
      _clientGeneration = null;
      _clientToken = token;
      _setConnected(false);
    }
  }

  void _setConnected(bool connected) {
    if (_isConnected == connected) return;
    _isConnected = connected;
    _callbacks.onConnectionStateChange?.call(
      connected ? ConnectionState.authenticated : ConnectionState.disconnected,
    );
  }

  Future<void> connect() {
    final token = _tokenProvider();
    if (!_isAppInForeground || token == null || token.trim().isEmpty) {
      return Future<void>.value();
    }
    _invalidateChangedToken(token);
    if (_isConnected) return Future<void>.value();
    final pending = _connecting;
    if (pending != null && _connectingGeneration == _generation) return pending;

    final generation = _generation;
    late final Future<void> task;
    task = _connectNewClient().whenComplete(() {
      if (identical(_connecting, task)) {
        _connecting = null;
        _connectingGeneration = null;
      }
    });
    _connectingGeneration = generation;
    _connecting = task;
    return task;
  }

  Future<void> _connectNewClient() async {
    final token = _tokenProvider();
    if (token == null || token.trim().isEmpty || !_isAppInForeground) return;
    final generation = _generation;

    final previousClient = _client;
    if (previousClient != null) {
      _client = null;
      _clientGeneration = null;
      _clientToken = null;
      await _retireClient(previousClient);
      if (!_isCurrent(generation, token)) return;
    }

    if (!_isCurrent(generation, token)) return;
    late final WebSocketClientAdapter client;
    final scopedCallbacks = _scopedCallbacks(
      generation,
      token,
      () => client,
    );
    client = _DisconnectOnceWebSocketClientAdapter(
      _clientFactory(
        url: _uriForToken(token),
        callbacks: scopedCallbacks,
      ),
    );
    if (!_isCurrent(generation, token)) {
      await _retireClient(client);
      return;
    }

    _client = client;
    _clientGeneration = generation;
    _clientToken = token;
    _callbackScopes[client] = _WebSocketClientCallbackScope.active;
    try {
      if (!_isCurrent(generation, token)) {
        await _retireClient(client);
        return;
      }
      final connectOperation = client.connect();
      _clientOperations[client] = connectOperation;
      await connectOperation;
      if (identical(_clientOperations[client], connectOperation)) {
        _clientOperations.remove(client);
      }
      if (!_isCurrent(generation, token) || !identical(_client, client)) {
        if (identical(_client, client)) {
          _client = null;
          _clientGeneration = null;
          _clientToken = null;
        }
        await _retireClient(client);
      }
    } catch (_) {
      if (identical(_client, client)) {
        _client = null;
        _clientGeneration = null;
        _clientToken = null;
      }
      await _retireClient(client);
      rethrow;
    }
  }

  WebSocketClientCallbacks _scopedCallbacks(
    int generation,
    String token,
    WebSocketClientAdapter Function() clientProvider,
  ) {
    bool active() {
      final client = clientProvider();
      return _callbackScopes[client] == _WebSocketClientCallbackScope.active &&
          _isCurrent(generation, token) &&
          identical(_client, client);
    }

    bool acceptsInboundData() {
      final client = clientProvider();
      final scope = _callbackScopes[client];
      if (scope == _WebSocketClientCallbackScope.backgroundRetiring) {
        return _hasToken(token);
      }
      return scope == _WebSocketClientCallbackScope.active &&
          identical(_client, client);
    }

    return WebSocketClientCallbacks(
      onMessage: (payload, seq) {
        if (acceptsInboundData()) _callbacks.onMessage?.call(payload, seq);
      },
      onAckMessageId: (clientMsgId, messageId) {
        if (acceptsInboundData()) {
          _callbacks.onAckMessageId?.call(clientMsgId, messageId);
        }
      },
      onMessageFailed: (failure) {
        if (acceptsInboundData()) {
          _callbacks.onMessageFailed?.call(failure);
        }
      },
      onConnectionStateChange: (state) {
        if (!active()) return;
        final connected = state == ConnectionState.authenticated;
        _isConnected = connected;
        _callbacks.onConnectionStateChange?.call(state);
      },
      onError: (message, clientMsgId) {
        if (active()) _callbacks.onError?.call(message, clientMsgId);
      },
      onAuthFailed: (error) {
        if (active()) _callbacks.onAuthFailed?.call(error);
      },
    );
  }

  Future<void> forceReconnect() async {
    final token = _tokenProvider();
    if (token == null || token.trim().isEmpty || !_isAppInForeground) {
      return;
    }
    _invalidateChangedToken(token);
    final generation = _generation;
    final pendingConnect = _connecting;
    if (pendingConnect != null && _connectingGeneration == generation) {
      await pendingConnect;
      return;
    }

    final currentClient = _client;
    if (currentClient == null || _clientGeneration != generation) {
      await connect();
      return;
    }

    _setConnected(false);
    final pendingOperation = _clientOperations[currentClient];
    if (pendingOperation != null) {
      await pendingOperation;
      return;
    }

    final reconnectOperation = currentClient.forceReconnect();
    _clientOperations[currentClient] = reconnectOperation;
    try {
      await reconnectOperation;
    } finally {
      if (identical(_clientOperations[currentClient], reconnectOperation)) {
        _clientOperations.remove(currentClient);
      }
    }
    if (!_isCurrent(generation, token) || !identical(_client, currentClient)) {
      if (identical(_client, currentClient)) {
        _client = null;
        _clientGeneration = null;
        _clientToken = null;
      }
      await _retireClient(currentClient);
    }
  }

  Future<void> onConnectivityChanged(bool online) async {
    if (!online || _isConnected) return;
    try {
      await forceReconnect();
    } catch (error, stack) {
      debugPrint('[WS] connectivity reconnect failed: $error');
      debugPrint(stack.toString());
    }
  }

  void markFrameReceived([DateTime? now]) {
    _lastFrameAt = now ?? DateTime.now();
  }

  Future<void> runHealthCheck({
    required bool online,
    DateTime? now,
  }) async {
    if (!_isAppInForeground || !_isConnected || !online) return;
    final checkedAt = now ?? DateTime.now();
    if (checkedAt.difference(_lastFrameAt) > const Duration(seconds: 90)) {
      try {
        await forceReconnect();
      } catch (error, stack) {
        debugPrint('[WS] health reconnect failed: $error');
        debugPrint(stack.toString());
      }
    }
  }

  Future<void> disconnect() async {
    _generation++;
    _setConnected(false);
    final activeClient = _client;
    _client = null;
    _clientGeneration = null;
    _clientToken = null;
    if (activeClient != null) {
      if (_callbackScopes[activeClient] !=
          _WebSocketClientCallbackScope.backgroundRetiring) {
        _invalidateClientCallbacks(activeClient);
      }
      _retiredClients.add(activeClient);
    }

    for (final client in _retiredClients.toList()) {
      try {
        await _disconnectClient(client);
      } catch (error, stack) {
        debugPrint('[WS] transport disconnect failed: $error');
        debugPrint(stack.toString());
      } finally {
        _retiredClients.remove(client);
        _removeClientCallbacks(client);
      }
    }
  }

  Future<void> _retireClient(WebSocketClientAdapter client) async {
    if (_callbackScopes[client] !=
        _WebSocketClientCallbackScope.backgroundRetiring) {
      _invalidateClientCallbacks(client);
    }
    _retiredClients.add(client);
    try {
      await _disconnectClient(client);
    } finally {
      _retiredClients.remove(client);
      _removeClientCallbacks(client);
    }
  }

  Future<void> _disconnectClient(WebSocketClientAdapter client) {
    final pendingDisconnect = _disconnectingClients[client];
    if (pendingDisconnect != null) return pendingDisconnect;

    final previousOperation = _clientOperations[client];
    late final Future<void> task;
    task = () async {
      if (previousOperation != null) {
        await _awaitShutdownPhase(
          previousOperation,
          'pending transport operation',
        );
      }
      await _awaitShutdownPhase(client.disconnect(), 'transport disconnect');
    }()
        .whenComplete(() {
      if (identical(_clientOperations[client], previousOperation)) {
        _clientOperations.remove(client);
      }
      if (identical(_disconnectingClients[client], task)) {
        _disconnectingClients.remove(client);
      }
    });
    _disconnectingClients[client] = task;
    return task;
  }

  Future<void> _awaitShutdownPhase(
    Future<void> operation,
    String phase,
  ) async {
    try {
      await operation.timeout(_transportShutdownTimeout);
    } catch (error, stack) {
      debugPrint('[WS] $phase failed during shutdown: $error');
      debugPrint(stack.toString());
    }
  }
}

/// 全局 WebSocket 服务，内部使用 ReliableWebSocketClient
/// 支持聊天消息、通知推送的实时功能
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._();
  factory WebSocketService() => _instance;

  WebSocketService._()
      : _playNotificationSound = null,
        _playOnlineSound = null,
        _performLightImpact = null,
        _currentUserIdProvider = null,
        _isConversationOpen = null,
        _shutdownTimeout = const Duration(seconds: 2) {
    _connectionCoordinator = WebSocketConnectionCoordinator(
      tokenProvider: () => ApiClient.token,
      uriForToken: _uriForToken,
      callbacks: _buildCallbacks(),
    );
  }

  WebSocketService.forTesting({
    WebSocketConnectionCoordinator? connectionCoordinator,
    WebSocketConnectionCoordinatorFactory? connectionCoordinatorFactory,
    void Function()? playNotificationSound,
    void Function()? playOnlineSound,
    void Function()? performLightImpact,
    String? Function()? currentUserIdProvider,
    bool Function(int conversationId)? isConversationOpen,
    Duration shutdownTimeout = const Duration(seconds: 2),
  })  : assert(
          (connectionCoordinator == null) !=
              (connectionCoordinatorFactory == null),
          'Provide exactly one connection coordinator source.',
        ),
        _playNotificationSound = playNotificationSound,
        _playOnlineSound = playOnlineSound,
        _performLightImpact = performLightImpact,
        _currentUserIdProvider = currentUserIdProvider,
        _isConversationOpen = isConversationOpen,
        _shutdownTimeout = shutdownTimeout {
    _connectionCoordinator = connectionCoordinator ??
        connectionCoordinatorFactory!(_buildCallbacks());
  }

  WebSocketClientCallbacks _buildCallbacks() {
    return WebSocketClientCallbacks(
      onMessage: _onMessage,
      onAckMessageId: (clientMsgId, messageId) {
        if (_isDisposed) return;
        _ackMessageIdController.add({
          'clientMsgId': clientMsgId,
          'message_id': messageId,
        });
        _messageController.add({
          'event': 'ack',
          'clientMsgId': clientMsgId,
          'client_msg_id': clientMsgId,
          'message_id': messageId,
        });
      },
      onMessageFailed: (failure) {
        if (_isDisposed) return;
        debugPrint(
          '[WS] reliable send failed '
          '(clientMsgId=${failure.clientMsgId}, status=${failure.status}, '
          'code=${failure.code ?? 'none'})',
        );
        _sendErrorController.add(ChatSendFailure.fromReliable(failure));
      },
      onConnectionStateChange: _onConnectionStateChange,
      onError: (message, clientMsgId) {
        if (_isDisposed) return;
        debugPrint(
          '[WS] server error '
          '(clientMsgId=$clientMsgId, exception_type=ServerError)',
        );
        if (clientMsgId != null && clientMsgId.isNotEmpty) {
          _sendErrorController.add(ChatSendFailure(
            clientMsgId: clientMsgId,
            code: 'SEND_FAILED',
            message: message.trim().isNotEmpty ? message : '发送失败',
            retryable: false,
          ));
        }
      },
      onAuthFailed: (error) {
        if (_isDisposed) return;
        debugPrint('[WS] auth failed (exception_type=AuthFailure)');
        if (_isConnected) {
          _isConnected = false;
          _connectionController.add(false);
        }
        _authExpiredController.add(error ?? 'auth_failed');
      },
    );
  }

  static const _diagnosticKeys = <String>[
    'ws_last_event',
    'ws_last_event_at',
    'ws_last_seq',
    'ws_is_app_in_foreground',
    'ws_is_connected',
    'ws_last_notification_decision',
  ];

  late final WebSocketConnectionCoordinator _connectionCoordinator;
  final void Function()? _playNotificationSound;
  final void Function()? _playOnlineSound;
  final void Function()? _performLightImpact;
  final String? Function()? _currentUserIdProvider;
  final bool Function(int conversationId)? _isConversationOpen;
  final Duration _shutdownTimeout;
  bool _isConnected = false;
  // 网络恢复监听：网络从离线→在线时主动重连，避免等心跳超时（60s+）才重连。
  // 之前用户切 WiFi/4G 后要等很久才恢复 WS，是「经常断开」的主因之一。
  StreamSubscription<bool>? _connectivitySub;
  // 定期健康检查：兜底捕获「socket 看似 authenticated 实则僵死」的极端情况
  // （心跳 ping 发出去了但 pong 永不返回、且心跳定时器被异常取消等）。
  // 每 90s 检查一次：若长时间未收到任何 WS 帧，强制重连。
  Timer? _healthCheckTimer;
  bool _isDisposed = false;
  Future<void>? _disposeTask;

  // 事件流控制器
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _sessionListController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _authExpiredController = StreamController<String>.broadcast();
  final _friendOnlineController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _friendOfflineController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _onlineFriendsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _communityPresenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _ackMessageIdController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _sendErrorController = StreamController<ChatSendFailure>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<List<Map<String, dynamic>>> get sessionListStream =>
      _sessionListController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// 认证失效流（JWT 过期/被踢下线/认证失败），业务层监听后执行注销
  Stream<String> get authExpiredStream => _authExpiredController.stream;

  /// 好友上线流
  Stream<Map<String, dynamic>> get friendOnlineStream =>
      _friendOnlineController.stream;

  /// 好友下线流
  Stream<Map<String, dynamic>> get friendOfflineStream =>
      _friendOfflineController.stream;

  /// 在线好友批量推送流（认证时服务端推送当前所有在线好友）
  Stream<Map<String, dynamic>> get onlineFriendsStream =>
      _onlineFriendsController.stream;

  /// 社群成员 App 在线状态变化流
  Stream<Map<String, dynamic>> get communityPresenceStream =>
      _communityPresenceController.stream;

  /// ACK 携带 message_id 流
  Stream<Map<String, dynamic>> get ackMessageIdStream =>
      _ackMessageIdController.stream;

  /// 发送错误流（携带 clientMsgId，用于 ChatSendQueue 匹配失败消息）
  Stream<ChatSendFailure> get sendErrorStream => _sendErrorController.stream;

  bool get isConnected => _isConnected;

  void setAppForeground(bool foreground) {
    if (_isDisposed) return;
    _connectionCoordinator.setAppForeground(foreground);
    if (!foreground) {
      _isConnected = false;
      _stopHealthCheck();
    }
    unawaited(_recordDiagnostic({
      'ws_is_app_in_foreground': foreground,
      'ws_is_connected': _isConnected,
    }));
  }

  Future<Map<String, dynamic>> debugSnapshot() async {
    final result = <String, dynamic>{
      'isConnected': _isConnected,
      'isAppInForeground': _connectionCoordinator.isAppInForeground,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearLegacySensitiveDiagnostics(prefs);
      for (final key in _diagnosticKeys) {
        result[key] = prefs.getString(key) ?? '';
      }
    } catch (error) {
      result['ws_debug_error'] = error.runtimeType.toString();
    }
    return result;
  }

  Future<void> _clearLegacySensitiveDiagnostics(
    SharedPreferences prefs,
  ) async {
    await prefs.remove('ws_last_payload_summary');
    await prefs.remove('ws_last_local_notification_trigger_at');
    await prefs.remove('ws_last_local_notification_trigger_type');
  }

  Future<void> _recordDiagnostic(Map<String, Object?> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearLegacySensitiveDiagnostics(prefs);
      for (final entry in values.entries) {
        final value = entry.value;
        if (value == null) {
          await prefs.remove(entry.key);
        } else {
          await prefs.setString(entry.key, value.toString());
        }
      }
    } catch (error) {
      debugPrint(
        '[WS] diagnostic write failed '
        '(exception_type=${error.runtimeType})',
      );
    }
  }

  static String _uriForToken(String token) {
    final wsUrl = AppConfig.wsUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    return '$wsUrl?access_token=$token';
  }

  /// 初始化连接（通常在登录成功后调用）
  Future<void> connect() async {
    if (_isDisposed || !_connectionCoordinator.isAppInForeground) return;
    final token = ApiClient.token;
    if (token == null || token.trim().isEmpty) {
      debugPrint('[WS] ❗ no token, skip connect');
      return;
    }
    _ensureConnectivityListener();
    debugPrint('[WS] 🔌 connecting to ${AppConfig.wsUrl}');
    try {
      await _connectionCoordinator.connect();
      debugPrint('[WS] ✅ client.connect() completed');
    } catch (e, stack) {
      debugPrint('[WS] ❌ connect threw: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  void _onConnectionStateChange(ConnectionState state) {
    if (_isDisposed) return;
    debugPrint('[WS] state → ${state.name}');
    final connected = state == ConnectionState.authenticated;
    if (_isConnected != connected) {
      _isConnected = connected;
      _connectionController.add(connected);
      unawaited(_recordDiagnostic({'ws_is_connected': connected}));
      if (connected) {
        debugPrint('[WS] ✅ 已连接（认证成功）');
        DataLayer().flushOfflineQueue();
        _connectionCoordinator.markFrameReceived();
        _startHealthCheck();
      } else {
        debugPrint('[WS] ❌ 已断开');
        _stopHealthCheck();
      }
    }
  }

  /// 启动定期健康检查：兜底捕获僵死连接。
  /// 心跳 ping/pong 已是主要保活机制，这里只防极端情况（定时器异常、
  /// socket 半开等）。若 90s 内未收到任何 WS 帧且网络在线，强制重连。
  void _startHealthCheck() {
    if (_isDisposed) return;
    _stopHealthCheck();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      unawaited(_connectionCoordinator.runHealthCheck(
        online: ConnectivityService().isOnline,
      ));
    });
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// 订阅网络状态：网络从离线恢复到在线时，立即发起一次重连，
  /// 而不是被动等待 20s 心跳 × 3 次未响应（~60s+）才重连。
  /// 这是「用户切网络后 WS 经常断开、很久才恢复」的关键修复，
  /// 也是「有网就不断 WS」的主动保障。
  void _ensureConnectivityListener() {
    if (_isDisposed || _connectivitySub != null) return;
    ConnectivityService().start();
    _connectivitySub = ConnectivityService().isOnlineStream.listen((online) {
      debugPrint('[WS] connectivity → online=$online, connected=$_isConnected');
      unawaited(_connectionCoordinator.onConnectivityChanged(online));
    });
  }

  /// 强制重连。后台或未认证时保持 no-op。
  Future<void> forceReconnect() async {
    if (_isDisposed || !_connectionCoordinator.isAppInForeground) return;
    final token = ApiClient.token;
    if (token == null || token.trim().isEmpty) return;
    _ensureConnectivityListener();
    debugPrint('[WS] 🔄 force reconnect (network recovered / app resumed)');
    try {
      await _connectionCoordinator.forceReconnect();
    } catch (e, stack) {
      debugPrint('[WS] force reconnect error: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }

  @visibleForTesting
  void handleInboundEventForTesting(
    Map<String, dynamic> payload,
    int seq,
  ) {
    _onMessage(payload, seq);
  }

  /// 处理收到的推送消息（payload 来自 {type:'message', seq, payload:{event:...}} 的内层）
  void _onMessage(Map<String, dynamic> payload, int seq) {
    if (_isDisposed) return;
    final event = payload['event'] as String?;
    final innerData = payload['data'];
    debugPrint('WebSocket: received event=$event seq=$seq');
    // 记录最近收到帧的时间，供健康检查判断连接是否僵死
    _connectionCoordinator.markFrameReceived();
    unawaited(_recordDiagnostic({
      'ws_last_event': event ?? '',
      'ws_last_event_at': DateTime.now().toIso8601String(),
      'ws_last_seq': seq,
      'ws_is_app_in_foreground': _connectionCoordinator.isAppInForeground,
      'ws_is_connected': _isConnected,
    }));

    switch (event) {
      case 'new_message':
        final msgData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : <String, dynamic>{});
        var normalized = <String, dynamic>{
          ...msgData,
          if (msgData['conversation_id'] != null)
            'conversation_id': msgData['conversation_id'],
          if (msgData['data'] is Map)
            ...Map<String, dynamic>.from(msgData['data'] as Map),
        };
        if (normalized['conversation_id'] == null &&
            payload['conversation_id'] != null) {
          normalized['conversation_id'] = payload['conversation_id'];
        }
        if (normalized['data'] == null) {
          normalized['data'] = msgData;
        }
        if (normalized['message_type'] == null && normalized['type'] != null) {
          normalized['message_type'] = normalized['type'];
        }
        if (normalized['content'] == null && normalized['text'] != null) {
          normalized['content'] = normalized['text'];
        }
        if (normalized['sender_id'] == null && normalized['user_id'] != null) {
          normalized['sender_id'] = normalized['user_id'];
        }
        normalized = Message.normalizeJson(normalized);
        if (normalized['message_type'] == null) {
          normalized['message_type'] = 'text';
        }
        // 不用当前时间兜底缺失的 created_at；历史/异常消息缺少服务端时间时，
        // 交给 Message.fromJson 返回 null，并在时间轴排序中落到最早位置。
        // 否则旧消息会被伪装成“刚刚”，长期停在私聊底部。
        // Notifier 需要 event 字段；MessagesNotifier 读 data 子对象，ConversationsNotifier 读顶层字段
        _messageController.add({
          'event': 'new_message',
          'conversation_id': normalized['conversation_id'],
          if (payload['unread_count'] != null)
            'unread_count': payload['unread_count'],
          'data': normalized,
          ...normalized,
        });
        // 提醒：收到他人发来的新消息、且当前不在该聊天室时，播放通知音 + 震动，
        // 让用户即使不在线也能感知到新消息（之前只有 new_notification 才有声音）。
        try {
          final convIdRaw = normalized['conversation_id'];
          final convIdInt = convIdRaw is int
              ? convIdRaw
              : (int.tryParse(convIdRaw?.toString() ?? '') ?? 0);
          final isConvOpen = convIdInt != 0 &&
              (_isConversationOpen?.call(convIdInt) ??
                  ChatRoomState.isOpen(convIdInt));
          // 是否本人发送的消息回显（不提醒自己）
          final senderId = normalized['sender_id'];
          final myId = LocalDbService().currentUserId;
          final effectiveMyId = _currentUserIdProvider?.call() ?? myId;
          final isOwn = senderId != null &&
              effectiveMyId != null &&
              senderId.toString() == effectiveMyId;
          final token = ApiClient.token;
          if (!_connectionCoordinator.isAppInForeground) {
            unawaited(_recordDiagnostic({
              'ws_last_notification_decision':
                  'background_push_handles_message_alert',
            }));
          } else {
            if (!isConvOpen && !isOwn && token != null && token.isNotEmpty) {
              final playNotificationSound = _playNotificationSound;
              if (playNotificationSound != null) {
                playNotificationSound();
              } else {
                SoundService().playNotificationSound();
              }
              final performLightImpact = _performLightImpact;
              if (performLightImpact != null) {
                performLightImpact();
              } else {
                HapticFeedback.lightImpact();
              }
              unawaited(_recordDiagnostic({
                'ws_last_notification_decision':
                    'foreground_in_app_message_alert',
              }));
            } else {
              final reason = isConvOpen
                  ? 'skipped_open_conversation'
                  : (isOwn ? 'skipped_own_message' : 'skipped_no_token');
              unawaited(
                  _recordDiagnostic({'ws_last_notification_decision': reason}));
            }
          }
        } catch (error) {
          debugPrint(
            '[WS] in-app message effect failed '
            '(exception_type=${error.runtimeType})',
          );
        }
        break;

      case 'message_read':
      case 'conversation_read':
        final readData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : payload);
        _messageController.add({
          'event': event,
          'conversation_id': readData['conversation_id'],
          ...readData,
        });
        break;

      case 'session_list':
        // 认证成功后服务端自动推送会话列表
        final sessions = (innerData is Map ? innerData['sessions'] : null) ??
            payload['sessions'];
        if (sessions is List) {
          _sessionListController.add(
            sessions
                .whereType<Map>()
                .map((s) => Map<String, dynamic>.from(s))
                .toList(),
          );
        }
        break;

      case 'friend_online':
        final onlineData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : payload);
        _friendOnlineController.add(onlineData);
        if (_connectionCoordinator.isAppInForeground) {
          final playOnlineSound = _playOnlineSound;
          if (playOnlineSound != null) {
            playOnlineSound();
          } else {
            SoundService().playOnlineSound();
          }
        }
        break;

      case 'friend_offline':
        final offlineData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : payload);
        _friendOfflineController.add(offlineData);
        break;

      case 'online_friends':
        final friendsData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : payload);
        _onlineFriendsController.add(friendsData);
        break;

      case 'community_member_presence':
        final presenceData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : payload);
        _communityPresenceController.add(presenceData);
        break;

      case 'new_notification':
      case 'notifications_read':
        final notifData = innerData is Map<String, dynamic>
            ? Map<String, dynamic>.from(innerData)
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : Map<String, dynamic>.from(payload));
        final rawNotification = notifData['notification'];
        if (rawNotification is Map) {
          notifData['notification'] =
              Map<String, dynamic>.from(rawNotification);
        }
        _notificationController.add({
          'event': event,
          ...notifData,
        });
        if (event == 'new_notification') {
          if (_connectionCoordinator.isAppInForeground) {
            final playNotificationSound = _playNotificationSound;
            if (playNotificationSound != null) {
              playNotificationSound();
            } else {
              SoundService().playNotificationSound();
            }
          }
          unawaited(_recordDiagnostic({
            'ws_last_notification_decision':
                _connectionCoordinator.isAppInForeground
                    ? 'foreground_in_app_interaction_alert'
                    : 'background_push_handles_interaction_alert',
          }));
        }
        break;

      case 'typing':
      case 'stop_typing':
        final typingData = innerData is Map<String, dynamic>
            ? Map<String, dynamic>.from(innerData)
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : Map<String, dynamic>.from(payload));
        typingData['event'] ??= event;
        _messageController.add(typingData);
        _typingController.add(typingData);
        break;

      case 'friend_accepted_chat':
        // 好友通过后服务端推送新会话 + Hi 消息。
        // payload 顶层携带 conversation / message（无 event/data 包裹），
        // 这里标准化后转发给 ConversationsNotifier / MessagesNotifier。
        final conv = payload['conversation'];
        final hiMsg = payload['message'];
        final convId = conv is Map ? conv['id'] : null;
        debugPrint('[WS] friend_accepted_chat convId=$convId');
        _messageController.add({
          'event': 'friend_accepted_chat',
          'conversation': conv is Map ? Map<String, dynamic>.from(conv) : null,
          'message': hiMsg is Map ? Map<String, dynamic>.from(hiMsg) : null,
          if (convId != null) 'conversation_id': convId,
        });
        break;

      case 'message_recalled':
        final recallData = innerData is Map<String, dynamic>
            ? Map<String, dynamic>.from(innerData)
            : (innerData is Map
                ? Map<String, dynamic>.from(innerData)
                : Map<String, dynamic>.from(payload));
        // 同时推给 messageStream，ConversationsNotifier 和 MessagesNotifier 都能收到
        _messageController.add({
          'event': 'message_recalled',
          'conversation_id': recallData['conversation_id'],
          ...recallData,
        });
        break;

      default:
        debugPrint('WebSocket: unhandled event=$event');
    }
  }

  /// 断开连接（通常在注销时调用）
  Future<void> disconnect() async {
    debugPrint('[WS] disconnecting');
    _stopHealthCheck();
    final connectivitySub = _connectivitySub;
    _connectivitySub = null;
    try {
      if (connectivitySub != null) {
        await _attemptShutdown(
          'connectivity subscription cancellation',
          connectivitySub.cancel,
        );
      }
      await _attemptShutdown(
        'connection coordinator disconnect',
        _connectionCoordinator.disconnect,
      );
    } finally {
      final wasConnected = _isConnected;
      _isConnected = false;
      if (wasConnected && !_isDisposed && !_connectionController.isClosed) {
        _connectionController.add(false);
      }
    }
  }

  /// 加入会话房间
  void joinConversation(int conversationId) {
    _sendRaw({
      'type': 'join',
      'payload': {'conversation_id': conversationId}
    });
  }

  /// 离开会话房间
  void leaveConversation(int conversationId) {
    _sendRaw({
      'type': 'leave',
      'payload': {'conversation_id': conversationId}
    });
  }

  /// 通过 WebSocket 发送聊天消息（经发件箱 + ACK 可靠发送）
  Future<String> sendMessage(
    int conversationId,
    String content, {
    String messageType = 'text',
    String? mediaUrl,
    int? relatedId,
    String? receiverId,
    int? quoteMessageId,
    String? quotePreview,
  }) {
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'content': content,
      'message_type': messageType,
    };
    if (quoteMessageId != null) payload['quote_message_id'] = quoteMessageId;
    if (quotePreview != null) payload['quote_preview'] = quotePreview;
    if (mediaUrl != null) payload['media_url'] = mediaUrl;
    if (relatedId != null) payload['related_id'] = relatedId;
    if (receiverId != null) payload['receiver_id'] = int.parse(receiverId);
    return _send(payload);
  }

  /// 发送"正在输入"状态
  void sendTyping(int conversationId) {
    _sendRaw({
      'type': 'typing',
      'payload': {'conversation_id': conversationId}
    });
  }

  /// 发送"停止输入"状态
  void sendStopTyping(int conversationId) {
    _sendRaw({
      'type': 'stop_typing',
      'payload': {'conversation_id': conversationId}
    });
  }

  /// 标记会话消息为已读
  Future<String> markConversationRead(int conversationId) {
    _sendRaw({
      'type': 'send_event',
      'payload': {
        'event': 'conversation_read',
        'conversation_id': conversationId,
      },
    });
    return Future.value('');
  }

  /// 撤回消息
  void sendRecallMessage(int messageId) {
    _sendRaw({
      'type': 'recall_message',
      'payload': {
        'message_id': messageId,
      },
    });
  }

  /// 可靠发送（经发件箱，带 ACK）
  Future<String> _send(Map<String, dynamic> payload) async {
    if (_isDisposed) return '';
    final client = _connectionCoordinator.client;
    if (!_isConnected || client == null) return '';
    try {
      return await client.send(payload);
    } catch (e) {
      debugPrint('WebSocket: send error $e');
      return '';
    }
  }

  /// 原始帧发送（fire-and-forget，用于 join/leave/typing 等控制帧）
  void _sendRaw(Map<String, dynamic> frame) {
    if (_isDisposed) return;
    final client = _connectionCoordinator.client;
    if (!_isConnected || client == null) return;
    client.sendRaw(frame);
  }

  Future<void> dispose() {
    final existingTask = _disposeTask;
    if (existingTask != null) return existingTask;
    _isDisposed = true;
    _connectionCoordinator.setAppForeground(false);
    _stopHealthCheck();
    return _disposeTask = _dispose();
  }

  Future<void> _dispose() async {
    try {
      await disconnect();
    } catch (error, stack) {
      debugPrint('[WS] disconnect failed during disposal: $error');
      debugPrint(stack.toString());
    } finally {
      await Future.wait(<Future<void>>[
        _closeController('message controller', _messageController),
        _closeController('notification controller', _notificationController),
        _closeController('typing controller', _typingController),
        _closeController('connection controller', _connectionController),
        _closeController('session list controller', _sessionListController),
        _closeController('error controller', _errorController),
        _closeController('auth expired controller', _authExpiredController),
        _closeController('friend online controller', _friendOnlineController),
        _closeController('friend offline controller', _friendOfflineController),
        _closeController('online friends controller', _onlineFriendsController),
        _closeController(
          'community presence controller',
          _communityPresenceController,
        ),
        _closeController('ack message id controller', _ackMessageIdController),
        _closeController('send error controller', _sendErrorController),
      ]);
    }
  }

  Future<void> _closeController(
    String name,
    StreamController<dynamic> controller,
  ) {
    if (controller.isClosed) return Future<void>.value();
    return _attemptShutdown(name, controller.close);
  }

  Future<void> _attemptShutdown(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action().timeout(_shutdownTimeout);
    } catch (error, stack) {
      debugPrint('[WS] $operation failed during shutdown: $error');
      debugPrint(stack.toString());
    }
  }
}
