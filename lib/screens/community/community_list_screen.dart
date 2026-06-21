import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/providers/community_notifier.dart';
import 'package:nonto/screens/community/community_detail_screen.dart';
import 'package:nonto/screens/community/community_create_screen.dart';

/// 社群列表/发现页 — 推特风格
/// 包含：我的社群（横向卡片）+ 推荐社群（纵向列表）+ 搜索 + 创建入口
class CommunityListScreen extends ConsumerStatefulWidget {
  const CommunityListScreen({super.key});

  @override
  ConsumerState<CommunityListScreen> createState() =>
      _CommunityListScreenState();
}

class _CommunityListScreenState extends ConsumerState<CommunityListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(communityListProvider.notifier).loadInitial());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityListProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索社群...',
                  border: InputBorder.none,
                ),
                onSubmitted: (v) {
                  if (v.isNotEmpty) {
                    ref.read(communityListProvider.notifier).search(v);
                  }
                },
              )
            : const Text('社群'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchCtrl.clear();
                  ref.read(communityListProvider.notifier).loadInitial();
                }
              });
            },
          ),
        ],
      ),
      body: _buildBody(state),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CommunityCreateScreen()),
        ),
        icon: const Icon(Icons.group_add),
        label: const Text('创建社群'),
      ),
    );
  }

  Widget _buildBody(CommunityListState state) {
    if (state.isLoading && state.discovered.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.discovered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: () =>
                    ref.read(communityListProvider.notifier).loadInitial(),
                child: const Text('重试')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(communityListProvider.notifier).loadInitial(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 我的社群
          if (state.myCommunities.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('我的社群',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.myCommunities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) =>
                    _buildMyCommunityCard(state.myCommunities[i]),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 推荐/搜索结果
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _isSearching ? '搜索结果' : '推荐社群',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (state.discovered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无社群')),
            )
          else
            ...state.discovered.map((c) => _CommunityListItem(c)),
        ],
      ),
    );
  }

  Widget _buildMyCommunityCard(Community c) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityDetailScreen(communityId: c.id),
        ),
      ),
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage:
                  c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
              child: c.avatarUrl == null
                  ? Text(c.name[0], style: const TextStyle(fontSize: 20))
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityListItem extends StatelessWidget {
  final Community community;
  const _CommunityListItem(this.community);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    CommunityDetailScreen(communityId: community.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: community.avatarUrl != null
                    ? NetworkImage(community.avatarUrl!)
                    : null,
                child: community.avatarUrl == null
                    ? Text(community.name[0],
                        style: const TextStyle(fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(community.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    if (community.description != null)
                      Text(community.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('${community.memberCount} 成员',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
