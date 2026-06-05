import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/message.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/local_db_service.dart';
import 'package:facebook_clone/services/sound_service.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// Twitter/X DM 风格聊天室页面（支持 WebSocket 实时消息 + 表情包）
class ChatRoomScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatRoomScreen({super.key, required this.conversation});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final ChatService _chatService = ChatService();
  final WebSocketService _wsService = WebSocketService();
  final RefreshController _refreshController = RefreshController(initialRefresh: true);
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final FocusNode _messageFocusNode = FocusNode();

  final List<Message> _messages = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  bool _showEmojiPicker = false;
  bool _otherUserTyping = false;
  Timer? _typingTimer;
  StreamSubscription? _msgSubscription;
  StreamSubscription? _typingSubscription;

  @override
  void initState() {
    super.initState();
    _loadLocalMessages();
    _setupWebSocket();
    _chatService.markRead(widget.conversation.id);
  }

  Future<void> _loadLocalMessages() async {
    final localMsgs = await LocalDbService().getMessages(widget.conversation.id, limit: 50);
    if (localMsgs.isNotEmpty && mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(localMsgs);
      });
    }
    // Then load from server
    await _loadMessages();
  }

  void _setupWebSocket() {
    // Ensure connected
    _wsService.connect();
    // Join room
    _wsService.joinConversation(widget.conversation.id);

    // Listen for new messages (backend sends: receive_message)
    _msgSubscription = _wsService.messageStream.listen((data) {
      final msgConvId = data['conversation_id'];
      if (msgConvId == widget.conversation.id) {
        final msg = Message.fromJson(data);
        // Check if this is a message we already have (optimistic duplicate check)
        final alreadyExists = _messages.any((m) =>
          m.id == msg.id ||
          (m.senderId == msg.senderId && m.content == msg.content &&
           ((m.createdAt ?? DateTime.now()).difference(msg.createdAt ?? DateTime.now()).inSeconds.abs() < 5))
        );
        if (!alreadyExists) {
          // Save to local DB
          LocalDbService().insertMessage(msg);
          setState(() {
            // Remove any pending optimistic message from same sender with same content
            _messages.removeWhere((m) =>
              m.id.toString().length < 10 && // Optimistic IDs are timestamps (long strings)
              m.senderId == msg.senderId && m.content == msg.content
            );
            _messages.add(msg);
          });
          _scrollToBottom();
        }
      }
    });

    // Listen for typing indicators
    _typingSubscription = _wsService.typingStream.listen((data) {
      final convId = data['conversation_id'];
      final type = data['type'] ?? 'typing';
      if (convId == widget.conversation.id) {
        setState(() => _otherUserTyping = type == 'typing');
      }
    });
  }

  @override
  void dispose() {
    _wsService.leaveConversation(widget.conversation.id);
    _msgSubscription?.cancel();
    _typingSubscription?.cancel();
    _refreshController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      final resp = await _chatService.getMessages(widget.conversation.id, page: _page);
      if (resp.success && resp.data != null) {
        final data = resp.data;
        List<dynamic> msgList = [];
        if (data is Map) {
          msgList = data['messages'] ?? [];
          _hasMore = data['has_more'] == true;
        } else if (data is List) {
          msgList = data;
        }
        final messages = msgList
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
        // Newest first from API, but we want newest at bottom
        messages.sort((a, b) => (a.createdAt ?? DateTime.now()).compareTo(b.createdAt ?? DateTime.now()));

        setState(() {
          if (_page == 1) {
            _messages.clear();
            _messages.addAll(messages);
          } else {
            _messages.insertAll(0, messages.reversed);
          }
          _page++;
        });
        // Save to local DB
        await LocalDbService().insertMessages(messages);
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      debugPrint('Load messages error: $e');
      if (mounted) setState(() => _error = '加载失败，请下拉重试');
    } finally {
      _isLoading = false;
      _refreshController.loadComplete();
      _refreshController.refreshCompleted();
      if (_page <= 2 && _messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
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

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final currentUserId = auth.user?.id;
    if (currentUserId == null) return;

    // Optimistic message
    final optimisticMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      conversationId: widget.conversation.id,
      senderId: currentUserId,
      content: text,
      messageType: MessageType.text,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(optimisticMsg);
      _isSending = true;
    });
    _messageController.clear();
    _scrollToBottom();

    // Save to local DB first
    await LocalDbService().insertMessage(optimisticMsg);

    // Send via WebSocket if connected, otherwise fallback to HTTP
    if (_wsService.isConnected) {
      _wsService.sendMessage(widget.conversation.id, text);
      SoundService().playSendSound();
      setState(() => _isSending = false);
    } else {
      // HTTP fallback
      try {
        final resp = await _chatService.sendMessage(widget.conversation.id, text);
        if (!resp.success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('发送失败'), duration: Duration(seconds: 2)),
          );
        }
      } catch (e) {
        debugPrint('Send message error: $e');
      } finally {
        if (mounted) setState(() => _isSending = false);
      }
    }
  }

  void _onTextChanged(String text) {
    if (_wsService.isConnected) {
      _wsService.sendTyping(widget.conversation.id);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _wsService.sendStopTyping(widget.conversation.id);
      });
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
        await _sendImageMessage(bytes, picked.name);
      }
    } catch (e) {
      debugPrint('Pick image error: $e');
    }
  }

  Future<void> _sendImageMessage(Uint8List bytes, String fileName) async {
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.user?.id;
    if (currentUserId == null) return;

    setState(() => _isSending = true);
    try {
      final uploadResp = await ApiClient().uploadBytes(
        '/upload/chat/image',
        bytes,
        fileName,
      );
      if (uploadResp.success) {
        final url = _extractUrl(uploadResp.data);
        if (url != null) {
          if (_wsService.isConnected) {
            _wsService.sendMessage(
              widget.conversation.id,
              url,
              messageType: 'image',
            );
            SoundService().playSendSound();
          } else {
            await _chatService.sendMessage(widget.conversation.id, url, messageType: 'image');
          }
        }
      }
    } catch (e) {
      debugPrint('Send image error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String? _extractUrl(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      return data['url']?.toString()
          ?? data['image_url']?.toString()
          ?? data['media_url']?.toString();
    }
    return data.toString();
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
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.user?.id;
    final otherUser = widget.conversation.otherUser;

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
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              _otherUserTyping
                  ? '正在输入...'
                  : '@${otherUser?.username ?? ''}',
              style: TextStyle(
                color: _otherUserTyping ? AppColors.primary : AppColors.textSecondary,
                fontSize: 13,
                fontStyle: _otherUserTyping ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppColors.textPrimary, size: 22),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('聊天信息'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('对方: ${widget.conversation.otherUser?.displayName ?? '未知用户'}'),
                      Text('用户名: @${widget.conversation.otherUser?.username ?? ''}'),
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
          // Messages
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() { _error = null; _page = 1; _hasMore = true; });
                            _loadMessages();
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
                : _messages.isEmpty && !_isLoading
                ? _buildEmpty(otherUser)
                : SmartRefresher(
                    controller: _refreshController,
                    enablePullDown: true,
                    enablePullUp: _hasMore,
                    onRefresh: () async {
                      setState(() { _page = 1; _hasMore = true; });
                      await _loadMessages();
                    },
                    onLoading: _loadMessages,
                    header: const WaterDropHeader(
                      complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
                      waterDropColor: AppColors.primary,
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final msg = _messages[i];
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
          _buildInputBar(),
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('@${otherUser?.username ?? ''}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
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

  Widget _buildInputBar() {
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
              _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            onPressed: _toggleEmojiPicker,
          ),
          // Image button
          IconButton(
            icon: const Icon(Icons.image_outlined, color: AppColors.primary, size: 24),
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
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: '开始新消息',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _isSending
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send, color: AppColors.primary, size: 24),
                  onPressed: _sendMessage,
                ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    // Common emoji categories
    final emojis = [
      // Smileys
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
      '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
      '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
      '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
      // Reactions
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
      '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '👍', '👎',
      '👏', '🙌', '🤝', '✊', '🤛', '🤜', '🤞', '✌️', '🤟', '🤘',
      // Animals
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
      '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦆',
      // Food
      '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
      '🍈', '🍒', '🍑', '🍍', '🥝', '🍅', '🥑', '🍆', '🥔', '🥕',
      // Activities
      '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
      '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '⛳', '🏹', '🎣', '🤿',
      // Objects
      '💻', '🖥️', '🖨️', '⌨️', '🖱️', '🖲️', '💽', '💾', '💿', '📀',
      '📱', '📲', '☎️', '📞', '📟', '📠', '🔋', '🔌', '💡', '🔦',
      // Symbols
      '🔥', '✨', '🎉', '🎊', '🎁', '🎈', '🌟', '⭐', '💫', '💥',
      '💢', '💦', '💨', '🕳️', '💣', '💬', '👁️\u200d🗨️', '🗨️', '🗯️', '💭',
    ];

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

  const _MessageBubble({required this.message, required this.isMe, this.otherUser});

  @override
  Widget build(BuildContext context) {
    final isText = message.messageType == MessageType.text;
    final time = AppDateUtils.formatTimeAgo(message.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            ImageUtils.buildAvatar(otherUser, radius: 14),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.borderLight,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
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
                            color: isMe ? Colors.white : AppColors.textPrimary,
                          ),
                        )
                      else if (message.messageType == MessageType.image)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: message.mediaUrl ?? message.content ?? '',
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) => Container(
                              width: 200,
                              height: 200,
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (ctx, url, err) => Container(
                              width: 200,
                              height: 100,
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        )
                      else ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              message.messageType == MessageType.video ? Icons.videocam
                                  : message.messageType == MessageType.file ? Icons.insert_drive_file
                                  : message.messageType == MessageType.post ? Icons.article
                                  : Icons.comment,
                              size: 16,
                              color: isMe ? Colors.white70 : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                message.content ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isMe ? Colors.white : AppColors.textPrimary,
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
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
