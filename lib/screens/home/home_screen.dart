import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/models/notification.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/screens/community/community_list_screen.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/app_transitions.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nonto/widgets/authenticated_shell.dart';

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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final List<Widget?> _tabCache = List<Widget?>.filled(4, null);
  int _visibleTabIndex = 0;

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
    _friendOnlineSub?.cancel();
    super.dispose();
  }

  Widget _createTab(int index) {
    return switch (index) {
      0 => const FeedTab(),
      1 => const SearchTab(),
      2 => const MessagesTab(),
      3 => const ProfileTab(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildLazyTab(int index) {
    if (index != _visibleTabIndex && _tabCache[index] == null) {
      return const SizedBox.shrink();
    }
    return _tabCache[index] ??= _createTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final barVisible = ref.watch(barVisibleProvider);
    final totalBadge = ref.watch(unreadMessagesCountProvider).toInt();
    final currentIndex = ref.watch(currentTabIndexProvider);
    _visibleTabIndex = currentIndex;

    final isWide = WideShellScope.isWideOf(context);
    final tabChildren = List.generate(_tabCache.length, _buildLazyTab);
    final content = IndexedStack(
      index: currentIndex,
      children: tabChildren,
    );

    return Scaffold(
      extendBody: !isWide,
      body: isWide
          ? _WideTabTransitionStack(
              index: currentIndex,
              children: tabChildren,
            )
          : content,
      drawer: isWide ? null : _buildDrawer(context),
      floatingActionButton:
          isWide ? null : _buildComposeButton(barVisible, currentIndex),
      bottomNavigationBar: isWide
          ? null
          : _buildBottomNavigationBar(
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
      backgroundColor: AppColors.unreadBadge,
      textColor: Colors.white,
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
              leading:
                  Icon(Icons.verified_outlined, color: AppColors.textPrimary),
              title: Text('我的身份',
                  style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.identityCenter);
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

/// Keeps every cached tab mounted while animating only the wide-screen content.
class _WideTabTransitionStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _WideTabTransitionStack({
    required this.index,
    required this.children,
  });

  @override
  State<_WideTabTransitionStack> createState() =>
      _WideTabTransitionStackState();
}

class _WideTabTransitionStackState extends State<_WideTabTransitionStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTransitions.slideDuration,
  );
  int? _outgoingIndex;
  late int _activeIndex = widget.index;
  int _direction = 1;

  @override
  void didUpdateWidget(_WideTabTransitionStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;

    _outgoingIndex = oldWidget.index;
    _activeIndex = widget.index;
    _direction = widget.index >= oldWidget.index ? 1 : -1;
    _controller
      ..stop()
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final isAnimating = _outgoingIndex != null && _controller.value < 1.0;
          final progress = Curves.easeOutCubic.transform(_controller.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (isAnimating && _outgoingIndex != null)
                Positioned.fill(
                  child: _WideTabLayer(
                    key: ValueKey(_outgoingIndex),
                    isActive: false,
                    isOutgoing: true,
                    isAnimating: true,
                    progress: progress,
                    direction: _direction,
                    child: widget.children[_outgoingIndex!],
                  ),
                ),
              Positioned.fill(
                child: _WideTabLayer(
                  key: ValueKey(_activeIndex),
                  isActive: true,
                  isOutgoing: false,
                  isAnimating: isAnimating,
                  progress: progress,
                  direction: _direction,
                  child: widget.children[_activeIndex],
                ),
              ),
              for (var index = 0; index < widget.children.length; index++)
                if (index != _activeIndex && index != _outgoingIndex)
                  Positioned.fill(
                    child: _WideTabLayer(
                      key: ValueKey(index),
                      isActive: false,
                      isOutgoing: false,
                      isAnimating: false,
                      progress: progress,
                      direction: _direction,
                      child: widget.children[index],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Stable wrapper for one cached tab. Its child never changes parents during a
/// transition, so scroll positions and other tab-local state remain intact.
class _WideTabLayer extends StatelessWidget {
  final Widget child;
  final bool isActive;
  final bool isOutgoing;
  final bool isAnimating;
  final double progress;
  final int direction;

  const _WideTabLayer({
    super.key,
    required this.child,
    required this.isActive,
    required this.isOutgoing,
    required this.isAnimating,
    required this.progress,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final visible = isActive || isOutgoing;
    final opacity = !visible
        ? 0.0
        : isAnimating && isActive
            ? progress
            : isAnimating && isOutgoing
                ? 1.0 - progress
                : 1.0;
    final translation = !visible || !isAnimating
        ? Offset.zero
        : isActive
            ? Offset(direction * 0.12 * (1 - progress), 0)
            : Offset(-direction * 0.06 * progress, 0);

    return TickerMode(
      enabled: visible,
      child: Offstage(
        offstage: !visible,
        child: IgnorePointer(
          ignoring: !isActive || isAnimating,
          child: Opacity(
            opacity: opacity,
            child: FractionalTranslation(
              translation: translation,
              child: child,
            ),
          ),
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
