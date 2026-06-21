import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/community.dart';
import 'package:nonto/providers/community_notifier.dart';
import 'package:nonto/screens/community/community_create_screen.dart';
import 'package:nonto/screens/community/community_detail_screen.dart';

/// 社群列表/发现页
/// 包含：我的社群、精选发现、搜索与创建入口。
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
      () => ref.read(communityListProvider.notifier).loadInitial(),
    );
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
                  hintText: '搜索社群、话题或兴趣...',
                  border: InputBorder.none,
                ),
                onSubmitted: (value) {
                  final keyword = value.trim();
                  if (keyword.isNotEmpty) {
                    ref.read(communityListProvider.notifier).search(keyword);
                  }
                },
              )
            : const Text('Nonto 社群广场'),
        actions: [
          IconButton(
            tooltip: _isSearching ? '关闭搜索' : '搜索社群',
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
          IconButton(
            tooltip: '创建社群',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityCreateScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(CommunityListState state) {
    if (state.error != null && state.discovered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 42, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text('社群加载失败', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(communityListProvider.notifier).loadInitial(),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    final discoveredCount = state.discovered.length;
    final itemCount = discoveredCount == 0 ? 4 : discoveredCount + 3;

    return RefreshIndicator(
      onRefresh: () => ref.read(communityListProvider.notifier).loadInitial(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeroHeader();
          }
          if (index == 1) {
            return _buildMyCommunitiesSection(state.myCommunities);
          }
          if (index == 2) {
            return _buildDiscoveryHeader();
          }
          if (state.isLoading && discoveredCount == 0) {
            return _buildDiscoverySkeleton();
          }
          if (discoveredCount == 0) {
            return _buildEmptyDiscoveryState();
          }
          return _buildDiscoveryItem(state.discovered[index - 3]);
        },
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.96),
            AppColors.primary.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nonto 社群广场',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '找到同频的人，一起沉淀作品、想法和长期讨论。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.diversity_3, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMyCommunitiesSection(List<Community> communities) {
    if (communities.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: AppColors.textTertiary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.bookmark_add_outlined, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '加入社群后，它们会出现在这里，方便你快速回到常逛的地方。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '我的社群',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: communities.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, index) =>
                  _buildMyCommunityCard(communities[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isSearching ? '搜索结果' : '精选发现',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            _isSearching ? '按相关度排序' : '持续更新',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverySkeleton() {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.textTertiary.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 60,
                width: 60,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 140,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: 0.58,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.textTertiary.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDiscoveryState() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.textTertiary.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Icon(Icons.travel_explore, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          const Text(
            '还没有找到合适的社群',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _isSearching ? '换个关键词试试，或创建一个新的兴趣据点。' : '成为第一个把好想法聚起来的人。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildMyCommunityCard(Community community) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityDetailScreen(communityId: community.id),
        ),
      ),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            CircleAvatar(
              radius: 31,
              backgroundImage: community.avatarUrl != null
                  ? NetworkImage(community.avatarUrl!)
                  : null,
              child: community.avatarUrl == null
                  ? Text(community.name[0],
                      style: const TextStyle(fontSize: 20))
                  : null,
            ),
            const SizedBox(height: 7),
            Text(
              community.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryItem(Community community) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CommunityDetailScreen(communityId: community.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: community.avatarUrl != null
                    ? NetworkImage(community.avatarUrl!)
                    : null,
                child: community.avatarUrl == null
                    ? Text(community.name[0],
                        style: const TextStyle(fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (community.description != null &&
                        community.description!.trim().isNotEmpty)
                      Text(
                        community.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildMetaPill(
                            Icons.people_alt, '${community.memberCount} 成员'),
                        _buildMetaPill(Icons.article_outlined,
                            '${community.postCount} 动态'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
