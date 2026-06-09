import 'dart:async';
import 'package:drift/drift.dart';
import 'database_io.dart' if (dart.library.html) 'database_web.dart';

part 'app_database.g.dart';

class MessagesTable extends Table {
  IntColumn get id => integer()();
  IntColumn get conversationId => integer()();
  IntColumn get senderId => integer()();
  TextColumn get content => text().nullable()();
  TextColumn get mediaUrl => text().nullable()();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer().nullable()();
  TextColumn get requestId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ConversationsTable extends Table {
  IntColumn get id => integer()();
  IntColumn get user1Id => integer().nullable()();
  IntColumn get user2Id => integer().nullable()();
  IntColumn get otherUserId => integer().nullable()();
  TextColumn get otherUserName => text().nullable()();
  TextColumn get otherUserAvatar => text().nullable()();
  TextColumn get otherUserUsername => text().nullable()();
  TextColumn get lastMessage => text().nullable()();
  IntColumn get lastMessageAt => integer().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [MessagesTable, ConversationsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(QueryExecutor e) : super(e);

  static Future<AppDatabase> forUser(String userId) async {
    final dbName = 'chat_$userId';
    final executor = await createDatabaseExecutor(dbName);
    return AppDatabase._(executor);
  }

  /// 删除指定用户的数据库文件（含 WAL/Journal 文件）。
  /// 用于账号切换时清理旧数据。Web 端为空操作。
  static Future<void> deleteDatabaseFile(String userId) async {
    final dbName = 'chat_$userId';
    await deleteDatabaseFileImpl(dbName); // conditionally imported
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await customStatement(
              'CREATE INDEX idx_msg_conv ON messages (conversation_id, created_at)');
          await _createCacheTable();
          await _createOfflineQueueTable();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await _createCacheTable();
          }
          if (from < 3) {
            await _createOfflineQueueTable();
            try {
              await customStatement(
                  'ALTER TABLE messages ADD COLUMN request_id TEXT');
            } catch (_) {}
          }
        },
      );

  Future<void> _createCacheTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cache (
        cache_key TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        ttl_seconds INTEGER NOT NULL
      )
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cache_created ON cache (created_at)');
  }

  Future<void> _createOfflineQueueTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cache_key TEXT NOT NULL,
        data TEXT NOT NULL,
        action TEXT NOT NULL DEFAULT 'write',
        created_at INTEGER NOT NULL
      )
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_offline_queue_created ON offline_queue (created_at)');
  }

  // ==================== Cache DAO ====================

  Future<String?> cacheGet(String key) async {
    final result = await customSelect(
      'SELECT data, created_at, ttl_seconds FROM cache WHERE cache_key = ?',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();
    if (result == null) return null;
    final data = result.readString('data');
    final createdAt = result.readInt('created_at');
    final ttl = result.readInt('ttl_seconds');
    if (ttl > 0) {
      final expireAt = DateTime.fromMillisecondsSinceEpoch(createdAt)
          .add(Duration(seconds: ttl));
      if (DateTime.now().isAfter(expireAt)) {
        await cacheDelete(key);
        return null;
      }
    }
    return data;
  }

  Future<void> cacheSet(String key, String data, {int ttlSeconds = 300}) =>
      customStatement(
        'INSERT OR REPLACE INTO cache (cache_key, data, created_at, ttl_seconds) '
        'VALUES (?, ?, ?, ?)',
        [key, data, DateTime.now().millisecondsSinceEpoch, ttlSeconds],
      );

  Future<void> cacheDelete(String key) =>
      customStatement('DELETE FROM cache WHERE cache_key = ?', [key]);

  Future<void> cacheDeleteLike(String pattern) =>
      customStatement('DELETE FROM cache WHERE cache_key LIKE ?', [pattern]);

  Future<void> cacheClear() => customStatement('DELETE FROM cache');

  // ==================== Offline Queue DAO ====================

  Future<void> offlineQueueInsert(
          String cacheKey, String data, String action) =>
      customStatement(
        'INSERT INTO offline_queue (cache_key, data, action, created_at) '
        'VALUES (?, ?, ?, ?)',
        [cacheKey, data, action, DateTime.now().millisecondsSinceEpoch],
      );

  Future<List<OfflineQueueRow>> offlineQueueGetAll() async {
    final result = await customSelect(
      'SELECT id, cache_key, data, action, created_at '
      'FROM offline_queue ORDER BY created_at ASC',
    ).get();
    return result
        .map((r) => OfflineQueueRow(
              id: r.readInt('id'),
              cacheKey: r.readString('cache_key'),
              data: r.readString('data'),
              action: r.readString('action'),
              createdAt: r.readInt('created_at'),
            ))
        .toList();
  }

  Future<void> offlineQueueDelete(int id) =>
      customStatement('DELETE FROM offline_queue WHERE id = ?', [id]);

  Future<void> offlineQueueClear() =>
      customStatement('DELETE FROM offline_queue');

  // ==================== Message DAO ====================

  Future<void> insertMessage(MessagesTableCompanion msg) =>
      into(messagesTable).insertOnConflictUpdate(msg);

  Future<void> insertMessages(List<MessagesTableCompanion> messages) =>
      batch((batch) {
        batch.insertAllOnConflictUpdate(messagesTable, messages);
      });

  Future<List<MessagesTableData>> getMessages(
    int conversationId, {
    int limit = 50,
    int offset = 0,
  }) =>
      (select(messagesTable)
            ..where((t) => t.conversationId.equals(conversationId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit, offset: offset))
          .get();

  Future<MessagesTableData?> getMessageAfterId(
          int conversationId, int afterId) =>
      (select(messagesTable)
            ..where((t) => t.conversationId.equals(conversationId) &
                t.id.isBiggerThanValue(afterId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> markMessagesRead(int conversationId) =>
      (update(messagesTable)
            ..where((t) => t.conversationId.equals(conversationId) &
                t.isRead.equals(false)))
          .write(const MessagesTableCompanion(isRead: Value(true)));

  Future<void> updateMessageId(int oldId, int newId) =>
      (update(messagesTable)..where((t) => t.id.equals(oldId)))
          .write(MessagesTableCompanion(id: Value(newId)));

  Future<int> getUnreadCount(int conversationId) async {
    final result = await (selectOnly(messagesTable)
          ..addColumns([messagesTable.id.count()])
          ..where(messagesTable.conversationId.equals(conversationId) &
              messagesTable.isRead.equals(false)))
        .getSingleOrNull();
    return result?.read(messagesTable.id.count()) ?? 0;
  }

  Future<void> updateMessageReadStatus(int messageId, bool isRead) =>
      (update(messagesTable)..where((t) => t.id.equals(messageId)))
          .write(MessagesTableCompanion(isRead: Value(isRead)));

  Future<void> deleteMessage(int messageId) =>
      (delete(messagesTable)..where((t) => t.id.equals(messageId))).go();

  // ==================== Conversation DAO ====================

  Future<void> insertConversation(ConversationsTableCompanion conv) =>
      into(conversationsTable).insertOnConflictUpdate(conv);

  Future<void> insertConversations(
          List<ConversationsTableCompanion> conversations) =>
      batch((batch) {
        batch.insertAllOnConflictUpdate(conversationsTable, conversations);
      });

  Future<List<ConversationsTableData>> getConversations() =>
      (select(conversationsTable)
            ..orderBy([(t) => OrderingTerm.desc(t.lastMessageAt)]))
          .get();

  Future<void> updateConversationLastMessage(
    int conversationId,
    String lastMessage,
    int lastMessageAtEpoch, {
    int unreadIncrement = 0,
  }) async {
    if (unreadIncrement > 0) {
      await customStatement(
        'UPDATE conversations SET unread_count = unread_count + ?, '
        'last_message = ?, last_message_at = ? WHERE id = ?',
        [unreadIncrement, lastMessage, lastMessageAtEpoch, conversationId],
      );
      return;
    }
    await (update(conversationsTable)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsTableCompanion(
          lastMessage: Value(lastMessage),
          lastMessageAt: Value(lastMessageAtEpoch),
        ));
  }

  Future<void> clearConversationUnread(int conversationId) =>
      (update(conversationsTable)..where((t) => t.id.equals(conversationId)))
          .write(const ConversationsTableCompanion(unreadCount: Value(0)));

  Future<void> deleteConversation(int conversationId) async {
    await (delete(messagesTable)
          ..where((t) => t.conversationId.equals(conversationId)))
        .go();
    await (delete(conversationsTable)
          ..where((t) => t.id.equals(conversationId)))
        .go();
  }

  // ==================== Pruning ====================

  Future<int> pruneMessages(int conversationId,
      {int maxCount = 500, int maxDays = 30}) async {
    final cutoffMs =
        DateTime.now().subtract(Duration(days: maxDays)).millisecondsSinceEpoch;

    final countResult = await (selectOnly(messagesTable)
          ..addColumns([messagesTable.id.count()])
          ..where(messagesTable.conversationId.equals(conversationId)))
        .getSingleOrNull();
    final total = countResult?.read(messagesTable.id.count()) ?? 0;
    if (total <= maxCount) return 0;

    final idsToDelete = await customSelect(
      'SELECT id FROM messages WHERE conversation_id = ? '
      'AND (created_at < ? OR id NOT IN ('
      '  SELECT id FROM messages WHERE conversation_id = ? '
      '  ORDER BY created_at DESC LIMIT ?'
      '))',
      variables: [
        Variable.withInt(conversationId),
        Variable.withInt(cutoffMs),
        Variable.withInt(conversationId),
        Variable.withInt(maxCount),
      ],
    ).get();

    if (idsToDelete.isEmpty) return 0;

    final ids = idsToDelete.map((r) => r.readInt('id')).toList();
    int deleted = 0;
    for (int i = 0; i < ids.length; i += 200) {
      final chunk =
          ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
      final placeholders = chunk.map((_) => '?').join(',');
      await customStatement(
        'DELETE FROM messages WHERE id IN ($placeholders)',
        chunk,
      );
      deleted += chunk.length;
    }
    return deleted;
  }

  Future<List<int>> getPrunableConversationIds({int? excludeConvId}) async {
    final query = excludeConvId != null
        ? 'SELECT DISTINCT conversation_id FROM messages WHERE conversation_id != ?'
        : 'SELECT DISTINCT conversation_id FROM messages';
    final vars = excludeConvId != null
        ? [Variable.withInt(excludeConvId)]
        : <Variable<Object>>[];
    final result = await customSelect(query, variables: vars).get();
    return result.map((r) => r.readInt('conversation_id')).toList();
  }
}

class OfflineQueueRow {
  final int id;
  final String cacheKey;
  final String data;
  final String action;
  final int createdAt;

  const OfflineQueueRow({
    required this.id,
    required this.cacheKey,
    required this.data,
    required this.action,
    required this.createdAt,
  });
}
