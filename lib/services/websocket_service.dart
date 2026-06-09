import 'dart:async';

import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:facebook_clone/services/sound_service.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:reliable_websocket/reliable_websocket.dart';

/// 全局 WebSocket 服务，内部使用 ReliableWebSocketClient
/// 支持聊天消息、通知推送的实时功能
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._();
  factory WebSocketService() => _instance;
  WebSocketService._();

  ReliableWebSocketClient? _client;
  bool _isConnected = false;

  // 事件流控制器
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _sessionListController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _authExpiredController = StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<List<Map<String, dynamic>>> get sessionListStream => _sessionListController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// 认证失效流（JWT 过期/被踢下线/认证失败），业务层监听后执行注销
  Stream<String> get authExpiredStream => _authExpiredController.stream;

  bool get isConnected => _isConnected;

  /// 初始化连接（通常在登录成功后调用）
  Future<void> connect() async {
    final token = ApiClient.token;
    if (token == null || token.isEmpty) {
      print('[WS] ❗ no token, skip connect');
      return;
    }
    if (_isConnected) {
      print('[WS] ⚠️ already connected, skip');
      return;
    }

    // 断开旧连接
    await _client?.disconnect();

    final wsUrl = AppConfig.wsUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    // 后端协议：连接不带 token，认证通过 auth 消息完成（reliable_websocket 自动处理）
    final uri = '$wsUrl/ws';

    print('[WS] 🔌 connecting to $uri (token=${token.substring(0, 12)}...)');

    _client = ReliableWebSocketClient(
      url: uri,
      getToken: () async => ApiClient.token ?? '',
      onMessage: _onMessage,
      onConnectionStateChange: _onConnectionStateChange,
      onError: (message, clientMsgId) {
        print('[WS] server error: $message (clientMsgId=$clientMsgId)');
        _errorController.add(message);
      },
      onAuthFailed: (error) {
        print('[WS] ❗ auth failed/expired: $error');
        if (_isConnected) {
          _isConnected = false;
          _connectionController.add(false);
        }
        // 通知业务层（AuthNotifier）执行注销
        _authExpiredController.add(error ?? 'auth_failed');
      },
    );

    try {
      await _client!.connect();
      print('[WS] ✅ client.connect() completed');
    } catch (e, stack) {
      print('[WS] ❌ connect threw: $e');
      print(stack);
    }
  }

  void _onConnectionStateChange(ConnectionState state) {
    print('[WS] state → ${state.name}');
    final connected = state == ConnectionState.authenticated;
    if (_isConnected != connected) {
      _isConnected = connected;
      _connectionController.add(connected);
      if (connected) {
        print('[WS] ✅ 已连接（认证成功）');
        DataLayer().flushOfflineQueue();
      } else {
        print('[WS] ❌ 已断开');
      }
    }
  }

  /// 处理收到的推送消息（payload 来自 {type:'message', seq, payload:{event:...}} 的内层）
  void _onMessage(Map<String, dynamic> payload, int seq) {
    // 后端协议：payload 内用 event 字段标识事件类型
    final event = payload['event'] as String?;
    debugPrint('WebSocket: received event=$event seq=$seq');

    switch (event) {
      case 'new_message':
        _messageController.add(payload);
        SoundService().playNotificationSound();
        break;

      case 'message_read':
        // 对方标记消息已读（已读回执）
        _messageController.add(payload);
        break;

      case 'conversation_read':
        // 会话已读确认（含全局未读数）
        _messageController.add(payload);
        break;

      case 'session_list':
        // 认证成功后服务端自动推送会话列表
        final sessions = payload['sessions'];
        if (sessions is List) {
          _sessionListController.add(
            sessions.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
          );
        }
        break;

      case 'new_notification':
        _notificationController.add(payload);
        SoundService().playNotificationSound();
        break;

      case 'typing':
      case 'stop_typing':
        _typingController.add(payload);
        break;

      default:
        debugPrint('WebSocket: unhandled event=$event');
    }
  }

  /// 断开连接（通常在注销时调用）
  Future<void> disconnect() async {
    print('[WS] disconnecting');
    await _client?.disconnect();
    _isConnected = false;
  }

  /// 加入会话房间（fire-and-forget，不经过发件箱）
  void joinConversation(int conversationId) {
    _sendRaw({'type': 'join', 'conversation_id': conversationId});
  }

  /// 离开会话房间（fire-and-forget）
  void leaveConversation(int conversationId) {
    _sendRaw({'type': 'leave', 'conversation_id': conversationId});
  }

  /// 通过 WebSocket 发送聊天消息（经发件箱 + ACK 可靠发送）
  Future<String> sendMessage(int conversationId, String content, {
    String messageType = 'text',
    String? mediaUrl,
    int? relatedId,
    String? receiverId,
  }) {
    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'content': content,
      'message_type': messageType,
    };
    if (mediaUrl != null) payload['media_url'] = mediaUrl;
    if (relatedId != null) payload['related_id'] = relatedId;
    if (receiverId != null) payload['receiver_id'] = int.parse(receiverId);
    return _send(payload);
  }

  /// 发送"正在输入"状态（fire-and-forget）
  void sendTyping(int conversationId) {
    _sendRaw({'type': 'typing', 'conversation_id': conversationId});
  }

  /// 发送"停止输入"状态（fire-and-forget）
  void sendStopTyping(int conversationId) {
    _sendRaw({'type': 'stop_typing', 'conversation_id': conversationId});
  }

  /// 标记会话消息为已读（经发件箱可靠发送）
  Future<String> markConversationRead(int conversationId) {
    return _send({
      'event': 'conversation_read',
      'conversation_id': conversationId,
    });
  }

  /// 可靠发送（经发件箱，带 ACK）
  Future<String> _send(Map<String, dynamic> payload) async {
    if (!_isConnected || _client == null) return '';
    try {
      return await _client!.send(payload);
    } catch (e) {
      debugPrint('WebSocket: send error $e');
      return '';
    }
  }

  /// 原始帧发送（fire-and-forget，用于 join/leave/typing 等控制帧）
  void _sendRaw(Map<String, dynamic> frame) {
    if (!_isConnected || _client == null) return;
    _client!.sendRaw(frame);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _notificationController.close();
    _typingController.close();
    _connectionController.close();
    _sessionListController.close();
    _errorController.close();
    _authExpiredController.close();
  }
}
