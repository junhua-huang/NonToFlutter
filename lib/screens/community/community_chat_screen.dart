import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/data/emoji_data.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/chat_room_state.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/screens/community/community_detail_screen.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/api/upload_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/sound_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/utils/picker_error_utils.dart';
import 'package:nonto/widgets/twitter_bottom_sheet.dart';
import 'package:nonto/widgets/message_highlight_wrapper.dart';

/// 社群群聊页
/// 支持：发送消息、图片/视频、表情、@提及、撤回与管理员删除。
class CommunityChatScreen extends ConsumerStatefulWidget {
  final int communityId;
  final String? communityName;
  final String? communityAvatar;
  const CommunityChatScreen({
    super.key,
    required this.communityId,
    this.communityName,
    this.communityAvatar,
  });

  @override
  ConsumerState<CommunityChatScreen> createState() =>
      _CommunityChatScreenState();
}

class _CommunityChatScreenState extends ConsumerState<CommunityChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _msgFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final Set<int> _mentionUserIds = {};
  final List<Map<String, dynamic>> _messages = [];
  List<CommunityMember> _members = [];
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  int? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isMembersLoading = false;
  bool _showEmojiPicker = false;
  int _emojiTabIndex = 0;
  Map<String, dynamic>? _quotedMessage;

  /// 向上翻页：是否还有更早消息
  bool _hasMore = false;

  /// 向上翻页：当前已加载的最小 message id
  int? _oldestMessageId;
  bool _loadingMore = false;

  /// message.id → GlobalKey，用于引用跳转定位
  final Map<int, GlobalKey> _msgAnchors = {};

  /// 命中 jumpTo 后需要高亮的消息 id
  int? _highlightMessageId;

  @override
  void initState() {
    super.initState();
    _messageSub =
        WebSocketService().messageStream.listen(_appendRealtimeMessage);
    _presenceSub = WebSocketService()
        .communityPresenceStream
        .listen(_applyCommunityPresence);
    _loadMessages();
    unawaited(_loadMembersForHeader());
  }

  Future<void> _loadMessages() async {
    if (mounted) setState(() => _isLoading = _messages.isEmpty);
    await _loadCachedMessages();
    try {
      final api = CommunityApiService();
      final resp = await api.getChat(widget.communityId, limit: 50);
      if (resp.data is Map) {
        final data = Map<String, dynamic>.from(resp.data as Map);
        final conversation = data['conversation'];
        if (conversation is Map) {
          final conversationId =
              conversation['conversation_id'] ?? conversation['id'];
          _conversationId = conversationId is int
              ? conversationId
              : int.tryParse(conversationId?.toString() ?? '');
          if (_conversationId != null) {
            WebSocketService().joinConversation(_conversationId!);
            ChatRoomState.setConversation(_conversationId);
            await _markConversationRead();
            await DataLayer().write(
              CacheKeys.communityChatConversation(widget.communityId),
              Map<String, dynamic>.from(conversation),
            );
          }
        }
        if (data['messages'] is List) {
          final serverMessages = (data['messages'] as List)
              .whereType<Map>()
              .map((message) => Map<String, dynamic>.from(message))
              .toList();
          final merged = _mergeServerMessages(serverMessages);
          if (mounted) {
            setState(() {
              _messages
                ..clear()
                ..addAll(merged);
              _hasMore = data['has_more'] == true;
              _oldestMessageId =
                  _messages.isEmpty ? null : _messageId(_messages.first);
            });
          }
          await _writeMessagesCache();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markConversationRead() async {
    final conversationId = _conversationId;
    if (conversationId == null) return;

    if (WebSocketService().isConnected) {
      WebSocketService().markConversationRead(_conversationId!);
    } else {
      await ChatService().markRead(_conversationId!);
    }

    ref
        .read(conversationsProvider.notifier)
        .clearConversationUnread(_conversationId!);
  }

  Future<void> _loadCachedMessages() async {
    try {
      final snapshot = await DataLayer().query(
        CacheKeys.communityChatRecent(widget.communityId),
        () async => null,
      );
      final cached = snapshot.data;
      if (cached is List && cached.isNotEmpty && mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(cached.whereType<Map>().map(
                  (message) => Map<String, dynamic>.from(message),
                ));
          _isLoading = false;
        });
      }
    } catch (_) {}
  }

  String? _messageIdentity(Map<String, dynamic> message) {
    final id = message['id'];
    if (id != null) return id.toString();
    final clientMsgId = message['client_msg_id']?.toString();
    if (clientMsgId != null && clientMsgId.isNotEmpty) {
      return 'client:$clientMsgId';
    }
    return null;
  }

  int? _messageId(Map<String, dynamic> message) {
    final id = message['id'];
    return id is int ? id : int.tryParse(id?.toString() ?? '');
  }

  List<Map<String, dynamic>> _mergeServerMessages(
      List<Map<String, dynamic>> serverMessages) {
    final merged = <Map<String, dynamic>>[];
    final serverIds = serverMessages
        .map((message) => _messageIdentity(message))
        .where((id) => id != null)
        .toSet();
    final serverClientMsgIds = serverMessages
        .map((message) => message['client_msg_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    final pendingOptimistic = _messages.where((message) {
      final status = message['status']?.toString();
      final id = _messageIdentity(message);
      final clientMsgId = message['client_msg_id']?.toString();
      return status == 'sending' &&
          (id == null || !serverIds.contains(id)) &&
          (clientMsgId == null ||
              clientMsgId.isEmpty ||
              !serverClientMsgIds.contains(clientMsgId));
    }).map((message) => Map<String, dynamic>.from(message));
    merged
      ..addAll(serverMessages)
      ..addAll(pendingOptimistic);
    merged.sort((a, b) => _messageTime(a).compareTo(_messageTime(b)));
    return merged;
  }

  Future<void> _writeMessagesCache() async {
    final snapshot =
        _messages.map((message) => Map<String, dynamic>.from(message)).toList();
    await DataLayer().write(
      CacheKeys.communityChatRecent(widget.communityId),
      snapshot,
    );
    final conversationId = _conversationId;
    if (conversationId != null) {
      await DataLayer().write(CacheKeys.msgRecent(conversationId), snapshot);
    }
  }

  void _applyCommunityPresence(Map<String, dynamic> event) {
    final communityId = _parsePresenceInt(event['community_id']);
    final userId = _parsePresenceInt(event['user_id']);
    final isOnline = event['is_online'];
    if (communityId != widget.communityId ||
        userId == null ||
        isOnline is! bool) {
      return;
    }

    final index = _members.indexWhere((member) => member.userId == userId);
    if (index < 0) return;
    final member = _members[index];
    final user = member.user;
    if (user == null || user.isOnline == isOnline) return;

    if (!mounted) return;
    setState(() {
      _members[index] = member.copyWith(
        user: user.copyWith(isOnline: isOnline),
      );
    });
  }

  int? _parsePresenceInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  void dispose() {
    final conversationId = _conversationId;
    if (conversationId != null) {
      WebSocketService().leaveConversation(conversationId);
    }
    ChatRoomState.setConversation(null);
    _messageSub?.cancel();
    _presenceSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _msgFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty) return;
    final mentionUserIds = _mentionUserIds.toList();
    final quoted = _quotedMessage;
    final quoteMessageId = _extractQuoteId(quoted);
    final quotePreview = quoted == null ? null : _quotePreviewOf(quoted);
    final clientMsgId = _newClientMsgId();
    _msgCtrl.clear();
    final optimistic = _buildOptimisticMessage(
      content: content,
      messageType: 'text',
      mentionUserIds: mentionUserIds,
      quoteMessageId: quoteMessageId,
      quotePreview: quotePreview,
      clientMsgId: clientMsgId,
    );
    setState(() {
      _messages.add(optimistic);
      _quotedMessage = null;
    });
    _mentionUserIds.clear();
    _syncConversationPreview(content, 'text');
    unawaited(SoundService().playSendSound());
    await _writeMessagesCache();

    try {
      final resp = await CommunityApiService().sendMessage(
        widget.communityId,
        content: content,
        messageType: 'text',
        mentionUserIds: mentionUserIds,
        quoteMessageId: quoteMessageId,
        clientMsgId: clientMsgId,
      );
      _replaceOptimisticWithResponse(optimistic, resp.data);
    } catch (e) {
      if (mounted) {
        _markOptimisticFailed(optimistic['id']);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    } finally {
      await _writeMessagesCache();
    }
  }

  Map<String, dynamic> _buildOptimisticMessage({
    required String content,
    required String messageType,
    String? mediaUrl,
    List<int>? mentionUserIds,
    int? quoteMessageId,
    String? quotePreview,
    String? clientMsgId,
  }) {
    final user = ref.read(authProvider).user;
    final now = DateTime.now();
    return {
      'id': now.millisecondsSinceEpoch,
      'conversation_id': _conversationId,
      'community_id': widget.communityId,
      'sender_id': user?.id,
      'sender': {
        'id': user?.id,
        'username': user?.username ?? '',
        'display_name': user?.displayName,
        'avatar_url': user?.avatarUrl,
      },
      'content': content,
      'message_type': messageType,
      'media_url': mediaUrl,
      'mention_user_ids': mentionUserIds ?? const <int>[],
      if (quoteMessageId != null) 'quote_message_id': quoteMessageId,
      if (quotePreview != null) 'quote_preview': quotePreview,
      if (clientMsgId != null && clientMsgId.isNotEmpty)
        'client_msg_id': clientMsgId,
      'created_at': now.toIso8601String(),
      'status': 'sending',
    };
  }

  String _newClientMsgId() =>
      'community_${widget.communityId}_${DateTime.now().microsecondsSinceEpoch}';

  void _replaceOptimisticWithResponse(
      Map<String, dynamic> optimistic, dynamic responseData) {
    final serverMessage = _extractMessageMap(responseData);
    if (serverMessage == null || !mounted) return;
    _replaceOptimisticOrAppend(serverMessage, optimisticId: optimistic['id']);
  }

  Map<String, dynamic>? _extractMessageMap(dynamic data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final nested = map['message'];
      if (nested is Map) return Map<String, dynamic>.from(nested);
      return map;
    }
    return null;
  }

  void _markOptimisticFailed(dynamic optimisticId) {
    final updated = _messages.map((message) {
      if (message['id'] == optimisticId) {
        return {...message, 'status': 'failed'};
      }
      return message;
    }).toList();
    setState(() {
      _messages
        ..clear()
        ..addAll(updated);
    });
  }

  void _retryMessage(Map<String, dynamic> message) {
    final content = message['content']?.toString() ?? '';
    if (content.trim().isEmpty) return;
    final messageType = message['message_type']?.toString() ?? 'text';
    final mediaUrl = message['media_url']?.toString();
    final mentionUserIds = (message['mention_user_ids'] is List)
        ? (message['mention_user_ids'] as List)
            .map((id) => int.tryParse(id?.toString() ?? ''))
            .whereType<int>()
            .toList()
        : const <int>[];

    setState(() {
      _messages.removeWhere((item) => item['id'] == message['id']);
    });
    final clientMsgId = _newClientMsgId();
    final optimistic = _buildOptimisticMessage(
      content: content,
      messageType: messageType,
      mediaUrl: mediaUrl?.isNotEmpty == true ? mediaUrl : null,
      mentionUserIds: mentionUserIds,
      clientMsgId: clientMsgId,
    );
    setState(() => _messages.add(optimistic));
    _syncConversationPreview(content, messageType);
    unawaited(SoundService().playSendSound());
    unawaited(_writeMessagesCache());

    unawaited(() async {
      try {
        final resp = await CommunityApiService().sendMessage(
          widget.communityId,
          content: content,
          messageType: messageType,
          mediaUrl: mediaUrl?.isNotEmpty == true ? mediaUrl : null,
          mentionUserIds: mentionUserIds,
          clientMsgId: clientMsgId,
        );
        _replaceOptimisticWithResponse(optimistic, resp.data);
      } catch (e) {
        if (mounted) {
          _markOptimisticFailed(optimistic['id']);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('重试失败: $e')));
        }
      } finally {
        await _writeMessagesCache();
      }
    }());
  }

  Future<void> _recallMessage(int messageId, bool isMine) async {
    if (!isMine) return;
    try {
      await CommunityApiService().recallMessage(widget.communityId, messageId);
      _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('撤回失败: $e')));
      }
    }
  }

  /// 向上加载更早的历史消息（基于 before_id 分页）。
  Future<void> _loadMoreHistory() async {
    if (_loadingMore || !_hasMore || _oldestMessageId == null) return;
    setState(() => _loadingMore = true);
    final previousFirstId = _oldestMessageId;
    final firstKey = _msgAnchors[previousFirstId];
    final firstCtx = firstKey?.currentContext;
    // 在 setState 之前测量原"第一条"在视口中的位置，便于加载后回正。
    double? revealOffsetBefore;
    if (firstCtx != null) {
      final firstBox = firstCtx.findRenderObject() as RenderBox?;
      if (firstBox != null && firstBox.hasSize) {
        final viewport = RenderAbstractViewport.of(firstBox);
        revealOffsetBefore = viewport.getOffsetToReveal(firstBox, 0.0).offset;
      }
    }
    try {
      final resp = await CommunityApiService().getChat(
        widget.communityId,
        limit: 50,
        beforeId: previousFirstId,
      );
      if (resp.data is Map) {
        final data = Map<String, dynamic>.from(resp.data as Map);
        if (data['messages'] is List) {
          final older = (data['messages'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          if (older.isNotEmpty && mounted) {
            final existingIds = _messages
                .map((message) => _messageIdentity(message))
                .where((id) => id != null)
                .toSet();
            final uniqueOlder = older
                .where((message) {
                  final id = _messageIdentity(message);
                  return id == null || !existingIds.contains(id);
                })
                .map((message) => Map<String, dynamic>.from(message))
                .toList();
            setState(() {
              _messages
                ..insertAll(0, uniqueOlder)
                ..sort((a, b) => _messageTime(a).compareTo(_messageTime(b)));
              _hasMore = data['has_more'] == true;
              _oldestMessageId =
                  _messages.isEmpty ? null : _messageId(_messages.first);
            });
            await _writeMessagesCache();
            // 加载更早消息后，原"第一条"向下移动了 older.length 条；
            // reverse:true 下，让其回到原视口位置。
            if (revealOffsetBefore != null && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final newCtx = firstKey?.currentContext;
                if (newCtx == null) return;
                final newBox = newCtx.findRenderObject() as RenderBox?;
                if (newBox == null) return;
                final viewport = RenderAbstractViewport.of(newBox);
                final offsetToReveal =
                    viewport.getOffsetToReveal(newBox, 0.0).offset;
                _scrollCtrl.jumpTo(offsetToReveal);
                revealOffsetBefore;
              });
            }
          } else if (mounted) {
            setState(() => _hasMore = false);
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 点击引用预览条 → 定位到原消息。本地找不到时调用 around 接口拉上下文。
  Future<void> _onQuoteTap(int? quoteMessageId) async {
    if (quoteMessageId == null) return;
    final ok = await _jumpToMessage(quoteMessageId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('原消息已被删除')),
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessage(quoteMessageId);
    });
  }

  Future<bool> _jumpToMessage(int targetId) async {
    // 1) 本地已有
    if (_messages.any((m) {
      final id = m['id'];
      return (id is int ? id : int.tryParse(id?.toString() ?? '')) == targetId;
    })) {
      setState(() => _highlightMessageId = targetId);
      return true;
    }
    // 2) 拉上下文窗口
    setState(() => _isLoading = true);
    try {
      final resp = await CommunityApiService()
          .getMessagesAround(widget.communityId, targetId);
      if (resp.data is! Map) {
        if (mounted) setState(() => _isLoading = false);
        return false;
      }
      final data = Map<String, dynamic>.from(resp.data as Map);
      if (data['messages'] is! List) {
        if (mounted) setState(() => _isLoading = false);
        return false;
      }
      final window = (data['messages'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final hasTarget = window.any((m) {
        final id = m['id'];
        return (id is int ? id : int.tryParse(id?.toString() ?? '')) ==
            targetId;
      });
      if (!hasTarget) {
        if (mounted) setState(() => _isLoading = false);
        return false;
      }
      if (mounted) {
        setState(() {
          _messages
            ..clear()
            ..addAll(window);
          _hasMore = data['has_more_before'] == true;
          _oldestMessageId = window.isEmpty
              ? null
              : (window.first['id'] is int
                  ? window.first['id'] as int
                  : int.tryParse(window.first['id']?.toString() ?? ''));
          _highlightMessageId = targetId;
          _isLoading = false;
        });
        await _writeMessagesCache();
      }
      return true;
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
      return false;
    }
  }

  GlobalKey _anchorKey(int msgId) =>
      _msgAnchors.putIfAbsent(msgId, () => GlobalKey());

  void _scrollToMessage(int msgId) {
    final key = _msgAnchors[msgId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _clearHighlight() {
    if (_highlightMessageId != null) {
      setState(() => _highlightMessageId = null);
    }
  }

  /// 长按消息气泡：弹出操作菜单（回复 / 撤回 / 复制 等）。
  Future<void> _showMessageMenu(
      Map<String, dynamic> message, bool isMine) async {
    final messageType = message['message_type']?.toString() ?? 'text';
    final isRecalled = message['is_recalled'] == true;
    final isFailed = message['status']?.toString() == 'failed';
    if (isRecalled || isFailed || messageType == 'system') return;

    final canRecall = isMine;
    final options = <TwitterSheetOption<String>>[
      const TwitterSheetOption(
          icon: Icons.format_quote, label: '回复', value: 'reply'),
      if (messageType == 'text')
        const TwitterSheetOption(
            icon: Icons.copy, label: '复制文字', value: 'copy'),
      if (canRecall)
        const TwitterSheetOption(
          icon: Icons.undo,
          label: '撤回',
          value: 'recall',
          isDestructive: true,
        ),
    ];
    if (options.isEmpty) return;

    final action =
        await TwitterBottomSheet.show<String>(context, options: options);
    if (!mounted) return;
    switch (action) {
      case 'reply':
        setState(() => _quotedMessage = message);
        _msgFocusNode.requestFocus();
        break;
      case 'copy':
        await Clipboard.setData(
            ClipboardData(text: message['content']?.toString() ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已复制')));
        }
        break;
      case 'recall':
        final rawId = message['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (id != null) await _recallMessage(id, isMine);
        break;
    }
  }

  int? _extractQuoteId(Map<String, dynamic>? message) {
    if (message == null) return null;
    final raw = message['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  /// 仅用于乐观渲染时本地展示，后端响应到达后会用服务器生成的 preview 覆盖。
  String _quotePreviewOf(Map<String, dynamic> message) {
    final type = message['message_type']?.toString() ?? 'text';
    switch (type) {
      case 'image':
        return '[图片]';
      case 'video':
        return '[视频]';
      case 'post':
        final t = message['content']?.toString().trim() ?? '';
        return t.isEmpty
            ? '[帖子]'
            : '[帖子] ${t.length > 30 ? '${t.substring(0, 30)}...' : t}';
      default:
        final t = message['content']?.toString() ?? '';
        return t.length > 50 ? '${t.substring(0, 50)}...' : t;
    }
  }

  void _appendRealtimeMessage(Map<String, dynamic> payload) {
    if (payload['event'] != 'new_message') return;
    final rawMessage = payload['message'] ?? payload['data'] ?? payload;
    if (rawMessage is! Map) return;

    final messageMap = Map<String, dynamic>.from(rawMessage);
    final rawConversationId =
        payload['conversation_id'] ?? messageMap['conversation_id'];
    final conversationId = rawConversationId is int
        ? rawConversationId
        : int.tryParse(rawConversationId?.toString() ?? '');
    final rawCommunityId =
        payload['community_id'] ?? messageMap['community_id'];
    final communityId = rawCommunityId is int
        ? rawCommunityId
        : int.tryParse(rawCommunityId?.toString() ?? '');

    if (_conversationId != null && conversationId != _conversationId) return;
    if (_conversationId == null && communityId != widget.communityId) return;
    if (!mounted) return;

    _replaceOptimisticOrAppend(messageMap);
    unawaited(_writeMessagesCache());
    final messageType = messageMap['message_type']?.toString() ?? 'text';
    final preview = messageMap['media_url']?.toString().isNotEmpty == true
        ? messageMap['media_url'].toString()
        : (messageMap['content']?.toString() ?? '');
    _syncConversationPreview(preview, messageType);
  }

  void _replaceOptimisticOrAppend(Map<String, dynamic> messageMap,
      {dynamic optimisticId}) {
    final messageId = _messageIdentity(messageMap);
    final existingIdx = messageId == null
        ? -1
        : _messages
            .indexWhere((existing) => _messageIdentity(existing) == messageId);
    if (existingIdx >= 0) return;

    final optimisticIdx = optimisticId == null
        ? _messages.indexWhere(
            (existing) => _isMatchingOptimistic(existing, messageMap))
        : _messages.indexWhere((existing) => existing['id'] == optimisticId);
    setState(() {
      if (optimisticIdx >= 0) {
        _messages[optimisticIdx] = messageMap;
      } else {
        _messages.add(messageMap);
      }
      _messages.sort((a, b) => _messageTime(a).compareTo(_messageTime(b)));
    });
  }

  bool _isMatchingOptimistic(
      Map<String, dynamic> existing, Map<String, dynamic> incoming) {
    if (existing['status']?.toString() != 'sending') return false;
    final existingClientMsgId = existing['client_msg_id']?.toString();
    final incomingClientMsgId = incoming['client_msg_id']?.toString();
    if (existingClientMsgId != null &&
        existingClientMsgId.isNotEmpty &&
        existingClientMsgId == incomingClientMsgId) {
      return true;
    }
    final sameSender =
        existing['sender_id']?.toString() == incoming['sender_id']?.toString();
    final sameContent =
        existing['content']?.toString() == incoming['content']?.toString();
    final sameType = (existing['message_type']?.toString() ?? 'text') ==
        (incoming['message_type']?.toString() ?? 'text');
    final sameMedia = (existing['media_url']?.toString() ?? '') ==
        (incoming['media_url']?.toString() ?? '');
    final closeTime = _messageTime(existing)
            .difference(_messageTime(incoming))
            .inMinutes
            .abs() <=
        2;
    return sameSender && sameContent && sameType && sameMedia && closeTime;
  }

  DateTime _messageTime(Map<String, dynamic> message) {
    return AppDateUtils.parseServerTime(message['created_at']?.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _onTextChanged(String value) {
    if (value.endsWith('@')) {
      _showMentionMemberPicker();
    }
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
    if (_showEmojiPicker) {
      _msgFocusNode.unfocus();
    } else {
      _msgFocusNode.requestFocus();
    }
  }

  void _insertTextAtCursor(String text) {
    final currentText = _msgCtrl.text;
    final cursorPos = _msgCtrl.selection.baseOffset;
    final before =
        cursorPos >= 0 ? currentText.substring(0, cursorPos) : currentText;
    final after = cursorPos >= 0 ? currentText.substring(cursorPos) : '';
    final nextText = '$before$text$after';
    _msgCtrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: before.length + text.length),
    );
  }

  void _insertEmoji(String emoji) {
    _insertTextAtCursor(emoji);
  }

  void _insertMention(CommunityMember member) {
    final user = member.user;
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.username.trim().isNotEmpty == true
            ? user!.username.trim()
            : '用户${member.userId}');
    final currentText = _msgCtrl.text;
    final cursorPos = _msgCtrl.selection.baseOffset;
    if (cursorPos > 0 && currentText.substring(0, cursorPos).endsWith('@')) {
      _msgCtrl.value = TextEditingValue(
        text:
            '${currentText.substring(0, cursorPos - 1)}@$name ${currentText.substring(cursorPos)}',
        selection: TextSelection.collapsed(offset: cursorPos + name.length + 1),
      );
    } else {
      _insertTextAtCursor('@$name ');
    }
    _mentionUserIds.add(member.userId);
    _msgFocusNode.requestFocus();
  }

  Future<void> _insertMentionFromMessage(Map<String, dynamic> message) async {
    await _ensureMembersLoaded();
    final senderId = message['sender_id'] is int
        ? message['sender_id'] as int
        : int.tryParse(message['sender_id']?.toString() ?? '');
    if (senderId == null) return;
    final member = _members.cast<CommunityMember?>().firstWhere(
          (member) => member?.userId == senderId,
          orElse: () => null,
        );
    if (member != null) {
      _insertMention(member);
      return;
    }

    final sender = message['sender'] is Map
        ? Map<String, dynamic>.from(message['sender'] as Map)
        : <String, dynamic>{};
    final name = sender['display_name']?.toString().trim().isNotEmpty == true
        ? sender['display_name'].toString().trim()
        : (sender['username']?.toString().trim().isNotEmpty == true
            ? sender['username'].toString().trim()
            : '用户$senderId');
    _insertTextAtCursor('@$name ');
    _mentionUserIds.add(senderId);
    _msgFocusNode.requestFocus();
  }

  List<CommunityMember> get _onlineMembers =>
      _members.where((member) => member.user?.isOnline == true).toList();

  Future<List<CommunityMember>> _fetchMembers() async {
    final resp = await CommunityApiService().getMembers(widget.communityId);
    final raw = resp.data;
    List<dynamic> list = const [];
    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);
      final members = data['members'] ?? data['items'] ?? data['data'];
      if (members is List) list = members;
    }
    return list
        .whereType<Map>()
        .map((member) =>
            CommunityMember.fromJson(Map<String, dynamic>.from(member)))
        .toList();
  }

  Future<void> _loadMembersForHeader() async {
    if (_isMembersLoading) return;
    if (mounted) setState(() => _isMembersLoading = true);
    try {
      final members = await _fetchMembers();
      if (mounted) {
        setState(() => _members = members);
      } else {
        _members = members;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isMembersLoading = false);
    }
  }

  Future<void> _ensureMembersLoaded() async {
    if (_members.isNotEmpty) return;
    _members = await _fetchMembers();
  }

  Future<void> _showMentionMemberPicker() async {
    try {
      await _ensureMembersLoaded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('成员加载失败: $e')));
      }
      return;
    }
    if (!mounted) return;

    final searchCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        var filtered = List<CommunityMember>.from(_members);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void filter(String keyword) {
              final query = keyword.trim().toLowerCase();
              setSheetState(() {
                filtered = _members.where((member) {
                  final user = member.user;
                  final displayName = user?.displayName?.toLowerCase() ?? '';
                  final username = user?.username.toLowerCase() ?? '';
                  return query.isEmpty ||
                      displayName.contains(query) ||
                      username.contains(query) ||
                      member.userId.toString().contains(query);
                }).toList();
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '@ 提及成员',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '搜索成员',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onChanged: filter,
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              '没有找到成员',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final member = filtered[index];
                              final user = member.user;
                              final name =
                                  user?.displayName?.trim().isNotEmpty == true
                                      ? user!.displayName!.trim()
                                      : (user?.username.trim().isNotEmpty ==
                                              true
                                          ? user!.username.trim()
                                          : '用户${member.userId}');
                              return ListTile(
                                leading:
                                    _buildMemberAvatar(name, user?.avatarUrl),
                                title: Text(name),
                                subtitle: Text(member.role),
                                onTap: () {
                                  Navigator.pop(context);
                                  _insertMention(member);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
  }

  void _showMediaPicker() {
    _msgFocusNode.unfocus();
    setState(() => _showEmojiPicker = false);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('发送图片'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('发送视频'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendVideo();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _extractUploadUrl(dynamic resp) {
    final data = resp.data;
    if (data is String && data.isNotEmpty) return data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      for (final key in ['url', 'file_url', 'media_url']) {
        final value = map[key]?.toString();
        if (value != null && value.isNotEmpty) return value;
      }
      final nested = map['data'];
      if (nested is Map) {
        for (final key in ['url', 'file_url', 'media_url']) {
          final value = nested[key]?.toString();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }

  Future<void> _pickAndSendImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _sendMediaMessage(
        upload: () => UploadService().uploadImage(file),
        messageType: 'image',
      );
    } catch (e) {
      if (mounted) showPickerErrorSnackBar(context, e, target: '相册');
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      await _sendMediaMessage(
        upload: () => UploadService().uploadVideo(file),
        messageType: 'video',
      );
    } catch (e) {
      if (mounted) showPickerErrorSnackBar(context, e, target: '视频');
    }
  }

  Future<void> _sendMediaMessage({
    required Future<dynamic> Function() upload,
    required String messageType,
  }) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final uploadResp = await upload();
      final url = _extractUploadUrl(uploadResp);
      if (url == null || url.isEmpty) {
        throw Exception(uploadResp.message ?? '上传失败');
      }
      final clientMsgId = _newClientMsgId();
      final optimistic = _buildOptimisticMessage(
        content: url,
        messageType: messageType,
        mediaUrl: url,
        clientMsgId: clientMsgId,
      );
      if (mounted) {
        setState(() => _messages.add(optimistic));
      }
      _syncConversationPreview(url, messageType);
      unawaited(SoundService().playSendSound());
      await _writeMessagesCache();
      final resp = await CommunityApiService().sendMessage(
        widget.communityId,
        content: url,
        messageType: messageType,
        mediaUrl: url,
        clientMsgId: clientMsgId,
      );
      _replaceOptimisticWithResponse(optimistic, resp.data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送媒体失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _syncConversationPreview(String content, String msgType) {
    final conversationId = _conversationId;
    if (conversationId == null) {
      ref.read(conversationsProvider.notifier).loadConversations();
      return;
    }
    ref.read(conversationsProvider.notifier).upsertCommunityConversationPreview(
          conversationId: conversationId,
          communityId: widget.communityId,
          content: content,
          msgType: msgType,
        );
  }

  String get _displayCommunityName =>
      widget.communityName?.trim().isNotEmpty == true
          ? widget.communityName!.trim()
          : '社群交流';

  PreferredSizeWidget _buildCommunityAppBar() {
    return AppBar(
      titleSpacing: 0,
      title: _buildCommunityTitle(),
      actions: [
        IconButton(
          tooltip: '群详情',
          icon: const Icon(Icons.info_outline),
          onPressed: _openCommunityDetail,
        ),
      ],
    );
  }

  Widget _buildCommunityTitle() {
    return Row(
      children: [
        _buildCommunityAvatar(_displayCommunityName, widget.communityAvatar),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _displayCommunityName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showOnlineMembers,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '在线 ${_onlineMembers.length} 人',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityAvatar(String name, String? avatarUrl) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage:
            CachedNetworkImageProvider(ImageUtils.resolveUrl(avatarUrl)),
      );
    }
    return CircleAvatar(
      radius: 18,
      child: Text(name.isNotEmpty ? name[0] : '?'),
    );
  }

  void _openCommunityDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(communityId: widget.communityId),
      ),
    );
  }

  Future<void> _showOnlineMembers() async {
    try {
      await _ensureMembersLoaded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('在线成员加载失败: $e')));
      }
      return;
    }
    if (!mounted) return;
    final onlineMembers = _onlineMembers;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => _buildOnlineMembersSheet(onlineMembers),
    );
  }

  Widget _buildOnlineMembersSheet(List<CommunityMember> onlineMembers) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '在线成员 (${onlineMembers.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (onlineMembers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '暂无在线成员',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: onlineMembers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = onlineMembers[index];
                    final user = member.user;
                    final name = user?.displayName?.trim().isNotEmpty == true
                        ? user!.displayName!.trim()
                        : (user?.username.trim().isNotEmpty == true
                            ? user!.username.trim()
                            : '用户${member.userId}');
                    return ListTile(
                      leading: _buildMemberAvatar(name, user?.avatarUrl),
                      title: Text(name),
                      subtitle: Text(_roleLabel(member.role)),
                      trailing: const Icon(
                        Icons.circle,
                        color: Color(0xFF00BA7C),
                        size: 10,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return '创始人';
      case 'admin':
        return '管理员';
      default:
        return '成员';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildCommunityAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          if (_quotedMessage != null) _buildQuickReplyBar(),
          _buildComposer(),
          if (_showEmojiPicker) _buildEmojiPicker(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return _buildEmptyMessagesState();
    }
    final currentUserId = ref.watch(authProvider).user?.id;
    // reverse:true 时 index=0 在视觉底部，index=length-1 是视觉顶部。
    // hasMore 时在顶部加 1 个占位用于显示 "查看更早的消息"
    final showLoadMore = _hasMore || _loadingMore;
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      itemCount: _messages.length + (showLoadMore ? 1 : 0),
      itemBuilder: (_, index) {
        // 视觉顶部 → 加载更多按钮
        if (showLoadMore && index == _messages.length) {
          return _buildLoadMoreHistory();
        }
        final message = _messages[_messages.length - 1 - index];
        final isMine = message['sender_id'] == currentUserId;
        final rawId = message['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        final bubble = _MessageBubble(
          message: message,
          isMine: isMine,
          onRecall: () => _recallMessage(message['id'], isMine),
          onAvatarLongPress: () => _insertMentionFromMessage(message),
          onLongPress: () => _showMessageMenu(message, isMine),
          onRetry: () => _retryMessage(message),
          onQuoteTap: _onQuoteTap,
        );
        if (id == null) return bubble;
        return KeyedSubtree(
          key: _anchorKey(id),
          child: MessageHighlightWrapper(
            active: _highlightMessageId == id,
            onCompleted: _clearHighlight,
            child: bubble,
          ),
        );
      },
    );
  }

  Widget _buildLoadMoreHistory() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _loadMoreHistory,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '查看更早的消息',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.primary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildEmptyMessagesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 46, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text(
              '在社群里开始第一句交流',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '问一个问题、分享一个进展，或欢迎刚加入的伙伴。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  /// 输入框上方的回复引用条
  Widget _buildQuickReplyBar() {
    final msg = _quotedMessage!;
    final sender = msg['sender'] is Map
        ? Map<String, dynamic>.from(msg['sender'] as Map)
        : <String, dynamic>{};
    final senderName =
        sender['display_name']?.toString().trim().isNotEmpty == true
            ? sender['display_name'].toString().trim()
            : (sender['username']?.toString().trim().isNotEmpty == true
                ? sender['username'].toString().trim()
                : (msg['sender_name']?.toString().trim().isNotEmpty == true
                    ? msg['sender_name'].toString().trim()
                    : '用户'));
    final preview = _quotePreviewOf(msg);
    final isMine = msg['sender_id'] == ref.watch(authProvider).user?.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMine ? '回复 你' : '回复 $senderName',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: AppColors.textTertiary),
            onPressed: () => setState(() => _quotedMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              tooltip: '表情',
              icon: const Icon(Icons.emoji_emotions_outlined, size: 24),
              onPressed: _toggleEmojiPicker,
            ),
            IconButton(
              tooltip: '图片/视频',
              icon: const Icon(Icons.image_outlined, size: 24),
              onPressed: _isSending ? null : _showMediaPicker,
            ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                focusNode: _msgFocusNode,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '说点有用、有温度的话...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              color: Colors.white,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    final categories = EmojiData.categories;
    final emojis = categories[_emojiTabIndex].value;
    return Container(
      height: 292,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final selected = index == _emojiTabIndex;
                return InkWell(
                  onTap: () => setState(() => _emojiTabIndex = index),
                  child: Container(
                    width: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color:
                              selected ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      categories[index].key,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) => InkWell(
                onTap: () => _insertEmoji(emojis[index]),
                borderRadius: BorderRadius.circular(20),
                child: Center(
                  child: Text(
                    emojis[index],
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(String name, String? avatarUrl) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        backgroundImage:
            CachedNetworkImageProvider(ImageUtils.resolveUrl(avatarUrl)),
      );
    }
    return CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?'));
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final VoidCallback? onRecall;
  final VoidCallback? onAvatarLongPress;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;

  /// 点击引用预览条时触发，传入被引消息 id。
  final void Function(int? quoteMessageId)? onQuoteTap;

  const _MessageBubble({
    required this.message,
    this.isMine = false,
    this.onRecall,
    this.onAvatarLongPress,
    this.onLongPress,
    this.onRetry,
    this.onQuoteTap,
  });

  @override
  Widget build(BuildContext context) {
    final recalled = message['is_recalled'] == true;
    final bool isFailed = message['status']?.toString() == 'failed';
    final content = message['content'] ?? '';
    final messageType = message['message_type']?.toString() ?? 'text';
    final mediaUrl = message['media_url']?.toString().isNotEmpty == true
        ? message['media_url'].toString()
        : content.toString();
    final sender = message['sender'] is Map
        ? Map<String, dynamic>.from(message['sender'] as Map)
        : <String, dynamic>{};
    final senderName =
        sender['display_name']?.toString().trim().isNotEmpty == true
            ? sender['display_name'].toString()
            : (message['sender_name']?.toString().trim().isNotEmpty == true
                ? message['sender_name'].toString()
                : (sender['username']?.toString().trim().isNotEmpty == true
                    ? sender['username'].toString()
                    : '用户'));
    final senderAvatar = sender['avatar_url']?.toString();
    final time =
        message['created_at'] != null ? _formatTime(message['created_at']) : '';

    if (recalled) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: Text(
            '消息已撤回',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    if (messageType == 'system') {
      return _buildSystemMessage(content.toString());
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            GestureDetector(
              onLongPress: onAvatarLongPress,
              child: _buildSenderAvatar(senderName, senderAvatar),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMine ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMine ? 16 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          senderName,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (message['quote_message_id'] != null &&
                        (message['quote_preview']?.toString().isNotEmpty ??
                            false))
                      _buildQuotePreview(message, isMine),
                    if (messageType == 'image')
                      _buildImageMessage(mediaUrl)
                    else if (messageType == 'video')
                      _buildVideoMessage(mediaUrl)
                    else if (messageType == 'post')
                      _buildPostCard(context, message)
                    else
                      Text(
                        content.toString(),
                        style: TextStyle(
                          color: isMine ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: isMine ? Colors.white70 : AppColors.textTertiary,
                      ),
                    ),
                    if (isMine && isFailed)
                      TextButton.icon(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('重试', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
      ),
    );
  }

  /// 引用预览条（消息气泡内）
  Widget _buildQuotePreview(Map<String, dynamic> message, bool isMine) {
    final preview = message['quote_preview']?.toString() ?? '';
    final rawQuoteId = message['quote_message_id'];
    final quoteId = rawQuoteId is int
        ? rawQuoteId
        : int.tryParse(rawQuoteId?.toString() ?? '');
    final borderColor =
        isMine ? Colors.white.withValues(alpha: 0.7) : AppColors.primary;
    final bgColor = isMine
        ? Colors.white.withValues(alpha: 0.15)
        : AppColors.primary.withValues(alpha: 0.08);
    final textColor =
        isMine ? Colors.white.withValues(alpha: 0.9) : AppColors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onQuoteTap == null ? null : () => onQuoteTap!(quoteId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: borderColor, width: 2.5)),
        ),
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, height: 1.3, color: textColor),
        ),
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, Map<String, dynamic> message) {
    final relatedId = int.tryParse(message['related_id']?.toString() ?? '');
    final title = message['content']?.toString().trim().isNotEmpty == true
        ? message['content'].toString().trim()
        : '查看帖子 #${relatedId ?? ''}';
    final rawImageUrl = message['media_url']?.toString().trim();
    final imageUrl = rawImageUrl != null && rawImageUrl.isNotEmpty
        ? ImageUtils.resolveUrl(rawImageUrl)
        : null;

    return InkWell(
      onTap: relatedId == null
          ? null
          : () => Navigator.pushNamed(
                context,
                AppRoutes.postDetailId(relatedId.toString()),
              ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.article_outlined,
                          size: 15, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('帖子',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text('点击查看详情',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageMessage(String mediaUrl) {
    final url = ImageUtils.resolveUrl(mediaUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 220,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 220,
          height: 160,
          color: AppColors.backgroundSecondary,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 220,
          height: 120,
          color: AppColors.backgroundSecondary,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }

  Widget _buildVideoMessage(String mediaUrl) {
    return Container(
      width: 220,
      height: 132,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.play_circle_fill,
            color: Colors.white,
            size: 54,
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              mediaUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSenderAvatar(String senderName, String? avatarUrl) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final url = ImageUtils.resolveUrl(avatarUrl);
      return CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.backgroundSecondary,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Text(
              senderName.isNotEmpty ? senderName[0] : '?',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 16,
      child: Text(senderName.isNotEmpty ? senderName[0] : '?',
          style: const TextStyle(fontSize: 12)),
    );
  }

  String _formatTime(dynamic time) {
    if (time is String) {
      final dt = DateTime.tryParse(time);
      if (dt != null) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    return '';
  }
}
