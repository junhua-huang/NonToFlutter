import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/models/user.dart' as app_user;
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/database/app_database.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';

/// 本地数据库服务 - 存储聊天记录（按用户账号隔离）
/// 基于 drift，支持 Web / iOS / Android 三端
class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  AppDatabase? _db;
  String? _currentUserId;

  /// 当前 LocalDbService 绑定的用户 ID（与登录态用户的字符串 ID 一致）。
  /// 用于跨模块做"token 用户 ↔ DB 用户"一致性断言。
  String? get currentUserId => _currentUserId;

  /// 立刻清掉身份字段并断开 DB 引用，但 **不删** 磁盘文件。
  /// 用于 token 与 DB 用户不一致时的紧急止血：保证后续 `init(newUserId)`
  /// 一定走"开新库"分支，而不会被 `_currentUserId == userId` 短路掉。
  ///
  /// 调用方应紧接着 `await init(newUserId)`，否则期间任何 DB 操作都会无声失败。
  Future<void> resetIdentity() async {
    final oldDb = _db;
    _db = null;
    _currentUserId = null;
    try {
      await oldDb?.close();
    } catch (_) {}
  }

  Future<void> _closeCurrent() async {
    await _db?.close();
  }

  /// 初始化数据库（传入当前登录用户ID以隔离数据）
  Future<void> init(String userId) async {
    if (_currentUserId == userId && _db != null) return;
    await _closeCurrent();
    _currentUserId = userId;
    try {
      _db = await AppDatabase.forUser(userId);
      DataLayer().init(_db!);
    } catch (e) {
      debugPrint('[LocalDbService] DB init failed for user $userId: $e');
      _db = null;
      // Don't rethrow — app should still work with network-only mode
    }
  }

  // ==================== 消息操作 ====================

  Future<void> insertMessage(Message msg) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.insertMessage(_messageToCompanion(msg));
    } catch (e) {
      debugPrint('[DB] insertMessage failed (non-critical): $e');
    }
  }

  Future<void> insertMessages(List<Message> messages) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.insertMessages(messages.map(_messageToCompanion).toList());
    } catch (e) {
      debugPrint('[DB] insertMessages failed (non-critical): $e');
    }
  }

  Future<List<Message>> getMessages(int conversationId,
      {int limit = 50, int offset = 0}) async {
    final db = _db;
    if (db == null) return [];
    final rows =
        await db.getMessages(conversationId, limit: limit, offset: offset);
    return rows.map(_driftRowToMessage).toList().reversed.toList();
  }

  Future<void> markMessagesRead(int conversationId) async {
    final db = _db;
    if (db == null) return;
    await db.markMessagesRead(conversationId);
  }

  Future<void> updateMessageId(int oldId, int newId) async {
    final db = _db;
    if (db == null) return;
    await db.updateMessageId(oldId, newId);
  }

  Future<int> getUnreadCount(int conversationId) async {
    final db = _db;
    if (db == null) return 0;
    return db.getUnreadCount(conversationId);
  }

  Future<void> updateMessageReadStatus(int messageId, bool isRead) async {
    final db = _db;
    if (db == null) return;
    await db.updateMessageReadStatus(messageId, isRead);
  }

  Future<void> deleteMessage(int messageId) async {
    final db = _db;
    if (db == null) return;
    await db.deleteMessage(messageId);
  }

  /// Prune old messages for a conversation: keep last [maxCount] or within [maxDays].
  Future<int> pruneMessages(int conversationId,
      {int maxCount = 500, int maxDays = 30}) async {
    final db = _db;
    if (db == null) return 0;
    return db.pruneMessages(conversationId,
        maxCount: maxCount, maxDays: maxDays);
  }

  // ==================== 会话操作 ====================

  Future<void> insertConversation(Conversation conv) async {
    final db = _db;
    if (db == null) return;
    await db.insertConversation(_conversationToCompanion(conv));
  }

  Future<void> insertConversations(List<Conversation> conversations) async {
    final db = _db;
    if (db == null) return;
    final persistableConversations = conversations
        .where((conversation) => !conversation.isCommunity)
        .toList();
    if (persistableConversations.isEmpty) return;
    await db.insertConversations(
        persistableConversations.map(_conversationToCompanion).toList());
  }

  Future<List<Conversation>> getConversations() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.getConversations();
    return rows.map(_driftRowToConversation).toList();
  }

  Future<void> updateConversationLastMessage(
    int conversationId,
    String lastMessage,
    DateTime lastMessageAt, {
    int unreadIncrement = 0,
    MessageType messageType = MessageType.text,
    String? mediaUrl,
    int? relatedId,
    bool isRecalled = false,
  }) async {
    final db = _db;
    if (db == null) return;
    await db.updateConversationLastMessage(
      conversationId,
      lastMessage,
      lastMessageAt.millisecondsSinceEpoch,
      unreadIncrement: unreadIncrement,
      messageType: messageType.name,
      mediaUrl: mediaUrl,
      relatedId: relatedId,
      isRecalled: isRecalled,
    );
  }

  Future<void> clearConversationUnread(int conversationId) async {
    final db = _db;
    if (db == null) return;
    await db.clearConversationUnread(conversationId);
  }

  Future<void> deleteConversation(int conversationId) async {
    final db = _db;
    if (db == null) return;
    await db.deleteConversation(conversationId);
  }

  // ==================== 工具方法 ====================

  MessagesTableCompanion _messageToCompanion(Message msg) {
    return MessagesTableCompanion(
      id: Value(msg.id),
      conversationId: Value(msg.conversationId),
      senderId: Value(msg.senderId),
      content: Value(msg.content),
      mediaUrl: Value(msg.mediaUrl),
      relatedId: Value(msg.relatedId),
      messageType: Value(msg.messageType.name),
      isRead: Value(msg.isRead),
      createdAt: Value(msg.createdAt?.millisecondsSinceEpoch),
      requestId: Value(msg.requestId),
      clientMsgId: Value(msg.clientMsgId),
      seq: msg.seq != null ? Value(msg.seq) : const Value.absent(),
      status: Value(msg.status),
      uploadProgress: Value(msg.uploadProgress),
      quoteMessageId: Value(msg.quoteMessageId),
      quotePreview: Value(msg.quotePreview),
      isRecalled: Value(msg.isRecalled),
    );
  }

  Message _driftRowToMessage(MessagesTableData row) {
    return Message(
      id: row.id,
      conversationId: row.conversationId,
      senderId: row.senderId,
      content: row.content,
      mediaUrl: row.mediaUrl,
      relatedId: row.relatedId,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == row.messageType,
        orElse: () => MessageType.text,
      ),
      isRead: row.isRead,
      createdAt: row.createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.createdAt!)
          : null,
      requestId: row.requestId,
      clientMsgId: row.clientMsgId,
      seq: row.seq,
      status: row.status,
      uploadProgress: row.uploadProgress,
      quoteMessageId: row.quoteMessageId,
      quotePreview: row.quotePreview,
      isRecalled: row.isRecalled,
    );
  }

  ConversationsTableCompanion _conversationToCompanion(Conversation conv) {
    return ConversationsTableCompanion(
      id: Value(conv.id),
      user1Id: Value(conv.user1Id),
      user2Id: Value(conv.user2Id),
      otherUserId: Value(conv.otherUser?.id),
      otherUserName: Value(conv.otherUser?.displayName),
      otherUserAvatar: Value(conv.otherUser?.avatarUrl),
      otherUserUsername: Value(conv.otherUser?.username),
      lastMessage: Value(conv.lastMessage?.content),
      lastMessageType: Value(conv.lastMessage?.messageType.name ?? MessageType.text.name),
      lastMessageMediaUrl: Value(conv.lastMessage?.mediaUrl),
      lastMessageRelatedId: Value(conv.lastMessage?.relatedId),
      lastMessageIsRecalled: Value(conv.lastMessage?.isRecalled ?? false),
      lastMessageAt: Value(conv.lastMessageAt?.millisecondsSinceEpoch),
      unreadCount: Value(conv.unreadCount),
      isOnline: const Value(false),
      // Use lastMessageAt as the best available timestamp for SQLite creation order
      createdAt: Value(conv.lastMessageAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch),
    );
  }

  Conversation _driftRowToConversation(ConversationsTableData row) {
    final lastMessageType = MessageType.values.firstWhere(
      (e) => e.name == row.lastMessageType,
      orElse: () => MessageType.text,
    );
    return Conversation(
      id: row.id,
      user1Id: row.user1Id ?? 0,
      user2Id: row.user2Id ?? 0,
      otherUser: row.otherUserId != null
          ? app_user.User(
              id: row.otherUserId!,
              username: row.otherUserUsername ?? '',
              email: '',
              displayName: row.otherUserName,
              avatarUrl: row.otherUserAvatar,
            )
          : null,
      lastMessage: row.lastMessage != null
          ? Message(
              id: 0,
              conversationId: row.id,
              senderId: 0,
              content: row.lastMessage!,
              messageType: lastMessageType,
              mediaUrl: row.lastMessageMediaUrl,
              relatedId: row.lastMessageRelatedId,
              isRecalled: row.lastMessageIsRecalled,
              createdAt: row.lastMessageAt != null
                  ? DateTime.fromMillisecondsSinceEpoch(row.lastMessageAt!)
                  : null,
            )
          : null,
      lastMessageAt: row.lastMessageAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.lastMessageAt!)
          : null,
      unreadCount: row.unreadCount,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _currentUserId = null;
  }

  // ==================== 启动预加载 ====================

  /// 从闪屏/登录进入主页后调用：对每个会话执行「持久层→缓存→网络→持久层→缓存」。
  ///
  /// 1. 从 MessagesTable 读取一页消息 → 写入 DataLayer 缓存
  /// 2. 从网络获取一页最新消息 → 插入 MessagesTable → 更新 DataLayer 缓存
  ///
  /// [perPage] 每页消息数，默认 50 条。
  /// 完成后广播 `chat:preload:done` 通知 UI 刷新。
  Future<void> preloadRecentConversationMessages(
      {int perPage = 30, int maxConversations = 5}) async {
    final db = _db;
    if (db == null) return;

    final userId = _currentUserId;
    if (userId == null) return;

    final conversations = await getConversations();
    final convIds =
        conversations.map((c) => c.id).take(maxConversations).toList();
    if (convIds.isEmpty) return;

    for (final convId in convIds) {
      final localMessages = await getMessages(convId, limit: perPage);
      if (localMessages.isNotEmpty) {
        final localJson = localMessages.map((m) => m.toJson()).toList();
        await DataLayer().write(CacheKeys.msgRecent(convId), localJson);
        await DataLayer()
            .write(CacheKeys.msgRecentByUser(convId, userId), localJson);
      }
    }

    try {
      debugPrint(
          '[Preload] recent batch HTTP: ${convIds.length} convs, perPage=$perPage');
      final resp = await ChatService()
          .getBatchMessages(convIds, perPage: perPage)
          .timeout(const Duration(seconds: 12));
      if (resp.success && resp.data != null) {
        final data = resp.data is String
            ? (() {
                try {
                  return jsonDecode(resp.data as String);
                } catch (_) {
                  return {};
                }
              })()
            : resp.data;
        final batchConversations = data['data']?['conversations'] ??
            data['conversations'] ??
            <dynamic>[];

        debugPrint(
            '[Preload] recent batch returned ${batchConversations.length} conversations');

        for (final c in batchConversations) {
          if (c is! Map<String, dynamic>) continue;
          final convId = c['conversation_id'] ?? c['id'];
          final messages = c['messages'];
          if (convId is int && messages is List && messages.isNotEmpty) {
            final localMessages = await getMessages(convId, limit: perPage);
            await _mergeAndPersist(
              db: db,
              userId: userId,
              convId: convId,
              perPage: perPage,
              localMessages: localMessages,
              serverJsonList: messages.cast<Map<String, dynamic>>(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Preload] recent preload skipped: $e');
    }

    DataLayer().invalidate(CacheKeys.convPattern);
  }

  /// 合并服务端消息 + 本地消息，写入 SQLite + DataLayer 缓存
  Future<void> _mergeAndPersist({
    required AppDatabase db,
    required String userId,
    required int convId,
    required int perPage,
    required List localMessages,
    required List<Map<String, dynamic>> serverJsonList,
  }) async {
    final cacheKey = CacheKeys.msgRecent(convId);
    final userCacheKey = CacheKeys.msgRecentByUser(convId, userId);

    final serverMessages =
        serverJsonList.map((e) => Message.fromJson(e)).toList();

    await insertMessages(serverMessages);

    final existingIds = localMessages.map((m) => m.id).toSet();
    final newFromServer =
        serverMessages.where((m) => !existingIds.contains(m.id));
    final merged = [
      ...localMessages.whereType<Message>(),
      ...newFromServer,
    ];
    merged.sort((a, b) =>
        (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    final finalMsgs = merged.length > perPage
        ? merged.sublist(merged.length - perPage)
        : merged;

    final finalJson = finalMsgs.map((m) => m.toJson()).toList();
    await DataLayer().write(cacheKey, finalJson);
    await DataLayer().write(userCacheKey, finalJson);
  }

  /// 关闭当前数据库并删除数据库文件，用于账号切换时彻底清理旧数据。
  /// 删除失败不影响后续流程（文件可能已被删除或权限不足）。
  Future<void> deleteCurrentDb() async {
    final userId = _currentUserId;
    await _db?.close();
    _db = null;
    _currentUserId = null;
    if (userId != null) {
      try {
        await AppDatabase.deleteDatabaseFile(userId);
      } catch (_) {
        // 删除失败不阻塞，文件可能已被删除或权限不足
      }
    }
  }
}
