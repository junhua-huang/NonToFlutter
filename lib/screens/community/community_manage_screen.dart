import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/services/api/community_service.dart';

/// 社群管理页 — 管理后台
/// Tab 1: 待审核 | Tab 2: 公告 | Tab 3: 成员 | Tab 4: 黑名单
class CommunityManageScreen extends ConsumerStatefulWidget {
  final int communityId;
  const CommunityManageScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityManageScreen> createState() =>
      _CommunityManageScreenState();
}

class _CommunityManageScreenState extends ConsumerState<CommunityManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _api = CommunityApiService();

  List<CommunityJoinRequest> _requests = [];
  List<CommunityAnnouncement> _announcements = [];
  List<CommunityMember> _members = [];
  List<CommunityBan> _bans = [];
  bool _loadingRequests = true;
  bool _loadingAnn = true;
  bool _loadingMembers = true;
  bool _loadingBans = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadRequests();
    _loadAnnouncements();
    _loadMembers();
    _loadBans();
  }

  Future<void> _loadRequests() async {
    try {
      final resp = await _api.getJoinRequests(widget.communityId);
      if (resp.data is Map && resp.data['requests'] is List) {
        _requests = (resp.data['requests'] as List)
            .map((e) => CommunityJoinRequest.fromJson(e))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingRequests = false);
  }

  Future<void> _loadAnnouncements() async {
    try {
      final resp = await _api.getAnnouncements(widget.communityId);
      if (resp.data is Map && resp.data['announcements'] is List) {
        _announcements = (resp.data['announcements'] as List)
            .map((e) => CommunityAnnouncement.fromJson(e))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingAnn = false);
  }

  Future<void> _loadMembers() async {
    try {
      final resp = await _api.getMembers(widget.communityId, limit: 100);
      if (resp.data is Map && resp.data['members'] is List) {
        _members = (resp.data['members'] as List)
            .map((e) => CommunityMember.fromJson(e))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMembers = false);
  }

  Future<void> _loadBans() async {
    try {
      final resp = await _api.getBans(widget.communityId);
      if (resp.data is Map && resp.data['bans'] is List) {
        _bans = (resp.data['bans'] as List)
            .map((e) => CommunityBan.fromJson(e))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingBans = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理社群'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: [
            Tab(text: '待审核 (${_requests.length})'),
            Tab(text: '公告 (${_announcements.length})'),
            Tab(text: '成员 (${_members.length})'),
            Tab(text: '黑名单 (${_bans.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildRequestsTab(),
          _buildAnnouncementsTab(),
          _buildMembersTab(),
          _buildBansTab(),
        ],
      ),
    );
  }

  // ── 待审核 Tab ──

  Widget _buildRequestsTab() {
    if (_loadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requests.isEmpty) {
      return const Center(child: Text('暂无待审核申请'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _requests.length,
      itemBuilder: (_, i) {
        final r = _requests[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(r.user?.username ?? '用户'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.message != null) Text(r.message!, maxLines: 2),
                Text('申请时间: ${_formatTime(r.createdAt)}',
                    style:
                        TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _handleReject(r.id),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _handleApprove(r.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleApprove(int reqId) async {
    try {
      await _api.approveJoin(widget.communityId, reqId);
      _loadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  Future<void> _handleReject(int reqId) async {
    try {
      await _api.rejectJoin(widget.communityId, reqId);
      _loadRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  // ── 公告 Tab ──

  Widget _buildAnnouncementsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showCreateAnnouncementDialog,
              icon: const Icon(Icons.add),
              label: const Text('发布公告'),
            ),
          ),
        ),
        Expanded(
          child: _loadingAnn
              ? const Center(child: CircularProgressIndicator())
              : _announcements.isEmpty
                  ? const Center(child: Text('暂无公告'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _announcements.length,
                      itemBuilder: (_, i) {
                        final a = _announcements[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: a.isPinned
                                ? const Icon(Icons.push_pin,
                                    color: Colors.amber)
                                : null,
                            title: Text(a.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (a.content != null)
                                  Text(a.content!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                if (a.author != null)
                                  Text('由 ${a.author!.username} 发布',
                                      style: TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 11)),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _handleDeleteAnnouncement(a.id),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _showCreateAnnouncementDialog() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    bool pin = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('发布公告'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题 *',
                  border: OutlineInputBorder(),
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('置顶'),
                Switch(
                  value: pin,
                  onChanged: (v) => setDialogState(() => pin = v),
                ),
              ]),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                try {
                  await _api.createAnnouncement(widget.communityId,
                      title: titleCtrl.text.trim(),
                      content: contentCtrl.text.trim(),
                      isPinned: pin);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAnnouncements();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('发布失败: $e')));
                  }
                }
              },
              child: const Text('发布'),
            ),
          ],
        ),
      ),
    );
    titleCtrl.dispose();
    contentCtrl.dispose();
  }

  Future<void> _handleDeleteAnnouncement(int aid) async {
    try {
      await _api.deleteAnnouncement(widget.communityId, aid);
      _loadAnnouncements();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  // ── 成员 Tab ──

  Widget _buildMembersTab() {
    if (_loadingMembers) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
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
              : m.isAdmin
                  ? PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'remove_admin') {
                          _api.setRole(widget.communityId, m.userId, 'member');
                          _loadMembers();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'remove_admin', child: Text('撤销管理员')),
                      ],
                    )
                  : PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'set_admin') {
                          _api.setRole(widget.communityId, m.userId, 'admin');
                          _loadMembers();
                        } else if (v == 'kick') {
                          _api.kick(widget.communityId, m.userId);
                          _loadMembers();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'set_admin', child: Text('设为管理员')),
                        const PopupMenuItem(
                            value: 'kick',
                            child: Text('踢出',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
        );
      },
    );
  }

  // ── 黑名单 Tab ──

  Widget _buildBansTab() {
    if (_loadingBans) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showBanDialog,
              icon: const Icon(Icons.block),
              label: const Text('拉黑用户'),
            ),
          ),
        ),
        Expanded(
          child: _bans.isEmpty
              ? const Center(child: Text('暂无黑名单'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _bans.length,
                  itemBuilder: (_, i) {
                    final b = _bans[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(b.user?.username ?? '用户'),
                        subtitle: Text(b.reason ?? '无原因'),
                        trailing: IconButton(
                          icon: const Icon(Icons.lock_open),
                          onPressed: () => _handleUnban(b.userId),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showBanDialog() {
    final uidCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拉黑用户'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: uidCtrl,
              decoration: const InputDecoration(
                  labelText: '用户 ID *', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                  labelText: '原因（可选）', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final uid = int.tryParse(uidCtrl.text.trim());
              if (uid == null) return;
              try {
                await _api.banUser(widget.communityId,
                    userId: uid, reason: reasonCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _loadBans();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('拉黑失败: $e')));
                }
              }
            },
            child: const Text('拉黑'),
          ),
        ],
      ),
    );
    uidCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<void> _handleUnban(int userId) async {
    try {
      await _api.unbanUser(widget.communityId, userId);
      _loadBans();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('解封失败: $e')));
      }
    }
  }

  // ── 工具 ──

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

  String _formatTime(DateTime? dt) {
    if (dt == null) {
      return '';
    }
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
