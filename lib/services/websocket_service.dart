import 'dart:async';
import 'dart:convert';

import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 全局 WebSocket 服务，管理原生 WebSocket 连接
/// 支持聊天消息、通知推送的实时功能
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._();
  factory WebSocketService() => _instance;
  WebSocketService._();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isReconnecting = false;
  int _connectionId = 0;
  String? _currentToken;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _pingInterval = Duration(seconds: 25);

  // 事件流控制器
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _isConnected;

  /// 初始化连接（通常在登录成功后调用）
  void connect() {
    final token = ApiClient.token;
    if (token == null || token.isEmpty) {
      debugPrint('WebSocket: no token, skip connect');
      return;
    }
    if (_isConnected && _currentToken == token) {
      return;
    }

    _disconnectInternal();
    _currentToken = token;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    if (_currentToken == null) return;
    _connectionId++;
    final thisConnectionId = _connectionId;

    final wsUrl =
        AppConfig.wsUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/ws?token=$_currentToken');

    debugPrint('WebSocket: connecting to $uri (connId=$thisConnectionId)');

    try {
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          debugPrint('WebSocket: stream error connId=$thisConnectionId curId=$_connectionId: $error');
          if (_connectionId != thisConnectionId) return;
          _handleConnectionLoss();
        },
        onDone: () {
          debugPrint('WebSocket: stream done connId=$thisConnectionId curId=$_connectionId');
          if (_connectionId != thisConnectionId) return;
          _handleConnectionLoss();
        },
        cancelOnError: false,
      );

      _channel!.ready.then((_) {
        debugPrint('WebSocket: ready connId=$thisConnectionId curId=$_connectionId');
        if (_connectionId != thisConnectionId) return;
        debugPrint('WebSocket: connected successfully');
        _isConnected = true;
        _isReconnecting = false;
        _reconnectAttempts = 0;
        _connectionController.add(true);
        _startPing();
      }).catchError((e, stack) {
        debugPrint('WebSocket: ready failed connId=$thisConnectionId curId=$_connectionId: $e');
        debugPrint('WebSocket: stack trace: $stack');
        if (_connectionId != thisConnectionId) return;
        _handleConnectionLoss();
      });
    } catch (e, stack) {
      debugPrint('WebSocket: init error connId=$thisConnectionId: $e');
      debugPrint('WebSocket: stack trace: $stack');
      if (_connectionId != thisConnectionId) return;
      _handleConnectionLoss();
    }
  }

  void _handleConnectionLoss() {
    _isConnected = false;
    _stopPing();
    _connectionController.add(false);
    _scheduleReconnect();
  }

  void _onMessage(dynamic data) {
    try {
      final Map<String, dynamic> msg;
      if (data is String) {
        msg = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map) {
        msg = Map<String, dynamic>.from(data);
      } else {
        return;
      }

      final type = msg['type'] as String?;
      debugPrint('WebSocket: received type=$type');

      switch (type) {
        case 'new_message':
        case 'conversation_read':
          _messageController.add(msg);
          SoundService().playNotificationSound();
          break;
        case 'new_notification':
        case 'notifications_read':
          _notificationController.add(msg);
          SoundService().playNotificationSound();
          break;
        case 'friend_online':
          SoundService().playOnlineSound();
          break;
        case 'typing':
        case 'stop_typing':
          _typingController.add(msg);
          break;
        case 'connected':
        case 'pong':
          break;
        default:
          debugPrint('WebSocket: unhandled type=$type');
      }
    } catch (e) {
      debugPrint('WebSocket: parse error $e');
    }
  }

  void _startPing() {
    _stopPing();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_isConnected) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    if (_isReconnecting) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WebSocket: max reconnect attempts reached');
      return;
    }
    _isReconnecting = true;
    _reconnectAttempts++;
    debugPrint(
        'WebSocket: reconnect $_reconnectAttempts/$_maxReconnectAttempts in ${_reconnectDelay.inSeconds}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _isReconnecting = false;
      if (!_isConnected) {
        _doConnect();
      }
    });
  }

  void _disconnectInternal() {
    _stopPing();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _connectionId++;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
    _reconnectAttempts = 0;
  }

  /// 断开连接（通常在注销时调用）
  void disconnect() {
    _disconnectInternal();
    _currentToken = null;
  }

  /// 加入会话房间
  void joinConversation(int conversationId) {
    _send({'type': 'join', 'conversation_id': conversationId});
  }

  /// 离开会话房间
  void leaveConversation(int conversationId) {
    _send({'type': 'leave', 'conversation_id': conversationId});
  }

  /// 通过 WebSocket 发送消息
  void sendMessage(int conversationId, String content, {String messageType = 'text'}) {
    _send({
      'type': 'send_message',
      'conversation_id': conversationId,
      'content': content,
      'message_type': messageType,
    });
  }

  /// 发送"正在输入"状态
  void sendTyping(int conversationId) {
    _send({'type': 'typing', 'conversation_id': conversationId});
  }

  /// 发送"停止输入"状态
  void sendStopTyping(int conversationId) {
    _send({'type': 'stop_typing', 'conversation_id': conversationId});
  }

  /// 发送 JSON 数据到 WebSocket
  void _send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('WebSocket: send error $e');
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _notificationController.close();
    _typingController.close();
    _connectionController.close();
  }
}
