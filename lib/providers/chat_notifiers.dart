import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/message.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:facebook_clone/services/local_db_service.dart';
import 'package:facebook_clone/services/sound_service.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Conversations Provider ──

class ConversationsState {
  final List<Conversation> conversations;
  final bool isLoading;
  final String? error;

  const ConversationsState({
    this.conversations = const [],
    this.isLoading = true,
    this.error,
  });

  ConversationsState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
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
  StreamSubscription? _dataSub;

  ConversationsNotifier() : super(const ConversationsState()) {
    _loadData();
    _wsMsgSub = _ws.messageStream.listen(_onWsMessage);
    _wsSessionSub = _ws.sessionListStream.listen(_onSessionList);
    _dataSub = DataLayer().changeStream.listen((key) {
      if (key == '__auth:logout') {
        _reset();
      } else if (key == 'conv:full:list') {
        _loadData();
      }
    });
  }

  /// 构造时先读缓存，空则等 AppWarmup 推送后再决定是否网络加载
  Future<void> _loadData() async {
    if (state.conversations.isNotEmpty) return;
    try {
      final result = await DataLayer()
          .query('conv:full:list', () async => null)
          .timeout(const Duration(seconds: 2));
      if (result.data is List && (result.data as List).isNotEmpty) {
        final conversations = (result.data as List<dynamic>)
            .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
            .toList();
        state = state.copyWith(conversations: conversations, isLoading: false);
        LocalDbService().insertConversations(conversations);
        return;
      }
      // 缓存空：等 1.5s 让 AppWarmup 写入，再读一次
      await Future.delayed(const Duration(milliseconds: 1500));
      final retryResult = await DataLayer()
          .query('conv:full:list', () async => null)
          .timeout(const Duration(seconds: 2));
      if (retryResult.data is List && (retryResult.data as List).isNotEmpty) {
        final conversations = (retryResult.data as List<dynamic>)
            .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
            .toList();
        state = state.copyWith(conversations: conversations, isLoading: false);
        LocalDbService().insertConversations(conversations);
        return;
      }
      // 仍未命中，触发网络加载
      unawaited(loadConversations());
    } catch (_) {
      // 缓存读取失败，尝试网络
      unawaited(loadConversations());
    }
  }

  void _onSessionList(List<Map<String, dynamic>> sessions) {
    final conversations = sessions.map((e) => Conversation.fromJson(e)).toList();
    state = state.copyWith(conversations: conversations, isLoading: false);
    LocalDbService().insertConversations(conversations);
    DataLayer().write("conv:full:list", sessions);
    DataLayer().invalidate("conv:*:list");
  }

  void _onWsMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'new_message') {
      final convId = data['conversation_id'] as int?;
      if (convId != null) {
        _handleIncrementalNewMessage(data);
      }
    } else if (type == 'batch_messages') {
      final convId = data['conversation_id'] as int?;
      final messages = data['messages'] as List<dynamic>?;
      if (convId != null && messages != null) {
        _handleBatchMessages(convId, messages);
      }
    }
  }

  void _handleIncrementalNewMessage(Map<String, dynamic> data) {
    final msgId = data['id'] as int?;
    if (msgId != null && _processedMessageIds.contains(msgId)) return;
    if (msgId != null) {
      if (_processedMessageIds.length >= _maxProcessedIds) {
        // 清理前半部分旧 ID，防止无限增长
        final idsToRemove = _processedMessageIds.take(_maxProcessedIds ~/ 2).toSet();
        _processedMessageIds.removeAll(idsToRemove);
      }
      _processedMessageIds.add(msgId);
    }

    final convId = data['conversation_id'] as int;
    final content = data['content'] as String? ?? '';
    final msgType = data['message_type'] as String? ?? 'text';
    final preview = _formatPreview(content, msgType);

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
          ? DateTime.tryParse(data['created_at'].toString())
          : DateTime.now(),
    );

    final existingIdx = state.conversations.indexWhere((c) => c.id == convId);
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
        unreadCount: conv.unreadCount + 1,
      );
      updated = List.from(state.conversations)
        ..removeAt(existingIdx)
        ..insert(0, updatedConv);
    } else {
      loadConversations();
      return;
    }
    state = state.copyWith(conversations: updated);
    LocalDbService().updateConversationLastMessage(
      convId, preview, lastMsg.createdAt!, unreadIncrement: 1,
    );
    DataLayer().invalidate("conv:*:list");
  }

  void _handleBatchMessages(int conversationId, List<dynamic> messages) {
    final msgs = messages.map((e) => Message.fromJson(e as Map<String, dynamic>)).toList();
    LocalDbService().insertMessages(msgs);

    final lastMsg = msgs.last;
    final preview = _formatPreview(lastMsg.content ?? '', lastMsg.messageType.name);
    final existingIdx = state.conversations.indexWhere((c) => c.id == conversationId);
    if (existingIdx >= 0) {
      final conv = state.conversations[existingIdx];
      final updatedConv = Conversation(
        id: conv.id,
        user1Id: conv.user1Id,
        user2Id: conv.user2Id,
        otherUser: conv.otherUser,
        lastMessage: lastMsg,
        lastMessageAt: lastMsg.createdAt,
        unreadCount: conv.unreadCount + msgs.length,
      );
      final updated = List<Conversation>.from(state.conversations)
        ..removeAt(existingIdx)
        ..insert(0, updatedConv);
      state = state.copyWith(conversations: updated);
      LocalDbService().updateConversationLastMessage(
        conversationId, preview, lastMsg.createdAt!, unreadIncrement: msgs.length,
      );
    } else {
      loadConversations();
    }
    DataLayer().invalidate("conv:*:list");
  }

  String _formatPreview(String content, String msgType) {
    switch (msgType) {
      case 'image': return '图片';
      case 'video': return '视频';
      case 'file': return '文件';
      case 'post': return '帖子';
      case 'comment': return '评论';
      default:
        return content.length > 30 ? '${content.substring(0, 30)}...' : content;
    }
  }

  Future<void> loadConversations() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _chatService
          .getConversations()
          .timeout(const Duration(seconds: 25));
      if (response.success && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final List<dynamic> conversationList;
        if (data is Map<String, dynamic>) {
          conversationList = data['conversations'] ?? [];
        } else if (data is List) {
          conversationList = data;
        } else {
          conversationList = [];
        }
        final conversations = conversationList
            .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
            .toList();
        state = state.copyWith(conversations: conversations, isLoading: false);
        await LocalDbService().insertConversations(conversations);
        DataLayer().write('conv:full:list', conversationList);
      } else {
        state = state.copyWith(
          error: response.message ?? '加载失败',
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(error: '网络错误，请稍后重试', isLoading: false);
    }
  }

  Future<void> refresh() async {
    if (_ws.isConnected) {
      final localConvs = await LocalDbService().getConversations();
      if (localConvs.isNotEmpty) {
        state = state.copyWith(conversations: localConvs);
      }
    } else {
      await loadConversations();
    }
  }

  void _reset() {
    state = const ConversationsState();
  }

  @override
  void dispose() {
    _wsMsgSub?.cancel();
    _wsSessionSub?.cancel();
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

  const MessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.hasMore = true,
    this.page = 1,
    this.error,
    this.typingUserIds = const [],
    this.wsConnected = false,
    this.otherUserTyping = false,
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
    );
  }
}

class MessagesNotifier extends StateNotifier<MessagesState> {
  final int conversationId;
  final ChatService _chatService = ChatService();
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _wsMsgSub;
  StreamSubscription? _wsTypingSub;
  StreamSubscription? _wsConnSub;
  StreamSubscription? _wsErrorSub;
  Timer? _typingTimer;
  int? _currentUserId;
  bool _initialized = false;

  MessagesNotifier(this.conversationId) : super(const MessagesState()) {
    _wsMsgSub = _ws.messageStream.listen(_onWsMessage);
    _wsTypingSub = _ws.typingStream.listen(_onWsTyping);
    _wsConnSub = _ws.connectionStream.listen((connected) {
      if (mounted) state = state.copyWith(wsConnected: connected);
    });
    _wsErrorSub = _ws.errorStream.listen(_onWsError);
    state = state.copyWith(wsConnected: _ws.isConnected);
  }

  /// 由 ChatRoomScreen 在 initState 中调用，传入当前用户 ID 并启动加载
  void init(int currentUserId) {
    if (_initialized) return;
    _initialized = true;
    _currentUserId = currentUserId;
    _ws.joinConversation(conversationId);
    _loadMessages();
  }

  // ── 数据加载 ──

  Future<void> _loadMessages() async {
    debugPrint('[Messages] ═══════════════════════════════════════');
    debugPrint('[Messages] _loadMessages START conv=$conversationId');

    // Dump: 检查所有可能的缓存 key 在 DataLayer 中的状态
    final cacheKey = 'msg:$conversationId:recent';
    final altKey1 = 'msg:$conversationId:1';
    String altKey2 = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('current_user_id') ?? '?';
      altKey2 = 'msg:$uid:$conversationId:recent';
    } catch (_) {}

    // 逐个 key 尝试 DataLayer 读取（不触发网络）
    for (final key in [cacheKey, altKey1, altKey2]) {
      if (key.isEmpty) continue;
      final snapshot = await DataLayer().query(key, () async => null,
          forceRefresh: false);
      final cached = snapshot.data;
      debugPrint('[Messages]   DataLayer key="$key" → ${cached is List ? '${cached.length} msgs' : cached == null ? 'MISS' : 'type=${cached.runtimeType}'}');
    }

    // Step 1: 优先从 warmup 缓存加载（msg:$convId:1, 预热时写入）
    // 因为通过 dump 已知 warmup 是否有数据，优先用缓存而不是等待 SQLite
    try {
      final warmupKey = 'msg:$conversationId:1';
      final warmupSnapshot = await DataLayer().query(warmupKey, () async => null,
          forceRefresh: false);
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
          await LocalDbService().getMessages(conversationId, limit: 50);
      debugPrint('[Messages] Step2 SQLite: ${localMessages.length} msgs');
      if (localMessages.isNotEmpty) {
        // SQLite 有数据但 warmup 没命中 → 用 SQLite
        if (state.messages.isEmpty) {
          debugPrint('[Messages] Step2 → SQLite fallback, ${localMessages.length} msgs');
          state = state.copyWith(
            messages: localMessages.reversed.toList(),
            isLoading: false,
          );
        }
        // warmup 有数据但 SQLite 没有 → 补充写入 SQLite
        if (state.messages.isNotEmpty) {
          final localIds =
              localMessages.map((m) => m.id).toSet();
          final toInsert = state.messages
              .where((m) => !localIds.contains(m.id))
              .toList();
          if (toInsert.isNotEmpty) {
            await LocalDbService().insertMessages(toInsert);
            debugPrint('[Messages] Step2 → wrote ${toInsert.length} new msgs to SQLite');
          }
        }
      } else {
        debugPrint('[Messages] Step2 → SQLite EMPTY for conv=$conversationId');
      }
    } catch (e) {
      debugPrint('[Messages] Step2 SQLite ERROR: $e');
    }

    // Step 3: DataLayer 标准缓存 + 网络兜底
    // 已有数据时静默更新，无数据时强制网络
    try {
      final cacheKey = state.messages.isNotEmpty
          ? 'msg:$conversationId:recent'
          : 'msg:$conversationId:recent';

      final result = await DataLayer().query(cacheKey, () async {
        debugPrint('[Messages] Step3 HTTP fetch conv=$conversationId');
        final resp = await _chatService.getMessages(conversationId);
        if (resp.success && resp.data != null) {
          final data =
              resp.data is String ? jsonDecode(resp.data) : resp.data;
          final list = data['messages'] as List<dynamic>? ?? [];
          debugPrint('[Messages] Step3 HTTP got ${list.length} msgs');
          return list;
        }
        return null;
      }, forceRefresh: state.messages.isEmpty); // 无数据时强制网络

      if (result.data != null) {
        final messages = (result.data as List<dynamic>)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
        if (result.source.name != 'memory' ||
            messages.length != state.messages.length) {
          state = state.copyWith(messages: messages, isLoading: false);
          await LocalDbService().insertMessages(messages);
          debugPrint('[Messages] Step3 → updated: ${messages.length} msgs (source=${result.source.name})');
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

    debugPrint('[Messages] _loadMessages DONE: ${state.messages.length} msgs in state');

    // 增量同步（填补离线期间的消息间隙）
    if (state.messages.isNotEmpty) {
      await syncIncremental();
    }

    // Step 4: 标记已读
    _sendMarkRead();
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
      final resp = await _chatService.getMessagesAfter(
          conversationId, lastMessageId);
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
        await LocalDbService().insertMessages(newMsgs);
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
    final localMsgs = await LocalDbService().getMessages(
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
      final resp = await _chatService.getMessages(
          conversationId,
          page: state.page + 1);
      if (resp.success && resp.data != null) {
        final data =
            resp.data is String ? jsonDecode(resp.data) : resp.data;
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
          await LocalDbService().insertMessages(newMsgs);
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

  String _generateRequestId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch}-'
        '${r.nextInt(0xFFFFF).toRadixString(16).padLeft(5, '0')}-'
        '${r.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
  }

  /// 发送文本消息（经 WebSocket 可靠投递）
  void sendMessage(String content,
      {String messageType = 'text', String? mediaUrl}) {
    if (_currentUserId == null) return;
    final requestId = _generateRequestId();
    final now = DateTime.now();

    // 乐观消息
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
    );

    state = state.copyWith(
      messages: [...state.messages, optimisticMsg],
      isSending: true,
    );
    LocalDbService().insertMessage(optimisticMsg);
    _syncL1();

    _ws.sendMessage(conversationId, content,
        messageType: messageType, mediaUrl: mediaUrl)
      .then((clientMsgId) {
        debugPrint('[Chat] WS send queued: requestId=$requestId, clientMsgId=$clientMsgId');
      })
      .catchError((e) {
        debugPrint('[Chat] WS send error: $e');
        _removeOptimistic(optimisticMsg.id);
      });
    SoundService().playSendSound();

    // 超时保护：8s 后若仍未收到服务端 echo，重置 isSending
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && state.isSending) {
        debugPrint('[Chat] isSending timeout reset');
        state = state.copyWith(isSending: false);
      }
    });
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
    );

    state = state.copyWith(
      messages: [...state.messages, optimisticMsg],
      isSending: true,
    );
    LocalDbService().insertMessage(optimisticMsg);

    try {
      final uploadResp = await ApiClient().uploadBytes(
        '/upload/chat/image',
        bytes,
        fileName,
      );
      if (uploadResp.success) {
        final url = _extractUrl(uploadResp.data);
        if (url != null) {
          if (_ws.isConnected) {
            _ws.sendMessage(conversationId, url,
                messageType: 'image', mediaUrl: url);
            SoundService().playSendSound();
          } else {
            await _chatService.sendMessage(conversationId, url,
                messageType: 'image',
                mediaUrl: url,
                requestId: requestId);
            if (mounted) state = state.copyWith(isSending: false);
          }
        }
      } else {
        // 上传失败，移除乐观消息
        _removeOptimistic(optimisticMsg.id);
      }
    } catch (e) {
      debugPrint('Send image error: $e');
      _removeOptimistic(optimisticMsg.id);
    }
  }

  void _removeOptimistic(int optimisticId) {
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != optimisticId).toList(),
      isSending: false,
    );
    LocalDbService().deleteMessage(optimisticId);
  }

  String? _extractUrl(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      return data['url']?.toString()
          ?? data['image_url']?.toString()
          ?? data['media_url']?.toString();
    }
    return data.toString();
  }

  // ── WebSocket 事件处理 ──

  void _onWsMessage(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    final msgConvId = data['conversation_id'];
    if (msgConvId != conversationId) return;

    switch (event) {
      case 'new_message':
        final msgData = data['data'];
        if (msgData is Map<String, dynamic>) {
          debugPrint('[Chat] _onWsMessage new_message: conv=$conversationId, keys=${msgData.keys}');
          _handleNewMessage(Message.fromJson(msgData));
          _syncL1();
        } else {
          debugPrint('[Chat] _onWsMessage new_message: data is ${msgData.runtimeType}, raw=${data.keys}');
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
    }
  }

  void _handleNewMessage(Message message) {
    // 替换乐观消息：通过 requestId 或（同发送者 + 同内容）匹配
    final filtered = state.messages.where((m) {
      if (m.requestId != null && m.requestId == message.requestId) {
        return false;
      }
      if (m.id > 1000000000000 &&
          m.senderId == message.senderId &&
          m.content == message.content) {
        return false;
      }
      return m.id != message.id;
    }).toList();
    filtered.add(message);
    filtered.sort((a, b) =>
        (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    state = state.copyWith(messages: filtered, isSending: false);
    LocalDbService().insertMessage(message);
  }

  /// 对方标记已读：将本方所有未读消息标记为已读
  void _markPeerReadMessages() {
    if (_currentUserId == null) return;
    final updated = state.messages.map((m) {
      if (m.senderId == _currentUserId && !m.isRead) {
        LocalDbService().updateMessageReadStatus(m.id, true);
        return m.copyWith(isRead: true);
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  void _onWsTyping(Map<String, dynamic> data) {
    final tConvId = data['conversation_id'] as int?;
    if (tConvId != conversationId) return;
    final event = data['event'] ?? 'typing';
    state = state.copyWith(otherUserTyping: event == 'typing');
  }

  void _onWsError(String error) {
    if (!mounted) return;
    state = state.copyWith(isSending: false, error: '发送失败: $error');
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
    DataLayer().write('msg:$conversationId:recent', l1Data);
  }

  @override
  void dispose() {
    _ws.leaveConversation(conversationId);
    _wsMsgSub?.cancel();
    _wsTypingSub?.cancel();
    _wsConnSub?.cancel();
    _wsErrorSub?.cancel();
    _typingTimer?.cancel();
    // 清理旧消息（保留最近 500 条或 30 天内）
    LocalDbService()
        .pruneMessages(conversationId, maxCount: 500, maxDays: 30);
    super.dispose();
  }
}

final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, MessagesState, int>(
  (ref, conversationId) {
    return MessagesNotifier(conversationId);
  },
);
