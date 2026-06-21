import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/community_service.dart';

/// 社群群聊页
/// 支持：发送消息、@提及、撤回与管理员删除。
class CommunityChatScreen extends StatefulWidget {
  final int communityId;
  final String? communityName;
  const CommunityChatScreen({
    super.key,
    required this.communityId,
    this.communityName,
  });

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final api = CommunityApiService();
      final resp = await api.getChat(widget.communityId, limit: 50);
      if (resp.data is Map && resp.data['messages'] is List) {
        _messages.clear();
        _messages.addAll(
          (resp.data['messages'] as List).map(
            (message) => Map<String, dynamic>.from(message),
          ),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
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
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      itemCount: _messages.length,
      itemBuilder: (_, index) {
        final message = _messages[_messages.length - 1 - index];
        final isMine = message['sender_id'] == 0;
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
    final senderName = message['sender_name'] ?? '用户';
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
            CircleAvatar(
              radius: 16,
              child: Text(senderName[0], style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress:
                  isMine && onRecall != null ? () => onRecall!() : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMine ? AppColors.primary : Colors.grey[200],
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
                        color: isMine ? Colors.white : Colors.black87,
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
