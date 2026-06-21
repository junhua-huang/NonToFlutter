import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/image_utils.dart';

/// 社群群聊页
/// 支持：发送消息、@提及、撤回与管理员删除。
class CommunityChatScreen extends ConsumerStatefulWidget {
  final int communityId;
  final String? communityName;
  const CommunityChatScreen({
    super.key,
    required this.communityId,
    this.communityName,
  });

  @override
  ConsumerState<CommunityChatScreen> createState() =>
      _CommunityChatScreenState();
}

class _CommunityChatScreenState extends ConsumerState<CommunityChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  int? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messageSub =
        WebSocketService().messageStream.listen(_appendRealtimeMessage);
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
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
          }
        }
        if (data['messages'] is List) {
          _messages.clear();
          _messages.addAll(
            (data['messages'] as List).map(
              (message) => Map<String, dynamic>.from(message),
            ),
          );
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    final conversationId = _conversationId;
    if (conversationId != null) {
      WebSocketService().leaveConversation(conversationId);
    }
    _messageSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty || _isSending) return;
    _msgCtrl.clear();
    setState(() => _isSending = true);

    try {
      await CommunityApiService().sendMessage(
        widget.communityId,
        content: content,
      );
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        _msgCtrl.text = content;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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

  void _appendRealtimeMessage(Map<String, dynamic> payload) {
    if (payload['event'] != 'new_message') return;
    final message = payload['message'];
    if (message is! Map) return;

    final messageMap = Map<String, dynamic>.from(message);
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

    final messageId = messageMap['id'];
    final alreadyAdded = messageId != null &&
        _messages.any((existing) => existing['id'] == messageId);
    if (alreadyAdded || !mounted) return;

    setState(() => _messages.add(messageMap));
  }

  void _showMentionPicker() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('@ 提及'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入用户名...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final text = _msgCtrl.text;
              _msgCtrl.text = '$text@${controller.text} ';
              _msgCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _msgCtrl.text.length),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.communityName ?? '社群交流')),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return _buildEmptyMessagesState();
    }
    final currentUserId = ref.watch(authProvider).user?.id;
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      itemCount: _messages.length,
      itemBuilder: (_, index) {
        final message = _messages[_messages.length - 1 - index];
        final isMine = message['sender_id'] == currentUserId;
        return _MessageBubble(
          message: message,
          isMine: isMine,
          onRecall: () => _recallMessage(message['id'], isMine),
        );
      },
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

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
              tooltip: '@ 提及',
              icon: const Icon(Icons.alternate_email, size: 24),
              onPressed: _showMentionPicker,
            ),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
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
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              color: Colors.white,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final VoidCallback? onRecall;

  const _MessageBubble({
    required this.message,
    this.isMine = false,
    this.onRecall,
  });

  @override
  Widget build(BuildContext context) {
    final recalled = message['is_recalled'] == true;
    final content = message['content'] ?? '';
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            _buildSenderAvatar(senderName, senderAvatar),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress:
                  isMine && onRecall != null ? () => onRecall!() : null,
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
