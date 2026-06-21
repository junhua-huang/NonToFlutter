import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/providers/community_notifier.dart';
import 'package:nonto/screens/community/community_chat_screen.dart';
import 'package:nonto/screens/community/community_manage_screen.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:nonto/widgets/post_card.dart';

/// 社群详情页
/// Banner、信息区、成员动作与社群动态流。
class CommunityDetailScreen extends ConsumerStatefulWidget {
  final int communityId;
  const CommunityDetailScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  StreamSubscription<PostLikeEvent>? _likeSub;

  @override
  void initState() {
    super.initState();
    _likeSub = PostInteractionNotifier().onLikeChanged.listen((event) {
      ref.read(communityDetailProvider.notifier).updatePostLike(
            event.postId,
            event.isLiked,
            event.likeCount,
          );
    });
    Future.microtask(
      () => ref.read(communityDetailProvider.notifier).load(widget.communityId),
    );
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityDetailProvider);
    final community = state.community;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(community?.name ?? '社群'),
        actions: [
          if (community != null && (community.isManager || community.isMember))
            PopupMenuButton<String>(
              onSelected: (value) => _handleMenuAction(value, community),
              itemBuilder: (context) => _buildMenuItems(community),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('加载失败: ${state.error}'))
              : community == null
                  ? const Center(child: Text('社群不存在'))
                  : _buildContent(community, state, theme),
    );
  }

  Widget _buildContent(
    Community community,
    CommunityDetailState state,
    ThemeData theme,
  ) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(communityDetailProvider.notifier).load(widget.communityId),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _buildCommunityHeader(community, theme),
          ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          SliverToBoxAdapter(child: _buildDynamicToolbar(state)),
          if (state.posts.isEmpty)
            SliverToBoxAdapter(child: _buildPostEmptyState())
          else
            SliverList.builder(
              itemCount: state.posts.length,
              itemBuilder: (context, index) {
                final post = state.posts[index];
                return PostCard(
                  post: post,
                  onTap: () => Navigator.pushNamed(context, '/post/${post.id}'),
                  onLike: () => _togglePostLike(post),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _togglePostLike(Post post) async {
    final wasLiked = post.isLiked == true;
    final originalCount = post.likeCount;
    final nextCount = wasLiked ? originalCount - 1 : originalCount + 1;

    ref
        .read(communityDetailProvider.notifier)
        .updatePostLike(post.id, !wasLiked, nextCount);

    try {
      if (wasLiked) {
        await PostService().unlikePost(post.id);
      } else {
        await PostService().likePost(post.id);
      }
      PostInteractionNotifier()
          .notifyLikeChanged(post.id, !wasLiked, nextCount);
    } catch (_) {
      if (!mounted) return;
      ref
          .read(communityDetailProvider.notifier)
          .updatePostLike(post.id, wasLiked, originalCount);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  Widget _buildCommunityHeader(Community community, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (community.bannerUrl != null)
          Container(
            height: 168,
            width: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(community.bannerUrl!),
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          Container(
            height: 126,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.88),
                  AppColors.primary.withValues(alpha: 0.48),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(
                  Icons.groups_3,
                  color: Colors.white.withValues(alpha: 0.55),
                  size: 54,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundImage: community.avatarUrl != null
                        ? NetworkImage(community.avatarUrl!)
                        : null,
                    child: community.avatarUrl == null
                        ? Text(
                            community.name[0],
                            style: const TextStyle(fontSize: 25),
                          )
                        : null,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          community.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${community.memberCount} 成员 · ${community.postCount} 条社群动态',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (community.description != null &&
                  community.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(community.description!,
                    style: const TextStyle(height: 1.45)),
              ],
              if (community.rules != null &&
                  community.rules!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined,
                          color: AppColors.textSecondary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          community.rules!,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildActionButtons(community),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicToolbar(CommunityDetailState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '社群动态',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          _sortChip('最新', state.sortBy == 'latest', () {
            ref
                .read(communityDetailProvider.notifier)
                .loadPosts(widget.communityId);
          }),
          const SizedBox(width: 8),
          _sortChip('热门', state.sortBy == 'hot', () {
            ref
                .read(communityDetailProvider.notifier)
                .loadPosts(widget.communityId, hot: true);
          }),
        ],
      ),
    );
  }

  Widget _buildPostEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 96),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 42, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          const Text(
            '还没有社群动态',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '加入讨论，发布第一条有价值的分享。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.textTertiary,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textTertiary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(Community community) {
    return Row(
      children: [
        if (community.isMember)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CommunityChatScreen(communityId: community.id),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('群聊'),
            ),
          ),
        if (community.isMember) const SizedBox(width: 8),
        if (!community.isMember)
          Expanded(
            child: ElevatedButton(
              onPressed: () => _handleJoin(community),
              child: Text(community.isPending ? '审核中' : '加入社群'),
            ),
          )
        else
          Expanded(
            child: OutlinedButton(
              onPressed: () => _handleLeave(community),
              child: const Text('已加入'),
            ),
          ),
        const SizedBox(width: 8),
        if (community.isMember)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _navigateToCreatePost(community),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('发动态'),
            ),
          ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(Community community) {
    final items = <PopupMenuEntry<String>>[];
    if (community.isManager) {
      items.add(const PopupMenuItem(value: 'manage', child: Text('管理社群')));
    }
    items.add(const PopupMenuItem(value: 'members', child: Text('查看成员')));
    if (community.isMember) {
      items.add(const PopupMenuItem(value: 'leave', child: Text('退出社群')));
    }
    if (community.isOwner) {
      items.add(const PopupMenuDivider());
      items.add(
        const PopupMenuItem(
          value: 'disband',
          child: Text('解散社群', style: TextStyle(color: Colors.red)),
        ),
      );
    }
    return items;
  }

  void _handleMenuAction(String action, Community community) {
    switch (action) {
      case 'manage':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CommunityManageScreen(communityId: community.id),
          ),
        );
        break;
      case 'members':
        _showMembers(community.id);
        break;
      case 'leave':
        _handleLeave(community);
        break;
      case 'disband':
        _confirmDisband(community);
        break;
    }
  }

  void _handleJoin(Community community) async {
    final api = CommunityApiService();
    try {
      if (community.isApproval) {
        final message = await _showJoinDialog();
        if (message == null) return;
        await api.join(community.id, message: message);
      } else {
        await api.join(community.id);
      }
      ref.read(communityDetailProvider.notifier).load(widget.communityId);
      ref.read(communityListProvider.notifier).refreshMy();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  Future<String?> _showJoinDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('申请加入'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '写下你想加入的理由...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _handleLeave(Community community) async {
    final api = CommunityApiService();
    try {
      await api.leave(community.id);
      ref.read(communityDetailProvider.notifier).load(widget.communityId);
      ref.read(communityListProvider.notifier).refreshMy();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  void _confirmDisband(Community community) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解散社群'),
        content: const Text('确定要解散社群吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认解散'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await CommunityApiService().disband(community.id);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('解散失败: $e')));
        }
      }
    }
  }

  void _showMembers(int communityId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MembersSheet(communityId: communityId),
    );
  }

  void _navigateToCreatePost(Community community) {
    Navigator.pushNamed(
      context,
      '/create-post',
      arguments: {
        'community_id': community.id,
        'community_name': community.name
      },
    );
  }
}

/// 成员列表底部弹窗
class _MembersSheet extends ConsumerStatefulWidget {
  final int communityId;
  const _MembersSheet({required this.communityId});

  @override
  ConsumerState<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends ConsumerState<_MembersSheet> {
  List<CommunityMember> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await CommunityApiService().getMembers(widget.communityId);
      if (resp.data is Map && resp.data['members'] is List) {
        _members = (resp.data['members'] as List)
            .map((e) => CommunityMember.fromJson(e))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '成员 (${_members.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _members.length,
                itemBuilder: (_, index) {
                  final member = _members[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: member.user?.avatarUrl != null
                          ? NetworkImage(member.user!.avatarUrl!)
                          : null,
                      child: member.user != null
                          ? Text(member.user!.username[0])
                          : null,
                    ),
                    title: Text(member.user?.username ?? '用户'),
                    subtitle: Text(_roleLabel(member.role)),
                    trailing: member.isOwner
                        ? const Icon(Icons.star, color: Colors.amber)
                        : null,
                  );
                },
              ),
            ),
        ],
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
}
