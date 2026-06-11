import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/screens/chat/chat_room_screen.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/services/api/block_service.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/api/friend_service.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/report_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/media_viewer.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import 'package:facebook_clone/widgets/twitter_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// 查看其他用户的个人资料页（Facebook 风格）
class UserProfileScreen extends ConsumerStatefulWidget {
  final User user;
  const UserProfileScreen({super.key, required this.user});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

/// 好友关系状态
enum _FriendStatus {
  none,
  pending,
  received,
  friends,
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen>
    with TickerProviderStateMixin {
  User? _user;
  int _friendCount = 0;
  final List<Post> _userPosts = [];
  final List<Post> _likedPosts = [];
  bool _isLoadingPosts = false;
  bool _isLoadingLikes = false;
  bool _isLoadingStats = true;
  bool _isActionLoading = false;

  // Friend status management
  _FriendStatus _friendStatus = _FriendStatus.none;
  int? _pendingRequestId; // For canceling/accepting/rejecting
  bool _statusLoaded = false;

  final RefreshController _refreshController = RefreshController();

  String? _error;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1 && _likedPosts.isEmpty && !_isLoadingLikes) {
        _loadLikedPosts();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadStats(),
      _checkFriendStatus(),
      _loadUserPosts(),
    ]);
  }

  Future<void> _loadStats() async {
    try {
      final countResp = await FriendService().getFriendCount(_user!.id);
      if (countResp.success && countResp.data != null) {
        final data = countResp.data as Map<String, dynamic>;
        _friendCount = data['friend_count'] as int? ?? 0;
      }
    } catch (e) {
      debugPrint('UserProfile loadStats error: $e');
      if (mounted) setState(() => _error = '加载失败，请下拉重试');
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  /// Check friendship status with this user
  Future<void> _checkFriendStatus() async {
    final currentUserId = ref.read(authProvider).user?.id;
    try {
      final resp = await FriendService().checkStatus(_user!.id);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'none';
        final friendship = data['friendship'] as Map<String, dynamic>?;

        setState(() {
          if (status == 'accepted') {
            _friendStatus = _FriendStatus.friends;
          } else if (status == 'pending') {
            if (friendship != null && currentUserId != null) {
              final senderId = friendship['sender_id'] as int?;
              if (senderId == currentUserId) {
                _friendStatus = _FriendStatus.pending;
              } else {
                _friendStatus = _FriendStatus.received;
              }
            } else {
              _friendStatus = _FriendStatus.pending;
            }
            _pendingRequestId = friendship?['id'] as int?;
          } else {
            _friendStatus = _FriendStatus.none;
          }
          _statusLoaded = true;
        });
      } else {
        setState(() => _statusLoaded = true);
      }
    } catch (e) {
      debugPrint('Check friend status error: $e');
      setState(() => _statusLoaded = true);
    }
  }

  Future<void> _loadUserPosts() async {
    setState(() => _isLoadingPosts = true);
    try {
      final resp = await PostService().getUserPosts(_user!.id);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final list = data['posts'] as List? ?? [];
        setState(() {
          _userPosts.clear();
          _userPosts.addAll(
            list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList(),
          );
        });
      }
    } catch (e) {
      debugPrint('Load user posts error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _loadLikedPosts() async {
    if (_isLoadingLikes) return;
    setState(() => _isLoadingLikes = true);
    try {
      final resp = await PostService().getUserLikedPosts(_user!.id);
      if (mounted && resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final list = data['posts'] as List? ?? [];
        setState(() {
          _likedPosts.clear();
          _likedPosts.addAll(
            list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList(),
          );
        });
      }
    } catch (e) {
      debugPrint('Load liked posts error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLikes = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadData();
    _refreshController.refreshCompleted();
  }

  // ========== Friend Actions ==========

  Future<void> _sendFriendRequest() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);
    try {
      final resp = await FriendService().sendRequest(_user!.id);
      if (resp.success) {
        final friendship = (resp.data as Map<String, dynamic>?)?['friendship'] as Map<String, dynamic>?;
        setState(() {
          _friendStatus = _FriendStatus.pending;
          _pendingRequestId = friendship?['id'] as int?;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('好友请求已发送'), duration: Duration(seconds: 2)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '发送失败'), duration: const Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _cancelRequest() async {
    if (_isActionLoading || _pendingRequestId == null) return;
    setState(() => _isActionLoading = true);
    try {
      await FriendService().cancelRequest(_pendingRequestId!);
      setState(() {
        _friendStatus = _FriendStatus.none;
        _pendingRequestId = null;
      });
    } catch (e) {
      debugPrint('Cancel request error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('撤销请求失败，请重试'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _acceptRequest() async {
    if (_isActionLoading || _pendingRequestId == null) return;
    setState(() => _isActionLoading = true);
    try {
      final resp = await FriendService().acceptRequest(_pendingRequestId!);
      if (resp.success) {
        setState(() {
          _friendStatus = _FriendStatus.friends;
          _pendingRequestId = null;
          _friendCount++;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('你们已成为好友！'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      debugPrint('Accept request error: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _rejectRequest() async {
    if (_isActionLoading || _pendingRequestId == null) return;
    setState(() => _isActionLoading = true);
    try {
      await FriendService().rejectRequest(_pendingRequestId!);
      setState(() {
        _friendStatus = _FriendStatus.none;
        _pendingRequestId = null;
      });
    } catch (e) {
      debugPrint('Reject request error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _unfriend() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('取消好友关系',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('确定要取消与 ${_user!.displayName} 的好友关系吗？',
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isActionLoading = true);
      try {
        await FriendService().deleteFriend(_user!.id);
        setState(() {
          _friendStatus = _FriendStatus.none;
          _pendingRequestId = null;
          if (_friendCount > 0) _friendCount--;
        });
      } catch (e) {
        debugPrint('Unfriend error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('操作失败，请重试'), duration: Duration(seconds: 2)),
          );
        }
      } finally {
        if (mounted) setState(() => _isActionLoading = false);
      }
    }
  }

  // ========== Report & Block Actions ==========

  static const List<String> reportReasons = [
    '垃圾信息',
    '骚扰',
    '仇恨言论',
    '暴力内容',
    '其他'
  ];

  /// 统一更多选项菜单
  Future<void> _showMoreOptions({bool includeUnfriend = false}) async {
    final options = <TwitterSheetOption<String>>[
      const TwitterSheetOption(icon: Icons.flag_outlined, label: '举报用户', value: 'report'),
      const TwitterSheetOption(icon: Icons.block_outlined, label: '屏蔽用户', value: 'block'),
      if (includeUnfriend)
        const TwitterSheetOption(icon: Icons.person_remove_outlined, label: '取消关注', value: 'unfriend'),
    ];
    final action = await TwitterBottomSheet.show<String>(context, options: options);
    switch (action) {
      case 'report': _reportUser(); break;
      case 'block': _blockUser(); break;
      case 'unfriend': _unfriend(); break;
    }
  }

  Future<void> _reportUser() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('举报用户',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        children: [
          for (final r in reportReasons)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Text(r, style: const TextStyle(fontSize: 15)),
            ),
        ],
      ),
    );
    if (reason != null && mounted) {
      try {
        final resp = await ReportService().reportUser(_user!.id, reason);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('举报已提交，我们会尽快处理'), backgroundColor: Colors.green),
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
            const SnackBar(content: Text('操作失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('屏蔽用户',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('确定要屏蔽 ${_user!.displayName} 吗？屏蔽后你将无法看到对方的内容。',
            style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('屏蔽'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        final resp = await BlockService().blockUser(_user!.id);
        if (resp.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已屏蔽该用户'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message ?? '操作失败'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('操作失败，请重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _startChat() async {
    try {
      final resp = await ChatService().getOrCreateConversation(_user!.id);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final convJson = data['conversation'] ?? data;
        final conversation = Conversation.fromJson(convJson as Map<String, dynamic>);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatRoomScreen(conversation: conversation),
        ));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '无法创建聊天'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建聊天失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ========== Build ==========

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(user.displayName ?? user.username,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () async {
              final action = await TwitterBottomSheet.show<String>(
                context,
                options: const [
                  TwitterSheetOption(icon: Icons.flag_outlined, label: '举报用户', value: 'report'),
                  TwitterSheetOption(icon: Icons.block_outlined, label: '屏蔽', value: 'block'),
                ],
              );
              if (action == 'report') {
                _reportUser();
              } else if (action == 'block') {
                _blockUser();
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
      ),
      body: SmartRefresher(
        controller: _refreshController,
        enablePullDown: true,
        onRefresh: _onRefresh,
        header: const WaterDropHeader(complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)), waterDropColor: AppColors.primary),
        child: CustomScrollView(slivers: [
          // ===== Cover + Avatar Section =====
          SliverToBoxAdapter(child: _buildCoverSection(user)),

          // Spacer for avatar overlap
          const SliverToBoxAdapter(child: SizedBox(height: 56)),

          // ===== Info + Action Row =====
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(user.displayName ?? user.username,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.2)),
                  const SizedBox(height: 4),
                  // Username
                  Text('@${user.username}',
                    style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  // Bio
                  if (user.bio != null && user.bio!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(user.bio!,
                        style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary)),
                    ),
                  // Join date + stats row
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(user.createdAt != null
                        ? '${AppDateUtils.formatTimeAgo(user.createdAt)} 加入'
                        : '已加入',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(width: 16),
                      if (_isLoadingStats)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      else if (_error != null)
                        ErrorStateWidget(
                          message: _error!,
                          onRetry: () {
                            setState(() { _error = null; _isLoadingStats = true; });
                            _loadData();
                          },
                        )
                      else
                        Text('$_friendCount 位好友',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    ],
                  ),

                  // Action buttons row
                  const SizedBox(height: 12),
                  _buildActionButtons(),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // ===== Tabs =====
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabDelegate(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                  tabs: const [Tab(text: '帖子'), Tab(text: '喜欢')],
                ),
              ),
            ),
          ),
          // Tab content
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.of(context).size.height - 200,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPostsList(_userPosts, _isLoadingPosts, '暂无帖子'),
                  _buildPostsList(_likedPosts, _isLoadingLikes, '暂无喜欢的帖子'),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCoverSection(User user) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () {
            final url = user.coverPhotoUrl;
            if (url != null && url.isNotEmpty) {
              final fullUrl = url.startsWith('http') ? url : '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ImageViewerScreen(imageUrls: [fullUrl], initialIndex: 0),
              ));
            }
          },
          child: _buildCoverPhoto(user),
        ),
        Positioned(
          left: 16,
          bottom: -40,
          child: GestureDetector(
            onTap: () {
              final avatarUrl = user.avatarUrl;
              if (avatarUrl != null && avatarUrl.isNotEmpty) {
                final fullUrl = avatarUrl.startsWith('http') ? avatarUrl : '${AppConfig.baseUrl.replaceFirst('/api', '')}$avatarUrl';
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(imageUrls: [fullUrl], initialIndex: 0),
                ));
              }
            },
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 4),
                    borderRadius: BorderRadius.circular(44),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: ImageUtils.buildAvatar(user, radius: 44),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (user.isOnline == true) ? Colors.green : Colors.grey,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverPhoto(User user) {
    final url = user.coverPhotoUrl;
    if (url != null && url.isNotEmpty) {
      final fullUrl = url.startsWith('http') ? url : '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
      return ImageUtils.buildPostImage(fullUrl, width: double.infinity, height: 180);
    }
    return Container(
      height: 180,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (!_statusLoaded || _isActionLoading) {
      return Row(children: [
        Expanded(child: Container(
          height: 36,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
        )),
      ]);
    }

    switch (_friendStatus) {
      case _FriendStatus.friends:
        return Row(children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _startChat,
                icon: const Icon(Icons.chat_bubble_rounded, size: 18, color: AppColors.primary),
                label: const Text('发消息', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFC4CDD4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: _unfriend,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFC4CDD4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: EdgeInsets.zero,
                ),
                child: const Text('已互为好友', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            onPressed: () => _showMoreOptions(includeUnfriend: true),
          ),
        ]);

      case _FriendStatus.pending:
        // Request sent by us
        return Row(children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: _isActionLoading ? null : _cancelRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: Color(0xFFC4CDD4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('撤销请求', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  const Text('等待回应', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            onPressed: () => _showMoreOptions(),
          ),
        ]);

      case _FriendStatus.received:
        // Received request from them
        return Row(children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: _isActionLoading ? null : _acceptRequest,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('接受', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width:8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: _isActionLoading ? null : _rejectRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFC4CDD4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('拒绝', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            onPressed: () => _showMoreOptions(),
          ),
        ]);

      case _FriendStatus.none:
        return Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: _isActionLoading ? null : _sendFriendRequest,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: _isActionLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('添加好友', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            onPressed: () => _showMoreOptions(),
          ),
        ]);
    }
  }

  Widget _buildPostsList(List<Post> posts, bool isLoading, String emptyText) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (posts.isEmpty) {
      return Center(child: Text(emptyText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: posts.length,
      itemBuilder: (_, i) {
        final post = posts[i];
        return PostCard(
          post: post,
          onLike: () => _togglePostLike(post, i, posts),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: post.id),
          )),
        );
      },
    );
  }

  Future<void> _togglePostLike(Post post, int index, List<Post> postList) async {
    final currentIsLiked = post.isLiked ?? false;
    final currentCount = post.likeCount;
    setState(() {
      postList[index] = post.copyWith(
        isLiked: !currentIsLiked,
        likeCount: currentIsLiked ? currentCount - 1 : currentCount + 1,
      );
    });
    try {
      if (currentIsLiked) {
        await PostService().unlikePost(post.id);
      } else {
        await PostService().likePost(post.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        postList[index] = post.copyWith(
          isLiked: currentIsLiked,
          likeCount: currentCount,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败'), duration: Duration(seconds: 2)),
      );
    }
  }
}

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _TabDelegate({required this.child});

  @override double get minExtent => 48;
  @override double get maxExtent => 48;

  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override bool shouldRebuild(covariant _TabDelegate oldDelegate) => child != oldDelegate.child;
}
