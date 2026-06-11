import 'dart:async';

import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/providers/core_providers.dart';
import 'package:facebook_clone/services/cache_keys.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../comic/comic_my_events_page.dart';
import '../comic/comic_timeline_page.dart';
import '../friends/friend_requests_screen.dart';
import '../messages/messages_tab.dart';
import '../post/create_post_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../profile/profile_tab.dart';
import '../profile/settings_screen.dart';
import '../search/search_tab.dart';
import '../topics/my_topics_screen.dart';
import 'home/feed_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int? initialTab;

  const HomeScreen({super.key, this.initialTab});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final List<Widget> _tabs = const [
    FeedTab(),
    SearchTab(),
    MessagesTab(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      ref.read(currentTabIndexProvider.notifier).state = widget.initialTab!;
    }
    _listenFriendOnline();
  }

  StreamSubscription? _friendOnlineSub;

  void _listenFriendOnline() {
    _friendOnlineSub = WebSocketService().friendOnlineStream.listen((payload) async {
      final userId = payload['user_id'];
      if (userId == null || !mounted) return;
      String? name;
      try {
        final cached = await DataLayer().query(CacheKeys.friendList, () async => null);
        if (cached.data is List) {
          for (final item in cached.data as List) {
            if (item is Map && item['id'] == userId) {
              final user = User.fromJson(item as Map<String, dynamic>);
              name = user.displayName ?? user.username;
              break;
            }
          }
        }
      } catch (_) {}
      if (name != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.circle, color: Colors.green, size: 10),
                const SizedBox(width: 8),
                Text('$name 上线了'),
              ],
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _friendOnlineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final barVisible = ref.watch(barVisibleProvider);
    final totalBadge = (ref.watch(unreadNotificationsCountProvider) + ref.watch(unreadMessagesCountProvider)).toInt();
    final currentIndex = ref.watch(currentTabIndexProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),
      drawer: _buildDrawer(context),
      floatingActionButton: currentIndex == 0
          ? AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: barVisible ? Offset.zero : const Offset(0, 2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: barVisible ? 1.0 : 0.0,
                child: FloatingActionButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                    );
                    if (result == true) {}
                  },
                  backgroundColor: AppColors.primary,
                  elevation: 4,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.edit, color: Colors.white, size: 26),
                ),
              ),
            )
          : null,
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        offset: barVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: barVisible ? 1.0 : 0.0,
          child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) {
            ref.read(currentTabIndexProvider.notifier).state = i;
          },
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          items: [
            BottomNavigationBarItem(
              icon: _NavIcon(
                asset: 'assets/icons/未选中首页.svg',
                isSelected: currentIndex == 0,
                size: 26,
              ),
              activeIcon: _NavIcon(
                asset: 'assets/icons/选中首页.svg',
                isSelected: currentIndex == 0,
                size: 26,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _NavIcon(
                asset: 'assets/icons/未选中搜索.svg',
                isSelected: currentIndex == 1,
                size: 26,
              ),
              activeIcon: _NavIcon(
                asset: 'assets/icons/选中搜索.svg',
                isSelected: currentIndex == 1,
                size: 26,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _NavIcon(
                asset: 'assets/icons/未选中消息.svg',
                isSelected: currentIndex == 2,
                size: 26,
              ),
              activeIcon: _NavIcon(
                asset: 'assets/icons/选中消息.svg',
                isSelected: currentIndex == 2,
                size: 26,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _NavIcon(
                asset: 'assets/icons/未选中个人.svg',
                isSelected: currentIndex == 3,
                size: 26,
              ),
              activeIcon: _NavIcon(
                asset: 'assets/icons/选中个人.svg',
                isSelected: currentIndex == 3,
                size: 26,
              ),
              label: '',
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildDrawer(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            // User info section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 0.5)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary,
                    backgroundImage: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                        ? NetworkImage(
                            user.avatarUrl!.startsWith('http')
                                ? user.avatarUrl!
                                : '${AppConfig.baseUrl.replaceFirst('/api', '')}${user.avatarUrl}',
                          )
                        : null,
                    child: user?.avatarUrl == null || user!.avatarUrl!.isEmpty
                        ? Text(user?.initials ?? '?',
                            style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? user?.username ?? '用户',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${user?.username ?? 'user'}',
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Menu items
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: const Text('编辑个人资料', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_outlined, color: AppColors.textPrimary),
              title: const Text('好友申请', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.tag, color: AppColors.textPrimary),
              title: const Text('我的话题', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyTopicsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.event, color: AppColors.textPrimary),
              title: const Text('漫展时间线', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComicTimelinePage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border, color: AppColors.textPrimary),
              title: const Text('我的漫展', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComicMyEventsPage()),
                );
              },
            ),
            const Spacer(),
            const Divider(height: 1, color: AppColors.borderLight),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
              title: const Text('设置', style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.likeRed),
              title: const Text('退出登录', style: TextStyle(fontSize: 15, color: AppColors.likeRed)),
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).logout();
                Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeIcon({
    required IconData icon,
    required IconData activeIcon,
    required int count,
    bool isActive = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 26),
        if (count > 0)
          Positioned(
            right: -6,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    final authState = ref.watch(authProvider);
    final url = authState.user?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      final fullUrl = url.startsWith('http') ? url : '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
      return Image.network(fullUrl, fit: BoxFit.cover,
        errorBuilder: (ctx, err, st) => CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary,
          child: Text(authState.user?.initials ?? '?',
            style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary,
      child: Text(authState.user?.initials ?? '?',
        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

/// Navigation icon with scale animation when selected
class _NavIcon extends StatelessWidget {
  final String asset;
  final bool isSelected;
  final double size;

  const _NavIcon({
    required this.asset,
    required this.isSelected,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        isSelected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.6),
        BlendMode.srcIn,
      ),
    );
  }
}
