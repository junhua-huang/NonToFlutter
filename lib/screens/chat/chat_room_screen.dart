import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:nonto/data/emoji_data.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/models/message.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/screens/messages/messages_tab.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/twitter_bottom_sheet.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

// ── Twitter DM 颜色常量 ──
class _TwColors {
  // 浅色
  static const bg = Color(0xFFFFFFFF);
  static const otherBubble = Color(0xFFEFF3F4);
  static const selfBubble = Color(0xFF1D9BF0);
  static const text = Color(0xFF0F1419);
  static const timestamp = Color(0xFF68757A);
  static const divider = Color(0xFFEFF3F4);
  static const inputBg = Color(0xFFF7F9F9);
  // 暗色
  static const darkBg = Color(0xFF15202B);
  static const darkOtherBubble = Color(0xFF1E2732);
  static const darkText = Color(0xFFE7E9EA);
  static const darkTimestamp = Color(0xFF71767A);
  static const darkDivider = Color(0xFF2F3336);
  static const darkInputBg = Color(0xFF202327);
}

/// Twitter/X DM 风格聊天室页面
class ChatRoomScreen extends ConsumerStatefulWidget {
  final Conversation conversation;

  const ChatRoomScreen({super.key, required this.conversation});

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _messageFocusNode = FocusNode();

  bool _showEmojiPicker = false;
  Message? _quotedMessage;
  StreamSubscription? _errorSub;
  final Set<int> _reactions = {}; // optimistic reaction message IDs
  bool _loadingMore = false; // track history loading state
  int _lastMsgCount = 0; // track message count for auto-scroll

  @override
  void initState() {
    super.initState();
    MessagesTab.currentChatRoomConvId = widget.conversation.id.toString();

    final auth = ref.read(authProvider);
    final currentUserId = auth.user?.id ?? 0;
    ref
        .read(messagesProvider(widget.conversation.id).notifier)
        .init(currentUserId, otherUserId: widget.conversation.otherUser?.id);

    _errorSub = WebSocketService().errorStream.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('发送失败: $error'),
              duration: const Duration(seconds: 3)),
        );
      }
    });

    if (!WebSocketService().isConnected) {
      ChatService().markRead(widget.conversation.id);
    }

    // 立即清除本地未读气泡（不等服务端确认）
    ref.read(conversationsProvider.notifier).clearConversationUnread(widget.conversation.id);
  }

  @override
  void dispose() {
    MessagesTab.currentChatRoomConvId = null;
    _errorSub?.cancel();
    _refreshController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  // ── 发送 ──

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();

    final notifier = ref.read(messagesProvider(widget.conversation.id).notifier);
    if (_quotedMessage != null) {
      // 发送带引用的消息，不再拼「回复」前缀
      notifier.sendMessage(
        text,
        quoteMessageId: _quotedMessage!.id,
        quotePreview: _quotedMessage!.content ?? '',
      );
    } else {
      notifier.sendMessage(text);
    }
    _messageController.clear();
    setState(() => _quotedMessage = null);
    _scrollToBottom();
  }

  void _onTextChanged(String text) {
    if (WebSocketService().isConnected) {
      ref
          .read(messagesProvider(widget.conversation.id).notifier)
          .sendTyping();
    }
  }

  Future<void> _pickMedia(ImageSource source) async {
    try {
      final picked = await _picker.pickMultipleMedia();
      if (picked.isEmpty) return;
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        ref
            .read(messagesProvider(widget.conversation.id).notifier)
            .sendImageMessage(bytes, file.name);
      }
      _scrollToBottom();
    } catch (e) {
      // _picker.pickMultipleMedia may not be available on web, fallback to single
      try {
        final picked = await _picker.pickImage(
          source: source,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );
        if (picked != null) {
          final bytes = await picked.readAsBytes();
          if (!mounted) return;
          ref
              .read(messagesProvider(widget.conversation.id).notifier)
              .sendImageMessage(bytes, picked.name);
          _scrollToBottom();
        }
      } catch (e2) {
        debugPrint('Pick media error: $e2');
      }
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (_showEmojiPicker) {
      _messageFocusNode.unfocus();
    } else {
      _messageFocusNode.requestFocus();
    }
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text;
    final cursorPos = _messageController.selection.baseOffset;
    final before = cursorPos >= 0 ? text.substring(0, cursorPos) : text;
    final after = cursorPos >= 0 ? text.substring(cursorPos) : '';
    _messageController.text = '$before$emoji$after';
    _messageController.selection = TextSelection.collapsed(
      offset: before.length + emoji.length,
    );
  }

  // ── 消息交互 ──

  void _showMessageMenu(Message msg) async {
    final isMe = msg.senderId == ref.read(authProvider).user?.id;
    final canRecall = isMe && !msg.isRecalled && msg.id < 1000000000000;
    final options = <TwitterSheetOption<String>>[
      if (!msg.isRecalled)
        const TwitterSheetOption(icon: Icons.copy, label: '复制文字', value: 'copy'),
      if (!msg.isRecalled)
        const TwitterSheetOption(icon: Icons.format_quote, label: '引用回复', value: 'quote'),
      if (!msg.isRecalled)
        const TwitterSheetOption(icon: Icons.forward, label: '转发', value: 'forward'),
      if (canRecall)
        const TwitterSheetOption(icon: Icons.undo, label: '撤回', value: 'recall', isDestructive: true),
      if (isMe && !msg.isRecalled)
        const TwitterSheetOption(icon: Icons.delete_outline, label: '删除消息', value: 'delete', isDestructive: true),
      if (!msg.isRecalled)
        const TwitterSheetOption(icon: Icons.flag_outlined, label: '举报', value: 'report'),
    ];

    if (options.isEmpty) return; // 已撤回消息无菜单

    final action = await TwitterBottomSheet.show<String>(context, options: options);
    if (!mounted) return;
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: msg.content ?? ''));
        break;
      case 'quote':
        setState(() => _quotedMessage = msg);
        _messageFocusNode.requestFocus();
        break;
      case 'recall':
        ref.read(messagesProvider(widget.conversation.id).notifier).recallMessage(msg.id);
        break;
      case 'delete':
        ref.read(messagesProvider(widget.conversation.id).notifier).removeMessage(msg.id);
        break;
      case 'forward':
      case 'report':
      case null:
        break;
    }
  }

  void _toggleReaction(int msgId) {
    if (mounted) {
      setState(() {
        if (_reactions.contains(msgId)) {
          _reactions.remove(msgId);
        } else {
          _reactions.add(msgId);
        }
      });
    }
    HapticFeedback.lightImpact();
  }

  // ── 构建 ──

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final currentUserId = auth.user?.id;
    final msgState = ref.watch(messagesProvider(widget.conversation.id));
    final otherUser = widget.conversation.otherUser;

    // 仅在消息数量变化时滚动到底部（避免每次 build 都滚）
    final msgCount = msgState.messages.length;
    if (msgCount != _lastMsgCount && msgCount > 0) {
      _lastMsgCount = msgCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }

    return Scaffold(
      backgroundColor: _isDark ? _TwColors.darkBg : _TwColors.bg,
      appBar: _buildAppBar(otherUser, msgState),
      body: Column(
        children: [
          if (!msgState.wsConnected) _buildWsBanner(),
          Expanded(child: _buildMessageList(msgState, currentUserId, otherUser)),
          if (_quotedMessage != null) _buildQuickReplyBar(),
          _buildInputBar(msgState.isSending),
          if (_showEmojiPicker) _buildEmojiPicker(),
        ],
      ),
    );
  }

  // ── 导航栏 ──

  PreferredSizeWidget _buildAppBar(User? otherUser, MessagesState msgState) {
    final bgColor = _isDark ? _TwColors.darkBg : _TwColors.bg;
    final textColor = _isDark ? _TwColors.darkText : _TwColors.text;
    final subColor = _isDark ? _TwColors.darkTimestamp : _TwColors.timestamp;
    final divColor = _isDark ? _TwColors.darkDivider : _TwColors.divider;

    return AppBar(
      backgroundColor: bgColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leadingWidth: 48,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: textColor, size: 22),
        onPressed: () => Navigator.of(context).pop(),
        padding: EdgeInsets.zero,
      ),
      title: GestureDetector(
        onTap: () => _openUserProfile(otherUser),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (otherUser != null)
              ImageUtils.buildAvatar(otherUser, radius: 20),
            if (otherUser != null) const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  otherUser?.displayName ?? '聊天',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Builder(builder: (context) {
                  // 优先使用 msgState.otherUserIsOnline（来自 WS 实时推送）
                  // 回退到 otherUser.isOnline（构造时传入的静态值）
                  final isOnline = msgState.otherUserIsOnline ?? otherUser?.isOnline;
                  final statusText = isOnline == true
                      ? '在线'
                      : isOnline == false
                          ? '离线'
                          : (msgState.otherUserTyping ? '正在输入...' : '@${otherUser?.username ?? ''}');
                  final statusColor = isOnline == true
                      ? const Color(0xFF00BA7C)
                      : msgState.otherUserTyping
                          ? _TwColors.selfBubble
                          : subColor;
                  return Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontStyle: msgState.otherUserTyping
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
      centerTitle: false,
      actions: [
        if (otherUser != null)
          IconButton(
            icon: Icon(Icons.person_outline, color: textColor, size: 22),
            onPressed: () => _openUserProfile(otherUser),
            tooltip: '查看主页',
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(height: 0.5, color: divColor),
      ),
    );
  }

  void _openUserProfile(User? user) {
    if (user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(user: user),
      ),
    );
  }

  // ── WS 横幅 ──

  Widget _buildWsBanner() {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        color: const Color(0xFFF39C12),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 8),
            Text('正在重新连接...',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ── 消息列表 ──

  Widget _buildMessageList(
      MessagesState msgState, int? currentUserId, User? otherUser) {
    if (msgState.error != null) {
      return _buildError(msgState.error!);
    }
    if (msgState.messages.isEmpty && msgState.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _TwColors.selfBubble));
    }
    if (msgState.messages.isEmpty && !msgState.isLoading) {
      return _buildEmpty(otherUser);
    }

    final grouped = _groupMessages(msgState.messages, currentUserId ?? 0);
    final lastGroupIdx =
        grouped.lastIndexWhere((e) => e is _MsgGroup);

    return SmartRefresher(
      controller: _refreshController,
      enablePullDown: true,
      enablePullUp: false,
      onRefresh: () async {
        await ref
            .read(messagesProvider(widget.conversation.id).notifier)
            .syncIncremental();
        _refreshController.refreshCompleted();
      },
      header: WaterDropHeader(
        complete: const Text('刷新成功',
            style: TextStyle(color: _TwColors.selfBubble)),
        waterDropColor: _TwColors.selfBubble,
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        itemCount: grouped.length + (msgState.hasMore || _loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if ((msgState.hasMore || _loadingMore) && i == 0) {
            return _buildLoadMoreHistory(msgState.hasMore);
          }
          final offset = (msgState.hasMore || _loadingMore) ? 1 : 0;
          final item = grouped[i - offset];
          if (item is _TimeSeparatorData) {
            return _buildTimeSeparator(item.label);
          }
          if (item is _SystemMsgData) {
            return _buildSystemMessage(item.text);
          }
          // _MsgGroup
          final group = item as _MsgGroup;
          final isMe = group.senderId == currentUserId;
          return _buildMessageGroup(group, isMe, otherUser,
              isLastInList: i == lastGroupIdx);
        },
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: _TwColors.timestamp),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(
                  color: _TwColors.timestamp, fontSize: 15)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(messagesProvider(widget.conversation.id).notifier)
                  .retry();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _TwColors.selfBubble,
              foregroundColor: Colors.white,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(User? otherUser) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ImageUtils.buildAvatar(otherUser, radius: 40),
          const SizedBox(height: 12),
          Text(otherUser?.displayName ?? '',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _isDark ? _TwColors.darkText : _TwColors.text)),
          const SizedBox(height: 4),
          Text('@${otherUser?.username ?? ''}',
              style: const TextStyle(
                  color: _TwColors.timestamp, fontSize: 14)),
          const SizedBox(height: 16),
          const EmptyStateWidget(
            icon: Icons.chat_bubble_outline,
            title: '暂无消息',
            subtitle: '发一条开始聊天吧',
            iconSize: 36,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreHistory(bool hasMore) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _TwColors.selfBubble),
          ),
        ),
      );
    }
    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '没有更多了',
          textAlign: TextAlign.center,
          style: TextStyle(color: _TwColors.timestamp, fontSize: 13),
        ),
      );
    }
    return GestureDetector(
      onTap: () async {
        if (_loadingMore) return;
        setState(() => _loadingMore = true);
        try {
          await ref
              .read(messagesProvider(widget.conversation.id).notifier)
              .loadMore();
        } finally {
          if (mounted) setState(() => _loadingMore = false);
        }
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '查看更早的消息',
          textAlign: TextAlign.center,
          style: TextStyle(color: _TwColors.selfBubble, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildTimeSeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _isDark
                ? _TwColors.darkOtherBubble.withValues(alpha: 0.6)
                : _TwColors.otherBubble.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: _isDark ? _TwColors.darkTimestamp : _TwColors.timestamp,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemMessage(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: _isDark ? _TwColors.darkTimestamp : _TwColors.timestamp,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageGroup(
      _MsgGroup group, bool isMe, User? otherUser,
      {required bool isLastInList}) {
    final msgs = group.messages;
    final last = msgs.last;

    return Padding(
      padding: EdgeInsets.only(
        top: group.firstInSequence ? 12 : 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Opacity(
                opacity: group.showAvatar ? 1.0 : 0.0,
                child: ImageUtils.buildAvatar(otherUser, radius: 16),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                ...List.generate(msgs.length, (idx) {
                  final msg = msgs[idx];
                  final isFirst = idx == 0;
                  final isLast = idx == msgs.length - 1;
                  return _buildBubble(
                    msg: msg,
                    isMe: isMe,
                    isFirst: isFirst,
                    isLast: isLast,
                    groupSize: msgs.length,
                    showAvatar: group.showAvatar,
                  );
                }),
                // 状态图标（仅最后一条自己的消息显示）
                if (isMe && isLastInList)
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: _SendStatusIcon(message: last, isMe: true),
                  ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildBubble({
    required Message msg,
    required bool isMe,
    required bool isFirst,
    required bool isLast,
    required int groupSize,
    required bool showAvatar,
  }) {
    final isText = msg.messageType == MessageType.text;
    final isImage = msg.messageType == MessageType.image;
    final isRecalled = msg.isRecalled;
    final bubbleColor = isMe
        ? _TwColors.selfBubble
        : (_isDark ? _TwColors.darkOtherBubble : _TwColors.otherBubble);
    final textColor = isMe
        ? Colors.white
        : (_isDark ? _TwColors.darkText : _TwColors.text);

    // ── 已撤回消息：居中灰色提示 ──
    if (isRecalled) {
      return Padding(
        padding: EdgeInsets.only(
          left: isMe ? 48 : (showAvatar ? 0 : 44),
          right: isMe ? 0 : 48,
          top: isFirst ? 0 : 1,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _isDark ? _TwColors.darkOtherBubble : _TwColors.otherBubble,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.undo, size: 14,
                color: _isDark ? _TwColors.darkTimestamp : _TwColors.timestamp),
              const SizedBox(width: 4),
              Text(
                isMe ? '你撤回了一条消息' : '消息已撤回',
                style: TextStyle(
                  fontSize: 13,
                  color: _isDark ? _TwColors.darkTimestamp : _TwColors.timestamp,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 连续消息圆角
    const r = Radius.circular(16);
    const rSmall = Radius.circular(4);
    BorderRadius borderRadius;
    if (groupSize == 1) {
      borderRadius = const BorderRadius.all(r);
    } else if (isFirst) {
      borderRadius = isMe
          ? const BorderRadius.only(
              topLeft: r, topRight: r, bottomLeft: r, bottomRight: rSmall)
          : const BorderRadius.only(
              topLeft: r, topRight: r, bottomLeft: rSmall, bottomRight: r);
    } else if (isLast) {
      borderRadius = isMe
          ? const BorderRadius.only(
              topLeft: r, topRight: rSmall, bottomLeft: r, bottomRight: r)
          : const BorderRadius.only(
              topLeft: rSmall, topRight: r, bottomLeft: r, bottomRight: r);
    } else {
      borderRadius = isMe
          ? const BorderRadius.only(
              topLeft: r, topRight: rSmall, bottomLeft: r, bottomRight: rSmall)
          : const BorderRadius.only(
              topLeft: rSmall, topRight: r, bottomLeft: rSmall, bottomRight: r);
    }

    return GestureDetector(
      onLongPress: () => _showMessageMenu(msg),
      onDoubleTap: () => _toggleReaction(msg.id),
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 48 : (showAvatar ? 0 : 44),
          right: isMe ? 0 : 48,
          top: isFirst ? 0 : 1,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.70,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 引用预览条 ──
                  if (msg.quoteMessageId != null && msg.quotePreview != null)
                    _buildQuotePreview(msg, isMe),
                  if (isText)
                    Text(
                      msg.content ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: textColor,
                      ),
                    )
                  else if (isImage)
                    _buildImageBubble(msg)
                  else
                    _buildMediaBubble(msg, isMe, textColor),
                ],
              ),
              // 反应图标
              if (_reactions.contains(msg.id))
                Positioned(
                  right: -4,
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _isDark ? _TwColors.darkBg : _TwColors.bg,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Text('❤️', style: TextStyle(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageBubble(Message msg) {
    final url = msg.mediaUrl ?? msg.content ?? '';
    final isUploading = msg.status == 'uploading';
    final isFailed = msg.status == 'failed';
    final progress = (msg.uploadProgress ?? 0).clamp(0.0, 1.0).toDouble();

    Widget imageChild;
    if (isFailed) {
      // ── 上传失败：显示占位图 + 重试提示 ──
      imageChild = GestureDetector(
        onTap: () {
          ref
              .read(messagesProvider(widget.conversation.id).notifier)
              .retryImageUpload(msg.id);
        },
        child: Container(
          width: 240,
          height: 180,
          color: Colors.grey[300],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 36, color: Colors.grey[600]),
              const SizedBox(height: 8),
              Text(
                '上传失败，点击重试',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      );
    } else if (isUploading || url.isEmpty || !url.startsWith('http')) {
      imageChild = Container(
        width: 240,
        height: 240,
        color: Colors.grey[300],
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.image_outlined, size: 48, color: Colors.grey[500]),
            Positioned(
              left: 18,
              right: 18,
              bottom: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.6),
                    valueColor: const AlwaysStoppedAnimation<Color>(_TwColors.selfBubble),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress > 0 ? '上传中 ${(progress * 100).round()}%' : '准备上传...',
                    style: const TextStyle(fontSize: 12, color: _TwColors.timestamp),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      imageChild = CachedNetworkImage(
        imageUrl: url,
        width: 240,
        height: 240,
        fit: BoxFit.cover,
        placeholder: (ctx, url) => Container(
          width: 240,
          height: 240,
          color: Colors.grey[300],
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (ctx, url, err) => Container(
          width: 240,
          height: 100,
          color: Colors.grey[300],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: isFailed
            ? () => ref
                .read(messagesProvider(widget.conversation.id).notifier)
                .retryImageUpload(msg.id)
            : (url.startsWith('http') && !isUploading ? () => _showImageViewer(url) : null),
        child: imageChild,
      ),
    );
  }

  Widget _buildMediaBubble(Message msg, bool isMe, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          msg.messageType == MessageType.video
              ? Icons.videocam
              : msg.messageType == MessageType.file
                  ? Icons.insert_drive_file
                  : msg.messageType == MessageType.post
                      ? Icons.article
                      : Icons.comment,
          size: 16,
          color: isMe ? Colors.white70 : _TwColors.timestamp,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            msg.content ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: textColor),
          ),
        ),
      ],
    );
  }

  void _showImageViewer(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white54, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 快速回复栏 ──

  Widget _buildQuotePreview(Message msg, bool isMe) {
    final quoteColor = isMe
        ? Colors.white.withValues(alpha: 0.7)
        : _TwColors.selfBubble;
    final quoteBg = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : _TwColors.selfBubble.withValues(alpha: 0.08);
    final quoteTextColor = isMe
        ? Colors.white.withValues(alpha: 0.85)
        : (_isDark ? _TwColors.darkText : _TwColors.text);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: quoteBg,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: quoteColor, width: 2.5),
        ),
      ),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.60,
      ),
      child: Text(
        msg.quotePreview ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          color: quoteTextColor,
        ),
      ),
    );
  }

  Widget _buildQuickReplyBar() {
    final msg = _quotedMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isDark ? _TwColors.darkInputBg : _TwColors.inputBg,
        border: Border(
          top: BorderSide(
            color: _isDark ? _TwColors.darkDivider : _TwColors.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: _TwColors.selfBubble,
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
                  msg.senderId ==
                          ref.read(authProvider).user?.id
                      ? '你'
                      : widget.conversation.otherUser?.displayName ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _TwColors.selfBubble,
                  ),
                ),
                Text(
                  msg.content ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: _isDark ? _TwColors.darkText : _TwColors.text,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close,
                size: 18,
                color: _isDark ? _TwColors.darkTimestamp : _TwColors.timestamp),
            onPressed: () => setState(() => _quotedMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── 输入区域 ──

  Widget _buildInputBar(bool isSending) {
    final bgColor = _isDark ? _TwColors.darkBg : _TwColors.bg;
    final divColor = _isDark ? _TwColors.darkDivider : _TwColors.divider;
    final inputBg = _isDark ? _TwColors.darkInputBg : _TwColors.inputBg;
    final hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: divColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 表情按钮
          IconButton(
            icon: Icon(
              _showEmojiPicker
                  ? Icons.keyboard
                  : Icons.emoji_emotions_outlined,
              color: _TwColors.selfBubble,
              size: 22,
            ),
            onPressed: _toggleEmojiPicker,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          // 附件按钮
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: _TwColors.selfBubble, size: 22),
            onPressed: () => _showAttachmentOptions(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 4),
          // 输入框
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isDark
                      ? Colors.transparent
                      : _TwColors.divider.withValues(alpha: 0.5),
                ),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onChanged: _onTextChanged,
                style: TextStyle(
                  fontSize: 15,
                  color: _isDark ? _TwColors.darkText : _TwColors.text,
                ),
                decoration: InputDecoration(
                  hintText: '发一条私信',
                  hintStyle: TextStyle(
                    color: _isDark
                        ? _TwColors.darkTimestamp
                        : _TwColors.timestamp,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 发送按钮
          if (hasText || isSending)
            isSending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: _TwColors.selfBubble, strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: _TwColors.selfBubble, size: 22),
                    onPressed: _sendMessage,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
        ],
      ),
    );
  }

  void _showAttachmentOptions() async {
    final action = await TwitterBottomSheet.show<String>(
      context,
      options: const [
        TwitterSheetOption(icon: Icons.camera_alt_outlined, label: '拍照', value: 'camera'),
        TwitterSheetOption(icon: Icons.photo_library_outlined, label: '从相册选择', value: 'gallery'),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'camera':
        _pickMedia(ImageSource.camera);
        break;
      case 'gallery':
        _pickMedia(ImageSource.gallery);
        break;
    }
  }

  // ── 表情面板 ──

  int _emojiTabIndex = 0;

  Widget _buildEmojiPicker() {
    final categories = EmojiData.categories;
    final emojis = categories[_emojiTabIndex].value;
    return Container(
      height: 300,
      color: _isDark ? _TwColors.darkInputBg : _TwColors.inputBg,
      child: Column(
        children: [
          // 分类标签
          SizedBox(
            height: 40,
            child: Row(
              children: List.generate(categories.length, (i) {
                final isSelected = i == _emojiTabIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _emojiTabIndex = i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isSelected
                                ? _TwColors.selfBubble
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        categories[i].key,
                        style: TextStyle(
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // 表情网格（支持上下滑动）
          Expanded(
            child: GridView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1.2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () => _insertEmoji(emojis[index]),
                  borderRadius: BorderRadius.circular(20),
                  child: Center(
                    child: Text(
                      emojis[index],
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 消息分组逻辑 ──

  List<dynamic> _groupMessages(List<Message> messages, int currentUserId) {
    if (messages.isEmpty) return [];

    // 转换为正向（最旧→最新）便于分组
    final sorted = messages.toList()
      ..sort((a, b) => (a.createdAt ?? DateTime(0))
          .compareTo(b.createdAt ?? DateTime(0)));

    final result = <dynamic>[];
    _MsgGroup? currentGroup;

    for (int i = 0; i < sorted.length; i++) {
      final msg = sorted[i];
      final prev = i > 0 ? sorted[i - 1] : null;

      // 时间分隔符（> 1 小时）
      if (prev != null) {
        final gap = msg.createdAt!.difference(prev.createdAt!);
        if (gap.inHours >= 1) {
          result.add(_TimeSeparatorData(_formatSeparatorTime(msg.createdAt!)));
          currentGroup = null;
        }
      } else {
        // 第一条消息前加时间
        result.add(_TimeSeparatorData(_formatSeparatorTime(msg.createdAt!)));
      }

      // 系统消息（通过内容特征识别，如 "加入了群聊"、"创建了对话"）
      final content = msg.content ?? '';
      if (content.contains('加入了') ||
          content.contains('离开了') ||
          content.contains('创建了') ||
          content.contains('移出了')) {
        result.add(_SystemMsgData(content));
        currentGroup = null;
        continue;
      }

      final isMe = msg.senderId == currentUserId;
      final sameSender = currentGroup != null &&
          currentGroup.senderId == msg.senderId;
      final withinTime = currentGroup != null &&
          msg.createdAt!
                  .difference(currentGroup.messages.last.createdAt!)
                  .inMinutes <
              2;

      if (sameSender && withinTime) {
        // 同组追加
        currentGroup.messages.add(msg);
      } else {
        // 新组
        final senderChanged =
            currentGroup != null && currentGroup.senderId != msg.senderId;
        currentGroup = _MsgGroup(
          senderId: msg.senderId,
          messages: [msg],
          showAvatar: !isMe,
          firstInSequence: senderChanged || currentGroup == null,
        );
        result.add(currentGroup);
      }
    }

    return result;
  }

  String _formatSeparatorTime(DateTime dt) {
    final localDt = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(localDt.year, localDt.month, localDt.day);
    final diff = today.difference(msgDay).inDays;

    final time = '${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天 $time';
    if (diff == 1) return '昨天 $time';
    return '${localDt.year}年${localDt.month}月${localDt.day}日';
  }
}

// ── 分组数据模型 ──

class _TimeSeparatorData {
  final String label;
  _TimeSeparatorData(this.label);
}

class _SystemMsgData {
  final String text;
  _SystemMsgData(this.text);
}

class _MsgGroup {
  final int senderId;
  final List<Message> messages;
  final bool showAvatar;
  final bool firstInSequence;

  _MsgGroup({
    required this.senderId,
    required this.messages,
    required this.showAvatar,
    this.firstInSequence = false,
  });
}

// ── 发送状态图标 ──

class _SendStatusIcon extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _SendStatusIcon({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    if (!isMe) return const SizedBox.shrink();
    // 上传/发送中（乐观消息）
    if (message.status == 'uploading') {
      return Text(
        '上传中 ${(message.uploadProgress ?? 0) > 0 ? ((message.uploadProgress ?? 0) * 100).round() : 0}%',
        style: const TextStyle(fontSize: 11, color: _TwColors.timestamp),
      );
    }
    if (message.status == 'sending' || message.id >= 1000000000000) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
            strokeWidth: 1.5, color: _TwColors.timestamp),
      );
    }
    // 已读
    if (message.isRead == true) {
      return const Icon(Icons.done_all, size: 14, color: _TwColors.selfBubble);
    }
    // 已送达
    return const Icon(Icons.done_all, size: 14, color: _TwColors.timestamp);
  }
}
