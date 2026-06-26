import 'dart:async';

import 'package:nonto/config/app_config.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/connectivity_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/local_db_service.dart';
import 'package:nonto/services/sound_service.dart';
import 'package:nonto/providers/chat_room_state.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
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
  // 网络恢复监听：网络从离线→在线时主动重连，避免等心跳超时（60s+）才重连。
  // 之前用户切 WiFi/4G 后要等很久才恢复 WS，是「经常断开」的主因之一。
  StreamSubscription<bool>? _connectivitySub;
  // 定期健康检查：兜底捕获「socket 看似 authenticated 实则僵死」的极端情况
  // （心跳 ping 发出去了但 pong 永不返回、且心跳定时器被异常取消等）。
  // 每 90s 检查一次：若长时间未收到任何 WS 帧，强制重连。
  Timer? _healthCheckTimer;
  // 最近一次收到 WS 帧的时间，用于健康判断。
  DateTime _lastFrameAt = DateTime.now();

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
  final _communityPresenceController = StreamController<Map<String, dynamic>>.broadcast();
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

  /// 社群成员 App 在线状态变化流
  Stream<Map<String, dynamic>> get communityPresenceStream => _communityPresenceController.stream;

  /// ACK 携带 message_id 流
  Stream<Map<String, dynamic>> get ackMessageIdStream => _ackMessageIdController.stream;

  /// 发送错误流（携带 clientMsgId，用于 ChatSendQueue 匹配失败消息）
  Stream<Map<String, dynamic>> get sendErrorStream => _sendErrorController.stream;

  bool get isConnected => _isConnected;

  /// 初始化连接（通常在登录成功后调用）
  Future<void> connect() async {
    // 启动网络监听（幂等），网络恢复时主动重连
    _ensureConnectivityListener();
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
    final uri = '$wsUrl?access_token=$token';

    debugPrint('[WS] 🔌 connecting to $wsUrl');

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
      onMessageFailed: (clientMsgId, error) {
        debugPrint('[WS] reliable send failed: $error (clientMsgId=$clientMsgId)');
        _sendErrorController.add({'clientMsgId': clientMsgId, 'error': error});
      },
      onConnectionStateChange: _onConnectionStateChange,
      onError: (message, clientMsgId) {
        debugPrint('[WS] server error: $message (clientMsgId=$clientMsgId)');
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
        _lastFrameAt = DateTime.now();
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
    _stopHealthCheck();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (!_isConnected) return;
      final silentFor = DateTime.now().difference(_lastFrameAt);
      if (silentFor > const Duration(seconds: 90)) {
        final online = ConnectivityService().isOnline;
        debugPrint('[WS] 🩺 health check: no frames for ${silentFor.inSeconds}s, online=$online');
        if (online) {
          // 有网但 90s 无任何帧 → 连接僵死，强制重连
          _forceReconnect();
        }
      }
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
    if (_connectivitySub != null) return;
    ConnectivityService().start();
    _connectivitySub = ConnectivityService().isOnlineStream.listen((online) {
      debugPrint('[WS] connectivity → online=$online, connected=$_isConnected');
      if (online && !_isConnected) {
        // 网络恢复但 WS 没连上：强制重连（旧连接可能已僵死）。
        _forceReconnect();
      }
    });
  }

  /// 强制重连：调用 ReliableWebSocketClient.forceReconnect()，
  /// 无视当前状态重建连接。不会进入 disconnected 终态，保证「有网就不断」。
  /// 公开给 App 回前台、网络恢复等场景调用。
  Future<void> forceReconnect() => _forceReconnect();

  Future<void> _forceReconnect() async {
    final token = ApiClient.token;
    if (token == null || token.isEmpty) return;
    if (_client == null) {
      // 客户端还没建过（首次连接前网络就恢复了）→ 走正常 connect
      debugPrint('[WS] 🔄 force reconnect: no client, normal connect');
      await connect();
      return;
    }
    debugPrint('[WS] 🔄 force reconnect (network recovered / app resumed)');
    _isConnected = false;
    // 清掉进行中的连接 future，允许 connect() 重新进入
    _connecting = null;
    try {
      await _client!.forceReconnect();
    } catch (e) {
      debugPrint('[WS] force reconnect error: $e');
      // 失败也走正常 connect 兜底
      await connect();
    }
  }

  /// 处理收到的推送消息（payload 来自 {type:'message', seq, payload:{event:...}} 的内层）
  void _onMessage(Map<String, dynamic> payload, int seq) {
    final event = payload['event'] as String?;
    final innerData = payload['data'];
    debugPrint('WebSocket: received event=$event seq=$seq');
    // 记录最近收到帧的时间，供健康检查判断连接是否僵死
    _lastFrameAt = DateTime.now();

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
        // 提醒：收到他人发来的新消息、且当前不在该聊天室时，播放通知音 + 震动，
        // 让用户即使不在线也能感知到新消息（之前只有 new_notification 才有声音）。
        try {
          final convIdRaw = normalized['conversation_id'];
          final convIdInt = convIdRaw is int
              ? convIdRaw
              : (int.tryParse(convIdRaw?.toString() ?? '') ?? 0);
          final isConvOpen = convIdInt != 0 && ChatRoomState.isOpen(convIdInt);
          // 是否本人发送的消息回显（不提醒自己）
          final senderId = normalized['sender_id'];
          final myId = LocalDbService().currentUserId;
          final isOwn = senderId != null &&
              myId != null &&
              senderId.toString() == myId;
          final token = ApiClient.token;
          if (!isConvOpen && !isOwn && token != null && token.isNotEmpty) {
            SoundService().playNotificationSound();
            HapticFeedback.lightImpact();
          }
        } catch (_) {}
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

      case 'community_member_presence':
        final presenceData = innerData is Map<String, dynamic>
            ? innerData
            : (innerData is Map ? Map<String, dynamic>.from(innerData) : payload);
        _communityPresenceController.add(presenceData);
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
    _stopHealthCheck();
    _connectivitySub?.cancel();
    _connectivitySub = null;
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
    _communityPresenceController.close();
    _sendErrorController.close();
  }
}
