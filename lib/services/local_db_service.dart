import 'dart:async';

import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/message.dart';
import 'package:facebook_clone/models/user.dart' as app_user;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 本地数据库服务 - 存储聊天记录（按用户账号隔离）
class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _db;
  String? _currentUserId;

  /// 初始化数据库（传入当前登录用户ID以隔离数据）
  Future<void> init(String userId) async {
    if (kIsWeb) return; // Web平台不支持本地数据库
    if (_currentUserId == userId && _db != null) return;
    await _db?.close();
    _currentUserId = userId;
    _db = await _openDb(userId);
  }

  Future<Database> _openDb(String userId) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'chat_$userId.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // 会话表
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY,
            other_user_id INTEGER,
            other_user_name TEXT,
            other_user_avatar TEXT,
            other_user_username TEXT,
            last_message TEXT,
            last_message_at INTEGER,
            unread_count INTEGER DEFAULT 0,
            is_online INTEGER DEFAULT 0,
            created_at INTEGER
          )
        ''');
        // 消息表
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY,
            conversation_id INTEGER NOT NULL,
            sender_id INTEGER NOT NULL,
            content TEXT,
            media_url TEXT,
            message_type TEXT DEFAULT 'text',
            is_read INTEGER DEFAULT 0,
            created_at INTEGER,
            synced INTEGER DEFAULT 0
          )
        ''');
        // 索引
        await db.execute(
          'CREATE INDEX idx_msg_conv ON messages(conversation_id, created_at)',
        );
      },
    );
  }

  // ==================== 消息操作 ====================

  Future<void> insertMessage(Message msg) async {
    final db = _db;
    if (db == null) return;
    await db.insert('messages', _messageToMap(msg),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertMessages(List<Message> messages) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    for (final msg in messages) {
      batch.insert('messages', _messageToMap(msg),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Message>> getMessages(int conversationId,
      {int limit = 50, int offset = 0}) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_mapToMessage).toList().reversed.toList();
  }

  Future<void> markMessagesRead(int conversationId) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'conversation_id = ? AND is_read = 0',
      whereArgs: [conversationId],
    );
  }

  Future<int> getUnreadCount(int conversationId) async {
    final db = _db;
    if (db == null) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM messages WHERE conversation_id = ? AND is_read = 0',
      [conversationId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ==================== 会话操作 ====================

  Future<void> insertConversation(Conversation conv) async {
    final db = _db;
    if (db == null) return;
    await db.insert('conversations', _conversationToMap(conv),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertConversations(List<Conversation> conversations) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    for (final conv in conversations) {
      batch.insert('conversations', _conversationToMap(conv),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Conversation>> getConversations() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query('conversations',
        orderBy: 'last_message_at DESC');
    return rows.map(_mapToConversation).toList();
  }

  Future<void> updateConversationLastMessage(
    int conversationId,
    String lastMessage,
    DateTime lastMessageAt, {
    int unreadIncrement = 0,
  }) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'conversations',
      {
        'last_message': lastMessage,
        'last_message_at': lastMessageAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    if (unreadIncrement > 0) {
      await db.rawUpdate(
        'UPDATE conversations SET unread_count = unread_count + ? WHERE id = ?',
        [unreadIncrement, conversationId],
      );
    }
  }

  Future<void> clearConversationUnread(int conversationId) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'conversations',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> deleteConversation(int conversationId) async {
    final db = _db;
    if (db == null) return;
    await db.delete('messages',
        where: 'conversation_id = ?', whereArgs: [conversationId]);
    await db.delete('conversations',
        where: 'id = ?', whereArgs: [conversationId]);
  }

  // ==================== 工具方法 ====================

  Map<String, dynamic> _messageToMap(Message msg) {
    return {
      'id': msg.id,
      'conversation_id': msg.conversationId,
      'sender_id': msg.senderId,
      'content': msg.content,
      'media_url': msg.mediaUrl,
      'message_type': msg.messageType.name,
      'is_read': msg.isRead == true ? 1 : 0,
      'created_at': msg.createdAt?.millisecondsSinceEpoch,
    };
  }

  Message _mapToMessage(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as int,
      conversationId: map['conversation_id'] as int,
      senderId: map['sender_id'] as int,
      content: map['content'] as String?,
      mediaUrl: map['media_url'] as String?,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == (map['message_type'] as String? ?? 'text'),
        orElse: () => MessageType.text,
      ),
      isRead: (map['is_read'] as int?) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> _conversationToMap(Conversation conv) {
    return {
      'id': conv.id,
      'other_user_id': conv.otherUser?.id,
      'other_user_name': conv.otherUser?.displayName,
      'other_user_avatar': conv.otherUser?.avatarUrl,
      'other_user_username': conv.otherUser?.username,
      'last_message': conv.lastMessage?.content,
      'last_message_at': conv.lastMessageAt?.millisecondsSinceEpoch,
      'unread_count': conv.unreadCount,
      'is_online': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Conversation _mapToConversation(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as int,
      user1Id: 0,
      user2Id: map['other_user_id'] as int? ?? 0,
      otherUser: map['other_user_id'] != null
          ? app_user.User(
              id: map['other_user_id'] as int,
              username: map['other_user_username'] as String? ?? '',
              email: '',
              displayName: map['other_user_name'] as String?,
              avatarUrl: map['other_user_avatar'] as String?,
            )
          : null,
      lastMessage: map['last_message'] != null
          ? Message(
              id: 0,
              conversationId: map['id'] as int,
              senderId: 0,
              content: map['last_message'] as String,
              messageType: MessageType.text,
              createdAt: map['last_message_at'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      map['last_message_at'] as int)
                  : null,
            )
          : null,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
          : null,
      unreadCount: map['unread_count'] as int? ?? 0,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _currentUserId = null;
  }
}
