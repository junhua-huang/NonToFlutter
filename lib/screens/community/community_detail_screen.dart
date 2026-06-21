import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/providers/community_notifier.dart';
import 'package:nonto/widgets/post_card.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/screens/community/community_chat_screen.dart';
import 'package:nonto/screens/community/community_manage_screen.dart';

/// 社群详情页 — 推特风格
/// Banner → 信息区 → 操作按钮 → 公告 → 帖子流（最新/热门切换）
class CommunityDetailScreen extends ConsumerStatefulWidget {
  final int communityId;
  const CommunityDetailScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(communityDetailProvider.notifier).load(widget.communityId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityDetailProvider);
    final c = state.community;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? '社群'),
        actions: [
          if (c != null && (c.isManager || c.isMember))
            PopupMenuButton<String>(
              onSelected: (v) => _handleMenuAction(v, c),
              itemBuilder: (ctx) => _buildMenuItems(c),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('加载失败: ${state.error}'))
              : c == null
                  ? const Center(child: Text('社群不存在'))
                  : _buildContent(c, state, theme),
    );
  }

  Widget _buildContent(
      Community c, CommunityDetailState state, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(communityDetailProvider.notifier).load(widget.communityId),
      child: ListView(
        children: [
          // Banner 封面
          if (c.bannerUrl != null)
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                image: DecorationImage(
                    image: NetworkImage(c.bannerUrl!), fit: BoxFit.cover),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像 + 名称
                Row(children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage:
                        c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
                    child: c.avatarUrl == null
                        ? Text(c.name[0], style: const TextStyle(fontSize: 24))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('${c.memberCount} 成员 · ${c.postCount} 帖子',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // 简介
                if (c.description != null)
                  Text(c.description!, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),

                // 规则
                if (c.rules != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(c.rules!,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                const SizedBox(height: 12),

                // 操作按钮
                _buildActionButtons(c),
              ],
            ),
          ),

          // 置顶公告
          const Divider(height: 1),

          // 排序切换
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
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
            ]),
          ),

          // 帖子流
          if (state.posts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无帖子')),
            )
          else
            ...state.posts.map((p) => PostCard(
                post: p,
                onTap: () {
                  Navigator.pushNamed(context, '/post/${p.id}');
                })),
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
              color: selected ? AppColors.primary : AppColors.textTertiary),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.textTertiary,
                fontSize: 13)),
      ),
    );
  }

  Widget _buildActionButtons(Community c) {
    return Row(children: [
      // 群聊（仅成员可见）
      if (c.isMember)
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CommunityChatScreen(communityId: c.id))),
            icon: const Icon(Icons.chat, size: 18),
            label: const Text('群聊'),
          ),
        ),
      if (c.isMember) const SizedBox(width: 8),

      // 加入/已加入/待审核 按钮
      if (!c.isMember)
        Expanded(
          child: ElevatedButton(
            onPressed: () => _handleJoin(c),
            child: Text(c.isPending ? '审核中' : '加入'),
          ),
        )
      else
        Expanded(
          child: OutlinedButton(
            onPressed: () => _handleLeave(c),
            child: const Text('已加入'),
          ),
        ),
      const SizedBox(width: 8),

      // 发帖（仅成员）
      if (c.isMember)
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _navigateToCreatePost(c),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('发帖'),
          ),
        ),
    ]);
  }

  List<PopupMenuEntry<String>> _buildMenuItems(Community c) {
    final items = <PopupMenuEntry<String>>[];
    if (c.isManager) {
      items.add(const PopupMenuItem(value: 'manage', child: Text('管理社群')));
    }
    items.add(const PopupMenuItem(value: 'members', child: Text('查看成员')));
    if (c.isMember) {
      items.add(const PopupMenuItem(value: 'leave', child: Text('退出社群')));
    }
    if (c.isOwner) {
      items.add(const PopupMenuDivider());
      items.add(const PopupMenuItem(
          value: 'disband',
          child: Text('解散社群', style: TextStyle(color: Colors.red))));
    }
    return items;
  }

  void _handleMenuAction(String action, Community c) {
    switch (action) {
      case 'manage':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CommunityManageScreen(communityId: c.id)));
        break;
      case 'members':
        _showMembers(c.id);
        break;
      case 'leave':
        _handleLeave(c);
        break;
      case 'disband':
        _confirmDisband(c);
        break;
    }
  }

  void _handleJoin(Community c) async {
    final api = CommunityApiService();
    try {
      if (c.isApproval) {
        // 审核制：弹申请理由
        final message = await _showJoinDialog();
        if (message == null) return;
        await api.join(c.id, message: message);
      } else {
        await api.join(c.id);
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
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('申请加入'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: '申请理由...', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('提交')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _handleLeave(Community c) async {
    final api = CommunityApiService();
    try {
      await api.leave(c.id);
      ref.read(communityDetailProvider.notifier).load(widget.communityId);
      ref.read(communityListProvider.notifier).refreshMy();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  void _confirmDisband(Community c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散社群'),
        content: const Text('确定要解散社群吗？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认解散'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await CommunityApiService().disband(c.id);
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
      builder: (ctx) => _MembersSheet(communityId: communityId),
    );
  }

  void _navigateToCreatePost(Community c) {
    Navigator.pushNamed(context, '/create-post',
        arguments: {'community_id': c.id, 'community_name': c.name});
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
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('成员 (${_members.length})',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _members.length,
                itemBuilder: (_, i) {
                  final m = _members[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: m.user?.avatarUrl != null
                          ? NetworkImage(m.user!.avatarUrl!)
                          : null,
                      child: m.user != null ? Text(m.user!.username[0]) : null,
                    ),
                    title: Text(m.user?.username ?? '用户'),
                    subtitle: Text(_roleLabel(m.role)),
                    trailing: m.isOwner
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
