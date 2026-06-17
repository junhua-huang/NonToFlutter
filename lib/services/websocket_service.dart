import 'dart:async';

import 'package:nonto/config/app_config.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/connectivity_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/sound_service.dart';
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
  Future<void>? _connecting;

  // 事件流控制器
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _sessionListController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _authExpiredController = StreamController<String>.broadcast();
  final _friendOnlineController = StreamController<Map<String, dynamic>>.broadcast();
  final _friendOfflineController = StreamController<Map<String, dynamic>>.broadcast();
  final _onlineFriendsController = StreamController<Map<String, dynamic>>.broadcast();
  final _ackMessageIdController = StreamController<Map<String, dynamic>>.broadcast();
  final _sendErrorController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<List<Map<String, dynamic>>> get sessionListStream => _sessionListController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// 认证失效流（JWT 过期/被踢下线/认证失败），业务层监听后执行注销
  Stream<String> get authExpiredStream => _authExpiredController.stream;

  /// 好友上线流
  Stream<Map<String, dynamic>> get friendOnlineStream => _friendOnlineController.stream;

  /// 好友下线流
  Stream<Map<String, dynamic>> get friendOfflineStream => _friendOfflineController.stream;

  /// 在线好友批量推送流（认证时服务端推送当前所有在线好友）
  Stream<Map<String, dynamic>> get onlineFriendsStream => _onlineFriendsController.stream;

  /// ACK 携带 message_id 流
  Stream<Map<String, dynamic>> get ackMessageIdStream => _ackMessageIdController.stream;

  /// 发送错误流（携带 clientMsgId，用于 ChatSendQueue 匹配失败消息）
  Stream<Map<String, dynamic>> get sendErrorStream => _sendErrorController.stream;

  bool get isConnected => _isConnected;

  /// 初始化连接（通常在登录成功后调用）
  Future<void> connect() async {
    final token = ApiClient.token;
    if (token == null || token.isEmpty) {
      debugPrint('[WS] ❗ no token, skip connect');
      return;
    }
    if (_isConnected) {
      debugPrint('[WS] ⚠️ already connected, skip');
      return;
    }
    final pending = _connecting;
    if (pending != null) {
      debugPrint('[WS] ⚠️ connect already in progress, await existing');
      await pending;
      return;
    }
    _connecting = _connectInternal(token);
    try {
      await _connecting;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _connectInternal(String token) async {
    // 断开旧连接，避免登录/重登期间产生多个 ReliableWebSocketClient 同时收同一条 seq。
    await _client?.disconnect();

    final wsUrl = AppConfig.wsUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    // 带 token query 参数兼容连接层的低层鉴权
    final uri = '$wsUrl/ws?access_token=$token';

    debugPrint('[WS] 🔌 connecting to $wsUrl/ws');

    _client = ReliableWebSocketClient(
      url: uri,
      getToken: () async => ApiClient.token ?? '',
      onMessage: _onMessage,
      onAckMessageId: (clientMsgId, messageId) {
        _ackMessageIdController.add({'clientMsgId': clientMsgId, 'message_id': messageId});
        _messageController.add({
          'event': 'ack',
          'clientMsgId': clientMsgId,
          'client_msg_id': clientMsgId,
          'message_id': messageId,
        });
      },
      onConnectionStateChange: _onConnectionStateChange,
      onError: (message, clientMsgId) {
        debugPrint('[WS] server error: $message (clientMsgId=$clientMsgId)');
        _errorController.add(message);
        if (clientMsgId != null && clientMsgId.isNotEmpty) {
          _sendErrorController.add({'clientMsgId': clientMsgId, 'error': message});
        }
      },
      onAuthFailed: (error) {
        debugPrint('[WS] ❗ auth failed/expired: $error');
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
      debugPrint('[WS] ✅ client.connect() completed');
    } catch (e, stack) {
      debugPrint('[WS] ❌ connect threw: $e');
      debugPrint(stack.toString());
    }
  }

  void _onConnectionStateChange(ConnectionState state) {
    debugPrint('[WS] state → ${state.name}');
    final connected = state == ConnectionState.authenticated;
    if (_isConnected != connected) {
      _isConnected = connected;
      _connectionController.add(connected);
      if (connected) {
        debugPrint('[WS] ✅ 已连接（认证成功）');
        DataLayer().flushOfflineQueue();
      } else {
        debugPrint('[WS] ❌ 已断开');
      }
    }
  }

  /// 处理收到的推送消息（payload 来自 {type:'message', seq, payload:{event:...}} 的内层）
  void _onMessage(Map<String, dynamic> payload, int seq) {
    final event = payload['event'] as String?;
    final innerData = payload['data'];
    debugPrint('WebSocket: received event=$event seq=$seq');

    switch (event) {
      case 'new_message':
        final msgData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : <String, dynamic>{});
        final normalized = <String, dynamic>{
          ...msgData,
          if (msgData['conversation_id'] != null) 'conversation_id': msgData['conversation_id'],
          if (msgData['data'] is Map) ...Map<String, dynamic>.from(msgData['data'] as Map),
        };
        if (normalized['conversation_id'] == null && payload['conversation_id'] != null) {
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
        if (normalized['message_type'] == null) {
          normalized['message_type'] = 'text';
        }
        if (normalized['created_at'] == null) {
          normalized['created_at'] = DateTime.now().toIso8601String();
        }
        // Notifier 需要 event 字段；MessagesNotifier 读 data 子对象，ConversationsNotifier 读顶层字段
        _messageController.add({
          'event': 'new_message',
          'conversation_id': normalized['conversation_id'],
          'data': normalized,
          ...normalized,
        });
        break;

      case 'message_read':
      case 'conversation_read':
        final readData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : payload);
        _messageController.add({
          'event': event,
          'conversation_id': readData['conversation_id'],
          ...readData,
        });
        break;

      case 'session_list':
        // 认证成功后服务端自动推送会话列表
        final sessions = (innerData is Map ? innerData['sessions'] : null) ?? payload['sessions'];
        if (sessions is List) {
          _sessionListController.add(
            sessions.whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList(),
          );
        }
        break;

      case 'friend_online':
        final onlineData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : payload);
        _friendOnlineController.add(onlineData);
        SoundService().playOnlineSound();
        break;

      case 'friend_offline':
        final offlineData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : payload);
        _friendOfflineController.add(offlineData);
        break;

      case 'online_friends':
        final friendsData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : payload);
        _onlineFriendsController.add(friendsData);
        break;

      case 'new_notification':
      case 'notifications_read':
        final notifData = innerData is Map<String, dynamic>
            ? Map<String, dynamic>.from(innerData)
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : Map<String, dynamic>.from(payload));
        final rawNotification = notifData['notification'];
        if (rawNotification is Map) {
          notifData['notification'] = Map<String, dynamic>.from(rawNotification);
        }
        _notificationController.add({
          'event': event,
          ...notifData,
        });
        if (event == 'new_notification') {
          SoundService().playNotificationSound();
        }
        break;

      case 'typing':
      case 'stop_typing':
        final typingData = innerData is Map<String, dynamic>
            ? Map<String, dynamic>.from(innerData)
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : Map<String, dynamic>.from(payload));
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
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : Map<String, dynamic>.from(payload));
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
    _connecting = null;
    final client = _client;
    _client = null;
    await client?.disconnect();
    if (_isConnected) {
      _isConnected = false;
      _connectionController.add(false);
    }
  }

  /// 加入会话房间
  void joinConversation(int conversationId) {
    _sendRaw({'type': 'join', 'payload': {'conversation_id': conversationId}});
  }

  /// 离开会话房间
  void leaveConversation(int conversationId) {
    _sendRaw({'type': 'leave', 'payload': {'conversation_id': conversationId}});
  }

  /// 通过 WebSocket 发送聊天消息（经发件箱 + ACK 可靠发送）
  Future<String> sendMessage(int conversationId, String content, {
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
    _sendRaw({'type': 'typing', 'payload': {'conversation_id': conversationId}});
  }

  /// 发送"停止输入"状态
  void sendStopTyping(int conversationId) {
    _sendRaw({'type': 'stop_typing', 'payload': {'conversation_id': conversationId}});
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
    _friendOnlineController.close();
    _friendOfflineController.close();
    _onlineFriendsController.close();
    _sendErrorController.close();
  }
}
