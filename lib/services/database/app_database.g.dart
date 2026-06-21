// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MessagesTableTable extends MessagesTable
    with TableInfo<$MessagesTableTable, MessagesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<int> senderId = GeneratedColumn<int>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mediaUrlMeta =
      const VerificationMeta('mediaUrl');
  @override
  late final GeneratedColumn<String> mediaUrl = GeneratedColumn<String>(
      'media_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _messageTypeMeta =
      const VerificationMeta('messageType');
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
      'message_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('text'));
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _requestIdMeta =
      const VerificationMeta('requestId');
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
      'request_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('sent'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        conversationId,
        senderId,
        content,
        mediaUrl,
        messageType,
        isRead,
        createdAt,
        requestId,
        seq,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages_table';
  @override
  VerificationContext validateIntegrity(Insertable<MessagesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('media_url')) {
      context.handle(_mediaUrlMeta,
          mediaUrl.isAcceptableOrUnknown(data['media_url']!, _mediaUrlMeta));
    }
    if (data.containsKey('message_type')) {
      context.handle(
          _messageTypeMeta,
          messageType.isAcceptableOrUnknown(
              data['message_type']!, _messageTypeMeta));
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(_requestIdMeta,
          requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta));
    }
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MessagesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessagesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}conversation_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sender_id'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content']),
      mediaUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_url']),
      messageType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_type'])!,
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at']),
      requestId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}request_id']),
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
    );
  }

  @override
  $MessagesTableTable createAlias(String alias) {
    return $MessagesTableTable(attachedDatabase, alias);
  }
}

class MessagesTableData extends DataClass
    implements Insertable<MessagesTableData> {
  final int id;
  final int conversationId;
  final int senderId;
  final String? content;
  final String? mediaUrl;
  final String messageType;
  final bool isRead;
  final int? createdAt;
  final String? requestId;
  final int? seq;
  final String status;
  const MessagesTableData(
      {required this.id,
      required this.conversationId,
      required this.senderId,
      this.content,
      this.mediaUrl,
      required this.messageType,
      required this.isRead,
      this.createdAt,
      this.requestId,
      this.seq,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    map['sender_id'] = Variable<int>(senderId);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || mediaUrl != null) {
      map['media_url'] = Variable<String>(mediaUrl);
    }
    map['message_type'] = Variable<String>(messageType);
    map['is_read'] = Variable<bool>(isRead);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    if (!nullToAbsent || requestId != null) {
      map['request_id'] = Variable<String>(requestId);
    }
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  MessagesTableCompanion toCompanion(bool nullToAbsent) {
    return MessagesTableCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      mediaUrl: mediaUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaUrl),
      messageType: Value(messageType),
      isRead: Value(isRead),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      requestId: requestId == null && nullToAbsent
          ? const Value.absent()
          : Value(requestId),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      status: Value(status),
    );
  }

  factory MessagesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessagesTableData(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      senderId: serializer.fromJson<int>(json['senderId']),
      content: serializer.fromJson<String?>(json['content']),
      mediaUrl: serializer.fromJson<String?>(json['mediaUrl']),
      messageType: serializer.fromJson<String>(json['messageType']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
      requestId: serializer.fromJson<String?>(json['requestId']),
      seq: serializer.fromJson<int?>(json['seq']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'senderId': serializer.toJson<int>(senderId),
      'content': serializer.toJson<String?>(content),
      'mediaUrl': serializer.toJson<String?>(mediaUrl),
      'messageType': serializer.toJson<String>(messageType),
      'isRead': serializer.toJson<bool>(isRead),
      'createdAt': serializer.toJson<int?>(createdAt),
      'requestId': serializer.toJson<String?>(requestId),
      'seq': serializer.toJson<int?>(seq),
      'status': serializer.toJson<String>(status),
    };
  }

  MessagesTableData copyWith(
          {int? id,
          int? conversationId,
          int? senderId,
          Value<String?> content = const Value.absent(),
          Value<String?> mediaUrl = const Value.absent(),
          String? messageType,
          bool? isRead,
          Value<int?> createdAt = const Value.absent(),
          Value<String?> requestId = const Value.absent(),
          Value<int?> seq = const Value.absent(),
          String? status}) =>
      MessagesTableData(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        senderId: senderId ?? this.senderId,
        content: content.present ? content.value : this.content,
        mediaUrl: mediaUrl.present ? mediaUrl.value : this.mediaUrl,
        messageType: messageType ?? this.messageType,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        requestId: requestId.present ? requestId.value : this.requestId,
        seq: seq.present ? seq.value : this.seq,
        status: status ?? this.status,
      );
  MessagesTableData copyWithCompanion(MessagesTableCompanion data) {
    return MessagesTableData(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      content: data.content.present ? data.content.value : this.content,
      mediaUrl: data.mediaUrl.present ? data.mediaUrl.value : this.mediaUrl,
      messageType:
          data.messageType.present ? data.messageType.value : this.messageType,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      seq: data.seq.present ? data.seq.value : this.seq,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableData(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('messageType: $messageType, ')
          ..write('isRead: $isRead, ')
          ..write('createdAt: $createdAt, ')
          ..write('requestId: $requestId, ')
          ..write('seq: $seq, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, conversationId, senderId, content,
      mediaUrl, messageType, isRead, createdAt, requestId, seq, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessagesTableData &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.content == this.content &&
          other.mediaUrl == this.mediaUrl &&
          other.messageType == this.messageType &&
          other.isRead == this.isRead &&
          other.createdAt == this.createdAt &&
          other.requestId == this.requestId &&
          other.seq == this.seq &&
          other.status == this.status);
}

class MessagesTableCompanion extends UpdateCompanion<MessagesTableData> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<int> senderId;
  final Value<String?> content;
  final Value<String?> mediaUrl;
  final Value<String> messageType;
  final Value<bool> isRead;
  final Value<int?> createdAt;
  final Value<String?> requestId;
  final Value<int?> seq;
  final Value<String> status;
  const MessagesTableCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.content = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.messageType = const Value.absent(),
    this.isRead = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.requestId = const Value.absent(),
    this.seq = const Value.absent(),
    this.status = const Value.absent(),
  });
  MessagesTableCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required int senderId,
    this.content = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.messageType = const Value.absent(),
    this.isRead = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.requestId = const Value.absent(),
    this.seq = const Value.absent(),
    this.status = const Value.absent(),
  })  : conversationId = Value(conversationId),
        senderId = Value(senderId);
  static Insertable<MessagesTableData> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<int>? senderId,
    Expression<String>? content,
    Expression<String>? mediaUrl,
    Expression<String>? messageType,
    Expression<bool>? isRead,
    Expression<int>? createdAt,
    Expression<String>? requestId,
    Expression<int>? seq,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (content != null) 'content': content,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (messageType != null) 'message_type': messageType,
      if (isRead != null) 'is_read': isRead,
      if (createdAt != null) 'created_at': createdAt,
      if (requestId != null) 'request_id': requestId,
      if (seq != null) 'seq': seq,
      if (status != null) 'status': status,
    });
  }

  MessagesTableCompanion copyWith(
      {Value<int>? id,
      Value<int>? conversationId,
      Value<int>? senderId,
      Value<String?>? content,
      Value<String?>? mediaUrl,
      Value<String>? messageType,
      Value<bool>? isRead,
      Value<int?>? createdAt,
      Value<String?>? requestId,
      Value<int?>? seq,
      Value<String>? status}) {
    return MessagesTableCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      messageType: messageType ?? this.messageType,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      requestId: requestId ?? this.requestId,
      seq: seq ?? this.seq,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<int>(senderId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (mediaUrl.present) {
      map['media_url'] = Variable<String>(mediaUrl.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesTableCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('messageType: $messageType, ')
          ..write('isRead: $isRead, ')
          ..write('createdAt: $createdAt, ')
          ..write('requestId: $requestId, ')
          ..write('seq: $seq, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTableTable extends ConversationsTable
    with TableInfo<$ConversationsTableTable, ConversationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _user1IdMeta =
      const VerificationMeta('user1Id');
  @override
  late final GeneratedColumn<int> user1Id = GeneratedColumn<int>(
      'user1_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _user2IdMeta =
      const VerificationMeta('user2Id');
  @override
  late final GeneratedColumn<int> user2Id = GeneratedColumn<int>(
      'user2_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _otherUserIdMeta =
      const VerificationMeta('otherUserId');
  @override
  late final GeneratedColumn<int> otherUserId = GeneratedColumn<int>(
      'other_user_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _otherUserNameMeta =
      const VerificationMeta('otherUserName');
  @override
  late final GeneratedColumn<String> otherUserName = GeneratedColumn<String>(
      'other_user_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _otherUserAvatarMeta =
      const VerificationMeta('otherUserAvatar');
  @override
  late final GeneratedColumn<String> otherUserAvatar = GeneratedColumn<String>(
      'other_user_avatar', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _otherUserUsernameMeta =
      const VerificationMeta('otherUserUsername');
  @override
  late final GeneratedColumn<String> otherUserUsername =
      GeneratedColumn<String>('other_user_username', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageMeta =
      const VerificationMeta('lastMessage');
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
      'last_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageAtMeta =
      const VerificationMeta('lastMessageAt');
  @override
  late final GeneratedColumn<int> lastMessageAt = GeneratedColumn<int>(
      'last_message_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _unreadCountMeta =
      const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
      'unread_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isOnlineMeta =
      const VerificationMeta('isOnline');
  @override
  late final GeneratedColumn<bool> isOnline = GeneratedColumn<bool>(
      'is_online', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_online" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        user1Id,
        user2Id,
        otherUserId,
        otherUserName,
        otherUserAvatar,
        otherUserUsername,
        lastMessage,
        lastMessageAt,
        unreadCount,
        isOnline,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<ConversationsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user1_id')) {
      context.handle(_user1IdMeta,
          user1Id.isAcceptableOrUnknown(data['user1_id']!, _user1IdMeta));
    }
    if (data.containsKey('user2_id')) {
      context.handle(_user2IdMeta,
          user2Id.isAcceptableOrUnknown(data['user2_id']!, _user2IdMeta));
    }
    if (data.containsKey('other_user_id')) {
      context.handle(
          _otherUserIdMeta,
          otherUserId.isAcceptableOrUnknown(
              data['other_user_id']!, _otherUserIdMeta));
    }
    if (data.containsKey('other_user_name')) {
      context.handle(
          _otherUserNameMeta,
          otherUserName.isAcceptableOrUnknown(
              data['other_user_name']!, _otherUserNameMeta));
    }
    if (data.containsKey('other_user_avatar')) {
      context.handle(
          _otherUserAvatarMeta,
          otherUserAvatar.isAcceptableOrUnknown(
              data['other_user_avatar']!, _otherUserAvatarMeta));
    }
    if (data.containsKey('other_user_username')) {
      context.handle(
          _otherUserUsernameMeta,
          otherUserUsername.isAcceptableOrUnknown(
              data['other_user_username']!, _otherUserUsernameMeta));
    }
    if (data.containsKey('last_message')) {
      context.handle(
          _lastMessageMeta,
          lastMessage.isAcceptableOrUnknown(
              data['last_message']!, _lastMessageMeta));
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
          _lastMessageAtMeta,
          lastMessageAt.isAcceptableOrUnknown(
              data['last_message_at']!, _lastMessageAtMeta));
    }
    if (data.containsKey('unread_count')) {
      context.handle(
          _unreadCountMeta,
          unreadCount.isAcceptableOrUnknown(
              data['unread_count']!, _unreadCountMeta));
    }
    if (data.containsKey('is_online')) {
      context.handle(_isOnlineMeta,
          isOnline.isAcceptableOrUnknown(data['is_online']!, _isOnlineMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      user1Id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}user1_id']),
      user2Id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}user2_id']),
      otherUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}other_user_id']),
      otherUserName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}other_user_name']),
      otherUserAvatar: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}other_user_avatar']),
      otherUserUsername: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}other_user_username']),
      lastMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_message']),
      lastMessageAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_message_at']),
      unreadCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unread_count'])!,
      isOnline: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_online'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at']),
    );
  }

  @override
  $ConversationsTableTable createAlias(String alias) {
    return $ConversationsTableTable(attachedDatabase, alias);
  }
}

class ConversationsTableData extends DataClass
    implements Insertable<ConversationsTableData> {
  final int id;
  final int? user1Id;
  final int? user2Id;
  final int? otherUserId;
  final String? otherUserName;
  final String? otherUserAvatar;
  final String? otherUserUsername;
  final String? lastMessage;
  final int? lastMessageAt;
  final int unreadCount;
  final bool isOnline;
  final int? createdAt;
  const ConversationsTableData(
      {required this.id,
      this.user1Id,
      this.user2Id,
      this.otherUserId,
      this.otherUserName,
      this.otherUserAvatar,
      this.otherUserUsername,
      this.lastMessage,
      this.lastMessageAt,
      required this.unreadCount,
      required this.isOnline,
      this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || user1Id != null) {
      map['user1_id'] = Variable<int>(user1Id);
    }
    if (!nullToAbsent || user2Id != null) {
      map['user2_id'] = Variable<int>(user2Id);
    }
    if (!nullToAbsent || otherUserId != null) {
      map['other_user_id'] = Variable<int>(otherUserId);
    }
    if (!nullToAbsent || otherUserName != null) {
      map['other_user_name'] = Variable<String>(otherUserName);
    }
    if (!nullToAbsent || otherUserAvatar != null) {
      map['other_user_avatar'] = Variable<String>(otherUserAvatar);
    }
    if (!nullToAbsent || otherUserUsername != null) {
      map['other_user_username'] = Variable<String>(otherUserUsername);
    }
    if (!nullToAbsent || lastMessage != null) {
      map['last_message'] = Variable<String>(lastMessage);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<int>(lastMessageAt);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['is_online'] = Variable<bool>(isOnline);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<int>(createdAt);
    }
    return map;
  }

  ConversationsTableCompanion toCompanion(bool nullToAbsent) {
    return ConversationsTableCompanion(
      id: Value(id),
      user1Id: user1Id == null && nullToAbsent
          ? const Value.absent()
          : Value(user1Id),
      user2Id: user2Id == null && nullToAbsent
          ? const Value.absent()
          : Value(user2Id),
      otherUserId: otherUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(otherUserId),
      otherUserName: otherUserName == null && nullToAbsent
          ? const Value.absent()
          : Value(otherUserName),
      otherUserAvatar: otherUserAvatar == null && nullToAbsent
          ? const Value.absent()
          : Value(otherUserAvatar),
      otherUserUsername: otherUserUsername == null && nullToAbsent
          ? const Value.absent()
          : Value(otherUserUsername),
      lastMessage: lastMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessage),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      unreadCount: Value(unreadCount),
      isOnline: Value(isOnline),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
    );
  }

  factory ConversationsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationsTableData(
      id: serializer.fromJson<int>(json['id']),
      user1Id: serializer.fromJson<int?>(json['user1Id']),
      user2Id: serializer.fromJson<int?>(json['user2Id']),
      otherUserId: serializer.fromJson<int?>(json['otherUserId']),
      otherUserName: serializer.fromJson<String?>(json['otherUserName']),
      otherUserAvatar: serializer.fromJson<String?>(json['otherUserAvatar']),
      otherUserUsername:
          serializer.fromJson<String?>(json['otherUserUsername']),
      lastMessage: serializer.fromJson<String?>(json['lastMessage']),
      lastMessageAt: serializer.fromJson<int?>(json['lastMessageAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      isOnline: serializer.fromJson<bool>(json['isOnline']),
      createdAt: serializer.fromJson<int?>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'user1Id': serializer.toJson<int?>(user1Id),
      'user2Id': serializer.toJson<int?>(user2Id),
      'otherUserId': serializer.toJson<int?>(otherUserId),
      'otherUserName': serializer.toJson<String?>(otherUserName),
      'otherUserAvatar': serializer.toJson<String?>(otherUserAvatar),
      'otherUserUsername': serializer.toJson<String?>(otherUserUsername),
      'lastMessage': serializer.toJson<String?>(lastMessage),
      'lastMessageAt': serializer.toJson<int?>(lastMessageAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'isOnline': serializer.toJson<bool>(isOnline),
      'createdAt': serializer.toJson<int?>(createdAt),
    };
  }

  ConversationsTableData copyWith(
          {int? id,
          Value<int?> user1Id = const Value.absent(),
          Value<int?> user2Id = const Value.absent(),
          Value<int?> otherUserId = const Value.absent(),
          Value<String?> otherUserName = const Value.absent(),
          Value<String?> otherUserAvatar = const Value.absent(),
          Value<String?> otherUserUsername = const Value.absent(),
          Value<String?> lastMessage = const Value.absent(),
          Value<int?> lastMessageAt = const Value.absent(),
          int? unreadCount,
          bool? isOnline,
          Value<int?> createdAt = const Value.absent()}) =>
      ConversationsTableData(
        id: id ?? this.id,
        user1Id: user1Id.present ? user1Id.value : this.user1Id,
        user2Id: user2Id.present ? user2Id.value : this.user2Id,
        otherUserId: otherUserId.present ? otherUserId.value : this.otherUserId,
        otherUserName:
            otherUserName.present ? otherUserName.value : this.otherUserName,
        otherUserAvatar: otherUserAvatar.present
            ? otherUserAvatar.value
            : this.otherUserAvatar,
        otherUserUsername: otherUserUsername.present
            ? otherUserUsername.value
            : this.otherUserUsername,
        lastMessage: lastMessage.present ? lastMessage.value : this.lastMessage,
        lastMessageAt:
            lastMessageAt.present ? lastMessageAt.value : this.lastMessageAt,
        unreadCount: unreadCount ?? this.unreadCount,
        isOnline: isOnline ?? this.isOnline,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
      );
  ConversationsTableData copyWithCompanion(ConversationsTableCompanion data) {
    return ConversationsTableData(
      id: data.id.present ? data.id.value : this.id,
      user1Id: data.user1Id.present ? data.user1Id.value : this.user1Id,
      user2Id: data.user2Id.present ? data.user2Id.value : this.user2Id,
      otherUserId:
          data.otherUserId.present ? data.otherUserId.value : this.otherUserId,
      otherUserName: data.otherUserName.present
          ? data.otherUserName.value
          : this.otherUserName,
      otherUserAvatar: data.otherUserAvatar.present
          ? data.otherUserAvatar.value
          : this.otherUserAvatar,
      otherUserUsername: data.otherUserUsername.present
          ? data.otherUserUsername.value
          : this.otherUserUsername,
      lastMessage:
          data.lastMessage.present ? data.lastMessage.value : this.lastMessage,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      unreadCount:
          data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      isOnline: data.isOnline.present ? data.isOnline.value : this.isOnline,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableData(')
          ..write('id: $id, ')
          ..write('user1Id: $user1Id, ')
          ..write('user2Id: $user2Id, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('otherUserName: $otherUserName, ')
          ..write('otherUserAvatar: $otherUserAvatar, ')
          ..write('otherUserUsername: $otherUserUsername, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isOnline: $isOnline, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      user1Id,
      user2Id,
      otherUserId,
      otherUserName,
      otherUserAvatar,
      otherUserUsername,
      lastMessage,
      lastMessageAt,
      unreadCount,
      isOnline,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationsTableData &&
          other.id == this.id &&
          other.user1Id == this.user1Id &&
          other.user2Id == this.user2Id &&
          other.otherUserId == this.otherUserId &&
          other.otherUserName == this.otherUserName &&
          other.otherUserAvatar == this.otherUserAvatar &&
          other.otherUserUsername == this.otherUserUsername &&
          other.lastMessage == this.lastMessage &&
          other.lastMessageAt == this.lastMessageAt &&
          other.unreadCount == this.unreadCount &&
          other.isOnline == this.isOnline &&
          other.createdAt == this.createdAt);
}

class ConversationsTableCompanion
    extends UpdateCompanion<ConversationsTableData> {
  final Value<int> id;
  final Value<int?> user1Id;
  final Value<int?> user2Id;
  final Value<int?> otherUserId;
  final Value<String?> otherUserName;
  final Value<String?> otherUserAvatar;
  final Value<String?> otherUserUsername;
  final Value<String?> lastMessage;
  final Value<int?> lastMessageAt;
  final Value<int> unreadCount;
  final Value<bool> isOnline;
  final Value<int?> createdAt;
  const ConversationsTableCompanion({
    this.id = const Value.absent(),
    this.user1Id = const Value.absent(),
    this.user2Id = const Value.absent(),
    this.otherUserId = const Value.absent(),
    this.otherUserName = const Value.absent(),
    this.otherUserAvatar = const Value.absent(),
    this.otherUserUsername = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ConversationsTableCompanion.insert({
    this.id = const Value.absent(),
    this.user1Id = const Value.absent(),
    this.user2Id = const Value.absent(),
    this.otherUserId = const Value.absent(),
    this.otherUserName = const Value.absent(),
    this.otherUserAvatar = const Value.absent(),
    this.otherUserUsername = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  static Insertable<ConversationsTableData> custom({
    Expression<int>? id,
    Expression<int>? user1Id,
    Expression<int>? user2Id,
    Expression<int>? otherUserId,
    Expression<String>? otherUserName,
    Expression<String>? otherUserAvatar,
    Expression<String>? otherUserUsername,
    Expression<String>? lastMessage,
    Expression<int>? lastMessageAt,
    Expression<int>? unreadCount,
    Expression<bool>? isOnline,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (user1Id != null) 'user1_id': user1Id,
      if (user2Id != null) 'user2_id': user2Id,
      if (otherUserId != null) 'other_user_id': otherUserId,
      if (otherUserName != null) 'other_user_name': otherUserName,
      if (otherUserAvatar != null) 'other_user_avatar': otherUserAvatar,
      if (otherUserUsername != null) 'other_user_username': otherUserUsername,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isOnline != null) 'is_online': isOnline,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ConversationsTableCompanion copyWith(
      {Value<int>? id,
      Value<int?>? user1Id,
      Value<int?>? user2Id,
      Value<int?>? otherUserId,
      Value<String?>? otherUserName,
      Value<String?>? otherUserAvatar,
      Value<String?>? otherUserUsername,
      Value<String?>? lastMessage,
      Value<int?>? lastMessageAt,
      Value<int>? unreadCount,
      Value<bool>? isOnline,
      Value<int?>? createdAt}) {
    return ConversationsTableCompanion(
      id: id ?? this.id,
      user1Id: user1Id ?? this.user1Id,
      user2Id: user2Id ?? this.user2Id,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserAvatar: otherUserAvatar ?? this.otherUserAvatar,
      otherUserUsername: otherUserUsername ?? this.otherUserUsername,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (user1Id.present) {
      map['user1_id'] = Variable<int>(user1Id.value);
    }
    if (user2Id.present) {
      map['user2_id'] = Variable<int>(user2Id.value);
    }
    if (otherUserId.present) {
      map['other_user_id'] = Variable<int>(otherUserId.value);
    }
    if (otherUserName.present) {
      map['other_user_name'] = Variable<String>(otherUserName.value);
    }
    if (otherUserAvatar.present) {
      map['other_user_avatar'] = Variable<String>(otherUserAvatar.value);
    }
    if (otherUserUsername.present) {
      map['other_user_username'] = Variable<String>(otherUserUsername.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<int>(lastMessageAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isOnline.present) {
      map['is_online'] = Variable<bool>(isOnline.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsTableCompanion(')
          ..write('id: $id, ')
          ..write('user1Id: $user1Id, ')
          ..write('user2Id: $user2Id, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('otherUserName: $otherUserName, ')
          ..write('otherUserAvatar: $otherUserAvatar, ')
          ..write('otherUserUsername: $otherUserUsername, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isOnline: $isOnline, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CacheTableTable extends CacheTable
    with TableInfo<$CacheTableTable, CacheTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta =
      const VerificationMeta('cacheKey');
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
      'cache_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ttlSecondsMeta =
      const VerificationMeta('ttlSeconds');
  @override
  late final GeneratedColumn<int> ttlSeconds = GeneratedColumn<int>(
      'ttl_seconds', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dataVersionMeta =
      const VerificationMeta('dataVersion');
  @override
  late final GeneratedColumn<int> dataVersion = GeneratedColumn<int>(
      'data_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns =>
      [cacheKey, data, createdAt, ttlSeconds, dataVersion];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache';
  @override
  VerificationContext validateIntegrity(Insertable<CacheTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(_cacheKeyMeta,
          cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta));
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('ttl_seconds')) {
      context.handle(
          _ttlSecondsMeta,
          ttlSeconds.isAcceptableOrUnknown(
              data['ttl_seconds']!, _ttlSecondsMeta));
    } else if (isInserting) {
      context.missing(_ttlSecondsMeta);
    }
    if (data.containsKey('data_version')) {
      context.handle(
          _dataVersionMeta,
          dataVersion.isAcceptableOrUnknown(
              data['data_version']!, _dataVersionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  CacheTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheTableData(
      cacheKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cache_key'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      ttlSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ttl_seconds'])!,
      dataVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}data_version'])!,
    );
  }

  @override
  $CacheTableTable createAlias(String alias) {
    return $CacheTableTable(attachedDatabase, alias);
  }
}

class CacheTableData extends DataClass implements Insertable<CacheTableData> {
  final String cacheKey;
  final String data;
  final int createdAt;
  final int ttlSeconds;
  final int dataVersion;
  const CacheTableData(
      {required this.cacheKey,
      required this.data,
      required this.createdAt,
      required this.ttlSeconds,
      required this.dataVersion});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['data'] = Variable<String>(data);
    map['created_at'] = Variable<int>(createdAt);
    map['ttl_seconds'] = Variable<int>(ttlSeconds);
    map['data_version'] = Variable<int>(dataVersion);
    return map;
  }

  CacheTableCompanion toCompanion(bool nullToAbsent) {
    return CacheTableCompanion(
      cacheKey: Value(cacheKey),
      data: Value(data),
      createdAt: Value(createdAt),
      ttlSeconds: Value(ttlSeconds),
      dataVersion: Value(dataVersion),
    );
  }

  factory CacheTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheTableData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      data: serializer.fromJson<String>(json['data']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      ttlSeconds: serializer.fromJson<int>(json['ttlSeconds']),
      dataVersion: serializer.fromJson<int>(json['dataVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'data': serializer.toJson<String>(data),
      'createdAt': serializer.toJson<int>(createdAt),
      'ttlSeconds': serializer.toJson<int>(ttlSeconds),
      'dataVersion': serializer.toJson<int>(dataVersion),
    };
  }

  CacheTableData copyWith(
          {String? cacheKey,
          String? data,
          int? createdAt,
          int? ttlSeconds,
          int? dataVersion}) =>
      CacheTableData(
        cacheKey: cacheKey ?? this.cacheKey,
        data: data ?? this.data,
        createdAt: createdAt ?? this.createdAt,
        ttlSeconds: ttlSeconds ?? this.ttlSeconds,
        dataVersion: dataVersion ?? this.dataVersion,
      );
  CacheTableData copyWithCompanion(CacheTableCompanion data) {
    return CacheTableData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      data: data.data.present ? data.data.value : this.data,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      ttlSeconds:
          data.ttlSeconds.present ? data.ttlSeconds.value : this.ttlSeconds,
      dataVersion:
          data.dataVersion.present ? data.dataVersion.value : this.dataVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheTableData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('data: $data, ')
          ..write('createdAt: $createdAt, ')
          ..write('ttlSeconds: $ttlSeconds, ')
          ..write('dataVersion: $dataVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cacheKey, data, createdAt, ttlSeconds, dataVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheTableData &&
          other.cacheKey == this.cacheKey &&
          other.data == this.data &&
          other.createdAt == this.createdAt &&
          other.ttlSeconds == this.ttlSeconds &&
          other.dataVersion == this.dataVersion);
}

class CacheTableCompanion extends UpdateCompanion<CacheTableData> {
  final Value<String> cacheKey;
  final Value<String> data;
  final Value<int> createdAt;
  final Value<int> ttlSeconds;
  final Value<int> dataVersion;
  final Value<int> rowid;
  const CacheTableCompanion({
    this.cacheKey = const Value.absent(),
    this.data = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.ttlSeconds = const Value.absent(),
    this.dataVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheTableCompanion.insert({
    required String cacheKey,
    required String data,
    required int createdAt,
    required int ttlSeconds,
    this.dataVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : cacheKey = Value(cacheKey),
        data = Value(data),
        createdAt = Value(createdAt),
        ttlSeconds = Value(ttlSeconds);
  static Insertable<CacheTableData> custom({
    Expression<String>? cacheKey,
    Expression<String>? data,
    Expression<int>? createdAt,
    Expression<int>? ttlSeconds,
    Expression<int>? dataVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (data != null) 'data': data,
      if (createdAt != null) 'created_at': createdAt,
      if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
      if (dataVersion != null) 'data_version': dataVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheTableCompanion copyWith(
      {Value<String>? cacheKey,
      Value<String>? data,
      Value<int>? createdAt,
      Value<int>? ttlSeconds,
      Value<int>? dataVersion,
      Value<int>? rowid}) {
    return CacheTableCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      dataVersion: dataVersion ?? this.dataVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (ttlSeconds.present) {
      map['ttl_seconds'] = Variable<int>(ttlSeconds.value);
    }
    if (dataVersion.present) {
      map['data_version'] = Variable<int>(dataVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheTableCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('data: $data, ')
          ..write('createdAt: $createdAt, ')
          ..write('ttlSeconds: $ttlSeconds, ')
          ..write('dataVersion: $dataVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineQueueTableTable extends OfflineQueueTable
    with TableInfo<$OfflineQueueTableTable, OfflineQueueTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineQueueTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _cacheKeyMeta =
      const VerificationMeta('cacheKey');
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
      'cache_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('write'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, cacheKey, data, action, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_queue';
  @override
  VerificationContext validateIntegrity(
      Insertable<OfflineQueueTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cache_key')) {
      context.handle(_cacheKeyMeta,
          cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta));
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineQueueTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineQueueTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      cacheKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cache_key'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $OfflineQueueTableTable createAlias(String alias) {
    return $OfflineQueueTableTable(attachedDatabase, alias);
  }
}

class OfflineQueueTableData extends DataClass
    implements Insertable<OfflineQueueTableData> {
  final int id;
  final String cacheKey;
  final String data;
  final String action;
  final int createdAt;
  const OfflineQueueTableData(
      {required this.id,
      required this.cacheKey,
      required this.data,
      required this.action,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cache_key'] = Variable<String>(cacheKey);
    map['data'] = Variable<String>(data);
    map['action'] = Variable<String>(action);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  OfflineQueueTableCompanion toCompanion(bool nullToAbsent) {
    return OfflineQueueTableCompanion(
      id: Value(id),
      cacheKey: Value(cacheKey),
      data: Value(data),
      action: Value(action),
      createdAt: Value(createdAt),
    );
  }

  factory OfflineQueueTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineQueueTableData(
      id: serializer.fromJson<int>(json['id']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      data: serializer.fromJson<String>(json['data']),
      action: serializer.fromJson<String>(json['action']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'data': serializer.toJson<String>(data),
      'action': serializer.toJson<String>(action),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  OfflineQueueTableData copyWith(
          {int? id,
          String? cacheKey,
          String? data,
          String? action,
          int? createdAt}) =>
      OfflineQueueTableData(
        id: id ?? this.id,
        cacheKey: cacheKey ?? this.cacheKey,
        data: data ?? this.data,
        action: action ?? this.action,
        createdAt: createdAt ?? this.createdAt,
      );
  OfflineQueueTableData copyWithCompanion(OfflineQueueTableCompanion data) {
    return OfflineQueueTableData(
      id: data.id.present ? data.id.value : this.id,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      data: data.data.present ? data.data.value : this.data,
      action: data.action.present ? data.action.value : this.action,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineQueueTableData(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('data: $data, ')
          ..write('action: $action, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cacheKey, data, action, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineQueueTableData &&
          other.id == this.id &&
          other.cacheKey == this.cacheKey &&
          other.data == this.data &&
          other.action == this.action &&
          other.createdAt == this.createdAt);
}

class OfflineQueueTableCompanion
    extends UpdateCompanion<OfflineQueueTableData> {
  final Value<int> id;
  final Value<String> cacheKey;
  final Value<String> data;
  final Value<String> action;
  final Value<int> createdAt;
  const OfflineQueueTableCompanion({
    this.id = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.data = const Value.absent(),
    this.action = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OfflineQueueTableCompanion.insert({
    this.id = const Value.absent(),
    required String cacheKey,
    required String data,
    this.action = const Value.absent(),
    required int createdAt,
  })  : cacheKey = Value(cacheKey),
        data = Value(data),
        createdAt = Value(createdAt);
  static Insertable<OfflineQueueTableData> custom({
    Expression<int>? id,
    Expression<String>? cacheKey,
    Expression<String>? data,
    Expression<String>? action,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (data != null) 'data': data,
      if (action != null) 'action': action,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OfflineQueueTableCompanion copyWith(
      {Value<int>? id,
      Value<String>? cacheKey,
      Value<String>? data,
      Value<String>? action,
      Value<int>? createdAt}) {
    return OfflineQueueTableCompanion(
      id: id ?? this.id,
      cacheKey: cacheKey ?? this.cacheKey,
      data: data ?? this.data,
      action: action ?? this.action,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineQueueTableCompanion(')
          ..write('id: $id, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('data: $data, ')
          ..write('action: $action, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $AppMetaTableTable extends AppMetaTable
    with TableInfo<$AppMetaTableTable, AppMetaTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppMetaTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_meta';
  @override
  VerificationContext validateIntegrity(Insertable<AppMetaTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppMetaTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppMetaTableData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppMetaTableTable createAlias(String alias) {
    return $AppMetaTableTable(attachedDatabase, alias);
  }
}

class AppMetaTableData extends DataClass
    implements Insertable<AppMetaTableData> {
  final String key;
  final String value;
  final int updatedAt;
  const AppMetaTableData(
      {required this.key, required this.value, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  AppMetaTableCompanion toCompanion(bool nullToAbsent) {
    return AppMetaTableCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppMetaTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppMetaTableData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  AppMetaTableData copyWith({String? key, String? value, int? updatedAt}) =>
      AppMetaTableData(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppMetaTableData copyWithCompanion(AppMetaTableCompanion data) {
    return AppMetaTableData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaTableData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppMetaTableData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppMetaTableCompanion extends UpdateCompanion<AppMetaTableData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const AppMetaTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppMetaTableCompanion.insert({
    required String key,
    required String value,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value),
        updatedAt = Value(updatedAt);
  static Insertable<AppMetaTableData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppMetaTableCompanion copyWith(
      {Value<String>? key,
      Value<String>? value,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return AppMetaTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppMetaTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MessagesTableTable messagesTable = $MessagesTableTable(this);
  late final $ConversationsTableTable conversationsTable =
      $ConversationsTableTable(this);
  late final $CacheTableTable cacheTable = $CacheTableTable(this);
  late final $OfflineQueueTableTable offlineQueueTable =
      $OfflineQueueTableTable(this);
  late final $AppMetaTableTable appMetaTable = $AppMetaTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        messagesTable,
        conversationsTable,
        cacheTable,
        offlineQueueTable,
        appMetaTable
      ];
}

typedef $$MessagesTableTableCreateCompanionBuilder = MessagesTableCompanion
    Function({
  Value<int> id,
  required int conversationId,
  required int senderId,
  Value<String?> content,
  Value<String?> mediaUrl,
  Value<String> messageType,
  Value<bool> isRead,
  Value<int?> createdAt,
  Value<String?> requestId,
  Value<int?> seq,
  Value<String> status,
});
typedef $$MessagesTableTableUpdateCompanionBuilder = MessagesTableCompanion
    Function({
  Value<int> id,
  Value<int> conversationId,
  Value<int> senderId,
  Value<String?> content,
  Value<String?> mediaUrl,
  Value<String> messageType,
  Value<bool> isRead,
  Value<int?> createdAt,
  Value<String?> requestId,
  Value<int?> seq,
  Value<String> status,
});

class $$MessagesTableTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaUrl => $composableBuilder(
      column: $table.mediaUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get requestId => $composableBuilder(
      column: $table.requestId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaUrl => $composableBuilder(
      column: $table.mediaUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get requestId => $composableBuilder(
      column: $table.requestId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTableTable> {
  $$MessagesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<int> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$MessagesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTableTable,
    MessagesTableData,
    $$MessagesTableTableFilterComposer,
    $$MessagesTableTableOrderingComposer,
    $$MessagesTableTableAnnotationComposer,
    $$MessagesTableTableCreateCompanionBuilder,
    $$MessagesTableTableUpdateCompanionBuilder,
    (
      MessagesTableData,
      BaseReferences<_$AppDatabase, $MessagesTableTable, MessagesTableData>
    ),
    MessagesTableData,
    PrefetchHooks Function()> {
  $$MessagesTableTableTableManager(_$AppDatabase db, $MessagesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> conversationId = const Value.absent(),
            Value<int> senderId = const Value.absent(),
            Value<String?> content = const Value.absent(),
            Value<String?> mediaUrl = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<String?> requestId = const Value.absent(),
            Value<int?> seq = const Value.absent(),
            Value<String> status = const Value.absent(),
          }) =>
              MessagesTableCompanion(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            mediaUrl: mediaUrl,
            messageType: messageType,
            isRead: isRead,
            createdAt: createdAt,
            requestId: requestId,
            seq: seq,
            status: status,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int conversationId,
            required int senderId,
            Value<String?> content = const Value.absent(),
            Value<String?> mediaUrl = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
            Value<String?> requestId = const Value.absent(),
            Value<int?> seq = const Value.absent(),
            Value<String> status = const Value.absent(),
          }) =>
              MessagesTableCompanion.insert(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            mediaUrl: mediaUrl,
            messageType: messageType,
            isRead: isRead,
            createdAt: createdAt,
            requestId: requestId,
            seq: seq,
            status: status,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTableTable,
    MessagesTableData,
    $$MessagesTableTableFilterComposer,
    $$MessagesTableTableOrderingComposer,
    $$MessagesTableTableAnnotationComposer,
    $$MessagesTableTableCreateCompanionBuilder,
    $$MessagesTableTableUpdateCompanionBuilder,
    (
      MessagesTableData,
      BaseReferences<_$AppDatabase, $MessagesTableTable, MessagesTableData>
    ),
    MessagesTableData,
    PrefetchHooks Function()>;
typedef $$ConversationsTableTableCreateCompanionBuilder
    = ConversationsTableCompanion Function({
  Value<int> id,
  Value<int?> user1Id,
  Value<int?> user2Id,
  Value<int?> otherUserId,
  Value<String?> otherUserName,
  Value<String?> otherUserAvatar,
  Value<String?> otherUserUsername,
  Value<String?> lastMessage,
  Value<int?> lastMessageAt,
  Value<int> unreadCount,
  Value<bool> isOnline,
  Value<int?> createdAt,
});
typedef $$ConversationsTableTableUpdateCompanionBuilder
    = ConversationsTableCompanion Function({
  Value<int> id,
  Value<int?> user1Id,
  Value<int?> user2Id,
  Value<int?> otherUserId,
  Value<String?> otherUserName,
  Value<String?> otherUserAvatar,
  Value<String?> otherUserUsername,
  Value<String?> lastMessage,
  Value<int?> lastMessageAt,
  Value<int> unreadCount,
  Value<bool> isOnline,
  Value<int?> createdAt,
});

class $$ConversationsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get user1Id => $composableBuilder(
      column: $table.user1Id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get user2Id => $composableBuilder(
      column: $table.user2Id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get otherUserId => $composableBuilder(
      column: $table.otherUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get otherUserName => $composableBuilder(
      column: $table.otherUserName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get otherUserAvatar => $composableBuilder(
      column: $table.otherUserAvatar,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get otherUserUsername => $composableBuilder(
      column: $table.otherUserUsername,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastMessageAt => $composableBuilder(
      column: $table.lastMessageAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isOnline => $composableBuilder(
      column: $table.isOnline, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ConversationsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get user1Id => $composableBuilder(
      column: $table.user1Id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get user2Id => $composableBuilder(
      column: $table.user2Id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get otherUserId => $composableBuilder(
      column: $table.otherUserId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get otherUserName => $composableBuilder(
      column: $table.otherUserName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get otherUserAvatar => $composableBuilder(
      column: $table.otherUserAvatar,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get otherUserUsername => $composableBuilder(
      column: $table.otherUserUsername,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastMessageAt => $composableBuilder(
      column: $table.lastMessageAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isOnline => $composableBuilder(
      column: $table.isOnline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ConversationsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTableTable> {
  $$ConversationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get user1Id =>
      $composableBuilder(column: $table.user1Id, builder: (column) => column);

  GeneratedColumn<int> get user2Id =>
      $composableBuilder(column: $table.user2Id, builder: (column) => column);

  GeneratedColumn<int> get otherUserId => $composableBuilder(
      column: $table.otherUserId, builder: (column) => column);

  GeneratedColumn<String> get otherUserName => $composableBuilder(
      column: $table.otherUserName, builder: (column) => column);

  GeneratedColumn<String> get otherUserAvatar => $composableBuilder(
      column: $table.otherUserAvatar, builder: (column) => column);

  GeneratedColumn<String> get otherUserUsername => $composableBuilder(
      column: $table.otherUserUsername, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => column);

  GeneratedColumn<int> get lastMessageAt => $composableBuilder(
      column: $table.lastMessageAt, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => column);

  GeneratedColumn<bool> get isOnline =>
      $composableBuilder(column: $table.isOnline, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ConversationsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConversationsTableTable,
    ConversationsTableData,
    $$ConversationsTableTableFilterComposer,
    $$ConversationsTableTableOrderingComposer,
    $$ConversationsTableTableAnnotationComposer,
    $$ConversationsTableTableCreateCompanionBuilder,
    $$ConversationsTableTableUpdateCompanionBuilder,
    (
      ConversationsTableData,
      BaseReferences<_$AppDatabase, $ConversationsTableTable,
          ConversationsTableData>
    ),
    ConversationsTableData,
    PrefetchHooks Function()> {
  $$ConversationsTableTableTableManager(
      _$AppDatabase db, $ConversationsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> user1Id = const Value.absent(),
            Value<int?> user2Id = const Value.absent(),
            Value<int?> otherUserId = const Value.absent(),
            Value<String?> otherUserName = const Value.absent(),
            Value<String?> otherUserAvatar = const Value.absent(),
            Value<String?> otherUserUsername = const Value.absent(),
            Value<String?> lastMessage = const Value.absent(),
            Value<int?> lastMessageAt = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isOnline = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
          }) =>
              ConversationsTableCompanion(
            id: id,
            user1Id: user1Id,
            user2Id: user2Id,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatar: otherUserAvatar,
            otherUserUsername: otherUserUsername,
            lastMessage: lastMessage,
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount,
            isOnline: isOnline,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> user1Id = const Value.absent(),
            Value<int?> user2Id = const Value.absent(),
            Value<int?> otherUserId = const Value.absent(),
            Value<String?> otherUserName = const Value.absent(),
            Value<String?> otherUserAvatar = const Value.absent(),
            Value<String?> otherUserUsername = const Value.absent(),
            Value<String?> lastMessage = const Value.absent(),
            Value<int?> lastMessageAt = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isOnline = const Value.absent(),
            Value<int?> createdAt = const Value.absent(),
          }) =>
              ConversationsTableCompanion.insert(
            id: id,
            user1Id: user1Id,
            user2Id: user2Id,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatar: otherUserAvatar,
            otherUserUsername: otherUserUsername,
            lastMessage: lastMessage,
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount,
            isOnline: isOnline,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConversationsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ConversationsTableTable,
    ConversationsTableData,
    $$ConversationsTableTableFilterComposer,
    $$ConversationsTableTableOrderingComposer,
    $$ConversationsTableTableAnnotationComposer,
    $$ConversationsTableTableCreateCompanionBuilder,
    $$ConversationsTableTableUpdateCompanionBuilder,
    (
      ConversationsTableData,
      BaseReferences<_$AppDatabase, $ConversationsTableTable,
          ConversationsTableData>
    ),
    ConversationsTableData,
    PrefetchHooks Function()>;
typedef $$CacheTableTableCreateCompanionBuilder = CacheTableCompanion Function({
  required String cacheKey,
  required String data,
  required int createdAt,
  required int ttlSeconds,
  Value<int> dataVersion,
  Value<int> rowid,
});
typedef $$CacheTableTableUpdateCompanionBuilder = CacheTableCompanion Function({
  Value<String> cacheKey,
  Value<String> data,
  Value<int> createdAt,
  Value<int> ttlSeconds,
  Value<int> dataVersion,
  Value<int> rowid,
});

class $$CacheTableTableFilterComposer
    extends Composer<_$AppDatabase, $CacheTableTable> {
  $$CacheTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ttlSeconds => $composableBuilder(
      column: $table.ttlSeconds, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dataVersion => $composableBuilder(
      column: $table.dataVersion, builder: (column) => ColumnFilters(column));
}

class $$CacheTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheTableTable> {
  $$CacheTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ttlSeconds => $composableBuilder(
      column: $table.ttlSeconds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dataVersion => $composableBuilder(
      column: $table.dataVersion, builder: (column) => ColumnOrderings(column));
}

class $$CacheTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheTableTable> {
  $$CacheTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get ttlSeconds => $composableBuilder(
      column: $table.ttlSeconds, builder: (column) => column);

  GeneratedColumn<int> get dataVersion => $composableBuilder(
      column: $table.dataVersion, builder: (column) => column);
}

class $$CacheTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CacheTableTable,
    CacheTableData,
    $$CacheTableTableFilterComposer,
    $$CacheTableTableOrderingComposer,
    $$CacheTableTableAnnotationComposer,
    $$CacheTableTableCreateCompanionBuilder,
    $$CacheTableTableUpdateCompanionBuilder,
    (
      CacheTableData,
      BaseReferences<_$AppDatabase, $CacheTableTable, CacheTableData>
    ),
    CacheTableData,
    PrefetchHooks Function()> {
  $$CacheTableTableTableManager(_$AppDatabase db, $CacheTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> cacheKey = const Value.absent(),
            Value<String> data = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> ttlSeconds = const Value.absent(),
            Value<int> dataVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheTableCompanion(
            cacheKey: cacheKey,
            data: data,
            createdAt: createdAt,
            ttlSeconds: ttlSeconds,
            dataVersion: dataVersion,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String cacheKey,
            required String data,
            required int createdAt,
            required int ttlSeconds,
            Value<int> dataVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheTableCompanion.insert(
            cacheKey: cacheKey,
            data: data,
            createdAt: createdAt,
            ttlSeconds: ttlSeconds,
            dataVersion: dataVersion,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CacheTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CacheTableTable,
    CacheTableData,
    $$CacheTableTableFilterComposer,
    $$CacheTableTableOrderingComposer,
    $$CacheTableTableAnnotationComposer,
    $$CacheTableTableCreateCompanionBuilder,
    $$CacheTableTableUpdateCompanionBuilder,
    (
      CacheTableData,
      BaseReferences<_$AppDatabase, $CacheTableTable, CacheTableData>
    ),
    CacheTableData,
    PrefetchHooks Function()>;
typedef $$OfflineQueueTableTableCreateCompanionBuilder
    = OfflineQueueTableCompanion Function({
  Value<int> id,
  required String cacheKey,
  required String data,
  Value<String> action,
  required int createdAt,
});
typedef $$OfflineQueueTableTableUpdateCompanionBuilder
    = OfflineQueueTableCompanion Function({
  Value<int> id,
  Value<String> cacheKey,
  Value<String> data,
  Value<String> action,
  Value<int> createdAt,
});

class $$OfflineQueueTableTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineQueueTableTable> {
  $$OfflineQueueTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$OfflineQueueTableTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineQueueTableTable> {
  $$OfflineQueueTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$OfflineQueueTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineQueueTableTable> {
  $$OfflineQueueTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OfflineQueueTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OfflineQueueTableTable,
    OfflineQueueTableData,
    $$OfflineQueueTableTableFilterComposer,
    $$OfflineQueueTableTableOrderingComposer,
    $$OfflineQueueTableTableAnnotationComposer,
    $$OfflineQueueTableTableCreateCompanionBuilder,
    $$OfflineQueueTableTableUpdateCompanionBuilder,
    (
      OfflineQueueTableData,
      BaseReferences<_$AppDatabase, $OfflineQueueTableTable,
          OfflineQueueTableData>
    ),
    OfflineQueueTableData,
    PrefetchHooks Function()> {
  $$OfflineQueueTableTableTableManager(
      _$AppDatabase db, $OfflineQueueTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineQueueTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineQueueTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineQueueTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> cacheKey = const Value.absent(),
            Value<String> data = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
          }) =>
              OfflineQueueTableCompanion(
            id: id,
            cacheKey: cacheKey,
            data: data,
            action: action,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String cacheKey,
            required String data,
            Value<String> action = const Value.absent(),
            required int createdAt,
          }) =>
              OfflineQueueTableCompanion.insert(
            id: id,
            cacheKey: cacheKey,
            data: data,
            action: action,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OfflineQueueTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OfflineQueueTableTable,
    OfflineQueueTableData,
    $$OfflineQueueTableTableFilterComposer,
    $$OfflineQueueTableTableOrderingComposer,
    $$OfflineQueueTableTableAnnotationComposer,
    $$OfflineQueueTableTableCreateCompanionBuilder,
    $$OfflineQueueTableTableUpdateCompanionBuilder,
    (
      OfflineQueueTableData,
      BaseReferences<_$AppDatabase, $OfflineQueueTableTable,
          OfflineQueueTableData>
    ),
    OfflineQueueTableData,
    PrefetchHooks Function()>;
typedef $$AppMetaTableTableCreateCompanionBuilder = AppMetaTableCompanion
    Function({
  required String key,
  required String value,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$AppMetaTableTableUpdateCompanionBuilder = AppMetaTableCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$AppMetaTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppMetaTableTable> {
  $$AppMetaTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AppMetaTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppMetaTableTable> {
  $$AppMetaTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AppMetaTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppMetaTableTable> {
  $$AppMetaTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppMetaTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppMetaTableTable,
    AppMetaTableData,
    $$AppMetaTableTableFilterComposer,
    $$AppMetaTableTableOrderingComposer,
    $$AppMetaTableTableAnnotationComposer,
    $$AppMetaTableTableCreateCompanionBuilder,
    $$AppMetaTableTableUpdateCompanionBuilder,
    (
      AppMetaTableData,
      BaseReferences<_$AppDatabase, $AppMetaTableTable, AppMetaTableData>
    ),
    AppMetaTableData,
    PrefetchHooks Function()> {
  $$AppMetaTableTableTableManager(_$AppDatabase db, $AppMetaTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppMetaTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppMetaTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppMetaTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppMetaTableCompanion(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppMetaTableCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppMetaTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppMetaTableTable,
    AppMetaTableData,
    $$AppMetaTableTableFilterComposer,
    $$AppMetaTableTableOrderingComposer,
    $$AppMetaTableTableAnnotationComposer,
    $$AppMetaTableTableCreateCompanionBuilder,
    $$AppMetaTableTableUpdateCompanionBuilder,
    (
      AppMetaTableData,
      BaseReferences<_$AppDatabase, $AppMetaTableTable, AppMetaTableData>
    ),
    AppMetaTableData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MessagesTableTableTableManager get messagesTable =>
      $$MessagesTableTableTableManager(_db, _db.messagesTable);
  $$ConversationsTableTableTableManager get conversationsTable =>
      $$ConversationsTableTableTableManager(_db, _db.conversationsTable);
  $$CacheTableTableTableManager get cacheTable =>
      $$CacheTableTableTableManager(_db, _db.cacheTable);
  $$OfflineQueueTableTableTableManager get offlineQueueTable =>
      $$OfflineQueueTableTableTableManager(_db, _db.offlineQueueTable);
  $$AppMetaTableTableTableManager get appMetaTable =>
      $$AppMetaTableTableTableManager(_db, _db.appMetaTable);
}
