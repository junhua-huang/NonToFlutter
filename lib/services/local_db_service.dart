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
      print('[DB] insertMessage failed (non-critical): $e');
    }
  }

  Future<void> insertMessages(List<Message> messages) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.insertMessages(
          messages.map(_messageToCompanion).toList());
    } catch (e) {
      print('[DB] insertMessages failed (non-critical): $e');
    }
  }

  Future<List<Message>> getMessages(int conversationId,
      {int limit = 50, int offset = 0}) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.getMessages(conversationId,
        limit: limit, offset: offset);
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
    await db.insertConversations(
        conversations.map(_conversationToCompanion).toList());
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
  }) async {
    final db = _db;
    if (db == null) return;
    await db.updateConversationLastMessage(
      conversationId,
      lastMessage,
      lastMessageAt.millisecondsSinceEpoch,
      unreadIncrement: unreadIncrement,
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
      messageType: Value(msg.messageType.name),
      isRead: Value(msg.isRead),
      createdAt: Value(msg.createdAt?.millisecondsSinceEpoch),
      requestId: Value(msg.requestId),
      seq: msg.seq != null ? Value(msg.seq) : const Value.absent(),
      status: Value(msg.status),
    );
  }

  Message _driftRowToMessage(MessagesTableData row) {
    return Message(
      id: row.id,
      conversationId: row.conversationId,
      senderId: row.senderId,
      content: row.content,
      mediaUrl: row.mediaUrl,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == row.messageType,
        orElse: () => MessageType.text,
      ),
      isRead: row.isRead,
      createdAt: row.createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.createdAt!)
          : null,
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
      lastMessageAt: Value(conv.lastMessageAt?.millisecondsSinceEpoch),
      unreadCount: Value(conv.unreadCount),
      isOnline: const Value(false),
      // Use lastMessageAt as the best available timestamp for SQLite creation order
      createdAt: Value(conv.lastMessageAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  Conversation _driftRowToConversation(ConversationsTableData row) {
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
              messageType: MessageType.text,
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
  Future<void> preloadAllConversationMessages({int perPage = 50}) async {
    final db = _db;
    if (db == null) return;

    final userId = _currentUserId;
    if (userId == null) return;

    // 1. 从持久层加载会话列表
    final conversations = await getConversations();

    final allConvIds = conversations.map((c) => c.id).toList();

    // 2. 首轮：加载本地 SQLite + warmup 缓存，让 UI 立即可用
    for (final convId in allConvIds) {
      final localMessages = await getMessages(convId, limit: perPage);
      if (localMessages.isNotEmpty) {
        final localJson = localMessages.map((m) => m.toJson()).toList();
        await DataLayer().write(CacheKeys.msgRecentByUser(convId, userId), localJson);
      }
    }

    // 3. 网络刷新：无论缓存是否命中，批量请求 ALL 会话的最新数据
    //    warmup 缓存可能来自 L2 SQLite 旧数据，必须以网络最新数据为准
    if (allConvIds.isNotEmpty) {
      try {
        debugPrint('[Preload] batch HTTP: ${allConvIds.length} convs, perPage=$perPage');
        final resp = await ChatService()
            .getBatchMessages(allConvIds, perPage: perPage)
            .timeout(const Duration(seconds: 25));
        if (resp.success && resp.data != null) {
          final data = resp.data is String
              ? (() { try { return jsonDecode(resp.data as String); } catch (_) { return {}; } })()
              : resp.data;
          final batchConversations =
              data['data']?['conversations'] ?? data['conversations'] ?? <dynamic>[];
          final receivedIds = <int>{};

          debugPrint('[Preload] batch returned ${batchConversations.length} conversations');

          for (final c in batchConversations) {
            if (c is! Map<String, dynamic>) continue;
            final convId = c['conversation_id'] ?? c['id'];
            final messages = c['messages'];
            if (convId is int && messages is List && messages.isNotEmpty) {
              receivedIds.add(convId);
              debugPrint('[Preload]   conv=$convId: ${messages.length} msgs from batch');
              final localMessages = await getMessages(convId, limit: perPage);
              await _mergeAndPersist(
                db: db,
                userId: userId,
                convId: convId,
                perPage: perPage,
                localMessages: localMessages,
                serverJsonList: messages.cast<Map<String, dynamic>>(),
              );
              // 验证写入
              final verify = await getMessages(convId, limit: 5);
              debugPrint('[Preload]   conv=$convId: after write, SQLite has ${verify.length} msgs');
            }
          }

          // 4. 批量未覆盖的会话（后端部分失败），降级为逐个请求
          for (final id in allConvIds) {
            if (!receivedIds.contains(id)) {
              try {
                await _preloadSingleConversation(
                  userId: userId, convId: id, perPage: perPage, db: db,
                );
              } catch (_) {}
            }
          }
        }
      } catch (_) {
        // 批量整体失败，降级为逐个请求
        for (final id in allConvIds) {
          try {
            await _preloadSingleConversation(
              userId: userId, convId: id, perPage: perPage, db: db,
            );
          } catch (_) {}
        }
      }
    }

    // 通知 UI 预加载完成
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
    final cacheKey = CacheKeys.msgRecentByUser(convId, userId);

    final serverMessages = serverJsonList
        .map((e) => Message.fromJson(e))
        .toList();

    await insertMessages(serverMessages);

    final existingIds = localMessages
        .map((m) => m.id)
        .toSet();
    final newFromServer = serverMessages.where((m) => !existingIds.contains(m.id));
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
  }

  /// 单个会话的网络预加载（降级路径，批量不可用时使用）
  Future<void> _preloadSingleConversation({
    required String userId,
    required int convId,
    required int perPage,
    required AppDatabase db,
  }) async {
    final localMessages = await getMessages(convId, limit: perPage);

    final resp = await ChatService().getMessages(convId, perPage: perPage);
    if (!resp.success || resp.data == null) return;

    final data = resp.data is String ? jsonDecode(resp.data as String) : resp.data;
    final serverJsonList =
        (data['messages'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    if (serverJsonList.isEmpty) return;

    await _mergeAndPersist(
      db: db,
      userId: userId,
      convId: convId,
      perPage: perPage,
      localMessages: localMessages,
      serverJsonList: serverJsonList,
    );
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

