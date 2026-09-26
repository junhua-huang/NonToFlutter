import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/chat_service.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/post_share_target_resolver.dart';
import 'package:nonto/utils/image_utils.dart';

class PostShareToChatSheet extends StatefulWidget {
  final Post post;

  const PostShareToChatSheet({super.key, required this.post});

  static Future<void> show(BuildContext context, {required Post post}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PostShareToChatSheet(post: post),
    );
  }

  @override
  State<PostShareToChatSheet> createState() => _PostShareToChatSheetState();
}

class _PostShareToChatSheetState extends State<PostShareToChatSheet> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<PostShareTarget>> _targetsFuture;
  String _query = '';
  final Set<String> _selectedKeys = <String>{};
  final Set<String> _sendingKeys = <String>{};
  final Map<String, String> _failedMessages = <String, String>{};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _targetsFuture = PostShareTargetResolver().loadTargets();
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<ApiResponse> _sendToFriend(PostShareTarget target) async {
    final post = widget.post;
    final convResp = await ChatService().getOrCreateConversation(target.friend!.id);
    if (convResp.success != true) return convResp;
    final data = convResp.data;
    final conversation = data is Map ? (data['conversation'] ?? data) : null;
    final conversationId = conversation is Map
        ? int.tryParse(conversation['id']?.toString() ?? '')
        : null;
    if (conversationId == null || conversationId <= 0) {
      return ApiResponse(success: false, message: '发送失败，请重试');
    }
    return ChatService().sendMessage(
      conversationId,
      _postShareTitle(post),
      messageType: 'post',
      relatedId: post.id,
      mediaUrl: _postSharePreviewMediaUrl(post),
    );
  }

  Future<ApiResponse> _sendToCommunity(PostShareTarget target) {
    final post = widget.post;
    return CommunityApiService().sendMessage(
      target.community!.id,
      content: _postShareTitle(post),
      messageType: 'post',
      relatedId: post.id,
      mediaUrl: _postSharePreviewMediaUrl(post),
    );
  }

  Future<ApiResponse> _sendToTarget(PostShareTarget target) {
    switch (target.type) {
      case PostShareTargetType.friend:
        return _sendToFriend(target);
      case PostShareTargetType.community:
        return _sendToCommunity(target);
    }
  }

  String _postShareTitle(Post post) {
    final text = post.content?.trim();
    if (text == null || text.isEmpty) return '查看帖子 #${post.id}';
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  String? _postSharePreviewMediaUrl(Post post) {
    final images = post.images ?? const <String>[];
    for (final image in images) {
      if (image.trim().isNotEmpty) return image;
    }
    return post.thumbnailUrl?.trim().isNotEmpty == true ? post.thumbnailUrl : null;
  }

  void _toggleSelection(PostShareTarget target) {
    if (_sending) return;
    setState(() {
      final key = target.stableKey;
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
        _failedMessages.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _retryLoadTargets() {
    setState(() {
      _targetsFuture = PostShareTargetResolver().loadTargets();
      _selectedKeys.clear();
      _failedMessages.clear();
      _sendingKeys.clear();
    });
  }

  Future<void> _sendSelected(List<PostShareTarget> targets) async {
    if (_sending || _selectedKeys.isEmpty) return;
    final selectedTargets = targets
        .where((target) => _selectedKeys.contains(target.stableKey))
        .toList();
    if (selectedTargets.isEmpty) return;

    setState(() {
      _sending = true;
      _sendingKeys
        ..clear()
        ..addAll(selectedTargets.map((target) => target.stableKey));
      _failedMessages.clear();
    });

    final messenger = ScaffoldMessenger.of(context);
    var successCount = 0;
    for (final target in selectedTargets) {
      try {
        final response = await _sendToTarget(target);
        if (!mounted) return;
        if (response.success == true) {
          successCount += 1;
          setState(() {
            _selectedKeys.remove(target.stableKey);
            _sendingKeys.remove(target.stableKey);
          });
        } else {
          setState(() {
            _sendingKeys.remove(target.stableKey);
            _failedMessages[target.stableKey] =
                apiFailureMessage(response, fallback: '发送失败，请重试');
          });
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _sendingKeys.remove(target.stableKey);
          _failedMessages[target.stableKey] = '发送失败，请重试';
        });
      }
    }

    if (!mounted) return;
    setState(() => _sending = false);
    if (_failedMessages.isEmpty && successCount > 0) {
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('已发送给 $successCount 个聊天')));
    } else if (successCount > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('已发送 $successCount 个，失败 ${_failedMessages.length} 个')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: FutureBuilder<List<PostShareTarget>>(
          future: _targetsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 220,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '加载分享对象失败',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _retryLoadTargets,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final targets = snapshot.data ?? const <PostShareTarget>[];
            final filteredTargets = filterPostShareTargets(targets, _query);
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '发送帖子到聊天',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索好友或群聊',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close),
                            ),
                      filled: true,
                      fillColor: AppColors.backgroundSecondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (targets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('暂无可发送的聊天或社群')),
                    )
                  else if (filteredTargets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('没有找到相关好友或群聊')),
                    )
                  else
                    Flexible(child: _buildGroupedTargetList(targets, filteredTargets)),
                  const SizedBox(height: 12),
                  _buildBottomBar(targets),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroupedTargetList(
    List<PostShareTarget> allTargets,
    List<PostShareTarget> filteredTargets,
  ) {
    final recentKeys = allTargets
        .where((target) => target.isRecent)
        .map((target) => target.stableKey)
        .toSet();
    final recent = filteredTargets
        .where((target) => recentKeys.contains(target.stableKey))
        .toList();
    final friends = filteredTargets
        .where((target) => target.type == PostShareTargetType.friend && !recentKeys.contains(target.stableKey))
        .toList();
    final communities = filteredTargets
        .where((target) => target.type == PostShareTargetType.community && !recentKeys.contains(target.stableKey))
        .toList();

    final children = <Widget>[
      if (recent.isNotEmpty) ..._buildTargetSection('最近', recent),
      if (friends.isNotEmpty) ..._buildTargetSection('好友', friends),
      if (communities.isNotEmpty) ..._buildTargetSection('群聊', communities),
    ];
    return ListView(children: children);
  }

  List<Widget> _buildTargetSection(String title, List<PostShareTarget> targets) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          title,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      for (final target in targets) _buildTargetTile(target),
    ];
  }

  Widget _buildTargetTile(PostShareTarget target) {
    final selected = _selectedKeys.contains(target.stableKey);
    final sending = _sendingKeys.contains(target.stableKey);
    final failedMessage = _failedMessages[target.stableKey];
    return ListTile(
      enabled: !_sending || selected,
      contentPadding: EdgeInsets.zero,
      leading: _buildTargetAvatar(target),
      title: Text(target.title),
      subtitle: Text(failedMessage ?? target.subtitle),
      trailing: sending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textTertiary,
            ),
      selected: selected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: () => _toggleSelection(target),
    );
  }

  Widget _buildTargetAvatar(PostShareTarget target) {
    if (target.type == PostShareTargetType.friend) {
      return ImageUtils.buildAvatar(target.friend, radius: 20);
    }
    final community = target.community;
    final avatarUrl = _communityAvatarUrl(community);
    if (avatarUrl != null) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(ImageUtils.resolveUrl(avatarUrl)),
        backgroundColor: AppColors.backgroundSecondary,
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.backgroundSecondary,
      child: Icon(Icons.groups_3_outlined, color: AppColors.textSecondary),
    );
  }

  String? _communityAvatarUrl(Community? community) {
    final avatar = community?.avatarUrl?.trim();
    return avatar == null || avatar.isEmpty ? null : avatar;
  }

  Widget _buildBottomBar(List<PostShareTarget> targets) {
    final selectedCount = _selectedKeys.length;
    final failedCount = _failedMessages.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            failedCount > 0 ? '失败 $failedCount 个，可重试' : '已选 $selectedCount 个',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _sending || selectedCount == 0 ? null : () => _sendSelected(targets),
          child: Text(_sending ? '发送中...' : failedCount > 0 ? '重试' : '发送'),
        ),
      ],
    );
  }
}
