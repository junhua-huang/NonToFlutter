import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/screens/friends/friends_screen.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/screens/profile/edit_profile_screen.dart';
import 'package:facebook_clone/services/api/friend_service.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/upload_service.dart';
import 'package:facebook_clone/services/post_interaction_notifier.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/media_viewer.dart';
import 'package:facebook_clone/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// Twitter/X 风格个人资料页（头像半覆盖背景、可编辑、照片墙Tab）
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with SingleTickerProviderStateMixin {
  int _friendCount = 0;
  int _likeCount = 0;
  bool _isLoadingStats = true;
  final List<Post> _userPosts = [];
  bool _isLoadingPosts = false;
  String? _error;
  final RefreshController _postsRefreshController = RefreshController(initialRefresh: false);
  final RefreshController _likesRefreshController = RefreshController(initialRefresh: false);
  final RefreshController _photosRefreshController = RefreshController(initialRefresh: false);
  bool _activated = false;

  late final TabController _tabController;
  final ImagePicker _picker = ImagePicker();

  // 上传状态（防止重复触发 + 显示 loading）
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;

  // 本地预览路径（上传完成前立即更新 UI）
  String? _localAvatarPreview;
  String? _localCoverPreview;
  Uint8List? _localAvatarBytes;
  Uint8List? _localCoverBytes;

  StreamSubscription<bool>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    TabActivationNotifier.currentTab.addListener(_onTabActivated);
    PostInteractionNotifier().onLikeChanged.listen(_onPostLikeEvent);
    PostInteractionNotifier().onViewChanged.listen(_onPostViewEvent);
    // 监听 WebSocket 连接状态变化，实时更新在线指示器
    _connectionSub = WebSocketService().connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
    if (TabActivationNotifier.currentTab.value == 3) {
      _activate();
    }
  }

  @override
  void dispose() {
    TabActivationNotifier.currentTab.removeListener(_onTabActivated);
    _tabController.dispose();
    _postsRefreshController.dispose();
    _likesRefreshController.dispose();
    _photosRefreshController.dispose();
    _connectionSub?.cancel();
    super.dispose();
  }

  void _onTabActivated() {
    if (!_activated && TabActivationNotifier.currentTab.value == 3) {
      _activate();
    }
  }

  void _activate() {
    _activated = true;
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final auth = context.read<AuthProvider>();
      if (auth.user == null) return;

      final results = await Future.wait([
        FriendService().getFriends(),
        PostService().getUserLikedPosts(auth.user!.id),
      ]);

      // Friends
      final friendResp = results[0];
      if (friendResp.success && friendResp.data != null) {
        final data = friendResp.data;
        if (data is Map) {
          _friendCount = data['total'] ?? (data['friends'] as List?)?.length ?? 0;
        } else if (data is List) {
          _friendCount = data.length;
        }
      }

      // Likes count
      final likeResp = results[1];
      if (likeResp.success && likeResp.data != null) {
        final data = likeResp.data as Map<String, dynamic>;
        final list = data['posts'] as List? ?? [];
        _likeCount = list.length;
      }
    } catch (e) {
      debugPrint('ProfileTab loadStats error: $e');
      if (mounted) setState(() => _error = '加载失败，请下拉重试');
    } finally {
      setState(() => _isLoadingStats = false);
      _loadUserPosts();
    }
  }

  Future<void> _loadUserPosts() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() => _isLoadingPosts = true);
    try {
      final resp = await PostService().getUserPosts(auth.user!.id);
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
      setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _onRefresh(RefreshController controller) async {
    await Future.wait([
      context.read<AuthProvider>().loadSavedSession(),
      _loadStats(),
    ]);
    controller.refreshCompleted();
  }

  /// 修改头像
  Future<void> _changeAvatar() async {
    if (_isUploadingAvatar) return; // 防止重复触发

    try {
      final auth = context.read<AuthProvider>();
      if (auth.user == null) return;

      // 1. 选择图片（web 不支持 imageQuality 参数）
      XFile? picked;
      try {
        picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
      } catch (e) {
        // Edge/Web 兼容：回退到不传 imageQuality
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;

      // 2. 立即显示本地预览（无遮罩，用户可以看到选中的图片）
      final avatarBytes = await picked!.readAsBytes();
      setState(() {
        _localAvatarPreview = picked!.path;
        _localAvatarBytes = avatarBytes;
      });

      // 3. 尝试剪裁（失败则用原图）；剪裁后刷新预览
      String? finalPath = picked.path;
      try {
        final CroppedFile? cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: '剪裁头像',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: true,
            ),
            IOSUiSettings(title: '剪裁头像'),
            WebUiSettings(context: context),
          ],
        );
        if (cropped != null && cropped.path.isNotEmpty) {
          finalPath = cropped.path;
          // 刷新预览为剪裁后的图片
          final croppedBytes = await XFile(finalPath!).readAsBytes();
          if (mounted) {
            setState(() {
              _localAvatarPreview = finalPath;
              _localAvatarBytes = croppedBytes;
            });
          }
        }
      } catch (e) {
        debugPrint('Crop avatar error, using original: $e');
      }

      // 4. 开始上传 —— 此时才显示 loading 遮罩
      if (mounted) setState(() => _isUploadingAvatar = true);

      final resp = await UploadService().uploadAvatar(XFile(finalPath!));
      if (!mounted) return;

      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final newAvatarUrl = data['avatar_url'] ?? data['url'];
        if (newAvatarUrl != null) {
          final user = auth.user;
          if (user != null) {
            auth.updateUser(user.copyWith(avatarUrl: newAvatarUrl));
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('头像更新成功'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('头像上传失败: ${resp.message}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Change avatar error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('头像更新失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
          _localAvatarPreview = null;
          _localAvatarBytes = null;
        });
      }
    }
  }

  /// 修改背景图
  Future<void> _changeCoverPhoto() async {
    if (_isUploadingCover) return; // 防止重复触发

    try {
      final auth = context.read<AuthProvider>();
      if (auth.user == null) return;

      // 1. 选择图片
      XFile? picked;
      try {
        picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
      } catch (e) {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;

      // 2. 立即显示本地预览（无遮罩）
      final coverBytes = await picked!.readAsBytes();
      setState(() {
        _localCoverPreview = picked!.path;
        _localCoverBytes = coverBytes;
      });

      // 3. 尝试剪裁（16:9，失败则用原图）；剪裁后刷新预览
      String? finalPath = picked.path;
      try {
        final CroppedFile? cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: '剪裁背景图',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: true,
            ),
            IOSUiSettings(title: '剪裁背景图'),
            WebUiSettings(context: context),
          ],
        );
        if (cropped != null && cropped.path.isNotEmpty) {
          finalPath = cropped.path;
          // 刷新预览为剪裁后的图片
          final croppedBytes = await XFile(finalPath!).readAsBytes();
          if (mounted) {
            setState(() {
              _localCoverPreview = finalPath;
              _localCoverBytes = croppedBytes;
            });
          }
        }
      } catch (e) {
        debugPrint('Crop cover error, using original: $e');
      }

      // 4. 开始上传 —— 此时才显示 loading 遮罩
      if (mounted) setState(() => _isUploadingCover = true);

      final resp = await UploadService().uploadCoverPhoto(XFile(finalPath!));
      if (!mounted) return;

      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final newCoverUrl = data['cover_photo_url'] ?? data['url'];
        if (newCoverUrl != null) {
          final user = auth.user;
          if (user != null) {
            auth.updateUser(user.copyWith(coverPhotoUrl: newCoverUrl));
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('背景图更新成功'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('背景图上传失败: ${resp.message}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Change cover error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('背景图更新失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingCover = false;
          _localCoverPreview = null;
          _localCoverBytes = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (user == null) {
      return const Center(child: Text('请先登录', style: TextStyle(color: AppColors.textSecondary)));
    }

    final hasCover = user.coverPhotoUrl != null && user.coverPhotoUrl!.isNotEmpty;

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notif) {
        if (notif.dragDetails != null) {
          final delta = notif.scrollDelta ?? 0;
          if (delta > 5 && HomeScreen.barVisible.value) {
            HomeScreen.barVisible.value = false;
          } else if (delta < -5 && !HomeScreen.barVisible.value) {
            HomeScreen.barVisible.value = true;
          }
        }
        return false;
      },
      child: NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          expandedHeight: 480,
          floating: false,
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          toolbarHeight: 0,
          flexibleSpace: FlexibleSpaceBar(
            background: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Cover + Avatar (overlapping) ---
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () => _viewFullImage(user.coverPhotoUrl),
                      child: _buildCoverPhoto(user),
                    ),
                    if (!hasCover)
                      Container(
                        height: 180,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: GestureDetector(
                        onTap: () => _navigateToEditProfile(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.edit, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: -40,
                      child: GestureDetector(
                        onTap: () => _viewFullImage(user.avatarUrl),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 4),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: _buildNetworkAvatarRaw(user),
                            ),
                            // 在线状态小圆点（右下角）
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: _buildOnlineIndicator(),
                            ),
                            // 编辑按钮（右上角）
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () => _navigateToEditProfile(),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.edit, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Spacer for avatar overlap
                const SizedBox(height: 56),

                // --- Name + Username + Buttons ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName ?? user.username,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${user.username}',
                              style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),

                    ],
                  ),
                ),

                // --- Bio ---
                if (user.bio != null && user.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      user.bio!,
                      style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
                    ),
                  ),

                // --- Join date ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        user.createdAt != null
                            ? '${AppDateUtils.formatTimeAgo(user.createdAt)} 加入'
                            : '已加入',
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),

                // --- Stats (Friends / Likes) ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _isLoadingStats
                      ? const SizedBox(
                          height: 20,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                          ),
                        )
                      : _error != null
                          ? ErrorStateWidget(
                              message: _error!,
                              onRetry: () {
                                setState(() { _error = null; _isLoadingStats = true; });
                                _loadStats();
                              },
                            )
                          : Row(
                              children: [
                                GestureDetector(
                                  onTap: _navigateToFriends,
                                  child: Text(
                                    '$_friendCount 位好友',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  '$_likeCount 个喜欢',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              decoration: const BoxDecoration(
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
                unselectedLabelStyle: const TextStyle(fontSize: 15),
                tabs: const [
                  Tab(text: '帖子'),
                  Tab(text: '喜欢'),
                  Tab(text: '照片墙'),
                ],
              ),
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsTab(),
          _buildLikesTab(),
          _buildPhotosTab(),
        ],
      ),
    )
  );
  }

  Widget _buildCoverPhoto(User user) {
    final hasLocalPreview = _localCoverPreview != null;
    final hasCover = user.coverPhotoUrl != null && user.coverPhotoUrl!.isNotEmpty;

    // 本地预览优先
    if (hasLocalPreview) {
      return Stack(
        children: [
          Image.memory(
            _localCoverBytes!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(height: 180, color: const Color(0xFF2A2A2A)),
          ),
          if (_isUploadingCover)
            Container(
              height: 180,
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('上传中…', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    if (!hasCover) {
      return const SizedBox(height: 180);
    }
    final url = user.coverPhotoUrl!.startsWith('http')
        ? user.coverPhotoUrl!
        : '${AppConfig.baseUrl.replaceFirst('/api', '')}${user.coverPhotoUrl!}';
    return Stack(
      children: [
        Image.network(
          url,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(height: 180, color: const Color(0xFF2A2A2A)),
        ),
        if (_isUploadingCover)
          Container(
            height: 180,
            color: Colors.black45,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text('上传中…', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNetworkAvatarRaw(User user) {
    return ImageUtils.buildAvatar(user, radius: 40);
  }

  /// 在线状态指示器
  Widget _buildOnlineIndicator() {
    final isConnected = WebSocketService().isConnected;
    return Tooltip(
      message: isConnected ? '在线' : '离线',
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: isConnected ? Colors.green : Colors.grey,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  /// 点击查看头像/背景大图
  void _viewFullImage(String? url) {
    if (url == null || url.isEmpty) return;
    final resolved = url.startsWith('http') ? url : '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
    ImageViewerScreen.show(context, [resolved]);
  }

  /// 导航到编辑资料页
  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
  }

  Widget _buildPostsTab() {
    return SmartRefresher(
      controller: _postsRefreshController,
      enablePullDown: true,
      enablePullUp: false,
      onRefresh: () => _onRefresh(_postsRefreshController),
      header: const WaterDropHeader(
        complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      child: _buildPostsContent(),
    );
  }

  Widget _buildPostsContent() {
    if (_isLoadingPosts) {
      return ListView(children: const [
        SizedBox(height: 200),
        Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ]);
    }
    if (_userPosts.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('还没有发布帖子', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('发一条帖子让大家了解你吧', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ],
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _userPosts.length,
      itemBuilder: (context, index) => PostCard(
        post: _userPosts[index],
        onLike: () => _togglePostLike(_userPosts[index]),
        onTap: () => _openPostDetail(_userPosts[index]),
        onDelete: () => _deletePost(_userPosts[index]),
      ),
    );
  }

  Widget _buildLikesTab() {
    return SmartRefresher(
      controller: _likesRefreshController,
      enablePullDown: true,
      enablePullUp: false,
      onRefresh: () => _onRefresh(_likesRefreshController),
      header: const WaterDropHeader(
        complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      child: FutureBuilder<dynamic>(
        future: PostService().getUserLikedPosts(context.read<AuthProvider>().user!.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(children: const [
              SizedBox(height: 200),
              Center(child: CircularProgressIndicator(color: AppColors.primary)),
            ]);
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return ListView(children: [
              const SizedBox(height: 120),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('暂无喜欢的帖子', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ]);
          }
          final resp = snapshot.data as dynamic;
          if (resp.success && resp.data != null) {
            final data = resp.data as Map<String, dynamic>;
            final list = data['posts'] as List? ?? [];
            if (list.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite_border, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    const Text('还没有喜欢的帖子', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                  ],
                ),
              ]);
            }
            final posts = list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
            return ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: posts.length,
              itemBuilder: (context, index) => PostCard(
                post: posts[index],
                onLike: () => _togglePostLike(posts[index]),
                onTap: () => _openPostDetail(posts[index]),
              ),
            );
          }
          return ListView(children: const [
            SizedBox(height: 120),
            Center(child: Text('加载失败', style: TextStyle(color: AppColors.textSecondary))),
          ]);
        },
      ),
    );
  }

  Widget _buildPhotosTab() {
    final photoPosts = _userPosts.where((p) => p.hasImage).toList();
    if (photoPosts.isEmpty) {
      return SmartRefresher(
        controller: _photosRefreshController,
        enablePullDown: true,
        enablePullUp: false,
        onRefresh: () => _onRefresh(_photosRefreshController),
        header: const WaterDropHeader(
          complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
          waterDropColor: AppColors.primary,
        ),
        child: ListView(children: [
          const SizedBox(height: 120),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              const Text('还没有照片', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            ],
          ),
        ]),
      );
    }
    return SmartRefresher(
      controller: _photosRefreshController,
      enablePullDown: true,
      enablePullUp: false,
      onRefresh: () => _onRefresh(_photosRefreshController),
      header: const WaterDropHeader(
        complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: photoPosts.length,
        itemBuilder: (context, index) {
          final post = photoPosts[index];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)),
            ),
            child: Container(
              color: Colors.grey[200],
              child: ImageUtils.buildPostImage(post.images != null && post.images!.isNotEmpty ? post.images![0] : null, width: double.infinity, height: double.infinity),
            ),
          );
        },
      ),
    );
  }

  void _navigateToFriends() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  void _openPostDetail(Post post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)),
    );
  }

  Future<void> _togglePostLike(Post post) async {
    final wasLiked = post.isLiked ?? false;
    final originalCount = post.likeCount;

    // Optimistic update: update UI immediately
    setState(() {
      _updatePostLike(post.id, !wasLiked, wasLiked ? originalCount - 1 : originalCount + 1);
    });

    try {
      if (wasLiked) {
        await PostService().unlikePost(post.id);
      } else {
        await PostService().likePost(post.id);
      }
      PostInteractionNotifier().notifyLikeChanged(post.id, !wasLiked, wasLiked ? originalCount - 1 : originalCount + 1);
    } catch (e) {
      if (!mounted) return;
      // Rollback on failure
      setState(() {
        _updatePostLike(post.id, wasLiked, originalCount);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _updatePostLike(int postId, bool isLiked, int likeCount) {
    final idx = _userPosts.indexWhere((p) => p.id == postId);
    if (idx != -1) {
      _userPosts[idx] = _userPosts[idx].copyWith(isLiked: isLiked, likeCount: likeCount);
    }
  }

  void _onPostLikeEvent(PostLikeEvent event) {
    if (!mounted) return;
    setState(() {
      _updatePostLike(event.postId, event.isLiked, event.likeCount);
    });
  }

  void _onPostViewEvent(PostViewEvent event) {
    if (!mounted) return;
    final idx = _userPosts.indexWhere((p) => p.id == event.postId);
    if (idx == -1) return;
    setState(() {
      _userPosts[idx] = _userPosts[idx].copyWith(viewCount: event.viewCount);
    });
  }

  /// 从本地列表移除已删除的帖子（删除确认和 API 调用已由 PostCard 处理）
  void _deletePost(Post post) {
    setState(() {
      _userPosts.remove(post);
    });
  }
}
