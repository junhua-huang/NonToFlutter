import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/api/notification_service.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/chat_send_queue.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/sound_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/services/local_db_service.dart';
import 'package:nonto/providers/chat_room_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Conversations Provider ──

class ConversationsState {
  final List<Conversation> conversations;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  const ConversationsState({
    this.conversations = const [],
    this.unreadCount = 0,
    this.isLoading = true,
    this.error,
  });

  ConversationsState copyWith({
    List<Conversation>? conversations,
    int? unreadCount,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ConversationsNotifier extends StateNotifier<ConversationsState> {
  final ChatService _chatService = ChatService();
  final WebSocketService _ws = WebSocketService();
  final Set<int> _processedMessageIds = {};
  static const int _maxProcessedIds = 1000;
  StreamSubscription? _wsMsgSub;
  StreamSubscription? _wsSessionSub;
  StreamSubscription? _wsFriendOnlineSub;
  StreamSubscription? _wsFriendOfflineSub;
  StreamSubscription? _wsOnlineFriendsSub;
  StreamSubscription? _dataSub;
  bool _loadInProgress = false;
  int? _currentUserId;

  ConversationsNotifier() : super(const ConversationsState()) {
    _loadCurrentUserId();
    _loadData();
    _wsMsgSub = _ws.messageStream.listen(_onWsMessage);
    _wsSessionSub = _ws.sessionListStream.listen(_onSessionList);
    _wsFriendOnlineSub = _ws.friendOnlineStream.listen(_onFriendOnline);
    _wsFriendOfflineSub = _ws.friendOfflineStream.listen(_onFriendOffline);
    _wsOnlineFriendsSub = _ws.onlineFriendsStream.listen(_onOnlineFriends);
    _dataSub = DataLayer().changeStream.listen((key) {
      if (key == '__auth:logout') {
        _reset();
      } else if (key == CacheKeys.convFullList) {
        _loadData();
      }
    });
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('current_user_id');
      _currentUserId = raw == null ? null : int.tryParse(raw);
    } catch (_) {}
  }

  /// 先读缓存立即展示，同时后台走网络静默更新
  Future<void> _loadData() async {
    if (!state.isLoading || _loadInProgress) return;
    _loadInProgress = true;
    debugPrint('[Conv] _loadData START');
    // 先读缓存快速展示
    final cached =
        await DataLayer().query(CacheKeys.convFullList, () async => null);
    if (cached.data is List && (cached.data as List).isNotEmpty) {
      debugPrint(
          '[Conv] _loadData: loaded from CACHE, ${(cached.data as List).length} items');
      state = state.copyWith(
        conversations: (cached.data as List)
            .whereType<Map>()
            .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        isLoading: false,
      );
    } else {
      debugPrint(
          '[Conv] _loadData: cache empty or miss, source=${cached.source}');
    }
    // 后台网络请求，静默更新
    unawaited(loadConversations().whenComplete(() => _loadInProgress = false));
  }

  void _onSessionList(List<Map<String, dynamic>> sessions) {
    // WS 推送的字段名是 partner，统一转成 other_user 对齐 Conversation.fromJson
    final normalized =
        sessions.map((e) => Map<String, dynamic>.from(e)).map((s) {
      if (s['partner'] != null && s['other_user'] == null) {
        s['other_user'] = s['partner'];
        s['partner_id'] ??= s['partner']?['id'];
        s['conversation_id'] ??= s['id'];
      }
      return s;
    }).toList();
    final conversations =
        normalized.map((e) => Conversation.fromJson(e)).toList();
    debugPrint(
        '[Conv] _onSessionList: ${conversations.length} sessions from WS');
    state = state.copyWith(conversations: conversations, isLoading: false);
    DataLayer().persistConversations(conversations);
    DataLayer().write(CacheKeys.convFullList, normalized);
    DataLayer().invalidate(CacheKeys.convPattern);
  }

  void _onFriendOnline(Map<String, dynamic> data) {
    final userId = data['user_id'];
    if (userId == null) return;
    final uid = userId is int ? userId : int.tryParse(userId.toString());
    if (uid == null) return;
    _updateOtherUserOnlineStatus(uid, true);
  }

  void _onFriendOffline(Map<String, dynamic> data) {
    final userId = data['user_id'];
    if (userId == null) return;
    final uid = userId is int ? userId : int.tryParse(userId.toString());
    if (uid == null) return;
    _updateOtherUserOnlineStatus(uid, false);
  }

  /// 认证成功后服务端推送当前所有在线好友（解决后上线用户看不到早在线好友的问题）
  void _onOnlineFriends(Map<String, dynamic> data) {
    final userIds = data['user_ids'];
    if (userIds is! List) return;
    for (final uid in userIds) {
      final id = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
      if (id != null) {
        _updateOtherUserOnlineStatus(id, true);
      }
    }
  }

  /// 更新会话列表中指定用户的在线状态
  void _updateOtherUserOnlineStatus(int userId, bool isOnline) {
    final updated = state.conversations.map((c) {
      if (c.otherUser?.id == userId) {
        return Conversation.fromJson({
          ...c.toJson(),
          'other_user': {
            ...?c.otherUser?.toJson(),
            'is_online': isOnline,
          },
        });
      }
      return c;
    }).toList();
    state = state.copyWith(conversations: updated);
  }

  void _onWsMessage(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    // #region agent log
    debugPrint(
        '[Conv] _onWsMessage event=$event keys=${data.keys} convId=${data['conversation_id']}');
    // #endregion
    if (event == 'friend_accepted_chat') {
      // 好友通过 → 服务端推送新会话 + Hi 消息，直接插入会话列表并显示 Hi 预览
      _handleFriendAcceptedChat(data);
      return;
    }
    if (event == 'new_message') {
      final convId = data['conversation_id'] as int?;
      if (convId != null) {
        _handleIncrementalNewMessage(data);
      }
    } else if (event == 'batch_messages') {
      final convId = data['conversation_id'] as int?;
      final messages = data['messages'] as List<dynamic>?;
      if (convId != null && messages != null) {
        _handleBatchMessages(convId, messages);
      }
    } else if (event == 'message_recalled') {
      _handleMessageRecalledConv(data);
    } else if (event == 'conversation_read') {
      // 对方标记已读 → 清除本地未读气泡
      final convId = data['conversation_id'] as int?;
      if (convId != null) {
        clearConversationUnread(convId);
      }
    } else if (data['conversation'] != null) {
      // 兼容旧逻辑：带 conversation 的事件 → 重新拉取会话列表
      debugPrint('[Conv] conversation event received, reloading conversations');
      unawaited(loadConversations());
    }
  }

  /// 处理好友通过后的新会话 + Hi 消息推送。
  /// 直接构造/更新会话项插到列表顶部，避免等 loadConversations() 的往返延迟。
  void _handleFriendAcceptedChat(Map<String, dynamic> data) {
    final convRaw = data['conversation'];
    final msgRaw = data['message'];
    if (convRaw is! Map) {
      // 推送格式异常，回退到全量刷新
      unawaited(loadConversations());
      return;
    }
    final convMap = Map<String, dynamic>.from(convRaw);
    final convId = convMap['id'];
    if (convId == null) {
      unawaited(loadConversations());
      return;
    }
    final cid = convId is int ? convId : int.tryParse(convId.toString());
    if (cid == null) {
      unawaited(loadConversations());
      return;
    }
    // 已存在则刷新，否则构造新会话插顶
    final existingIdx = state.conversations.indexWhere((c) => c.id == cid);
    Conversation? newConv;
    try {
      newConv = Conversation.fromJson(convMap);
    } catch (_) {
      newConv = null;
    }

    // 用 Hi 消息更新 lastMessage（若推送带 message）
    if (msgRaw is Map && newConv != null) {
      try {
        final msg = Message.fromJson(Map<String, dynamic>.from(msgRaw));
        newConv = Conversation(
          id: newConv.id,
          user1Id: newConv.user1Id,
          user2Id: newConv.user2Id,
          otherUser: newConv.otherUser,
          lastMessage: msg,
          lastMessageAt: msg.createdAt,
          unreadCount:
              _currentUserId == null || msg.senderId != _currentUserId ? 1 : 0,
        );
      } catch (_) {}
    }

    if (newConv == null) {
      unawaited(loadConversations());
      return;
    }

    List<Conversation> updated;
    if (existingIdx >= 0) {
      updated = List.from(state.conversations)
        ..[existingIdx] = newConv
        ..sort((a, b) =>
            (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                    a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    } else {
      updated = [newConv, ...state.conversations];
    }
    state = state.copyWith(conversations: updated);
    // 失效缓存，下次拉取用最新数据
    DataLayer().invalidate(CacheKeys.convPattern);
  }

  void _handleIncrementalNewMessage(Map<String, dynamic> data) {
    final msgId = data['id'] as int?;
    if (msgId != null && _processedMessageIds.contains(msgId)) return;
    if (msgId != null) {
      if (_processedMessageIds.length >= _maxProcessedIds) {
        // 清理前半部分旧 ID，防止无限增长
        final idsToRemove =
            _processedMessageIds.take(_maxProcessedIds ~/ 2).toSet();
        _processedMessageIds.removeAll(idsToRemove);
      }
      _processedMessageIds.add(msgId);
    }

    final convId = data['conversation_id'] as int;
    final content = data['content'] as String? ?? '';
    final msgType = data['message_type'] as String? ?? 'text';
    final preview = _formatPreview(content, msgType);
    final rawUnread = data['unread_count'];
    final serverUnread = rawUnread is int
        ? rawUnread
        : int.tryParse(rawUnread?.toString() ?? '');

    final lastMsg = Message(
      id: msgId ?? 0,
      conversationId: convId,
      senderId: data['sender_id'] ?? 0,
      content: content,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == msgType,
        orElse: () => MessageType.text,
      ),
      createdAt: data['created_at'] != null
          ? AppDateUtils.parseBeijingTime(data['created_at'].toString())
          : DateTime.now(),
    );

    final existingIdx = state.conversations.indexWhere((c) => c.id == convId);
    // 是否本人发送。本人发的消息回显绝不应计入未读——之前若服务端回传的
    // unread_count 包含本人消息，会被错误地设到会话上，表现为「自己发的消息
    // 也算未读」。这里强制以本地判断为准：本人消息 → 未读清零。
    final isOwnMessage =
        _currentUserId != null && lastMsg.senderId == _currentUserId;
    // 当前会话正打开时（用户在该聊天室），任何新消息都不应产生未读红点。
    final isCurrentOpenConv = ChatRoomState.isOpen(convId);
    final shouldIncreaseUnread = !isOwnMessage &&
        !isCurrentOpenConv &&
        (_currentUserId == null || lastMsg.senderId != _currentUserId);
    // 最终未读数：本人消息 / 当前打开会话 → 0；否则优先服务端值，服务端无值时本地自增。
    final int effectiveUnread;
    if (isOwnMessage || isCurrentOpenConv) {
      effectiveUnread = 0;
    } else {
      effectiveUnread = serverUnread ??
          (shouldIncreaseUnread
              ? (state.conversations.isEmpty
                  ? 0
                  : (state.conversations[existingIdx >= 0 ? existingIdx : 0]
                          .unreadCount) +
                      1)
              : (existingIdx >= 0
                  ? state.conversations[existingIdx].unreadCount
                  : 0));
    }
    List<Conversation> updated;
    if (existingIdx >= 0) {
      final conv = state.conversations[existingIdx];
      final updatedConv = Conversation(
        id: conv.id,
        user1Id: conv.user1Id,
        user2Id: conv.user2Id,
        otherUser: conv.otherUser,
        lastMessage: lastMsg,
        lastMessageAt: lastMsg.createdAt,
        unreadCount: effectiveUnread,
        type: conv.type,
        communityId: conv.communityId,
        communityName: conv.communityName,
        communityAvatar: conv.communityAvatar,
      );
      updated = List.from(state.conversations)
        ..removeAt(existingIdx)
        ..insert(0, updatedConv);
    } else {
      loadConversations();
      return;
    }
    state = state.copyWith(conversations: updated);
    // 本人消息 / 当前打开会话：把本地 DB 未读同步置 0；否则按 shouldIncreaseUnread 自增。
    if (isOwnMessage || isCurrentOpenConv) {
      DataLayer().updateConvLastMessage(
        convId,
        preview,
        lastMsg.createdAt!,
        unreadIncrement: 0,
      );
      // 确保本地未读被清零（updateConvLastMessage 增量为 0 时不会改 unread_count）
      LocalDbService().clearConversationUnread(convId);
    } else {
      DataLayer().updateConvLastMessage(
        convId,
        preview,
        lastMsg.createdAt!,
        unreadIncrement: shouldIncreaseUnread ? 1 : 0,
      );
    }
    DataLayer().invalidate(CacheKeys.convPattern);
  }

  void _handleBatchMessages(int conversationId, List<dynamic> messages) {
    final msgs = messages
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
    DataLayer().persistMessages(msgs);
    // 排除本人发送的消息，再排除「当前正打开的会话」——后者不应产生未读。
    final isCurrentOpenConv = ChatRoomState.isOpen(conversationId);
    final unreadIncoming = isCurrentOpenConv
        ? 0
        : (_currentUserId == null
            ? msgs.length
            : msgs.where((m) => m.senderId != _currentUserId).length);

    final lastMsg = msgs.last;
    final preview =
        _formatPreview(lastMsg.content ?? '', lastMsg.messageType.name);
    final existingIdx =
        state.conversations.indexWhere((c) => c.id == conversationId);
    if (existingIdx >= 0) {
      final conv = state.conversations[existingIdx];
      // 当前会话打开时，强制未读为 0，避免批量回放把本人/已读消息算成未读。
      final newUnread =
          isCurrentOpenConv ? 0 : conv.unreadCount + unreadIncoming;
      final updatedConv = Conversation(
        id: conv.id,
        user1Id: conv.user1Id,
        user2Id: conv.user2Id,
        otherUser: conv.otherUser,
        lastMessage: lastMsg,
        lastMessageAt: lastMsg.createdAt,
        unreadCount: newUnread,
        type: conv.type,
        communityId: conv.communityId,
        communityName: conv.communityName,
        communityAvatar: conv.communityAvatar,
      );
      final updated = List<Conversation>.from(state.conversations)
        ..removeAt(existingIdx)
        ..insert(0, updatedConv);
      state = state.copyWith(conversations: updated);
      if (isCurrentOpenConv) {
        DataLayer().updateConvLastMessage(
          conversationId,
          preview,
          lastMsg.createdAt!,
          unreadIncrement: 0,
        );
        LocalDbService().clearConversationUnread(conversationId);
      } else {
        DataLayer().updateConvLastMessage(
          conversationId,
          preview,
          lastMsg.createdAt!,
          unreadIncrement: unreadIncoming,
        );
      }
    } else {
      loadConversations();
    }
    DataLayer().invalidate(CacheKeys.convPattern);
  }

  /// 处理 WS message_recalled 事件：更新会话列表 lastMessage
  void _handleMessageRecalledConv(Map<String, dynamic> data) {
    final recalledMsgId = data['message_id'] as int?;
    final convId = data['conversation_id'] as int?;
    if (recalledMsgId == null || convId == null) return;

    final existingIdx = state.conversations.indexWhere((c) => c.id == convId);
    if (existingIdx < 0) return;

    final conv = state.conversations[existingIdx];
    // 如果 lastMessage 就是被撤回的消息，更新预览
    if (conv.lastMessage?.id == recalledMsgId) {
      final updatedConv = Conversation(
        id: conv.id,
        user1Id: conv.user1Id,
        user2Id: conv.user2Id,
        otherUser: conv.otherUser,
        lastMessage: conv.lastMessage?.copyWith(isRecalled: true),
        lastMessageAt: conv.lastMessageAt,
        unreadCount: conv.unreadCount,
        type: conv.type,
        communityId: conv.communityId,
        communityName: conv.communityName,
        communityAvatar: conv.communityAvatar,
      );
      final updated = List<Conversation>.from(state.conversations)
        ..removeAt(existingIdx)
        ..insert(existingIdx, updatedConv);
      state = state.copyWith(conversations: updated);
      DataLayer().updateConvLastMessage(
          convId, '消息已撤回', conv.lastMessageAt ?? DateTime.now());
    }
  }

  void upsertCommunityConversationPreview({
    required int conversationId,
    required int communityId,
    required String content,
    required String msgType,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    final lastMsg = Message(
      id: 0,
      conversationId: conversationId,
      senderId: _currentUserId ?? 0,
      content: content,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == msgType,
        orElse: () => MessageType.text,
      ),
      mediaUrl: msgType == 'image' || msgType == 'video' ? content : null,
      createdAt: now,
    );

    final existingIdx =
        state.conversations.indexWhere((c) => c.id == conversationId);
    if (existingIdx < 0) {
      loadConversations();
      return;
    }

    final conv = state.conversations[existingIdx];
    final updatedConv = Conversation(
      id: conv.id,
      user1Id: conv.user1Id,
      user2Id: conv.user2Id,
      otherUser: conv.otherUser,
      lastMessage: lastMsg,
      lastMessageAt: now,
      unreadCount: conv.unreadCount,
      type: conv.type,
      communityId: conv.communityId,
      communityName: conv.communityName,
      communityAvatar: conv.communityAvatar,
    );
    final updated = List<Conversation>.from(state.conversations)
      ..removeAt(existingIdx)
      ..insert(0, updatedConv);
    state = state.copyWith(conversations: updated);
    DataLayer().invalidate(CacheKeys.convPattern);
  }

  /// 发送消息后更新会话列表（移顶、更新预览、更新时间）。
  void onMessageSent(int convId, String content, String msgType, DateTime now) {
    final preview = _formatPreview(content, msgType);
    final lastMsg = Message(
      id: 0,
      conversationId: convId,
      senderId: 0,
      content: content,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == msgType,
        orElse: () => MessageType.text,
      ),
      createdAt: now,
    );

    final existingIdx = state.conversations.indexWhere((c) => c.id == convId);
    if (existingIdx >= 0) {
      final conv = state.conversations[existingIdx];
      final updatedConv = Conversation(
        id: conv.id,
        user1Id: conv.user1Id,
        user2Id: conv.user2Id,
        otherUser: conv.otherUser,
        lastMessage: lastMsg,
        lastMessageAt: now,
        unreadCount: conv.unreadCount, // 不增加未读数
        type: conv.type,
        communityId: conv.communityId,
        communityName: conv.communityName,
        communityAvatar: conv.communityAvatar,
      );
      final updated = List<Conversation>.from(state.conversations)
        ..removeAt(existingIdx)
        ..insert(0, updatedConv);
      state = state.copyWith(conversations: updated);
      DataLayer().updateConvLastMessage(
        convId,
        preview,
        now,
        unreadIncrement: 0,
      );
      DataLayer().invalidate(CacheKeys.convPattern);
    } else {
      // 会话不在列表中（极少情况），全量刷新
      loadConversations();
    }
  }

  String _formatPreview(String content, String msgType) {
    switch (msgType) {
      case 'image':
        return '图片';
      case 'video':
        return '视频';
      case 'file':
        return '文件';
      case 'post':
        return '帖子';
      case 'comment':
        return '评论';
      default:
        return content.length > 30 ? '${content.substring(0, 30)}...' : content;
    }
  }

  Future<void> loadConversations() async {
    debugPrint('[Conv] loadConversations START (NETWORK)');
    state = state.copyWith(
      isLoading: state.conversations.isEmpty,
      clearError: true,
    );
    try {
      // 并发请求：会话列表 + 未读数量（各自独立超时，不互相影响）
      final results = await Future.wait([
        _chatService
            .getConversations()
            .timeout(const Duration(seconds: 25))
            .catchError((_) => null as dynamic),
        NotificationService()
            .getUnreadCount()
            .timeout(const Duration(seconds: 10))
            .catchError((_) => null as dynamic),
      ]);

      // 会话列表
      // results[0] 来自 .catchError((_) => null)，运行时确实可能为 null；
      // 分析器因 dynamic 推断为 non-null 误报，这里显式 cast 让语义清晰且消警告。
      final response = results[0] as dynamic;
      if (response == null) {
        debugPrint('[Conv] getConversations timed out or failed');
        state = state.copyWith(
          isLoading: false,
          error: state.conversations.isEmpty ? '加载超时，下拉重试' : null,
        );
        return;
      }
      debugPrint(
          '[Conv] getConversations success=${response.success}, statusCode=${response.statusCode}, msg=${response.message}, dataType=${response.data?.runtimeType}');
      if (response.success) {
        debugPrint(
            '[Conv] raw response.data type=${response.data?.runtimeType}');
        final data = response.data != null
            ? (response.data is String
                ? jsonDecode(response.data as String)
                : response.data)
            : null;
        final List<dynamic> conversationList;
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          conversationList = (map['conversations'] ?? map['sessions']) ?? [];
        } else if (data is List) {
          conversationList = data;
        } else {
          conversationList = [];
        }
        debugPrint(
            '[Conv] parsed conversationList.length=${conversationList.length}, data is ${data.runtimeType}');
        debugPrint(
            '[Conv] first item type=${conversationList.isNotEmpty ? conversationList[0].runtimeType : "empty"}');
        debugPrint(
            '[Conv] first item keys=${conversationList.isNotEmpty && conversationList[0] is Map ? (conversationList[0] as Map).keys : "n/a"}');
        final conversations = conversationList
            .whereType<Map>()
            .map((item) =>
                Conversation.fromJson(Map<String, dynamic>.from(item)))
            .toList();

        debugPrint('[Conv] conversations.length=${conversations.length}');
        if (conversations.isNotEmpty) {
          final c = conversations[0];
          debugPrint(
              '[Conv] conv[0] otherUser=${c.otherUser?.username} displayName=${c.otherUser?.displayName} avatar=${c.otherUser?.avatarUrl}');
        }

        // 提取未读通知数量（独立 try/catch，单个超时不影响会话列表）
        int unread = state.unreadCount;
        final unreadResp = results[1];
        try {
          debugPrint(
              '[Conv] getUnreadCount success=${unreadResp.success}, data=${unreadResp.data}');
          if (unreadResp.success && unreadResp.data != null) {
            final unreadData = unreadResp.data;
            if (unreadData is Map) {
              unread = unreadData['unread_count'] ?? unreadData['count'] ?? 0;
            } else if (unreadData is int) {
              unread = unreadData;
            }
          }
        } catch (_) {}

        state = state.copyWith(
          conversations: conversations,
          unreadCount: unread,
          isLoading: false,
          error: null,
        );
        debugPrint(
            '[Conv] STATE SET: conversations=${conversations.length}, unread=$unread, isLoading=false, error=null');
        // 持久化操作独立 try/catch：数据库异常不影响内存中的会话列表
        try {
          await DataLayer().persistConversations(conversations);
          DataLayer().write(CacheKeys.convFullList, conversationList);
          unawaited(_warmRecentMessageCaches(conversations));
        } catch (dbError) {
          debugPrint(
              '[Conv] persistConversations failed (non-fatal): $dbError');
        }
      } else {
        state = state.copyWith(
          error: response.message ?? '加载失败',
          isLoading: false,
        );
        debugPrint(
            '[Conv] STATE SET: error="${response.message ?? "加载失败"}", isLoading=false');
      }
    } catch (e, stack) {
      state = state.copyWith(error: '网络错误，请稍后重试', isLoading: false);
      debugPrint('[Conv] STATE SET: error="网络错误", exception=$e');
      debugPrint('[Conv] stack: $stack');
    }
  }

  Future<void> _warmRecentMessageCaches(List<Conversation> conversations) async {
    for (final conversation in conversations) {
      final lastMessage = conversation.lastMessage;
      if (lastMessage == null) continue;
      final data = [lastMessage.toJson()];
      await DataLayer().write(CacheKeys.msgRecent(conversation.id), data);
      if (conversation.isCommunity && conversation.communityId != null) {
        await DataLayer().write(
          CacheKeys.communityChatRecent(conversation.communityId!),
          data,
        );
      }
    }
  }

  Future<void> refresh() async {
    if (_ws.isConnected) {
      final localConvs = await DataLayer().loadConversationsFromDb();
      if (localConvs.isNotEmpty) {
        state = state.copyWith(conversations: localConvs);
      }
    } else {
      await loadConversations();
    }
  }

  void _reset() {
    _loadInProgress = false;
    state = const ConversationsState();
  }

  /// 清除所有会话的未读数（仅用于外层总角标归零；不会错误改写服务端每个会话未读）
  void clearAllUnreadCounts() {
    state = state.copyWith(unreadCount: 0);
  }

  /// 当前会话已读后，把这个会话的本地未读数归零。
  void clearConversationUnread(int conversationId) {
    final updated = state.conversations.map((c) {
      if (c.id == conversationId && c.unreadCount > 0) {
        return Conversation.fromJson({...c.toJson(), 'unread_count': 0});
      }
      return c;
    }).toList();
    state = state.copyWith(conversations: updated);
    DataLayer().invalidate(CacheKeys.convPattern);
  }

  @override
  void dispose() {
    _wsMsgSub?.cancel();
    _wsSessionSub?.cancel();
    _wsFriendOnlineSub?.cancel();
    _wsFriendOfflineSub?.cancel();
    _wsOnlineFriendsSub?.cancel();
    _dataSub?.cancel();
    super.dispose();
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  return ConversationsNotifier();
});

// ── Messages Provider (family by conversationId) ──

class MessagesState {
  final List<Message> messages;
  final bool isLoading;
  final bool isSending;
  final bool hasMore;
  final int page;
  final String? error;
  final List<int> typingUserIds;
  final bool wsConnected;
  final bool otherUserTyping;
  final bool? otherUserIsOnline;

  const MessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.hasMore = false,
    this.page = 1,
    this.error,
    this.typingUserIds = const [],
    this.wsConnected = false,
    this.otherUserTyping = false,
    this.otherUserIsOnline,
  });

  MessagesState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? isSending,
    bool? hasMore,
    int? page,
    String? error,
    List<int>? typingUserIds,
    bool? wsConnected,
    bool? otherUserTyping,
    bool? otherUserIsOnline,
    bool clearError = false,
  }) {
    return MessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
      typingUserIds: typingUserIds ?? this.typingUserIds,
      wsConnected: wsConnected ?? this.wsConnected,
      otherUserTyping: otherUserTyping ?? this.otherUserTyping,
      otherUserIsOnline: otherUserIsOnline ?? this.otherUserIsOnline,
    );
  }
}

class MessagesNotifier extends StateNotifier<MessagesState> {
  final int conversationId;
  final ChatService _chatService = ChatService();
  final WebSocketService _ws = WebSocketService();
  late final ChatSendQueue _sendQueue;
  StreamSubscription? _wsMsgSub;
  StreamSubscription? _wsTypingSub;
  StreamSubscription? _wsConnSub;
  StreamSubscription? _wsErrorSub;
  StreamSubscription? _wsSendErrorSub;
  StreamSubscription? _wsAckSub;
  StreamSubscription? _wsFriendOnlineSub;
  StreamSubscription? _wsFriendOfflineSub;
  Timer? _typingTimer;
  int? _currentUserId;
  bool _initialized = false;

  final void Function(int convId, String content, String msgType, DateTime now)?
      _onMessageSent;

  MessagesNotifier(this.conversationId,
      {void Function(int convId, String content, String msgType, DateTime now)?
          onMessageSent})
      : _onMessageSent = onMessageSent,
        super(const MessagesState()) {
    _wsMsgSub = _ws.messageStream.listen(_onWsMessage);
    _wsTypingSub = _ws.typingStream.listen(_onWsTyping);
    _wsConnSub = _ws.connectionStream.listen((connected) {
      if (mounted) state = state.copyWith(wsConnected: connected);
    });
    _wsErrorSub = _ws.errorStream.listen(_onWsError);
    // 监听发送错误（携带 clientMsgId），用于通知 ChatSendQueue 标记消息失败
    _wsSendErrorSub = _ws.sendErrorStream.listen(_onSendError);
    // 监听 ACK 携带的 message_id，用于替换乐观消息的临时 ID
    _wsAckSub = _ws.ackMessageIdStream.listen(_onAckMessageId);
    state = state.copyWith(wsConnected: _ws.isConnected);
  }

  void _onAckMessageId(Map<String, dynamic> data) {
    final clientMsgId = data['clientMsgId'] as String?;
    final messageId = data['message_id'] as int?;
    if (clientMsgId == null || messageId == null || !mounted) return;

    if (_sendQueue.handleProtocolAck(clientMsgId, messageId)) {
      return;
    }

    // 找到 clientMsgId 匹配的乐观消息，替换 ID
    final idx = state.messages.indexWhere((m) => m.clientMsgId == clientMsgId);
    if (idx < 0) return;
    final msg = state.messages[idx];
    if (msg.id < 1000000000000) return; // 已被服务端回显替换
    final updated = List<Message>.from(state.messages);
    updated[idx] =
        msg.copyWith(id: messageId, clientMsgId: clientMsgId, status: 'sent');
    state = state.copyWith(messages: updated, isSending: false);
    DataLayer().persistMessage(updated[idx]);
    _syncL1();
    debugPrint(
        '[Chat] ack message_id: ${msg.id} → $messageId (clientMsgId=$clientMsgId)');
  }

  /// 由 ChatRoomScreen 在 initState 中调用，传入当前用户 ID 和对方用户 ID 并启动加载。
  ///
  /// 注意：family Provider 不会随 ChatRoomScreen pop 自动销毁，
  /// 同一会话第二次进入时若直接 `if (_initialized) return;` 会跳过
  /// joinConversation / markRead，导致服务端不知道用户已重新进入房间，
  /// 表现为：对方已读回执不下发、typing 不显示。
  /// 因此把「重复进入也要做的事」放到守卫之前。
  void init(int currentUserId, {int? otherUserId}) {
    // 1) 每次进入都必须做的事：加房间 + 上报已读
    _ws.joinConversation(conversationId);
    _sendMarkRead();

    // 2) 已初始化过的实例：只补发 join/markRead，跳过订阅 / 队列重建 / 首次加载
    if (_initialized) {
      // 数据已在内存，触发一次轻量增量同步即可填补离线期间空档
      if (state.messages.isNotEmpty) {
        unawaited(syncIncremental());
      }
      return;
    }
    _initialized = true;
    _currentUserId = currentUserId;

    // 监听好友在线/离线事件，实时更新 AppBar 状态
    if (otherUserId != null) {
      _wsFriendOnlineSub = _ws.friendOnlineStream.listen((data) {
        final uid = data['user_id'];
        final id = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
        if (id == otherUserId && mounted) {
          state = state.copyWith(otherUserIsOnline: true);
        }
      });
      _wsFriendOfflineSub = _ws.friendOfflineStream.listen((data) {
        final uid = data['user_id'];
        final id = uid is int ? uid : int.tryParse(uid?.toString() ?? '');
        if (id == otherUserId && mounted) {
          state = state.copyWith(otherUserIsOnline: false);
        }
      });
    }

    _sendQueue = ChatSendQueue(
      conversationId: conversationId,
      senderId: currentUserId,
    );
    _sendQueue.onAck = _onQueueAck;
    _sendQueue.onFailed = _onQueueFailed;
    _loadMessages();
  }

  // ── 数据加载 ──

  Future<void> _loadMessages() async {
    debugPrint('[Messages] ═══════════════════════════════════════');
    debugPrint('[Messages] _loadMessages START conv=$conversationId');

    // Dump: 检查所有可能的缓存 key 在 DataLayer 中的状态
    final cacheKey = CacheKeys.msgRecent(conversationId);
    final altKey1 = CacheKeys.msgWarmup(conversationId);
    String altKey2 = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('current_user_id') ?? '?';
      altKey2 = CacheKeys.msgRecentByUser(conversationId, uid);
    } catch (_) {}

    // 逐个 key 尝试 DataLayer 读取（不触发网络）
    for (final key in [cacheKey, altKey1, altKey2]) {
      if (key.isEmpty) continue;
      final snapshot =
          await DataLayer().query(key, () async => null, forceRefresh: false);
      final cached = snapshot.data;
      debugPrint(
          '[Messages]   DataLayer key="$key" → ${cached is List ? '${cached.length} msgs' : cached == null ? 'MISS' : 'type=${cached.runtimeType}'}');
    }

    // Step 1: 优先从 warmup 缓存加载（msg:$convId:1, 预热时写入）
    // 因为通过 dump 已知 warmup 是否有数据，优先用缓存而不是等待 SQLite
    try {
      final warmupKey = CacheKeys.msgWarmup(conversationId);
      final warmupSnapshot = await DataLayer()
          .query(warmupKey, () async => null, forceRefresh: false);
      if (warmupSnapshot.data is List &&
          (warmupSnapshot.data as List).isNotEmpty) {
        final messages = (warmupSnapshot.data as List<dynamic>)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint(
            '[Messages] Step1 warmup HIT: ${messages.length} msgs from $warmupKey');
        state = state.copyWith(messages: messages, isLoading: false);
      }
    } catch (_) {
      // ignore
    }

    // Step 2: SQLite 持久层（已有 warmup 数据时也写入持久层，容错降级）
    try {
      final localMessages =
          await DataLayer().loadMessagesFromDb(conversationId, limit: 50);
      debugPrint('[Messages] Step2 SQLite: ${localMessages.length} msgs');
      if (localMessages.isNotEmpty) {
        // SQLite 有数据但 warmup 没命中 → 用 SQLite
        if (state.messages.isEmpty) {
          debugPrint(
              '[Messages] Step2 → SQLite fallback, ${localMessages.length} msgs');
          state = state.copyWith(
            messages: localMessages.reversed.toList(),
            isLoading: false,
          );
        }
        // warmup 有数据但 SQLite 没有 → 补充写入 SQLite
        if (state.messages.isNotEmpty) {
          final localIds = localMessages.map((m) => m.id).toSet();
          final toInsert =
              state.messages.where((m) => !localIds.contains(m.id)).toList();
          if (toInsert.isNotEmpty) {
            await DataLayer().persistMessages(toInsert);
            debugPrint(
                '[Messages] Step2 → wrote ${toInsert.length} new msgs to SQLite');
          }
        }
      } else {
        debugPrint('[Messages] Step2 → SQLite EMPTY for conv=$conversationId');
      }
    } catch (e) {
      debugPrint('[Messages] Step2 SQLite ERROR: $e');
    }

    // Step 3: DataLayer 标准缓存 + 网络兜底
    // 已有数据时静默更新（优先读缓存再网络），无数据时强制网络获取
    try {
      final cacheKey = CacheKeys.msgRecent(conversationId);

      final result = await DataLayer().query(cacheKey, () async {
        debugPrint('[Messages] Step3 HTTP fetch conv=$conversationId');
        final resp = await _chatService.getMessages(conversationId);
        if (resp.success && resp.data != null) {
          final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
          final list = data['messages'] as List<dynamic>? ?? [];
          final hasMoreFromServer =
              data['has_more'] == true || (list.length >= 50);
          debugPrint(
              '[Messages] Step3 HTTP got ${list.length} msgs has_more=$hasMoreFromServer');
          // 将 has_more 信息嵌入返回数据，供外层读取
          return {'messages': list, 'has_more': hasMoreFromServer};
        }
        return null;
      }, forceRefresh: state.messages.isEmpty); // 无数据时强制网络

      if (result.data != null) {
        final resultData = result.data;
        List<dynamic> msgList;
        bool hasMoreFromLoad = false;
        if (resultData is Map && resultData.containsKey('messages')) {
          msgList = resultData['messages'] as List<dynamic>;
          hasMoreFromLoad = resultData['has_more'] == true;
        } else if (resultData is List) {
          msgList = resultData;
          hasMoreFromLoad = resultData.length >= 50;
        } else {
          msgList = [];
        }
        final serverMessages = msgList
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
        if (result.source.name != 'memory' ||
            serverMessages.length != state.messages.length) {
          // BUG 修复：之前直接 `messages: serverMessages` 会覆盖掉用户刚发出、
          // 还没收到 ACK 的乐观消息（id >= 1e12），表现为「发完一条消息进入聊天室 /
          // 拉取增量时自己刚发的消息凭空消失」。这里把仍处于 pending 的乐观消息
          // 追加到服务端列表末尾，保留「发送中」气泡，等服务端 ACK 回来再替换。
          final serverIds = serverMessages.map((m) => m.id).toSet();
          final pendingOptimistic = state.messages
              .where((m) => m.id >= 1000000000000 && !serverIds.contains(m.id))
              .toList();
          final merged = <Message>[
            ...serverMessages,
            ...pendingOptimistic,
          ];
          state = state.copyWith(
              messages: merged, isLoading: false, hasMore: hasMoreFromLoad);
          await DataLayer().persistMessages(serverMessages);
          debugPrint(
              '[Messages] Step3 → updated: ${serverMessages.length} server msgs'
              '${pendingOptimistic.isNotEmpty ? " + ${pendingOptimistic.length} pending optimistic" : ""}'
              ' (source=${result.source.name}) hasMore=$hasMoreFromLoad');
        }
      } else if (state.messages.isEmpty) {
        state = state.copyWith(isLoading: false);
        debugPrint('[Messages] Step3 → NO DATA, isLoading=false');
      }
    } catch (e) {
      debugPrint('[Messages] Step3 ERROR: $e');
      if (state.messages.isEmpty) {
        state = state.copyWith(isLoading: false);
      }
    }

    debugPrint(
        '[Messages] _loadMessages DONE: ${state.messages.length} msgs in state');

    // 增量同步（填补离线期间的消息间隙）
    if (state.messages.isNotEmpty) {
      await syncIncremental();
    }

    // Step 4: 标记已读
    _sendMarkRead();
  }

  /// 重试：发送失败→重发消息，加载失败→重新加载
  Future<void> retry() async {
    // WS 发送失败 → 重发最后一条失败消息
    if ((state.error ?? '').startsWith('发送失败')) {
      final failedIdx =
          state.messages.lastIndexWhere((m) => m.id >= 1000000000000);
      if (failedIdx < 0) {
        state = state.copyWith(error: null);
        return;
      }

      final failed = state.messages[failedIdx];
      // 移除失败消息（内存 + 持久层）
      final updated = List<Message>.from(state.messages)..removeAt(failedIdx);
      state = state.copyWith(messages: updated, error: null);
      DataLayer().deletePersistedMessage(failed.id);

      sendMessage(failed.content ?? '',
          messageType: failed.messageType.name, mediaUrl: failed.mediaUrl);
    } else {
      // 加载失败 → 重新加载消息
      state = state.copyWith(error: null);
      _loadMessages();
    }
  }

  /// 增量同步：获取本地最新消息 ID 之后的服务端消息
  Future<void> syncIncremental() async {
    if (state.messages.isEmpty) return;

    int? lastMessageId;
    for (final m in state.messages.reversed) {
      if (m.id < 1000000000000) {
        lastMessageId = m.id;
        break;
      }
    }
    if (lastMessageId == null) return;

    try {
      final resp =
          await _chatService.getMessagesAfter(conversationId, lastMessageId);
      if (!resp.success || resp.data == null) return;
      final data = resp.data;
      final msgList =
          (data is Map) ? (data['messages'] ?? []) : (data as List?);
      if (msgList == null || msgList.isEmpty) return;

      final serverMsgs = (msgList as List<dynamic>)
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingIds = state.messages.map((m) => m.id).toSet();
      final newMsgs =
          serverMsgs.where((m) => !existingIds.contains(m.id)).toList();

      if (newMsgs.isNotEmpty) {
        final List<Message> allMsgs = [...state.messages, ...newMsgs];
        allMsgs.sort((a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        state = state.copyWith(messages: allMsgs);
        await DataLayer().persistMessages(newMsgs);
        _syncL1();
      }

      final hasMore = (data is Map) ? (data['has_more'] == true) : false;
      if (hasMore) {
        state = state.copyWith(hasMore: true);
      }
    } catch (e) {
      debugPrint('syncIncremental error: $e');
    }
  }

  /// 加载更多历史消息：先查本地 SQLite，不足再 HTTP 分页
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoading: true);

    // Step 1: 从本地 SQLite 获取更早的消息
    final localMsgs = await DataLayer().loadMessagesFromDb(
      conversationId,
      limit: 50,
      offset: state.messages.length,
    );

    if (localMsgs.isNotEmpty) {
      final existingIds = state.messages.map((m) => m.id).toSet();
      final newMsgs =
          localMsgs.where((m) => !existingIds.contains(m.id)).toList();
      if (newMsgs.isNotEmpty) {
        state = state.copyWith(
          messages: [...newMsgs, ...state.messages],
          hasMore: localMsgs.length >= 50,
          isLoading: false,
        );
        return;
      }
    }

    // Step 2: 本地不够 → HTTP 分页
    try {
      final resp =
          await _chatService.getMessages(conversationId, page: state.page + 1);
      if (resp.success && resp.data != null) {
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        List<dynamic> msgList = [];
        bool hasMoreFlag = false;
        if (data is Map) {
          msgList = data['messages'] ?? [];
          hasMoreFlag = data['has_more'] == true;
        } else if (data is List) {
          msgList = data;
        }
        final messages = msgList
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
        final existingIds = state.messages.map((m) => m.id).toSet();
        final newMsgs =
            messages.where((m) => !existingIds.contains(m.id)).toList();
        if (newMsgs.isNotEmpty) {
          final allMsgs = [...newMsgs, ...state.messages];
          allMsgs.sort((a, b) => (a.createdAt ?? DateTime(0))
              .compareTo(b.createdAt ?? DateTime(0)));
          state = state.copyWith(
            messages: allMsgs,
            page: state.page + 1,
            hasMore: hasMoreFlag || msgList.length >= 50,
            isLoading: false,
          );
          await DataLayer().persistMessages(newMsgs);
          _syncL1();
        } else {
          state = state.copyWith(page: state.page + 1, isLoading: false);
        }
      } else {
        state = state.copyWith(hasMore: false, isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  // ── 发送消息 ──

  static final _random = Random();

  String _generateRequestId() {
    final r = _random;
    return '${DateTime.now().millisecondsSinceEpoch}-'
        '${r.nextInt(0xFFFFF).toRadixString(16).padLeft(5, '0')}-'
        '${r.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
  }

  /// 发送文本消息（经发送队列保序串行）
  void sendMessage(String content,
      {String messageType = 'text',
      String? mediaUrl,
      int? quoteMessageId,
      String? quotePreview}) {
    if (_currentUserId == null) return;
    final requestId = _generateRequestId();
    final now = DateTime.now();

    debugPrint(
        '[Chat] sendMessage conv=$conversationId content="$content" type=$messageType qDepth=${_sendQueue.pendingCount}');

    // 乐观消息（先落本地再入队）
    final optimisticMsg = Message(
      id: now.millisecondsSinceEpoch,
      conversationId: conversationId,
      senderId: _currentUserId!,
      content: content,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == messageType,
        orElse: () => MessageType.text,
      ),
      mediaUrl: mediaUrl,
      isRead: false,
      createdAt: now,
      requestId: requestId,
      status: 'sending',
      quoteMessageId: quoteMessageId,
      quotePreview: quotePreview,
    );

    state = state.copyWith(
      messages: [...state.messages, optimisticMsg],
      isSending: true,
    );
    DataLayer().persistMessage(optimisticMsg);
    _syncL1();
    _onMessageSent?.call(conversationId, content, messageType, now);
    SoundService().playSendSound();

    // 入队由 ChatSendQueue 串行发送
    _sendQueue.enqueue(optimisticMsg);
  }

  /// 发送图片消息（先上传再发送）
  Future<void> sendImageMessage(Uint8List bytes, String fileName) async {
    if (_currentUserId == null) return;
    final requestId = _generateRequestId();
    final now = DateTime.now();

    // 乐观占位
    final optimisticMsg = Message(
      id: now.millisecondsSinceEpoch,
      conversationId: conversationId,
      senderId: _currentUserId!,
      content: '图片',
      messageType: MessageType.image,
      createdAt: now,
      requestId: requestId,
      status: 'uploading',
      tempBytes: bytes, // 暂存原始 bytes 用于失败重试
    );

    state = state.copyWith(
      messages: [...state.messages, optimisticMsg],
      isSending: true,
    );
    DataLayer().persistMessage(optimisticMsg);

    try {
      final uploadResp = await ApiClient().uploadBytes(
        '/upload/chat/image',
        bytes,
        fileName,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0).toDouble();
          final updated = state.messages
              .map((m) => m.id == optimisticMsg.id
                  ? m.copyWith(status: 'uploading', uploadProgress: progress)
                  : m)
              .toList();
          state = state.copyWith(messages: updated, isSending: true);
          _syncL1();
        },
      );
      if (uploadResp.success) {
        final url = _extractUrl(uploadResp.data);
        if (url != null) {
          final queuedMsg = optimisticMsg.copyWith(
            content: url,
            mediaUrl: url,
            status: 'sending',
            uploadProgress: 1.0,
            clearTempBytes: true, // 上传成功后清除临时 bytes
          );
          final updated = state.messages
              .map((m) => m.id == optimisticMsg.id ? queuedMsg : m)
              .toList();
          state = state.copyWith(messages: updated, isSending: true);
          await DataLayer().persistMessage(queuedMsg);
          _syncL1();
          SoundService().playSendSound();
          // 通知会话列表更新
          _onMessageSent?.call(conversationId, '图片', 'image', now);
          _sendQueue.enqueue(queuedMsg);
        }
      } else {
        // 上传失败，标记为 failed 但保留 tempBytes 用于重试
        _markUploadFailed(optimisticMsg.id, bytes);
      }
    } catch (e) {
      debugPrint('Send image error: $e');
      // 上传失败，标记为 failed 但保留 tempBytes 用于重试
      _markUploadFailed(optimisticMsg.id, bytes);
    }
  }

  /// 标记图片上传失败（保留 tempBytes 以便重试）
  void _markUploadFailed(int optimisticId, Uint8List bytes) {
    if (!mounted) return;
    final updated = state.messages.map((m) {
      if (m.id == optimisticId) {
        return m.copyWith(status: 'failed', tempBytes: bytes);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated, isSending: false);
  }

  /// 重试上传失败的图片消息
  Future<void> retryImageUpload(int msgId) async {
    final msgIdx = state.messages.indexWhere((m) => m.id == msgId);
    if (msgIdx < 0) return;
    final msg = state.messages[msgIdx];
    if (msg.status != 'failed' || msg.tempBytes == null) return;

    // 恢复为上传中状态
    final updated = state.messages.map((m) {
      if (m.id == msgId) {
        return m.copyWith(
          status: 'uploading',
          uploadProgress: 0.0,
          tempBytes: msg.tempBytes,
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated, isSending: true);

    try {
      final uploadResp = await ApiClient().uploadBytes(
        '/upload/chat/image',
        msg.tempBytes!,
        'retry_$msgId.jpg',
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0).toDouble();
          final progressUpdated = state.messages.map((m) {
            if (m.id == msgId) {
              return m.copyWith(status: 'uploading', uploadProgress: progress);
            }
            return m;
          }).toList();
          state = state.copyWith(messages: progressUpdated, isSending: true);
          _syncL1();
        },
      );
      if (uploadResp.success) {
        final url = _extractUrl(uploadResp.data);
        if (url != null) {
          final queuedMsg = msg.copyWith(
            content: url,
            mediaUrl: url,
            status: 'sending',
            uploadProgress: 1.0,
            clearTempBytes: true,
          );
          final finalUpdated =
              state.messages.map((m) => m.id == msgId ? queuedMsg : m).toList();
          state = state.copyWith(messages: finalUpdated, isSending: true);
          await DataLayer().persistMessage(queuedMsg);
          _syncL1();
          SoundService().playSendSound();
          _onMessageSent?.call(
              conversationId, '图片', 'image', msg.createdAt ?? DateTime.now());
          _sendQueue.enqueue(queuedMsg);
        }
      } else {
        _markUploadFailed(msgId, msg.tempBytes!);
      }
    } catch (e) {
      debugPrint('Retry image upload error: $e');
      _markUploadFailed(msgId, msg.tempBytes!);
    }
  }

  /// 从本地列表中移除一条消息（长按删除）
  void removeMessage(int msgId) {
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != msgId).toList(),
    );
    DataLayer().deletePersistedMessage(msgId);
  }

  String? _extractUrl(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      return data['url']?.toString() ??
          data['image_url']?.toString() ??
          data['media_url']?.toString();
    }
    return data.toString();
  }

  // ── WebSocket 事件处理 ──

  void _onWsMessage(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    final msgConvId = data['conversation_id'];
    // #region agent log
    debugPrint(
        '[Chat] _onWsMessage event=$event conv=$msgConvId target=$conversationId');
    // #endregion
    if (event == 'ack') {
      final ackClientMsgId =
          data['clientMsgId'] as String? ?? data['client_msg_id'] as String?;
      final ackMessageId = data['message_id'] is int
          ? data['message_id'] as int
          : int.tryParse(data['message_id']?.toString() ?? '');
      if (ackClientMsgId != null && ackMessageId != null) {
        _onAckMessageId(
            {'clientMsgId': ackClientMsgId, 'message_id': ackMessageId});
      }
      return;
    }

    // 类型安全比较：WS JSON 可能返回 String 或 int
    final msgConvIdInt = msgConvId is int
        ? msgConvId
        : int.tryParse(msgConvId?.toString() ?? '');
    if (msgConvIdInt != conversationId) return;

    switch (event) {
      case 'new_message':
        final msgData = data['data'];
        if (msgData is Map<String, dynamic>) {
          debugPrint(
              '[Chat] _onWsMessage new_message: conv=$conversationId, keys=${msgData.keys}');
          _handleNewMessage(Message.fromJson(msgData));
          _syncL1();
        } else {
          debugPrint(
              '[Chat] _onWsMessage new_message: data is ${msgData.runtimeType}, raw=${data.keys}');
        }
        break;
      case 'ack':
        final ackClientMsgId =
            data['clientMsgId'] as String? ?? data['client_msg_id'] as String?;
        final ackMessageId = data['message_id'] as int?;
        if (ackClientMsgId != null && ackMessageId != null) {
          _onAckMessageId(
              {'clientMsgId': ackClientMsgId, 'message_id': ackMessageId});
        }
        break;
      case 'message_read':
        final readBy = data['read_by'];
        if (readBy != null &&
            readBy != _currentUserId &&
            _currentUserId != null) {
          _markPeerReadMessages();
        }
        _syncL1();
        break;
      case 'conversation_read':
        final readBy = data['read_by'];
        if (readBy != null &&
            readBy != _currentUserId &&
            _currentUserId != null) {
          _markPeerReadMessages();
        }
        _syncL1();
        break;
      case 'message_recalled':
        _handleMessageRecalled(data);
        break;
    }
  }

  // ── 发送队列回调 ──

  void _onQueueAck(int optimisticMsgId, Message serverMsg) {
    if (!mounted) return;
    // 替换乐观消息为服务端回显
    final filtered =
        state.messages.where((m) => m.id != optimisticMsgId).toList();
    // 避免重复（_handleNewMessage 可能已添加）
    if (!filtered.any((m) => m.id == serverMsg.id)) {
      filtered.add(serverMsg);
    }
    filtered.sort((a, b) {
      if (a.seq != null && b.seq != null) return a.seq!.compareTo(b.seq!);
      return (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
    });
    state = state.copyWith(messages: filtered, isSending: false);
    DataLayer().persistMessage(serverMsg);
    DataLayer().deletePersistedMessage(optimisticMsgId);
    _syncL1();
  }

  void _onQueueFailed(int optimisticMsgId, String reason) {
    if (!mounted) return;
    final idx = state.messages.indexWhere((m) => m.id == optimisticMsgId);
    if (idx < 0) return;
    final updated = List<Message>.from(state.messages);
    updated[idx] = updated[idx].copyWith(status: 'failed');
    state = state.copyWith(messages: updated, isSending: false);
    DataLayer().persistMessage(updated[idx]);
    _syncL1();
  }

  /// 处理 WS message_recalled 事件：将对应消息标记为已撤回
  void _handleMessageRecalled(Map<String, dynamic> data) {
    final recalledMsgId = data['message_id'] as int?;
    if (recalledMsgId == null) return;

    final updated = state.messages.map((m) {
      if (m.id == recalledMsgId) {
        final recalled = m.copyWith(isRecalled: true);
        DataLayer().persistMessage(recalled);
        return recalled;
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
    _syncL1();
    debugPrint('[Chat] message_recalled: msgId=$recalledMsgId');
  }

  /// 撤回消息
  void recallMessage(int messageId) {
    if (!_ws.isConnected) return;
    _ws.sendRecallMessage(messageId);

    // 乐观更新：立即标记本地消息为已撤回
    final updated = state.messages.map((m) {
      if (m.id == messageId) {
        final recalled = m.copyWith(isRecalled: true);
        DataLayer().persistMessage(recalled);
        return recalled;
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
    _syncL1();
  }

  void _handleNewMessage(Message message) {
    // 通知发送队列：匹配到的乐观消息会被队列移除并触发 onAck
    _sendQueue.handleAck(message);
    // 替换乐观消息：优先 requestId → 次选 clientMsgId → 兜底（同发送者 + 同内容）
    final filtered = state.messages.where((m) {
      // 1) requestId 完全匹配
      if (m.requestId != null && m.requestId == message.requestId) {
        return false;
      }
      // 2) clientMsgId 匹配（可靠 WS 发件箱回显）
      if (m.clientMsgId != null && m.clientMsgId == message.clientMsgId) {
        return false;
      }
      // 3) 乐观消息模糊匹配：ID 时间戳 + 同发送者 + 同内容
      if (m.id > 1000000000000 &&
          m.senderId == message.senderId &&
          m.content == message.content) {
        return false;
      }
      return m.id != message.id;
    }).toList();
    filtered.add(message);
    // 排序：优先用服务端 seq，无 seq 时按 createdAt
    filtered.sort((a, b) {
      if (a.seq != null && b.seq != null) return a.seq!.compareTo(b.seq!);
      return (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
    });
    state = state.copyWith(messages: filtered, isSending: false);
    DataLayer().persistMessage(message);
  }

  /// 对方标记已读：将本方所有未读消息标记为已读
  void _markPeerReadMessages() {
    if (_currentUserId == null) return;
    final updated = state.messages.map((m) {
      if (m.senderId == _currentUserId && !m.isRead) {
        DataLayer().markMessageRead(m.id, true);
        return m.copyWith(isRead: true);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  void _onWsTyping(Map<String, dynamic> data) {
    // 服务端推送的 conversation_id 可能是 int 也可能是 String，
    // 之前用 `as int?` 强转，遇到 String 会抛 _TypeError，导致整个
    // typing 事件监听回调抛出、后续 typing 状态全部断流。
    final raw = data['conversation_id'];
    final tConvId = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (tConvId != conversationId) return;
    final event = data['event'] ?? 'typing';
    state = state.copyWith(otherUserTyping: event == 'typing');
  }

  void _onWsError(String error) {
    if (!mounted) return;
    state = state.copyWith(isSending: false, error: '发送失败: $error');
  }

  void _onSendError(Map<String, dynamic> data) {
    if (!mounted) return;
    final clientMsgId = data['clientMsgId'] as String?;
    final error = data['error'] as String? ?? '未知错误';
    if (clientMsgId == null) return;

    // 通知 ChatSendQueue 立即标记该消息为失败
    if (_sendQueue.handleSendError(clientMsgId, error)) {
      return;
    }

    // 兜底：直接在消息列表中查找匹配的消息并标记
    final idx = state.messages.indexWhere((m) => m.clientMsgId == clientMsgId);
    if (idx >= 0) {
      final updated = List<Message>.from(state.messages);
      updated[idx] = updated[idx].copyWith(status: 'failed');
      state = state.copyWith(messages: updated, isSending: false);
      DataLayer().persistMessage(updated[idx]);
    }
  }

  // ── 输入状态 & 已读 ──

  void sendTyping() {
    _ws.sendTyping(conversationId);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _ws.sendStopTyping(conversationId);
    });
  }

  void _sendMarkRead() {
    if (!_ws.isConnected) return;
    int maxId = 0;
    for (final msg in state.messages) {
      if (msg.id > maxId && msg.id < 1000000000000) {
        maxId = msg.id;
      }
    }
    if (maxId > 0) {
      _ws.markConversationRead(conversationId);
    }
  }

  /// 将当前消息列表同步写入 DataLayer L1
  void _syncL1() {
    final l1Data = state.messages.map((m) => m.toJson()).toList();
    DataLayer().write(CacheKeys.msgRecent(conversationId), l1Data);
  }

  @override
  void dispose() {
    _ws.leaveConversation(conversationId);
    _wsMsgSub?.cancel();
    _wsTypingSub?.cancel();
    _wsConnSub?.cancel();
    _wsErrorSub?.cancel();
    _wsSendErrorSub?.cancel();
    _wsAckSub?.cancel();
    _wsFriendOnlineSub?.cancel();
    _wsFriendOfflineSub?.cancel();
    _typingTimer?.cancel();
    _sendQueue.dispose();
    // 清理旧消息（保留最近 500 条或 30 天内）
    DataLayer().pruneMessages(conversationId, maxCount: 500, maxDays: 30);
    super.dispose();
  }
}

final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, int>(
  (ref, conversationId) {
    return MessagesNotifier(
      conversationId,
      onMessageSent: (convId, content, msgType, now) {
        ref
            .read(conversationsProvider.notifier)
            .onMessageSent(convId, content, msgType, now);
      },
    );
  },
);
