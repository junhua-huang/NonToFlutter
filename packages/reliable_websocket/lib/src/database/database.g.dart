// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientMsgIdMeta =
      const VerificationMeta('clientMsgId');
  @override
  late final GeneratedColumn<String> clientMsgId = GeneratedColumn<String>(
      'client_msg_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 10),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [clientMsgId, payload, timestamp, retryCount, status];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_msg_id')) {
      context.handle(
          _clientMsgIdMeta,
          clientMsgId.isAcceptableOrUnknown(
              data['client_msg_id']!, _clientMsgIdMeta));
    } else if (isInserting) {
      context.missing(_clientMsgIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientMsgId};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      clientMsgId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_msg_id'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timestamp'])!,
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  /// 客户端生成的 UUID，作为主键
  final String clientMsgId;

  /// 业务消息 JSON 字符串
  final String payload;

  /// 创建时间毫秒时间戳，用于按序重发
  final int timestamp;

  /// 已重试次数，默认 0
  final int retryCount;

  /// 消息状态：pending / acked / failed
  final String status;
  const OutboxEntry(
      {required this.clientMsgId,
      required this.payload,
      required this.timestamp,
      required this.retryCount,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_msg_id'] = Variable<String>(clientMsgId);
    map['payload'] = Variable<String>(payload);
    map['timestamp'] = Variable<int>(timestamp);
    map['retry_count'] = Variable<int>(retryCount);
    map['status'] = Variable<String>(status);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      clientMsgId: Value(clientMsgId),
      payload: Value(payload),
      timestamp: Value(timestamp),
      retryCount: Value(retryCount),
      status: Value(status),
    );
  }

  factory OutboxEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      clientMsgId: serializer.fromJson<String>(json['clientMsgId']),
      payload: serializer.fromJson<String>(json['payload']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientMsgId': serializer.toJson<String>(clientMsgId),
      'payload': serializer.toJson<String>(payload),
      'timestamp': serializer.toJson<int>(timestamp),
      'retryCount': serializer.toJson<int>(retryCount),
      'status': serializer.toJson<String>(status),
    };
  }

  OutboxEntry copyWith(
          {String? clientMsgId,
          String? payload,
          int? timestamp,
          int? retryCount,
          String? status}) =>
      OutboxEntry(
        clientMsgId: clientMsgId ?? this.clientMsgId,
        payload: payload ?? this.payload,
        timestamp: timestamp ?? this.timestamp,
        retryCount: retryCount ?? this.retryCount,
        status: status ?? this.status,
      );
  OutboxEntry copyWithCompanion(OutboxCompanion data) {
    return OutboxEntry(
      clientMsgId:
          data.clientMsgId.present ? data.clientMsgId.value : this.clientMsgId,
      payload: data.payload.present ? data.payload.value : this.payload,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('payload: $payload, ')
          ..write('timestamp: $timestamp, ')
          ..write('retryCount: $retryCount, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(clientMsgId, payload, timestamp, retryCount, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.clientMsgId == this.clientMsgId &&
          other.payload == this.payload &&
          other.timestamp == this.timestamp &&
          other.retryCount == this.retryCount &&
          other.status == this.status);
}

class OutboxCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<String> clientMsgId;
  final Value<String> payload;
  final Value<int> timestamp;
  final Value<int> retryCount;
  final Value<String> status;
  final Value<int> rowid;
  const OutboxCompanion({
    this.clientMsgId = const Value.absent(),
    this.payload = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String clientMsgId,
    required String payload,
    required int timestamp,
    this.retryCount = const Value.absent(),
    required String status,
    this.rowid = const Value.absent(),
  })  : clientMsgId = Value(clientMsgId),
        payload = Value(payload),
        timestamp = Value(timestamp),
        status = Value(status);
  static Insertable<OutboxEntry> custom({
    Expression<String>? clientMsgId,
    Expression<String>? payload,
    Expression<int>? timestamp,
    Expression<int>? retryCount,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientMsgId != null) 'client_msg_id': clientMsgId,
      if (payload != null) 'payload': payload,
      if (timestamp != null) 'timestamp': timestamp,
      if (retryCount != null) 'retry_count': retryCount,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith(
      {Value<String>? clientMsgId,
      Value<String>? payload,
      Value<int>? timestamp,
      Value<int>? retryCount,
      Value<String>? status,
      Value<int>? rowid}) {
    return OutboxCompanion(
      clientMsgId: clientMsgId ?? this.clientMsgId,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientMsgId.present) {
      map['client_msg_id'] = Variable<String>(clientMsgId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('payload: $payload, ')
          ..write('timestamp: $timestamp, ')
          ..write('retryCount: $retryCount, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastReceivedSeqMeta =
      const VerificationMeta('lastReceivedSeq');
  @override
  late final GeneratedColumn<int> lastReceivedSeq = GeneratedColumn<int>(
      'last_received_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastSyncTimeMeta =
      const VerificationMeta('lastSyncTime');
  @override
  late final GeneratedColumn<int> lastSyncTime = GeneratedColumn<int>(
      'last_sync_time', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, lastReceivedSeq, lastSyncTime];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(Insertable<SyncStateEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_received_seq')) {
      context.handle(
          _lastReceivedSeqMeta,
          lastReceivedSeq.isAcceptableOrUnknown(
              data['last_received_seq']!, _lastReceivedSeqMeta));
    }
    if (data.containsKey('last_sync_time')) {
      context.handle(
          _lastSyncTimeMeta,
          lastSyncTime.isAcceptableOrUnknown(
              data['last_sync_time']!, _lastSyncTimeMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      lastReceivedSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_received_seq'])!,
      lastSyncTime: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_sync_time']),
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateEntry extends DataClass implements Insertable<SyncStateEntry> {
  /// 主键，固定为 1（单行记录）
  final int id;

  /// 已交付给业务层的最大序号，默认 0
  final int lastReceivedSeq;

  /// 最近一次成功同步的时间戳（毫秒），可为空
  final int? lastSyncTime;
  const SyncStateEntry(
      {required this.id, required this.lastReceivedSeq, this.lastSyncTime});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['last_received_seq'] = Variable<int>(lastReceivedSeq);
    if (!nullToAbsent || lastSyncTime != null) {
      map['last_sync_time'] = Variable<int>(lastSyncTime);
    }
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      lastReceivedSeq: Value(lastReceivedSeq),
      lastSyncTime: lastSyncTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncTime),
    );
  }

  factory SyncStateEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateEntry(
      id: serializer.fromJson<int>(json['id']),
      lastReceivedSeq: serializer.fromJson<int>(json['lastReceivedSeq']),
      lastSyncTime: serializer.fromJson<int?>(json['lastSyncTime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastReceivedSeq': serializer.toJson<int>(lastReceivedSeq),
      'lastSyncTime': serializer.toJson<int?>(lastSyncTime),
    };
  }

  SyncStateEntry copyWith(
          {int? id,
          int? lastReceivedSeq,
          Value<int?> lastSyncTime = const Value.absent()}) =>
      SyncStateEntry(
        id: id ?? this.id,
        lastReceivedSeq: lastReceivedSeq ?? this.lastReceivedSeq,
        lastSyncTime:
            lastSyncTime.present ? lastSyncTime.value : this.lastSyncTime,
      );
  SyncStateEntry copyWithCompanion(SyncStateCompanion data) {
    return SyncStateEntry(
      id: data.id.present ? data.id.value : this.id,
      lastReceivedSeq: data.lastReceivedSeq.present
          ? data.lastReceivedSeq.value
          : this.lastReceivedSeq,
      lastSyncTime: data.lastSyncTime.present
          ? data.lastSyncTime.value
          : this.lastSyncTime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateEntry(')
          ..write('id: $id, ')
          ..write('lastReceivedSeq: $lastReceivedSeq, ')
          ..write('lastSyncTime: $lastSyncTime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, lastReceivedSeq, lastSyncTime);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateEntry &&
          other.id == this.id &&
          other.lastReceivedSeq == this.lastReceivedSeq &&
          other.lastSyncTime == this.lastSyncTime);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateEntry> {
  final Value<int> id;
  final Value<int> lastReceivedSeq;
  final Value<int?> lastSyncTime;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.lastReceivedSeq = const Value.absent(),
    this.lastSyncTime = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    this.lastReceivedSeq = const Value.absent(),
    this.lastSyncTime = const Value.absent(),
  });
  static Insertable<SyncStateEntry> custom({
    Expression<int>? id,
    Expression<int>? lastReceivedSeq,
    Expression<int>? lastSyncTime,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastReceivedSeq != null) 'last_received_seq': lastReceivedSeq,
      if (lastSyncTime != null) 'last_sync_time': lastSyncTime,
    });
  }

  SyncStateCompanion copyWith(
      {Value<int>? id,
      Value<int>? lastReceivedSeq,
      Value<int?>? lastSyncTime}) {
    return SyncStateCompanion(
      id: id ?? this.id,
      lastReceivedSeq: lastReceivedSeq ?? this.lastReceivedSeq,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastReceivedSeq.present) {
      map['last_received_seq'] = Variable<int>(lastReceivedSeq.value);
    }
    if (lastSyncTime.present) {
      map['last_sync_time'] = Variable<int>(lastSyncTime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('lastReceivedSeq: $lastReceivedSeq, ')
          ..write('lastSyncTime: $lastSyncTime')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [outbox, syncState];
}

typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String clientMsgId,
  required String payload,
  required int timestamp,
  Value<int> retryCount,
  required String status,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> clientMsgId,
  Value<String> payload,
  Value<int> timestamp,
  Value<int> retryCount,
  Value<String> status,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientMsgId => $composableBuilder(
      column: $table.clientMsgId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientMsgId => $composableBuilder(
      column: $table.clientMsgId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientMsgId => $composableBuilder(
      column: $table.clientMsgId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$OutboxTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxEntry,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxEntry, BaseReferences<_$AppDatabase, $OutboxTable, OutboxEntry>),
    OutboxEntry,
    PrefetchHooks Function()> {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> clientMsgId = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> timestamp = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxCompanion(
            clientMsgId: clientMsgId,
            payload: payload,
            timestamp: timestamp,
            retryCount: retryCount,
            status: status,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String clientMsgId,
            required String payload,
            required int timestamp,
            Value<int> retryCount = const Value.absent(),
            required String status,
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxCompanion.insert(
            clientMsgId: clientMsgId,
            payload: payload,
            timestamp: timestamp,
            retryCount: retryCount,
            status: status,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxEntry,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxEntry, BaseReferences<_$AppDatabase, $OutboxTable, OutboxEntry>),
    OutboxEntry,
    PrefetchHooks Function()>;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<int> lastReceivedSeq,
  Value<int?> lastSyncTime,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<int> lastReceivedSeq,
  Value<int?> lastSyncTime,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastReceivedSeq => $composableBuilder(
      column: $table.lastReceivedSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncTime => $composableBuilder(
      column: $table.lastSyncTime, builder: (column) => ColumnFilters(column));
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastReceivedSeq => $composableBuilder(
      column: $table.lastReceivedSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncTime => $composableBuilder(
      column: $table.lastSyncTime,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lastReceivedSeq => $composableBuilder(
      column: $table.lastReceivedSeq, builder: (column) => column);

  GeneratedColumn<int> get lastSyncTime => $composableBuilder(
      column: $table.lastSyncTime, builder: (column) => column);
}

class $$SyncStateTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncStateTable,
    SyncStateEntry,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateEntry,
      BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateEntry>
    ),
    SyncStateEntry,
    PrefetchHooks Function()> {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> lastReceivedSeq = const Value.absent(),
            Value<int?> lastSyncTime = const Value.absent(),
          }) =>
              SyncStateCompanion(
            id: id,
            lastReceivedSeq: lastReceivedSeq,
            lastSyncTime: lastSyncTime,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> lastReceivedSeq = const Value.absent(),
            Value<int?> lastSyncTime = const Value.absent(),
          }) =>
              SyncStateCompanion.insert(
            id: id,
            lastReceivedSeq: lastReceivedSeq,
            lastSyncTime: lastSyncTime,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncStateTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncStateTable,
    SyncStateEntry,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateEntry,
      BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateEntry>
    ),
    SyncStateEntry,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
