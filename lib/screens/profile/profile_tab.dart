import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cross_file/cross_file.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/screens/friends/friends_screen.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/screens/profile/edit_profile_screen.dart';
import 'package:nonto/services/api/auth_service.dart';
import 'package:nonto/services/api/friend_service.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/upload_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/post_interaction_notifier.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/media_viewer.dart';
import 'package:nonto/widgets/post_card.dart';
import 'package:flutter/material.dart';
import 'package:nonto/utils/bar_scroll_handler.dart';
import 'package:image_cropper_plus/image_cropper_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Twitter/X 风格个人资料页（头像半覆盖背景、可编辑、照片墙Tab）
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});
  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> with TickerProviderStateMixin {
  int _friendCount = 0;
  int _likeCount = 0;
  bool _isLoadingStats = true;
  final List<Post> _userPosts = [];
  // 默认 true：首帧显示 loading 而非「还没有发布帖子」缺省页。
  // _loadStats/_loadLikedPosts 完成后会回调 _loadUserPosts，加载完成后置 false。
  bool _isLoadingPosts = true;
  String? _error;
  bool _likesLoading = true;
  List<Post> _likedPosts = [];
  String? _likesError;
  bool _isRefreshing = false;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    PostInteractionNotifier().onLikeChanged.listen(_onPostLikeEvent);
    PostInteractionNotifier().onViewChanged.listen(_onPostViewEvent);
    _loadStats();
    // 并行触发帖子/喜欢列表加载，避免串行等待 stats 期间命中「没有帖子」缺省页。
    // _loadStats() 内部也会再调一次（命中缓存读取，开销极小，且自带重入语义）。
    _loadUserPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }



  Future<void> _loadStats() async {
    final auth = ref.read(authProvider);
    if (auth.user == null) {
      if (mounted) {
        setState(() { _isLoadingStats = false; _error = '无法获取用户信息'; });
      }
      return;
    }

    bool hasError = false;

    // 好友数量 —— 独立容错
    try {
      final friendResp = await FriendService()
          .getFriends()
          .timeout(const Duration(seconds: 20));
      if (friendResp.success && friendResp.data != null) {
        final data = friendResp.data;
        if (data is Map) {
          _friendCount =
              data['total'] ?? (data['friends'] as List?)?.length ?? 0;
        } else if (data is List) {
          _friendCount = data.length;
        }
      }
    } catch (e) {
      debugPrint('ProfileTab loadFriends error: $e');
      hasError = true;
    }

    // 喜欢数量 —— 走缓存层，未命中时通过 fetcher 回源
    try {
      final cacheKey = CacheKeys.userLiked(auth.user!.id);
      final likeResult = await DataLayer()
          .query(cacheKey, () async {
            final resp = await PostService()
                .getUserLikedPosts(auth.user!.id)
                .timeout(const Duration(seconds: 20));
            if (resp.success && resp.data != null) {
              final data = resp.data as Map<String, dynamic>;
              return data['posts'] as List? ?? [];
            }
            return null;
          })
          .timeout(const Duration(seconds: 25));
      if (likeResult.data is List) {
        _likeCount = (likeResult.data as List).length;
      }
    } catch (e) {
      debugPrint('ProfileTab loadLikes error: $e');
      hasError = true;
    }

    if (mounted) {
      setState(() {
        _isLoadingStats = false;
        if (hasError) _error = '加载失败，请下拉重试';
      });
    }

    _loadLikedPosts();
    _loadUserPosts();
  }

  Future<void> _loadLikedPosts() async {
    final auth = ref.read(authProvider);
    if (auth.user == null) {
      if (mounted) {
        setState(() { _likesLoading = false; _likesError = '无法获取用户信息'; });
      }
      return;
    }
    try {
      final cacheKey = CacheKeys.userLiked(auth.user!.id);
      final likeResult = await DataLayer()
          .query(cacheKey, () async {
            final resp = await PostService()
                .getUserLikedPosts(auth.user!.id)
                .timeout(const Duration(seconds: 20));
            if (resp.success && resp.data != null) {
              final data = resp.data as Map<String, dynamic>;
              return data['posts'] as List? ?? [];
            }
            return null;
          })
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      if (likeResult.data is List) {
        final list = likeResult.data as List;
        setState(() {
          _likedPosts = list
              .map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList();
          _likesLoading = false;
        });
        return;
      }
      setState(() { _likesLoading = false; });
    } catch (e) {
      debugPrint('ProfileTab loadLikedPosts error: $e');
      if (mounted) {
        setState(() {
          _likesLoading = false;
          _likesError = '加载失败，请下拉重试';
        });
      }
    }
  }

  Future<void> _loadUserPosts() async {
    final auth = ref.read(authProvider);
    if (auth.user == null) {
      if (mounted) {
        setState(() { _isLoadingPosts = false; _error = '无法获取用户信息'; });
      }
      return;
    }
    setState(() { _isLoadingPosts = true; _error = null; });
    try {
      final userId = auth.user!.id.toString();
      // L1 → L2 → 网络 三层读取
      final result = await DataLayer()
          .query(
            CacheKeys.userPosts(userId),
            () async {
              final resp = await PostService()
                  .getUserPosts(auth.user!.id)
                  .timeout(const Duration(seconds: 20));
              if (resp.success && resp.data != null) {
                final data = resp.data as Map<String, dynamic>;
                return data['posts'] as List? ?? [];
              }
              return null;
            },
          )
          .timeout(const Duration(seconds: 25));
      if (result.data is List && mounted) {
        final list = result.data as List<dynamic>;
        setState(() {
          _userPosts.clear();
          _userPosts.addAll(
            list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList(),
          );
          _isLoadingPosts = false;
        });
      } else if (mounted) {
        setState(() { _isLoadingPosts = false; _error = '加载失败，请下拉重试'; });
      }
    } catch (e) {
      debugPrint('Load user posts error: $e');
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
          _error = '加载失败，请下拉重试';
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    // 并行刷新：个人资料 + 统计 + 帖子 + 喜欢
    await Future.wait([
      _refreshUserProfile(),
      _loadStats(),
      _loadUserPostsForceRefresh(),
      _loadLikedPostsForceRefresh(),
    ]);

    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  /// 刷新用户资料（头像/背景/简介）
  Future<void> _refreshUserProfile() async {
    try {
      final auth = ref.read(authProvider);
      if (auth.user != null) {
        final resp = await AuthService().getProfile();
        if (resp.success && resp.data != null) {
          final refreshed = User.fromJson(resp.data as Map<String, dynamic>);
          final now = DateTime.now().millisecondsSinceEpoch;
          final avatarChanged = refreshed.avatarUrl != auth.user!.avatarUrl;
          final coverChanged = refreshed.coverPhotoUrl != auth.user!.coverPhotoUrl;
          final updated = refreshed.copyWith(
            avatarCacheTs: avatarChanged ? now : auth.user!.avatarCacheTs,
            coverCacheTs: coverChanged ? now : auth.user!.coverCacheTs,
          );
          ref.read(authProvider.notifier).updateUser(updated);
        }
      }
    } catch (_) {}
  }

  /// 强制刷新用户帖子（绕过缓存）
  Future<void> _loadUserPostsForceRefresh() async {
    final auth = ref.read(authProvider);
    if (auth.user == null) return;
    try {
      final resp = await PostService()
          .getUserPosts(auth.user!.id)
          .timeout(const Duration(seconds: 20));
      if (resp.success && resp.data != null && mounted) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['posts'] as List?) ?? [];
        setState(() {
          _userPosts.clear();
          _userPosts.addAll(
            list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList(),
          );
          _isLoadingPosts = false;
        });
      }
    } catch (e) {
      debugPrint('Force refresh user posts error: $e');
    }
  }

  /// 强制刷新喜欢列表（绕过缓存）
  Future<void> _loadLikedPostsForceRefresh() async {
    final auth = ref.read(authProvider);
    if (auth.user == null) return;
    try {
      final resp = await PostService()
          .getUserLikedPosts(auth.user!.id)
          .timeout(const Duration(seconds: 20));
      if (resp.success && resp.data != null && mounted) {
        final data = resp.data as Map<String, dynamic>;
        final list = (data['posts'] as List?) ?? [];
        setState(() {
          _likedPosts = list
              .map((e) => Post.fromJson(e as Map<String, dynamic>))
              .toList();
          _likesLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Force refresh liked posts error: $e');
    }
  }

  /// 修改头像
  Future<void> _changeAvatar() async {
    if (_isUploadingAvatar) return; // 防止重复触发

    try {
      final auth = ref.read(authProvider);
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

      // 3. 尝试剪裁（1:1，失败则用原图）；剪裁后刷新预览
      String? finalPath = picked.path;
      // 预读图片数据（showModalBottomSheet builder 是非 async 的）
      final imageBytes = await XFile(picked.path).readAsBytes();
      if (!mounted) return;

      try {
        final croppedBytes = await showModalBottomSheet<Uint8List>(
          context: context,
          isScrollControlled: true,
          builder: (_) => CropPage(
            imageBytes: imageBytes,
            config: const CropConfig(aspectRatio: 1.0),
          ),
        );
        if (croppedBytes != null) {
          finalPath = await _saveCroppedToTemp(croppedBytes);
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
            final now = DateTime.now().millisecondsSinceEpoch;
            ref.read(authProvider.notifier).updateUser(
              user.copyWith(avatarUrl: newAvatarUrl, avatarCacheTs: now),
            );
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
      final auth = ref.read(authProvider);
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
      // 预读图片数据（showModalBottomSheet builder 是非 async 的）
      final coverImageBytes = await XFile(picked.path).readAsBytes();
      if (!mounted) return;

      try {
        final croppedBytes = await showModalBottomSheet<Uint8List>(
          context: context,
          isScrollControlled: true,
          builder: (_) => CropPage(
            imageBytes: coverImageBytes,
            config: const CropConfig(aspectRatio: 16 / 9),
          ),
        );
        if (croppedBytes != null) {
          finalPath = await _saveCroppedToTemp(croppedBytes);
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
            final now = DateTime.now().millisecondsSinceEpoch;
            ref.read(authProvider.notifier).updateUser(
              user.copyWith(coverPhotoUrl: newCoverUrl, coverCacheTs: now),
            );
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

  /// 将裁剪后的字节数组保存为临时文件，返回文件路径
  Future<String> _saveCroppedToTemp(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    if (user == null) {
      return const Center(child: Text('请先登录', style: TextStyle(color: AppColors.textSecondary)));
    }

    final hasCover = user.coverPhotoUrl != null && user.coverPhotoUrl!.isNotEmpty;

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notif) {
        handleBarScrollNotification(notif, ref);
        return false;
      },
      child: NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          expandedHeight: 420,
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
                          ? GestureDetector(
                              onTap: () {
                                setState(() { _error = null; _isLoadingStats = true; });
                                _loadStats();
                              },
                              child: const Text(
                                '加载失败，点击重试',
                                style: TextStyle(fontSize: 13, color: AppColors.likeRed),
                              ),
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
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _onRefresh,
        // 在 body 内部刷新：RefreshIndicator 包在 NestedScrollView 外层时，
        // 下拉手势会被 header 的展开/收起逻辑消费，导致刷新失效。
        // 放到 body 内部则不受 header 影响。
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildPostsContent(),
            _buildLikesContent(),
            _buildPhotosContent(),
          ],
        ),
      ),
    ),
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
    final url = ImageUtils.resolveUrl(user.coverPhotoUrl);
    final cacheBustedUrl = user.coverCacheTs != null
        ? '${url}${url.contains('?') ? '&' : '?'}t=${user.coverCacheTs}'
        : url;
    return Stack(
      children: [
        CachedNetworkImage(
          key: ValueKey(cacheBustedUrl),
          imageUrl: cacheBustedUrl,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(height: 180, color: const Color(0xFF2A2A2A)),
          errorWidget: (_, __, ___) => Container(height: 180, color: const Color(0xFF2A2A2A)),
          fadeInDuration: const Duration(milliseconds: 300),
          fadeInCurve: Curves.easeInOut,
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
    return StreamBuilder<bool>(
      stream: WebSocketService().connectionStream,
      initialData: WebSocketService().isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? false;
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
      },
    );
  }

  /// 点击查看头像/背景大图
  void _viewFullImage(String? url) {
    if (url == null || url.isEmpty) return;
    final resolved = ImageUtils.resolveUrl(url);
    ImageViewerScreen.show(context, [resolved]);
  }

  /// 导航到编辑资料页，返回后刷新界面
  Future<void> _navigateToEditProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    // 编辑页现在按需保存，每个字段独立上传。
    // 返回后只需 setState 触发重建即可看到最新状态。
    if (mounted) setState(() {});
  }

  Widget _buildPostsContent() {
    if (_isLoadingPosts && _userPosts.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 200),
        Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ]);
    }
    if (_error != null && _userPosts.isEmpty) {
      return ErrorStateWidget(
        message: _error!,
        onRetry: () {
          setState(() { _error = null; _isLoadingPosts = true; });
          _loadUserPosts();
        },
      );
    }
    if (_userPosts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
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
      physics: const AlwaysScrollableScrollPhysics(),
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

  Widget _buildLikesContent() {
    if (_likesLoading) {
      return ListView(children: const [
        SizedBox(height: 200),
        Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ]);
    }
    if (_likesError != null) {
      return ErrorStateWidget(
        message: _likesError!,
        onRetry: () {
          setState(() { _likesLoading = true; _likesError = null; });
          _loadLikedPosts();
        },
      );
    }
    if (_likedPosts.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('还没有喜欢的帖子',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          ],
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _likedPosts.length,
      itemBuilder: (context, index) => PostCard(
        post: _likedPosts[index],
        onLike: () => _togglePostLike(_likedPosts[index]),
        onTap: () => _openPostDetail(_likedPosts[index]),
      ),
    );
  }

  Widget _buildPhotosContent() {
    final photoPosts = _userPosts.where((p) => p.hasImage).toList();
    if (photoPosts.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('还没有照片', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          ],
        ),
      ]);
    }
    return GridView.builder(
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
              MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id, initialPost: post)),
            ),
            child: Container(
              color: Colors.grey[200],
              child: ImageUtils.buildPostImage(post.images != null && post.images!.isNotEmpty ? post.images![0] : null, width: double.infinity, height: double.infinity),
            ),
          );
        },
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
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id, initialPost: post)),
    );
  }

  Future<void> _togglePostLike(Post post) async {
    final wasLiked = post.isLiked ?? false;
    final originalCount = post.likeCount;

    // Optimistic update: update UI immediately
    setState(() {
      _updatePostLike(post.id, !wasLiked, wasLiked ? originalCount - 1 : originalCount + 1);
    });
    // L2 + L1 同步写入
    _syncPostsToCache();

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
      _syncPostsToCache();
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

  /// 将当前用户帖子列表写入 DataLayer L2+L1
  void _syncPostsToCache() {
    final userId = ref.read(authProvider).user?.id.toString();
    if (userId == null || _userPosts.isEmpty) return;
    final data = _userPosts.map((p) => p.toJson()).toList();
    DataLayer().write(CacheKeys.userPosts(userId), data);
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
    _syncPostsToCache();
  }
}
