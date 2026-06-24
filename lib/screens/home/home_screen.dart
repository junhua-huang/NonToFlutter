import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/models/notification.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/screens/community/community_list_screen.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/push_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/app_transitions.dart';
import 'package:nonto/utils/image_utils.dart';
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

/// Nonto 主框架页：承载首页、发现、消息与我的四个核心入口。
///
/// 保留 IndexedStack 以维持各 Tab 状态，底部导航和发布入口只做轻量重组。
class HomeScreen extends ConsumerStatefulWidget {
  final int? initialTab;

  const HomeScreen({super.key, this.initialTab});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late final List<Widget> _tabs = const [
    FeedTab(),
    SearchTab(),
    MessagesTab(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialTab != null) {
      ref.read(currentTabIndexProvider.notifier).state = widget.initialTab!;
    }
    _listenFriendOnline();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService().requestPermission();
      PushService().reportAppState('foreground');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用回到前台时，WS socket 多半已被系统挂起（看似 authenticated 实则僵死）。
    // 用 forceReconnect 强制重建，绕过 connect() 的「已连接」短路——
    // 这是「有网就不断 WS」的关键：回前台必须立即恢复实时通道。
    if (state == AppLifecycleState.resumed) {
      PushService().reportAppState('foreground');
      final ws = WebSocketService();
      if (ApiClient.token != null && ApiClient.token!.isNotEmpty) {
        debugPrint('[Home] app resumed, force reconnecting WebSocket');
        ws.forceReconnect();
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      PushService().reportAppState('background');
    }
  }

  StreamSubscription? _friendOnlineSub;

  void _listenFriendOnline() {
    _friendOnlineSub =
        WebSocketService().friendOnlineStream.listen((payload) async {
      final userId = payload['user_id'];
      if (userId == null || !mounted) return;
      String? name;
      try {
        final cached =
            await DataLayer().query(CacheKeys.friendList, () async => null);
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
    WidgetsBinding.instance.removeObserver(this);
    _friendOnlineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barVisible = ref.watch(barVisibleProvider);
    final totalBadge = (ref.watch(unreadNotificationsCountProvider) +
            ref.watch(unreadMessagesCountProvider))
        .toInt();
    final currentIndex = ref.watch(currentTabIndexProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),
      drawer: _buildDrawer(context),
      floatingActionButton: _buildComposeButton(barVisible, currentIndex),
      bottomNavigationBar: _buildBottomNavigationBar(
        barVisible: barVisible,
        currentIndex: currentIndex,
        totalBadge: totalBadge,
      ),
    );
  }

  Widget? _buildComposeButton(bool barVisible, int currentIndex) {
    if (currentIndex != 0) return null;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      offset: barVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: barVisible ? 1.0 : 0.0,
        child: FloatingActionButton(
          onPressed: () async {
            await AppTransitions.pushBottom(context, const CreatePostScreen());
          },
          backgroundColor: AppColors.primary,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(Icons.edit, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar({
    required bool barVisible,
    required int currentIndex,
    required int totalBadge,
  }) {
    return AnimatedSlide(
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
            onTap: (index) {
              ref.read(currentTabIndexProvider.notifier).state = index;
            },
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            selectedFontSize: 0,
            unselectedFontSize: 0,
            items: _buildNavigationItems(
              currentIndex: currentIndex,
              totalBadge: totalBadge,
            ),
          ),
        ),
      ),
    );
  }

  List<BottomNavigationBarItem> _buildNavigationItems({
    required int currentIndex,
    required int totalBadge,
  }) {
    return [
      _buildNavItem(
        asset: 'assets/icons/未选中首页.svg',
        activeAsset: 'assets/icons/选中首页.svg',
        selected: currentIndex == 0,
      ),
      _buildNavItem(
        asset: 'assets/icons/未选中搜索.svg',
        activeAsset: 'assets/icons/选中搜索.svg',
        selected: currentIndex == 1,
      ),
      _buildNavItem(
        asset: 'assets/icons/未选中消息.svg',
        activeAsset: 'assets/icons/选中消息.svg',
        selected: currentIndex == 2,
        badgeCount: totalBadge,
      ),
      _buildNavItem(
        asset: 'assets/icons/未选中个人.svg',
        activeAsset: 'assets/icons/选中个人.svg',
        selected: currentIndex == 3,
      ),
    ];
  }

  BottomNavigationBarItem _buildNavItem({
    required String asset,
    required String activeAsset,
    required bool selected,
    int badgeCount = 0,
  }) {
    return BottomNavigationBarItem(
      icon: _buildNavIcon(
        asset: asset,
        selected: selected,
        badgeCount: badgeCount,
      ),
      activeIcon: _buildNavIcon(
        asset: activeAsset,
        selected: selected,
        badgeCount: badgeCount,
      ),
      label: '',
    );
  }

  Widget _buildNavIcon({
    required String asset,
    required bool selected,
    int badgeCount = 0,
  }) {
    final icon = ExcludeSemantics(
      child: _NavIcon(
        asset: asset,
        isSelected: selected,
        size: 26,
      ),
    );

    if (badgeCount <= 0) return icon;

    return Badge(
      label: Text(_formatBadgeCount(badgeCount)),
      child: icon,
    );
  }

  String _formatBadgeCount(int count) => count > 99 ? '99+' : '$count';

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
              decoration: BoxDecoration(
                border: Border(
                    bottom:
                        BorderSide(color: AppColors.borderLight, width: 0.5)),
              ),
              child: Row(
                children: [
                  ImageUtils.buildAvatar(user, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? user?.username ?? '用户',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${user?.username ?? 'user'}',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.textSecondary),
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
              leading: Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: Text('编辑个人资料',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.person_add_outlined, color: AppColors.textPrimary),
              title: Consumer(
                builder: (context, ref, _) {
                  final notifs = ref.watch(notificationsProvider).notifications;
                  final friendCount = notifs
                      .where((n) =>
                          n.parsedType == NotificationType.friendRequest &&
                          !n.isRead)
                      .length;
                  return Row(
                    children: [
                      Text('好友申请',
                          style: TextStyle(
                              fontSize: 15, color: AppColors.textPrimary)),
                      if (friendCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.likeRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$friendCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FriendRequestsScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.tag, color: AppColors.textPrimary),
              title: Text('我的话题',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyTopicsScreen()),
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.groups_outlined, color: AppColors.textPrimary),
              title: Text('社群',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CommunityListScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.event, color: AppColors.textPrimary),
              title: Text('漫展时间线',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComicTimelinePage()),
                );
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.bookmark_border, color: AppColors.textPrimary),
              title: Text('我的漫展',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ComicMyEventsPage()),
                );
              },
            ),
            const Spacer(),
            Divider(height: 1, color: AppColors.borderLight),
            ListTile(
              leading:
                  Icon(Icons.settings_outlined, color: AppColors.textPrimary),
              title: Text('设置',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
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
              title: const Text('退出登录',
                  style: TextStyle(fontSize: 15, color: AppColors.likeRed)),
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).logout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
        isSelected
            ? AppColors.primary
            : AppColors.textSecondary.withValues(alpha: 0.6),
        BlendMode.srcIn,
      ),
    );
  }
}
