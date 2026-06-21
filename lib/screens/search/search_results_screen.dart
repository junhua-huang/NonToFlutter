import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/search_service.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// 话题搜索结果页（点击 #话题 后进入，自动搜索该话题相关帖子）
class TopicSearchResultsScreen extends StatefulWidget {
  final String topicName;
  const TopicSearchResultsScreen({super.key, required this.topicName});

  @override
  State<TopicSearchResultsScreen> createState() =>
      _TopicSearchResultsScreenState();
}

class _TopicSearchResultsScreenState extends State<TopicSearchResultsScreen> {
  List<Post> _posts = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  final RefreshController _refreshController = RefreshController();

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts({bool isRefresh = false}) async {
    try {
      if (isRefresh) {
        _page = 1;
        _hasMore = true;
      }
      final resp =
          await SearchService().globalSearch(widget.topicName, page: _page);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['posts'] as List? ?? [])
            .map((e) => Post.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          if (isRefresh) {
            _posts = list;
          } else {
            _posts.addAll(list);
          }
          _isLoading = false;
          _error = null;
          _page++;
          if (list.length < 20) _hasMore = false;
          if (!data.containsKey('has_more') && list.isEmpty) _hasMore = false;
        });
        if (isRefresh) {
          _refreshController.refreshCompleted();
        } else {
          _refreshController.loadComplete();
        }
      } else {
        setState(() {
          _error = resp.message ?? '搜索失败';
          _isLoading = false;
        });
        if (isRefresh) {
          _refreshController.refreshFailed();
        } else {
          _refreshController.loadFailed();
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      if (isRefresh) {
        _refreshController.refreshFailed();
      } else {
        _refreshController.loadFailed();
      }
    }
  }

  Future<void> _togglePostLike(Post post) async {
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index == -1) return;

    final wasLiked = post.isLiked == true;
    final originalCount = post.likeCount;
    final nextCount = wasLiked ? originalCount - 1 : originalCount + 1;

    setState(() {
      _posts[index] = post.copyWith(isLiked: !wasLiked, likeCount: nextCount);
    });

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
      setState(() {
        _posts[index] =
            post.copyWith(isLiked: wasLiked, likeCount: originalCount);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('#${widget.topicName}',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: _isLoading && _posts.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null && _posts.isEmpty
              ? ErrorStateWidget(
                  message: _error!,
                  onRetry: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _loadPosts(isRefresh: true);
                  },
                )
              : _posts.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.tag_outlined,
                      title: '该话题下暂无帖子',
                      subtitle: '换个话题搜索试试',
                    )
                  : SmartRefresher(
                      controller: _refreshController,
                      enablePullDown: true,
                      enablePullUp: _hasMore,
                      onRefresh: () => _loadPosts(isRefresh: true),
                      onLoading: () => _loadPosts(),
                      header: const ClassicHeader(
                        refreshingText: '刷新中...',
                        completeText: '刷新成功',
                        failedText: '刷新失败',
                        idleText: '',
                        refreshingIcon: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2)),
                        completeIcon: Icon(Icons.check_circle,
                            color: AppColors.primary, size: 16),
                        failedIcon: Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        height: 44,
                      ),
                      footer: const ClassicFooter(
                        loadingText: '加载更多...',
                        noDataText: '没有更多了',
                        failedText: '加载失败，点击重试',
                      ),
                      child: ListView.builder(
                        itemCount: _posts.length,
                        itemBuilder: (_, i) => PostCard(
                          post: _posts[i],
                          feedPosts: _posts,
                          onLike: () => _togglePostLike(_posts[i]),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PostDetailScreen(
                                postId: _posts[i].id,
                                initialPost: _posts[i],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
    );
  }
}
