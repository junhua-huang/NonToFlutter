import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/topic.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/topic_service.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';

class MyTopicsScreen extends StatefulWidget {
  const MyTopicsScreen({super.key});

  @override
  State<MyTopicsScreen> createState() => _MyTopicsScreenState();
}

class _MyTopicsScreenState extends State<MyTopicsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TopicService _topicService = TopicService();

  List<Topic> _followedTopics = [];
  List<Topic> _referencedTopics = [];
  bool _isLoadingFollowed = true;
  bool _isLoadingReferenced = true;
  String? _followedError;
  String? _referencedError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadFollowed(), _loadReferenced()]);
  }

  Future<void> _loadFollowed() async {
    try {
      final resp = await _topicService.getFollowedTopics();
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['topics'] as List? ?? [])
            .map((e) => Topic.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _followedTopics = list;
          _isLoadingFollowed = false;
          _followedError = null;
        });
      } else {
        setState(() {
          _followedError = resp.message ?? '加载失败';
          _isLoadingFollowed = false;
        });
      }
    } catch (e) {
      setState(() {
        _followedError = '网络错误';
        _isLoadingFollowed = false;
      });
    }
  }

  Future<void> _loadReferenced() async {
    try {
      final resp = await _topicService.getReferencedTopics();
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['topics'] as List? ?? [])
            .map((e) => Topic.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _referencedTopics = list;
          _isLoadingReferenced = false;
          _referencedError = null;
        });
      } else {
        setState(() {
          _referencedError = resp.message ?? '加载失败';
          _isLoadingReferenced = false;
        });
      }
    } catch (e) {
      setState(() {
        _referencedError = '网络错误';
        _isLoadingReferenced = false;
      });
    }
  }

  void _navigateToTopicPosts(Topic topic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicSearchResultsScreen(topicName: topic.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '我的话题',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            tabs: const [
              Tab(text: '我关注的'),
              Tab(text: '我引用过的'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFollowedTab(),
          _buildReferencedTab(),
        ],
      ),
    );
  }

  Widget _buildFollowedTab() {
    if (_isLoadingFollowed) return const FriendSkeleton();
    if (_followedError != null) {
      return ErrorStateWidget(
        message: _followedError!,
        onRetry: () {
          setState(() => _isLoadingFollowed = true);
          _loadFollowed();
        },
      );
    }
    if (_followedTopics.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.tag,
        title: '还没有关注任何话题',
        subtitle: '去发现页面关注感兴趣的话题吧',
      );
    }
    return ListView.separated(
      itemCount: _followedTopics.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 72, color: AppColors.borderLight),
      itemBuilder: (_, i) => _buildTopicTile(_followedTopics[i]),
    );
  }

  Widget _buildReferencedTab() {
    if (_isLoadingReferenced) return const FriendSkeleton();
    if (_referencedError != null) {
      return ErrorStateWidget(
        message: _referencedError!,
        onRetry: () {
          setState(() => _isLoadingReferenced = true);
          _loadReferenced();
        },
      );
    }
    if (_referencedTopics.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.edit_note,
        title: '还没有引用过话题',
        subtitle: '发布帖子时使用 #话题 即可引用',
      );
    }
    return ListView.separated(
      itemCount: _referencedTopics.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 72, color: AppColors.borderLight),
      itemBuilder: (_, i) => _buildTopicTile(_referencedTopics[i]),
    );
  }

  Widget _buildTopicTile(Topic topic) {
    final colorHex = topic.color ?? '#3b82f6';
    final color = _parseColor(colorHex);

    return InkWell(
      onTap: () => _navigateToTopicPosts(topic),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Text(
                '#',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${topic.name}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _buildTopicSubtitle(topic),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _buildTopicSubtitle(Topic topic) {
    final parts = <String>[];
    if (topic.postCount > 0) {
      parts.add('${topic.postCount} 篇帖子');
    }
    if (topic.followerCount > 0) {
      parts.add('${topic.followerCount} 人关注');
    }
    if (parts.isEmpty) {
      return '暂无内容';
    }
    return parts.join(' · ');
  }

  Color _parseColor(String hex) {
    try {
      hex = hex.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return const Color(0xFF3B82F6);
    }
  }
}
