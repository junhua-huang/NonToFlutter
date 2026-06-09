/// Drift 表定义
///
/// 定义发件箱表（outbox）和同步状态表（sync_state）。
library;

import 'package:drift/drift.dart';

/// 发件箱表
///
/// 存储客户端已发送但未确认的消息。
/// 支持按状态和时间排序以快速加载待重试消息。
@DataClassName('OutboxEntry')
class Outbox extends Table {
  /// 客户端生成的 UUID，作为主键
  TextColumn get clientMsgId => text()();

  /// 业务消息 JSON 字符串
  TextColumn get payload => text()();

  /// 创建时间毫秒时间戳，用于按序重发
  IntColumn get timestamp => integer()();

  /// 已重试次数，默认 0
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// 消息状态：pending / acked / failed
  TextColumn get status => text().withLength(min: 1, max: 10)();

  @override
  Set<Column> get primaryKey => {clientMsgId};

  /// 快速加载待重试消息的联合索引
  @override
  List<String> get customConstraints => [
        'CHECK(status IN (\'pending\', \'acked\', \'failed\'))',
      ];
}

/// 同步状态表
///
/// 单行记录，存储已交付给业务层的最大序号和最近一次同步时间。
@DataClassName('SyncStateEntry')
class SyncState extends Table {
  /// 主键，固定为 1（单行记录）
  IntColumn get id => integer()();

  /// 已交付给业务层的最大序号，默认 0
  IntColumn get lastReceivedSeq => integer().withDefault(const Constant(0))();

  /// 最近一次成功同步的时间戳（毫秒），可为空
  IntColumn get lastSyncTime => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
