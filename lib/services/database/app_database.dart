import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'database_io.dart' if (dart.library.html) 'database_web.dart';

part 'app_database.g.dart';

// ═══════════════════════════════════════════════════════════════════════
//  Table 定义
//
//  Schema 版本演进规则（写在前面，团队必读）：
//  1. 修改表结构 = schemaVersion +1
//  2. onUpgrade 中追加 `if (from < N) { ... }` 分支，N = 新版本号
//  3. 已发布的 onUpgrade 分支【永不修改】，只追加新分支
//  4. 破坏性变更必须注释 `// DESTRUCTIVE:` 并说明原因
//  5. beforeOpen 会校验关键表存在，schema 损坏时直接抛错
//
//  版本历史：
//  - v1 (2026-06): 首版基线
//      · messages_table, conversations_table
//      · cache, offline_queue, app_meta
//      · idx_msg_conv 索引
// ═══════════════════════════════════════════════════════════════════════

/// 聊天消息表
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
  IntColumn get seq => integer().nullable()(); // 服务端消息序号
  TextColumn get status =>
      text().withDefault(const Constant('sent'))(); // sending/sent/failed

  @override
  Set<Column> get primaryKey => {id};
}

/// 会话表
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

/// L2 缓存表 —— DataLayer.write() 的持久化落点。
/// data_version 与 CacheEntry.dataVersion 对齐，用于 JSON 结构兼容。
class CacheTable extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get data => text()();
  IntColumn get createdAt => integer()();
  IntColumn get ttlSeconds => integer()();
  IntColumn get dataVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {cacheKey};

  @override
  String get tableName => 'cache';
}

/// 离线写入队列 —— DataLayer 级离线写入重放（与 WS outbox 职责不同）。
class OfflineQueueTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cacheKey => text()();
  TextColumn get data => text()();
  TextColumn get action => text().withDefault(const Constant('write'))();
  IntColumn get createdAt => integer()();

  @override
  String get tableName => 'offline_queue';
}

/// 应用元信息表 —— 记录 schema_version / app_build / last_user_id 等。
class AppMetaTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'app_meta';
}

@DriftDatabase(tables: [
  MessagesTable,
  ConversationsTable,
  CacheTable,
  OfflineQueueTable,
  AppMetaTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e);

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

  // ───────────────────────────────────────────────────────────────────
  //  Schema 版本 & 迁移策略
  //
  //  首版基线 = 1。改表结构时 +1，并在 onUpgrade 追加分支。
  //  详细规则见文件顶部注释。
  // ───────────────────────────────────────────────────────────────────

  /// 当前 schema 版本。
  @override
  int get schemaVersion => 1;

  /// 迁移元信息 key
  static const String metaKeySchemaVersion = 'schema_version';
  static const String metaKeyAppBuild = 'app_build';
  static const String metaKeyLastUserId = 'last_user_id';

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createMessageIndex();
          // 初始版本号
          await _writeMeta(metaKeySchemaVersion, schemaVersion.toString());
        },

        // 向上迁移：每个版本一个独立 block，向上累积，【永不修改已发布 block】
        onUpgrade: (Migrator m, int from, int to) async {
          // v1 → v2 示例（将来启用）：
          // if (from < 2) {
          //   await m.addColumn(messagesTable, messagesTable.editedAt);
          // }

          // 同步版本号到 app_meta（与 drift 内部版本号交叉校验）
          await _writeMeta(metaKeySchemaVersion, to.toString());
        },

        // 打开时自检 + 降级兜底。
        // Drift 没有独立 onDowngrade 回调；通过 beforeOpen 的
        // OpeningDetails.versionBefore > versionNow 检测降级，
        // 清空用户业务数据避免读未来版本写下的脏数据。
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON');

          // 降级（应用商店回滚 / 灰度回退）：清空业务数据，下次启动从服务端重拉
          final before = details.versionBefore;
          if (before != null && before > details.versionNow) {
            debugPrint(
                '[DB] downgrade $before → ${details.versionNow}: wiping user data');
            await _wipeAllUserData();
            await _writeMeta(
                metaKeySchemaVersion, details.versionNow.toString());
            return;
          }

          if (details.wasCreated) return;

          // 完整性自检：确保关键表都存在，防止库文件损坏导致脏读
          final tables = await customSelect(
            "SELECT name FROM sqlite_master WHERE type='table'",
          ).get();
          final names = tables.map((r) => r.read<String>('name')).toSet();
          const required = [
            'messages_table',
            'conversations_table',
            'cache',
            'offline_queue',
            'app_meta',
          ];
          for (final t in required) {
            if (!names.contains(t)) {
              throw StateError('[DB] schema corrupt: missing table $t');
            }
          }
        },
      );

  // ── 迁移辅助 ──

  Future<void> _createMessageIndex() async {
    try {
      await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages_table (conversation_id, created_at)');
    } catch (_) {}
  }

  Future<void> _writeMeta(String key, String value) async {
    try {
      await customStatement(
        'INSERT OR REPLACE INTO app_meta (key, value, updated_at) VALUES (?, ?, ?)',
        [key, value, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (_) {}
  }

  /// 清空所有用户业务数据（messages / conversations / cache / offline_queue），
  /// 不删表结构。用于 onDowngrade 兜底。
  Future<void> _wipeAllUserData() async {
    for (final stmt in [
      'DELETE FROM messages_table',
      'DELETE FROM conversations_table',
      'DELETE FROM cache',
      'DELETE FROM offline_queue',
    ]) {
      try {
        await customStatement(stmt);
      } catch (_) {}
    }
  }

  // ==================== AppMeta DAO ====================

  Future<String?> readMeta(String key) async {
    try {
      final r = await customSelect(
        'SELECT value FROM app_meta WHERE key = ?',
        variables: [Variable.withString(key)],
      ).getSingleOrNull();
      return r?.read<String>('value');
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMeta(String key, String value) => _writeMeta(key, value);

  // ==================== Cache DAO ====================
  //
  // 缓存数据格式：由 CacheEnvelope 编码后的 JSON 字符串，
  // data_version 字段与 CacheEnvelope 的版本号保持一致，便于按版本兼容解码。

  Future<({String data, int dataVersion})?> cacheGet(String key) async {
    final result = await customSelect(
      'SELECT data, created_at, ttl_seconds, data_version FROM cache WHERE cache_key = ?',
      variables: [Variable.withString(key)],
    ).getSingleOrNull();
    if (result == null) return null;
    final data = result.read<String>('data');
    final createdAt = result.read<int>('created_at');
    final ttl = result.read<int>('ttl_seconds');
    final dataVersion = result.read<int>('data_version');
    if (ttl > 0) {
      final expireAt = DateTime.fromMillisecondsSinceEpoch(createdAt)
          .add(Duration(seconds: ttl));
      if (DateTime.now().isAfter(expireAt)) {
        await cacheDelete(key);
        return null;
      }
    }
    return (data: data, dataVersion: dataVersion);
  }

  Future<void> cacheSet(String key, String data,
          {int ttlSeconds = 300, int dataVersion = 1}) =>
      customStatement(
        'INSERT OR REPLACE INTO cache (cache_key, data, created_at, ttl_seconds, data_version) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          key,
          data,
          DateTime.now().millisecondsSinceEpoch,
          ttlSeconds,
          dataVersion,
        ],
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
              id: r.read<int>('id'),
              cacheKey: r.read<String>('cache_key'),
              data: r.read<String>('data'),
              action: r.read<String>('action'),
              createdAt: r.read<int>('created_at'),
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
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.id.isBiggerThanValue(afterId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> markMessagesRead(int conversationId) => (update(messagesTable)
        ..where((t) =>
            t.conversationId.equals(conversationId) & t.isRead.equals(false)))
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
        'UPDATE conversations_table SET unread_count = unread_count + ?, '
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
      'SELECT id FROM messages_table WHERE conversation_id = ? '
      'AND (created_at < ? OR id NOT IN ('
      '  SELECT id FROM messages_table WHERE conversation_id = ? '
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

    final ids = idsToDelete.map((r) => r.read<int>('id')).toList();
    int deleted = 0;
    for (int i = 0; i < ids.length; i += 200) {
      final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
      final placeholders = chunk.map((_) => '?').join(',');
      await customStatement(
        'DELETE FROM messages_table WHERE id IN ($placeholders)',
        chunk,
      );
      deleted += chunk.length;
    }
    return deleted;
  }

  Future<List<int>> getPrunableConversationIds({int? excludeConvId}) async {
    final query = excludeConvId != null
        ? 'SELECT DISTINCT conversation_id FROM messages_table WHERE conversation_id != ?'
        : 'SELECT DISTINCT conversation_id FROM messages_table';
    final vars = excludeConvId != null
        ? [Variable.withInt(excludeConvId)]
        : <Variable<Object>>[];
    final result = await customSelect(query, variables: vars).get();
    return result.map((r) => r.read<int>('conversation_id')).toList();
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
