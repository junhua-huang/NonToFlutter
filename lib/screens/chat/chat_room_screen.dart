import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/data/emoji_data.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/message.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/providers/chat_notifiers.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/screens/messages/messages_tab.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// Twitter/X DM 风格聊天室页面（基于 Provider 驱动消息状态）
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
  StreamSubscription? _errorSub;

  @override
  void initState() {
    super.initState();
    MessagesTab.currentChatRoomConvId = widget.conversation.id.toString();

    // 初始化 Provider（传入当前用户 ID 并启动加载）
    final auth = ref.read(authProvider);
    final currentUserId = auth.user?.id ?? 0;
    ref
        .read(messagesProvider(widget.conversation.id).notifier)
        .init(currentUserId);

    // WS 错误 → SnackBar
    _errorSub = WebSocketService().errorStream.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('发送失败: $error'),
              duration: const Duration(seconds: 3)),
        );
      }
    });

    // HTTP markRead 降级（WS 未连接时）
    if (!WebSocketService().isConnected) {
      ChatService().markRead(widget.conversation.id);
    }
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

    ref
        .read(messagesProvider(widget.conversation.id).notifier)
        .sendMessage(text);
    _messageController.clear();
    _scrollToBottom();
  }

  void _onTextChanged(String text) {
    if (WebSocketService().isConnected) {
      ref
          .read(messagesProvider(widget.conversation.id).notifier)
          .sendTyping();
    }
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        ref
            .read(messagesProvider(widget.conversation.id).notifier)
            .sendImageMessage(bytes, picked.name);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Pick image error: $e');
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (!_showEmojiPicker) {
      _messageFocusNode.requestFocus();
    } else {
      _messageFocusNode.unfocus();
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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final currentUserId = auth.user?.id;
    final msgState = ref.watch(messagesProvider(widget.conversation.id));
    final otherUser = widget.conversation.otherUser;

    // 新消息到达时自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (msgState.messages.isNotEmpty) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              otherUser?.displayName ?? '聊天',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              msgState.otherUserTyping
                  ? '正在输入...'
                  : '@${otherUser?.username ?? ''}',
              style: TextStyle(
                color: msgState.otherUserTyping
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontSize: 13,
                fontStyle: msgState.otherUserTyping
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline,
                color: AppColors.textPrimary, size: 22),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('聊天信息'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '对方: ${widget.conversation.otherUser?.displayName ?? '未知用户'}'),
                      Text(
                          '用户名: @${widget.conversation.otherUser?.username ?? ''}'),
                      const SizedBox(height: 12),
                      const Text('聊天设置:'),
                      SwitchListTile(
                        title: const Text('消息通知'),
                        value: true,
                        onChanged: (v) {},
                      ),
                      SwitchListTile(
                        title: const Text('静音'),
                        value: false,
                        onChanged: (v) {},
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
      ),
      body: Column(
        children: [
          // WebSocket 断开提示
          if (!msgState.wsConnected)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
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
                    Text(
                      '正在重新连接...',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          // Messages
          Expanded(
            child: msgState.error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(msgState.error!,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 15)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            ref
                                .read(messagesProvider(widget.conversation.id)
                                    .notifier)
                                .syncIncremental();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : msgState.messages.isEmpty && msgState.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary),
                      )
                    : msgState.messages.isEmpty && !msgState.isLoading
                    ? _buildEmpty(otherUser)
                    : SmartRefresher(
                        controller: _refreshController,
                        enablePullDown: true,
                        enablePullUp: msgState.hasMore,
                        onRefresh: () async {
                          await ref
                              .read(messagesProvider(widget.conversation.id)
                                  .notifier)
                              .syncIncremental();
                          _refreshController.refreshCompleted();
                          _refreshController.loadComplete();
                        },
                        onLoading: () async {
                          await ref
                              .read(messagesProvider(widget.conversation.id)
                                  .notifier)
                              .loadMore();
                          _refreshController.loadComplete();
                        },
                        header: const WaterDropHeader(
                          complete: Text('刷新成功',
                              style: TextStyle(color: AppColors.primary)),
                          waterDropColor: AppColors.primary,
                        ),
                        footer: CustomFooter(
                          builder: (context, mode) {
                            if (mode == LoadStatus.loading) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('加载更多...',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13)),
                              );
                            }
                            if (mode == LoadStatus.failed) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('加载失败，点击重试',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.likeRed,
                                        fontSize: 13)),
                              );
                            }
                            if (mode == LoadStatus.noMore) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('没有更多了',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: msgState.messages.length,
                          itemBuilder: (_, i) {
                            final msg = msgState.messages[i];
                            final isMe = msg.senderId == currentUserId;
                            return _MessageBubble(
                              message: msg,
                              isMe: isMe,
                              otherUser: otherUser,
                            );
                          },
                        ),
                      ),
          ),
          // Input bar
          _buildInputBar(msgState.isSending),
          // Emoji picker
          if (_showEmojiPicker) _buildEmojiPicker(),
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
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('@${otherUser?.username ?? ''}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
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

  Widget _buildInputBar(bool isSending) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Emoji button
          IconButton(
            icon: Icon(
              _showEmojiPicker
                  ? Icons.keyboard
                  : Icons.emoji_emotions_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            onPressed: _toggleEmojiPicker,
          ),
          // Image button
          IconButton(
            icon: const Icon(Icons.image_outlined,
                color: AppColors.primary, size: 24),
            onPressed: _pickImage,
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onChanged: _onTextChanged,
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: '开始新消息',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          isSending
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send,
                      color: AppColors.primary, size: 24),
                  onPressed: _sendMessage,
                ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    final emojis = EmojiData.categories.expand((c) => c.value).toList();

    return Container(
      height: 280,
      color: AppColors.surface,
      child: Column(
        children: [
          Container(
            height: 40,
            alignment: Alignment.center,
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                childAspectRatio: 1.2,
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
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final User? otherUser;

  const _MessageBubble(
      {required this.message, required this.isMe, this.otherUser});

  @override
  Widget build(BuildContext context) {
    final isText = message.messageType == MessageType.text;
    final time = AppDateUtils.formatTimeAgo(message.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            ImageUtils.buildAvatar(otherUser, radius: 14),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.borderLight,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isMe
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isText)
                        Text(
                          message.content ?? '',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color:
                                isMe ? Colors.white : AppColors.textPrimary,
                          ),
                        )
                      else if (message.messageType == MessageType.image)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl:
                                message.mediaUrl ?? message.content ?? '',
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) => Container(
                              width: 200,
                              height: 200,
                              color: Colors.grey[300],
                              child: const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (ctx, url, err) => Container(
                              width: 200,
                              height: 100,
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey),
                            ),
                          ),
                        )
                      else ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              message.messageType == MessageType.video
                                  ? Icons.videocam
                                  : message.messageType == MessageType.file
                                      ? Icons.insert_drive_file
                                      : message.messageType ==
                                              MessageType.post
                                          ? Icons.article
                                          : Icons.comment,
                              size: 16,
                              color: isMe
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                message.content ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isMe
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(time,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
