import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/comment.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/screens/search/search_results_screen.dart';
import 'package:facebook_clone/services/api/comment_service.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/report_service.dart';
import 'package:facebook_clone/services/api/search_service.dart';
import 'package:facebook_clone/services/post_interaction_notifier.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/media_viewer.dart';
import 'package:facebook_clone/widgets/mention_topic_picker.dart';
import 'package:facebook_clone/widgets/rich_text_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// Twitter/X 帖子详情 + 评论页
class PostDetailScreen extends StatefulWidget {
  final int postId;
  final Post? initialPost;

  const PostDetailScreen({super.key, required this.postId, this.initialPost});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  bool _hasFreshData = false; // tracks whether API data has arrived
  final List<Comment> _comments = [];
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final RefreshController _refreshController = RefreshController();
  bool _isLoading = true;
  bool _isCommentsLoading = true;
  bool _hasMore = true;
  int _page = 1;

  // Reply state
  int? _replyingToCommentId;
  String? _replyingToName;

  // Expanded reply tracking (comment id -> isExpanded)
  final Set<int> _expandedReplies = {};

  // Like debounce: prevent concurrent like/unlike for same comment
  final Set<int> _likingCommentIds = {};
  
  // Like debounce: prevent concurrent like/unlike for post
  bool _isLikingPost = false;

  // Colors now use AppColors for dark mode support
  Color get _xBlack => AppColors.textPrimary;
  Color get _xDarkGrey => AppColors.textSecondary;
  Color get _xBlue => AppColors.primary;
  Color get _xLightGrey => AppColors.borderLight;
  static const Color _xLikeRed = Color(0xFFF91880);

  // Report reasons
  static const List<String> _reportReasons = [
    '垃圾信息',
    '骚扰',
    '仇恨言论',
    '暴力内容',
    '其他'
  ];

  @override
  void initState() {
    super.initState();
    // Show initial post immediately if provided (from feed card)
    if (widget.initialPost != null) {
      _post = widget.initialPost;
      _isLoading = false;
    }
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final postResp = await PostService().getPost(widget.postId);
      if (postResp.success && postResp.data != null) {
        final data = postResp.data as Map<String, dynamic>;
        final postJson = data['post'] ?? data;
        setState(() {
          _post = Post.fromJson(postJson as Map<String, dynamic>);
          _hasFreshData = true;
        });
        // 记录浏览
        try {
          await PostService().recordView(widget.postId);
          if (mounted) {
            setState(() {
              _post = _post!.copyWith(viewCount: _post!.viewCount + 1);
            });
            // 通知列表页同步浏览量
            PostInteractionNotifier().notifyViewChanged(widget.postId, _post!.viewCount);
          }
        } catch (e) {
          debugPrint('Record view error: $e');
        }
      }
      await _loadComments();
    } catch (e) {
      debugPrint('PostDetail load error: $e');
    } finally {
      if (!_hasFreshData) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadComments() async {
    try {
      final resp = await CommentService().getComments(widget.postId, page: _page);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final List commentsJson = data['comments'] ?? data['items'] ?? [];
        final comments = commentsJson.map((e) => Comment.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          _comments.addAll(comments);
          _isCommentsLoading = false;
          _hasMore = data['has_more'] == true;
          _page++;
        });
      } else {
        setState(() => _isCommentsLoading = false);
      }
    } catch (e) {
      debugPrint('Load comments error: $e');
      setState(() => _isCommentsLoading = false);
    }
  }

  /// Load more replies for a specific comment
  Future<void> _loadMoreReplies(int commentId) async {
    try {
      // Find the comment and update it with loading state
      final parentIdx = _comments.indexWhere((c) => c.id == commentId);
      if (parentIdx == -1) return;

      // Call API to get replies for this comment
      final resp = await CommentService().getReplies(widget.postId, parentId: commentId);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final List repliesJson = data['replies'] ?? data['items'] ?? data['comments'] ?? [];
        final allReplies = repliesJson.map((e) => Comment.fromJson(e as Map<String, dynamic>)).toList();

        setState(() {
          final parent = _comments[parentIdx];
          _comments[parentIdx] = Comment(
            id: parent.id,
            content: parent.content,
            userId: parent.userId,
            postId: parent.postId,
            parentId: parent.parentId,
            replyToUserId: parent.replyToUserId,
            replyToUser: parent.replyToUser,
            createdAt: parent.createdAt,
            user: parent.user,
            likeCount: parent.likeCount,
            replyCount: parent.replyCount,
            updatedAt: parent.updatedAt,
            replies: allReplies,
          );
          _expandedReplies.add(commentId);
        });
      }
    } catch (e) {
      debugPrint('Load more replies error: $e');
    }
  }

  /// Optimistic comment submit
  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _post == null) return;

    final isReply = _replyingToCommentId != null;
    final parentId = _replyingToCommentId;

    // Get current user for optimistic UI
    final auth = context.read<AuthProvider>();
    final currentUser = auth.user;

    // Get the user being replied to (for reply comment)
    User? replyTargetUser;
    int? replyToUserId;
    if (isReply && parentId != null) {
      final parentIdx = _comments.indexWhere((c) => c.id == parentId);
      if (parentIdx != -1) {
        replyTargetUser = _comments[parentIdx].user;
        replyToUserId = _comments[parentIdx].userId;
      }
    }

    // Create optimistic comment
    final optimisticComment = Comment(
      id: DateTime.now().millisecondsSinceEpoch, // temp ID (unique)
      content: text,
      userId: currentUser?.id ?? 0,
      postId: _post!.id,
      parentId: parentId,
      replyToUserId: replyToUserId,
      replyToUser: replyTargetUser,
      createdAt: DateTime.now(),
      user: currentUser,
    );

    // Optimistic UI update
    setState(() {
      if (isReply && parentId != null) {
        // Insert reply into parent comment's replies list
        final parentIdx = _comments.indexWhere((c) => c.id == parentId);
        if (parentIdx != -1) {
          final parent = _comments[parentIdx];
          _comments[parentIdx] = Comment(
            id: parent.id,
            content: parent.content,
            userId: parent.userId,
            postId: parent.postId,
            parentId: parent.parentId,
            replyToUserId: parent.replyToUserId,
            replyToUser: parent.replyToUser,
            createdAt: parent.createdAt,
            user: parent.user,
            likeCount: parent.likeCount,
            replyCount: parent.replyCount + 1,
            updatedAt: parent.updatedAt,
            replies: [...parent.replies, optimisticComment],
          );
          // Auto-expand this reply section
          _expandedReplies.add(parentId);
        } else {
          // Parent not found, add as top-level
          _comments.insert(0, optimisticComment);
        }
      } else {
        // Top-level comment
        _comments.insert(0, optimisticComment);
      }
      _post = _post!.copyWith(commentCount: _post!.commentCount + 1);
      _commentController.clear();
      _replyingToCommentId = null;
      _replyingToName = null;
    });

    // Send to server
    try {
      final resp = await CommentService().createComment(
        widget.postId,
        text,
        parentId: parentId,
      );
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final serverComment = Comment.fromJson(data['comment'] ?? data);
        // Replace optimistic comment with server version
        _replaceOptimisticComment(optimisticComment.id, serverComment);
      } else {
        // Rollback on failure
        _rollbackOptimisticComment(optimisticComment.id, parentId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('评论发送失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      // Rollback on error
      _rollbackOptimisticComment(optimisticComment.id, parentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('评论发送失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _replaceOptimisticComment(int tempId, Comment serverComment) {
    setState(() {
      // Check if it's a reply
      for (int i = 0; i < _comments.length; i++) {
        final parent = _comments[i];
        final replyIdx = parent.replies.indexWhere((r) => r.id == tempId);
        if (replyIdx != -1) {
          // Replace in parent's replies
          final newReplies = List<Comment>.from(parent.replies);
          newReplies[replyIdx] = serverComment;
          _comments[i] = Comment(
            id: parent.id,
            content: parent.content,
            userId: parent.userId,
            postId: parent.postId,
            parentId: parent.parentId,
            replyToUserId: parent.replyToUserId,
            replyToUser: parent.replyToUser,
            createdAt: parent.createdAt,
            user: parent.user,
            likeCount: parent.likeCount,
            replyCount: parent.replyCount,
            updatedAt: parent.updatedAt,
            replies: newReplies,
          );
          return;
        }
      }
      // Top-level replacement
      final idx = _comments.indexWhere((c) => c.id == tempId);
      if (idx != -1) {
        _comments[idx] = serverComment;
      }
    });
  }

  void _rollbackOptimisticComment(int tempId, int? parentId) {
    setState(() {
      if (parentId != null) {
        // Remove from parent's replies
        final parentIdx = _comments.indexWhere((c) => c.id == parentId);
        if (parentIdx != -1) {
          final parent = _comments[parentIdx];
          _comments[parentIdx] = Comment(
            id: parent.id,
            content: parent.content,
            userId: parent.userId,
            postId: parent.postId,
            parentId: parent.parentId,
            replyToUserId: parent.replyToUserId,
            replyToUser: parent.replyToUser,
            createdAt: parent.createdAt,
            user: parent.user,
            likeCount: parent.likeCount,
            replyCount: parent.replyCount > 0 ? parent.replyCount - 1 : 0,
            updatedAt: parent.updatedAt,
            replies: parent.replies.where((r) => r.id != tempId).toList(),
          );
        }
      } else {
        // Remove top-level
        _comments.removeWhere((c) => c.id == tempId);
      }
      _post = _post!.copyWith(commentCount: _post!.commentCount > 0 ? _post!.commentCount - 1 : 0);
    });
  }

  /// Optimistic like toggle
  Future<void> _toggleLike() async {
    if (_post == null) return;
    if (_isLikingPost) return;
    
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再点赞'), duration: Duration(seconds: 2)),
      );
      return;
    }
    
    _isLikingPost = true;
    final wasLiked = _post!.isLiked ?? false;
    final oldPost = _post!;

    setState(() {
      _post = _post!.copyWith(
        isLiked: !wasLiked,
        likeCount: wasLiked ? _post!.likeCount - 1 : _post!.likeCount + 1,
      );
    });
    try {
      if (wasLiked) {
        await PostService().unlikePost(_post!.id);
      } else {
        await PostService().likePost(_post!.id);
      }
      // Notify other screens about the like change
      PostInteractionNotifier().notifyLikeChanged(_post!.id, !wasLiked, _post!.likeCount);
    } catch (e) {
      setState(() => _post = oldPost); // Rollback
    } finally {
      _isLikingPost = false;
    }
  }

  void _focusCommentField() {
    _commentFocusNode.requestFocus();
  }

  Future<void> _showPostStatsDetail(Post post) async {
    try {
      final resp = await PostService().getPostStats(post.id);
      if (!mounted) return;
      if (resp.success && resp.data != null) {
        final stats = resp.data as Map<String, dynamic>;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('帖子统计'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('浏览量: ${stats['views'] ?? 0}'),
                Text('点赞数: ${stats['likes'] ?? post.likeCount}'),
                Text('评论数: ${stats['comments'] ?? post.commentCount}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('获取统计失败'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取统计失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  /// Optimistic comment like toggle (supports nested replies)
  Future<void> _toggleCommentLike(Comment comment) async {
    // Guard: prevent concurrent requests for same comment
    if (_likingCommentIds.contains(comment.id)) return;
    
    // Guard: login check
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || auth.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再点赞'), duration: Duration(seconds: 2)),
      );
      return;
    }
    
    _likingCommentIds.add(comment.id);
    final wasLiked = comment.isLiked;
    final oldComment = comment;

    // Helper to find and update in nested structure
    bool updateComment(Comment target, bool liked, int count) {
      // Search top-level
      final topIdx = _comments.indexWhere((c) => c.id == target.id);
      if (topIdx != -1) {
        _comments[topIdx] = target.copyWith(isLiked: liked, likeCount: count);
        return true;
      }
      // Search in nested replies
      for (int i = 0; i < _comments.length; i++) {
        final parent = _comments[i];
        final replyIdx = parent.replies.indexWhere((r) => r.id == target.id);
        if (replyIdx != -1) {
          final newReplies = List<Comment>.from(parent.replies);
          newReplies[replyIdx] = target.copyWith(isLiked: liked, likeCount: count);
          _comments[i] = Comment(
            id: parent.id, content: parent.content, userId: parent.userId,
            postId: parent.postId, parentId: parent.parentId,
            replyToUserId: parent.replyToUserId, replyToUser: parent.replyToUser,
            createdAt: parent.createdAt, user: parent.user,
            likeCount: parent.likeCount, replyCount: parent.replyCount,
            updatedAt: parent.updatedAt, replies: newReplies,
          );
          return true;
        }
      }
      return false;
    }

    setState(() {
      updateComment(comment, !wasLiked,
          wasLiked ? comment.likeCount - 1 : comment.likeCount + 1);
    });

    try {
      if (wasLiked) {
        await CommentService().unlikeComment(comment.id);
      } else {
        await CommentService().likeComment(comment.id);
      }
    } catch (e) {
      setState(() {
        updateComment(oldComment, wasLiked, oldComment.likeCount);
      });
    } finally {
      _likingCommentIds.remove(comment.id);
    }
  }

  void _startReply(Comment comment) {
    setState(() {
      _replyingToCommentId = comment.id;
      _replyingToName = comment.user?.displayName ?? '未知用户';
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToName = null;
    });
  }

  void _toggleExpandReplies(int commentId) {
    setState(() {
      if (_expandedReplies.contains(commentId)) {
        _expandedReplies.remove(commentId);
        // 收起时清空回复数据，防止残留显示
        final idx = _comments.indexWhere((c) => c.id == commentId);
        if (idx != -1) {
          _comments[idx] = Comment(
            id: _comments[idx].id,
            content: _comments[idx].content,
            userId: _comments[idx].userId,
            postId: _comments[idx].postId,
            parentId: _comments[idx].parentId,
            replyToUserId: _comments[idx].replyToUserId,
            replyToUser: _comments[idx].replyToUser,
            createdAt: _comments[idx].createdAt,
            user: _comments[idx].user,
            likeCount: _comments[idx].likeCount,
            replyCount: _comments[idx].replyCount,
            updatedAt: _comments[idx].updatedAt,
            replies: [],
          );
        }
      } else {
        _expandedReplies.add(commentId);
        _loadMoreReplies(commentId);
      }
    });
  }

  void _navigateToTopic(String topicName) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TopicSearchResultsScreen(topicName: topicName),
    ));
  }

  void _navigateToProfile(String username) {
    // Search for user by username and navigate to their profile
    _searchAndNavigateToUser(username);
  }

  Future<void> _searchAndNavigateToUser(String username) async {
    try {
      final resp = await SearchService().searchUsers(username, page: 1);
      if (resp.success && resp.data != null) {
        final data = resp.data;
        List userList = [];
        if (data is List) { userList = data; }
        else if (data is Map) { userList = data['users'] ?? data['items'] ?? []; }
        if (userList.isNotEmpty) {
          final userJson = userList.firstWhere(
            (u) => (u['username'] ?? '').toString().toLowerCase() == username.toLowerCase(),
            orElse: () => userList.first,
          ) as Map<String, dynamic>;
          final user = User.fromJson(userJson);
          if (!mounted) return;
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => UserProfileScreen(user: user),
          ));
        }
      }
    } catch (e) {
      debugPrint('Search user error: $e');
    }
  }

  /// 删除帖子
  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定要删除这条帖子吗？此操作不可撤销'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        final resp = await PostService().deletePost(widget.postId);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('帖子已删除'), backgroundColor: Colors.green),
            );
            Navigator.of(context).pop();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '删除失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 举报帖子
  Future<void> _reportPost() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('举报帖子'),
        children: [
          ..._reportReasons.map((r) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Text(r),
          )),
        ],
      ),
    );
    if (reason != null && mounted) {
      try {
        final resp = await ReportService().reportPost(widget.postId, reason);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('举报已提交'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '举报失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('举报失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 删除评论
  Future<void> _deleteComment(Comment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('确定要删除这条评论吗？此操作不可撤销'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        final resp = await CommentService().deleteComment(comment.id);
        if (resp.success) {
          setState(() {
            _comments.removeWhere((c) => c.id == comment.id);
            _post = _post!.copyWith(commentCount: _post!.commentCount > 0 ? _post!.commentCount - 1 : 0);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('评论已删除'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '删除失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 举报评论
  Future<void> _reportComment(Comment comment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('举报评论'),
        children: [
          ..._reportReasons.map((r) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Text(r),
          )),
        ],
      ),
    );
    if (reason != null && mounted) {
      try {
        final resp = await ReportService().reportComment(comment.id, reason);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('举报已提交'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '举报失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('举报失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  int _buildCommentItemCount() {
    // post + divider + (header or empty) + comments + bottom spacer
    if (_comments.isEmpty) return 4; // post, divider, empty, spacer
    return 3 + _comments.length + 1; // post, divider, header, comments, spacer
  }

  Widget _buildCommentListByIndex(BuildContext context, int index) {
    if (index == 0) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: ValueKey('post_${_hasFreshData ? 'fresh' : 'cached'}'),
          child: _buildPostCard(),
        ),
      );
    }
    if (index == 1) return Divider(height: 1, color: _xLightGrey);

    if (_comments.isEmpty) {
      if (index == 2) {
        if (_isCommentsLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('还没有评论，来说两句吧', style: TextStyle(color: _xDarkGrey, fontSize: 14)),
              ],
            ),
          ),
        );
      }
      // index == 3
      return const SizedBox(height: 16);
    }

    if (index == 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Text('评论',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _xBlack)),
            if (_post!.commentCount > 0) ...[
              const SizedBox(width: 8),
              Text('${_post!.commentCount}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _xDarkGrey)),
            ],
          ],
        ),
      );
    }

    final commentIndex = index - 3;
    if (commentIndex < _comments.length) {
      final c = _comments[commentIndex];
      final auth = context.read<AuthProvider>();
      final isCommentOwner = c.userId == auth.user?.id;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _CommentWidget(
          comment: c,
          onReply: () => _startReply(c),
          onToggleExpand: () => _toggleExpandReplies(c.id),
          onLoadMoreReplies: () => _loadMoreReplies(c.id),
          isExpanded: _expandedReplies.contains(c.id),
          isOwner: isCommentOwner,
          onTopicTap: _navigateToTopic,
          onMentionTap: _navigateToProfile,
          onDelete: isCommentOwner ? () => _deleteComment(c) : null,
          onReport: () => _reportComment(c),
          onLike: (cmt) => _toggleCommentLike(cmt),
        ),
      );
    }

    // Last item: bottom spacer
    return const SizedBox(height: 16);
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
          icon: Icon(Icons.arrow_back, color: _xBlack),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('帖子', style: TextStyle(color: _xBlack, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _xBlue))
          : _post == null
              ? Center(child: Text('帖子不存在', style: TextStyle(color: _xDarkGrey)))
              : Column(
                  children: [
                    Expanded(
                      child: SmartRefresher(
                        controller: _refreshController,
                        enablePullDown: true,
                        enablePullUp: _hasMore,
                        onRefresh: () async {
                          setState(() { _comments.clear(); _page = 1; _hasMore = true; _isCommentsLoading = true; _expandedReplies.clear(); });
                          await _loadComments();
                          _refreshController.refreshCompleted();
                        },
                        onLoading: _loadComments,
                        child: ListView.builder(
                          primary: false,
                          itemCount: _buildCommentItemCount(),
                          itemBuilder: _buildCommentListByIndex,
                        ),
                      ),
                    ),
                    _buildCommentInput(),
                  ],
                ),
    );
  }

  Widget _buildPostCard() {
    final post = _post!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Author
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (post.user != null) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => UserProfileScreen(user: post.user!),
                    ));
                  }
                },
                child: ImageUtils.buildAvatar(post.user, radius: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (post.user != null) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: post.user!),
                          ));
                        }
                      },
                      child: Text(post.user?.displayName ?? '未知用户',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _xBlack)),
                    ),
                    SizedBox(height: 2),
                    GestureDetector(
                      onTap: () {
                        if (post.user != null) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => UserProfileScreen(user: post.user!),
                          ));
                        }
                      },
                      child: Text('@${post.user?.username ?? ''}  ·  ${AppDateUtils.formatTimeAgo(post.createdAt)}',
                        style: TextStyle(color: _xDarkGrey, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (ctx) {
                  final auth = context.read<AuthProvider>();
                  final isOwner = post.userId == auth.user?.id;
                  return PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, size: 18, color: _xDarkGrey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deletePost();
                      } else if (value == 'report') {
                        _reportPost();
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (isOwner)
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      const PopupMenuItem(value: 'report', child: Text('举报')),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        // Content - RichText with #topic and @mention highlighting
        if (post.content != null && post.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: RichTextContent(
              text: post.content!,
              style: TextStyle(fontSize: 15, height: 1.45, color: _xBlack),
              onTopicTap: _navigateToTopic,
              onMentionTap: _navigateToProfile,
            ),
          ),
        // Image (tap to zoom) - single or gallery
        if (post.hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
            child: () {
              final allImages = <String>[];
              if (post.images != null) {
                for (final u in post.images!) {
                  if (u.isNotEmpty) allImages.add(u);
                }
              }
              if (allImages.isEmpty) return const SizedBox.shrink();
              if (allImages.length == 1) {
                return GestureDetector(
                  onTap: () => ImageViewerScreen.show(context, allImages, heroTag: 'detail_img_${post.id}_0'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Hero(
                      tag: 'detail_img_${post.id}_0',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ImageUtils.buildPostImage(allImages[0], width: double.infinity),
                      ),
                    ),
                  ),
                );
              }
              return ImageGalleryGrid(imageUrls: allImages, maxHeight: 300, post: post);
            }(),
          ),
        // Video
        if (post.hasVideo)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 16, right: 16),
            child: VideoPlayerPlaceholder(
              videoUrl: post.videoUrl,
              thumbnailUrl: (post.images != null && post.images!.isNotEmpty) ? post.images![0] : null,
              height: 200,
              width: double.infinity,
            ),
          ),
        // Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 16, 12),
          child: Row(
            children: [
              _Action(icon: Icons.comment_outlined, count: post.commentCount, onTap: _focusCommentField),
              const SizedBox(width: 8),
              _Action(
                icon: post.isLiked == true ? Icons.favorite : Icons.favorite_border,
                count: post.likeCount,
                color: post.isLiked == true ? _xLikeRed : null,
                onTap: _toggleLike,
              ),
              const SizedBox(width: 8),
              _Action(icon: Icons.bar_chart, count: post.viewCount, onTap: () => _showPostStatsDetail(post)),
            ],
          ),
        ),
      ],
    );
  }

  void _insertMention(String username) {
    final text = _commentController.text;
    final cursorPos = _commentController.selection.start;
    final before = cursorPos >= 0 ? text.substring(0, cursorPos) : text;
    final after = cursorPos >= 0 ? text.substring(cursorPos) : '';
    _commentController.text = '$before@$username $after';
    _commentController.selection = TextSelection.collapsed(
      offset: before.length + username.length + 2,
    );
    _commentFocusNode.requestFocus();
  }

  void _insertTopic(String topicName) {
    final text = _commentController.text;
    final cursorPos = _commentController.selection.start;
    final before = cursorPos >= 0 ? text.substring(0, cursorPos) : text;
    final after = cursorPos >= 0 ? text.substring(cursorPos) : '';
    _commentController.text = '$before#$topicName $after';
    _commentController.selection = TextSelection.collapsed(
      offset: before.length + topicName.length + 2,
    );
    _commentFocusNode.requestFocus();
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(left: 16, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _xLightGrey)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Replying indicator
          if (_replyingToName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _xLightGrey,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Text('回复 $_replyingToName',
                    style: TextStyle(color: _xDarkGrey, fontSize: 13)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Icon(Icons.close, size: 16, color: _xDarkGrey),
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitComment(),
                        style: TextStyle(fontSize: 15, color: _xBlack),
                        decoration: InputDecoration(
                          hintText: _replyingToName != null ? '发布回复...' : '发条评论...',
                          hintStyle: TextStyle(color: _xDarkGrey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                      // Toolbar: @ and #
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: Row(
                          children: [
                            _ToolbarButton(
                              icon: Icons.alternate_email,
                              label: '@',
                              onTap: () {
                                MentionTopicPicker.showMentions(context, onSelected: _insertMention);
                              },
                            ),
                            const SizedBox(width: 4),
                            _ToolbarButton(
                              icon: Icons.tag,
                              label: '#',
                              onTap: () {
                                MentionTopicPicker.showTopics(context, onSelected: _insertTopic);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.send, color: _xBlue, size: 24),
                onPressed: _submitComment,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const _Action({required this.icon, this.count = 0, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}K' : '$count',
                style: TextStyle(color: color ?? AppColors.textSecondary, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Single comment widget with proper indentation and expand/collapse replies
class _CommentWidget extends StatelessWidget {
  final Comment comment;
  final VoidCallback onReply;
  final VoidCallback onToggleExpand;
  final VoidCallback onLoadMoreReplies;
  final bool isExpanded;
  final bool isOwner;
  final void Function(String)? onTopicTap;
  final void Function(String)? onMentionTap;
  final bool isReply;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final ValueChanged<Comment>? onLike;

  const _CommentWidget({
    required this.comment,
    required this.onReply,
    required this.onToggleExpand,
    required this.onLoadMoreReplies,
    this.isExpanded = false,
    this.isOwner = false,
    this.onTopicTap,
    this.onMentionTap,
    this.isReply = false,
    this.onDelete,
    this.onReport,
    this.onLike,
  });

  void _navigateToUser(BuildContext context, User? user) {
    if (user == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => UserProfileScreen(user: user),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final totalReplyCount = comment.replyCount;
    // For top-level comments, show all replies when expanded, or first 2 when collapsed
    // For reply comments, they don't have their own reply list
    final visibleReplies = isReply ? <Comment>[]
        : (isExpanded ? comment.replies : <Comment>[]);
    final hasMoreReplies = !isReply && (totalReplyCount > 2 || totalReplyCount > comment.replies.length);

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 0 : 8, top: 6, bottom: 6),
      child: GestureDetector(
        onTap: onReply,
        onLongPress: () {
          if (isOwner || onReport != null) {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOwner && onDelete != null)
                      ListTile(
                        leading: const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('删除评论', style: TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(ctx);
                          onDelete!();
                        },
                      ),
                    if (onReport != null)
                      ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: const Text('举报评论'),
                        onTap: () {
                          Navigator.pop(ctx);
                          onReport!();
                        },
                      ),
                  ],
                ),
              ),
            );
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            GestureDetector(
              onTap: () => _navigateToUser(context, comment.user),
              child: SizedBox(
                width: isReply ? 28 : 32,
                child: ImageUtils.buildAvatar(comment.user, radius: isReply ? 12 : 14),
              ),
            ),
            const SizedBox(width: 10),
            // Content area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () => _navigateToUser(context, comment.user),
                          child: Text(comment.user?.displayName ?? '未知用户',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(AppDateUtils.formatTimeAgo(comment.createdAt),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const Spacer(),
                      // Like button on right side
                      GestureDetector(
                        onTap: onLike != null ? () => onLike!(comment) : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              comment.isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: comment.isLiked ? const Color(0xFFF91880) : AppColors.textSecondary,
                            ),
                            if (comment.likeCount > 0) ...[
                              const SizedBox(width: 2),
                              Text('${comment.likeCount}',
                                style: TextStyle(
                                  color: comment.isLiked ? const Color(0xFFF91880) : AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  // "Replying to @xxx" indicator
                  if (comment.replyToUser != null) ...[
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => _navigateToUser(context, comment.replyToUser),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          children: [
                            const TextSpan(text: '回复 '),
                            TextSpan(
                              text: '@${comment.replyToUser!.username}',
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  // Content
                  RichTextContent(
                    text: comment.content,
                    style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.textPrimary),
                    onTopicTap: onTopicTap,
                    onMentionTap: onMentionTap,
                  ),
                  // Actions row
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      GestureDetector(
                        onTap: onReply,
                        child: Text('回复', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      // Only show reply count for top-level comments
                      if (!isReply && totalReplyCount > 0)
                        GestureDetector(
                          onTap: onToggleExpand,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.comment_outlined, size: 13, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text('$totalReplyCount', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // "View more replies" button for top-level comments
                  if (hasMoreReplies && !isExpanded) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onLoadMoreReplies,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.borderLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '查看更多回复 ($totalReplyCount)',
                          style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],

                  // Inline replies (tree structure)
                  if (visibleReplies.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...visibleReplies.map((r) {
                      final isReplyOwner = r.userId == (context.read<AuthProvider>().user?.id);
                      return Container(
                        decoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: AppColors.borderLight, width: 2)),
                        ),
                        padding: const EdgeInsets.only(left: 12),
                        child: _CommentWidget(
                          comment: r,
                          onReply: onReply,
                          onToggleExpand: onToggleExpand,
                          onLoadMoreReplies: () {},
                          isExpanded: isExpanded,
                          isOwner: isReplyOwner,
                          onTopicTap: onTopicTap,
                          onMentionTap: onMentionTap,
                          isReply: true,
                          onDelete: isReplyOwner ? onDelete : null,
                          onReport: onReport,
                          onLike: onLike,
                        ),
                      );
                    }),
                  ],

                  // Collapse button
                  if (!isReply && isExpanded && comment.replies.length > 2) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onToggleExpand,
                      child: Text(
                        '收起回复',
                        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
