import 'dart:async';

import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

class HomeScreen extends StatefulWidget {
  final int? initialTab;

  /// Global notifier for bottom bar + tab AppBar visibility.
  /// Tabs listen to this via ValueListenableBuilder to animate their AppBars.
  /// Tab scroll-notifications toggle this value.
  static final ValueNotifier<bool> barVisible = ValueNotifier(true);

  const HomeScreen({super.key, this.initialTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  int _unreadNotifications = 0;
  int _unreadMessages = 0;
  StreamSubscription? _notifSubscription;
  StreamSubscription? _msgSubscription;

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
      _currentIndex = widget.initialTab!;
    }
    TabActivationNotifier.currentTab.value = _currentIndex;
    // Defer WebSocket & API to post-frame so first paint is not blocked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectWebSocket();
      _fetchInitialCounts();
    });
  }

  void _connectWebSocket() {
    WebSocketService().connect();
    // 实时通知事件：直接提取 unread_count
    _notifSubscription = WebSocketService().notificationStream.listen((data) {
      final type = data['type'] as String?;
      if (type == 'new_notification' || type == 'notifications_read') {
        final count = _extractInt(data, 'unread_count');
        if (mounted) setState(() => _unreadNotifications = count);
      }
    });
    // 实时消息事件：直接提取 unread_count
    _msgSubscription = WebSocketService().messageStream.listen((data) {
      final type = data['type'] as String?;
      if (type == 'new_message' || type == 'conversation_read') {
        final count = _extractInt(data, 'unread_count');
        if (mounted) setState(() => _unreadMessages = count);
      }
    });
  }

  int _extractInt(Map<String, dynamic> data, String key) {
    final val = data[key];
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  Future<void> _fetchInitialCounts() async {
    // Parallelize both API calls to reduce blocking time
    await Future.wait([
      _fetchNotifCount(),
      _fetchMsgCount(),
    ], eagerError: true);
  }

  Future<void> _fetchNotifCount() async {
    try {
      final notifResp = await NotificationService().getUnreadCount();
      if (notifResp.success && notifResp.data != null) {
        final data = notifResp.data;
        int count = 0;
        if (data is Map) {
          count = data['count'] ?? data['unread_count'] ?? 0;
        } else if (data is int) {
          count = data;
        }
        if (mounted) setState(() => _unreadNotifications = count);
      }
    } catch (_) {}
  }

  Future<void> _fetchMsgCount() async {
    try {
      final msgResp = await ChatService().getUnreadCount();
      if (msgResp.success && msgResp.data != null) {
        final data = msgResp.data;
        int count = 0;
        if (data is Map) {
          count = data['count'] ?? data['unread_count'] ?? 0;
        } else if (data is int) {
          count = data;
        }
        if (mounted) setState(() => _unreadMessages = count);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    _msgSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      drawer: _buildDrawer(context, auth),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
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
            )
          : null,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: HomeScreen.barVisible,
        builder: (_, visible, child) {
          return AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            offset: visible ? Offset.zero : const Offset(0, 1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: visible ? 1.0 : 0.0,
              child: child,
            ),
          );
        },
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            TabActivationNotifier.currentTab.value = i;
            // Clear badge when visiting messages tab
            if (i == 2) {
              setState(() {
                _unreadNotifications = 0;
                _unreadMessages = 0;
              });
            }
          },
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          items: [
            BottomNavigationBarItem(
              icon: _NavScaleIcon(
                icon: Icons.home_outlined,
                isSelected: _currentIndex == 0,
                size: 26,
              ),
              activeIcon: _NavScaleIcon(
                icon: Icons.home,
                isSelected: _currentIndex == 0,
                size: 26,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _NavScaleIcon(
                icon: Icons.search,
                isSelected: _currentIndex == 1,
                size: 26,
              ),
              activeIcon: _NavScaleIcon(
                icon: Icons.search,
                isSelected: _currentIndex == 1,
                size: 26,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _buildBadgeIcon(
                icon: Icons.notifications_none_outlined,
                activeIcon: Icons.notifications,
                count: _unreadNotifications + _unreadMessages,
              ),
              activeIcon: _buildBadgeIcon(
                icon: Icons.notifications,
                activeIcon: Icons.notifications,
                count: _unreadNotifications + _unreadMessages,
                isActive: true,
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: _NavScaleIcon(
                icon: Icons.person_outline,
                isSelected: _currentIndex == 3,
                size: 26,
              ),
              activeIcon: _NavScaleIcon(
                icon: Icons.person,
                isSelected: _currentIndex == 3,
                size: 26,
              ),
              label: '',
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildDrawer(BuildContext context, AuthProvider auth) {
    final user = auth.user;
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
                auth.logout();
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

  Widget _buildAvatar(AuthProvider auth) {
    final url = auth.user?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      final fullUrl = url.startsWith('http') ? url : '${AppConfig.baseUrl.replaceFirst('/api', '')}$url';
      return Image.network(fullUrl, fit: BoxFit.cover,
        errorBuilder: (ctx, err, st) => CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primary,
          child: Text(auth.user?.initials ?? '?',
            style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary,
      child: Text(auth.user?.initials ?? '?',
        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

/// Navigation icon with scale animation when selected
class _NavScaleIcon extends StatefulWidget {
  final IconData icon;
  final bool isSelected;
  final double size;

  const _NavScaleIcon({
    required this.icon,
    required this.isSelected,
    required this.size,
  });

  @override
  State<_NavScaleIcon> createState() => _NavScaleIconState();
}

class _NavScaleIconState extends State<_NavScaleIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isSelected) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_NavScaleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Icon(
        widget.icon,
        size: widget.size,
        color: widget.isSelected ? AppColors.primary : AppColors.textSecondary,
      ),
    );
  }
}
