import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/topic.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/services/api/search_service.dart';
import 'package:nonto/services/api/topic_service.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:flutter/material.dart';
/// 搜索建议下拉组件（实时搜索建议）
class SearchSuggestions extends StatefulWidget {
  final String query;
  final VoidCallback onClose;
  final void Function(String query)? onSearch;

  const SearchSuggestions({
    super.key,
    required this.query,
    required this.onClose,
    this.onSearch,
  });

  @override
  State<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends State<SearchSuggestions> {
  List<User> _users = [];
  List<Post> _posts = [];
  List<Topic> _topics = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void didUpdateWidget(covariant SearchSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    if (widget.query.trim().isEmpty) {
      setState(() {
        _users = [];
        _posts = [];
        _topics = [];
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SearchService().suggestUsers(widget.query, limit: 3),
        SearchService().globalSearch(widget.query),
        TopicService().getTopics(q: widget.query, perPage: 3),
      ]);

      // Users
      final userResp = results[0];
      if (userResp.success && userResp.data != null) {
        final data = userResp.data;
        List userList = [];
        if (data is List) { userList = data; }
        else if (data is Map) { userList = data['users'] ?? data['items'] ?? []; }
        _users = userList.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
      }

      // Posts
      final postResp = results[1];
      if (postResp.success && postResp.data != null) {
        final data = postResp.data as Map<String, dynamic>;
        final list = data['posts'] as List? ?? [];
        _posts = list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
      }

      // Topics
      final topicResp = results[2];
      if (topicResp.success && topicResp.data != null) {
        final data = topicResp.data;
        List topicList = [];
        if (data is List) { topicList = data; }
        else if (data is Map) { topicList = data['topics'] ?? data['items'] ?? []; }
        _topics = topicList.map((e) => Topic.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('SearchSuggestions error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.white,
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          : ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                // Search action
                InkWell(
                  onTap: () => widget.onSearch?.call(widget.query),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 20, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('搜索 "${widget.query}"',
                            style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),

                // Topics
                if (_topics.isNotEmpty) ...[
                  _buildSectionHeader('话题'),
                  ..._topics.map((t) => _buildTopicItem(t)),
                ],

                // Users
                if (_users.isNotEmpty) ...[
                  _buildSectionHeader('用户'),
                  ..._users.map((u) => _buildUserItem(u)),
                ],

                // Posts
                if (_posts.isNotEmpty) ...[
                  _buildSectionHeader('帖子'),
                  ..._posts.take(3).map((p) => _buildPostItem(p)),
                ],

                if (_topics.isEmpty && _users.isEmpty && _posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('暂无建议', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }

  Widget _buildUserItem(User user) {
    return InkWell(
      onTap: () {
        widget.onClose();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => UserProfileScreen(user: user),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ImageUtils.buildAvatar(user, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName ?? user.username,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                  Text('@${user.username}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicItem(Topic topic) {
    return InkWell(
      onTap: () {
        widget.onClose();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TopicSearchResultsScreen(topicName: topic.name),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.tag, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${topic.name}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                  if (topic.postCount > 0)
                    Text('${topic.postCount} 条帖子',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostItem(Post post) {
    return InkWell(
      onTap: () {
        widget.onClose();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => PostDetailScreen(postId: post.id),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ImageUtils.buildAvatar(post.user, radius: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.user?.displayName ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                  Text(post.content ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
