import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/services/api/friend_service.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class FriendsScreen extends StatefulWidget {
  final String title;

  const FriendsScreen({super.key, this.title = '好友'});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendService _friendService = FriendService();
  final RefreshController _refreshController = RefreshController();

  List<User> _friends = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends({bool isRefresh = false}) async {
    try {
      final response = await _friendService.getFriends();
      if (response.success) {
        final data = response.data;
        final friendList = (data['friends'] as List<dynamic>?)
                ?.map((e) => User.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        setState(() {
          _friends = friendList;
          _isLoading = false;
          _errorMessage = null;
        });
        if (isRefresh) _refreshController.refreshCompleted();
      } else {
        setState(() {
          _errorMessage = response.message ?? '加载失败';
          _isLoading = false;
        });
        if (isRefresh) _refreshController.refreshFailed();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '网络错误，请稍后重试';
        _isLoading = false;
      });
      if (isRefresh) _refreshController.refreshFailed();
    }
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
          widget.title,
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
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const FriendSkeleton();
    }

    if (_errorMessage != null) {
      return ErrorStateWidget(
        message: _errorMessage!,
        onRetry: () {
          setState(() => _isLoading = true);
          _loadFriends();
        },
      );
    }

    if (_friends.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.people_outline,
        title: '暂无好友',
        subtitle: '添加好友后他们会显示在这里',
      );
    }

    return SmartRefresher(
      controller: _refreshController,
      enablePullDown: true,
      enablePullUp: false,
      onRefresh: () => _loadFriends(isRefresh: true),
      header: const WaterDropHeader(
        complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      child: ListView.separated(
        itemCount: _friends.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, indent: 76, color: AppColors.borderLight),
        itemBuilder: (context, index) {
          final user = _friends[index];
          return _FriendTile(user: user);
        },
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final User user;

  const _FriendTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ImageUtils.buildAvatar(user, radius: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName ?? user.username,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.bio!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.more_horiz, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
