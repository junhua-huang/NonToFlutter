import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/data/emoji_data.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/api/upload_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/image_utils.dart';

/// 社群群聊页
/// 支持：发送消息、图片/视频、表情、@提及、撤回与管理员删除。
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
  final FocusNode _msgFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final Set<int> _mentionUserIds = {};
  final List<Map<String, dynamic>> _messages = [];
  List<CommunityMember> _members = [];
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  int? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  int _emojiTabIndex = 0;

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
    _msgFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty || _isSending) return;
    final mentionUserIds = _mentionUserIds.toList();
    _msgCtrl.clear();
    setState(() => _isSending = true);

    try {
      await CommunityApiService().sendMessage(
        widget.communityId,
        content: content,
        messageType: 'text',
        mentionUserIds: _mentionUserIds.toList(),
      );
      _mentionUserIds.clear();
      _syncConversationPreview(content, 'text');
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        _msgCtrl.text = content;
        _msgCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _msgCtrl.text.length),
        );
        _mentionUserIds
          ..clear()
          ..addAll(mentionUserIds);
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
    final messageType = messageMap['message_type']?.toString() ?? 'text';
    final preview = messageMap['media_url']?.toString().isNotEmpty == true
        ? messageMap['media_url'].toString()
        : (messageMap['content']?.toString() ?? '');
    _syncConversationPreview(preview, messageType);
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
    final before = cursorPos >= 0 ? currentText.substring(0, cursorPos) : currentText;
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
        text: '${currentText.substring(0, cursorPos - 1)}@$name ${currentText.substring(cursorPos)}',
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

  Future<void> _ensureMembersLoaded() async {
    if (_members.isNotEmpty) return;
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
    _members = list
        .whereType<Map>()
        .map((member) => CommunityMember.fromJson(Map<String, dynamic>.from(member)))
        .toList();
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final member = filtered[index];
                              final user = member.user;
                              final name = user?.displayName?.trim().isNotEmpty == true
                                  ? user!.displayName!.trim()
                                  : (user?.username.trim().isNotEmpty == true
                                      ? user!.username.trim()
                                      : '用户${member.userId}');
                              return ListTile(
                                leading: _buildMemberAvatar(name, user?.avatarUrl),
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
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _sendMediaMessage(
      upload: () => UploadService().uploadImage(file),
      messageType: 'image',
    );
  }

  Future<void> _pickAndSendVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    await _sendMediaMessage(
      upload: () => UploadService().uploadVideo(file),
      messageType: 'video',
    );
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
      await CommunityApiService().sendMessage(
        widget.communityId,
        content: url,
        messageType: messageType,
        mediaUrl: url,
      );
      _syncConversationPreview(url, messageType);
      await _loadMessages();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.communityName ?? '社群交流')),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(),
          if (_showEmojiPicker) _buildEmojiPicker(),
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
          onAvatarLongPress: () => _insertMentionFromMessage(message),
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
                          color: selected ? AppColors.primary : Colors.transparent,
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
        backgroundImage: CachedNetworkImageProvider(ImageUtils.resolveUrl(avatarUrl)),
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

  const _MessageBubble({
    required this.message,
    this.isMine = false,
    this.onRecall,
    this.onAvatarLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final recalled = message['is_recalled'] == true;
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
                    if (messageType == 'image')
                      _buildImageMessage(mediaUrl)
                    else if (messageType == 'video')
                      _buildVideoMessage(mediaUrl)
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
