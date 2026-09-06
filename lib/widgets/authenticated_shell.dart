import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/config/layout_breakpoints.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/models/notification.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/screens/comic/comic_my_events_page.dart';
import 'package:nonto/screens/comic/comic_timeline_page.dart';
import 'package:nonto/screens/friends/friend_requests_screen.dart';
import 'package:nonto/screens/post/create_post_screen.dart';
import 'package:nonto/screens/profile/edit_profile_screen.dart';
import 'package:nonto/screens/profile/settings_screen.dart';
import 'package:nonto/screens/topics/my_topics_screen.dart';
import 'package:nonto/screens/community/community_list_screen.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/utils/app_transitions.dart';
import 'package:nonto/widgets/wide_navigation_column.dart';

/// Tracks the root route so the persistent shell can exclude auth/start pages.
class ShellRouteObserver extends NavigatorObserver {
  final ValueNotifier<String?> currentRoute =
      ValueNotifier<String?>(AppRoutes.splash);
  final List<Route<dynamic>> _routes = [];
  int _syncGeneration = 0;

  bool get isPublicRoute {
    final name = currentRoute.value;
    return name == AppRoutes.splash ||
        name == AppRoutes.login ||
        name == AppRoutes.register;
  }

  static const homeRouteNames = <String>{
    AppRoutes.home,
    AppRoutes.search,
    AppRoutes.chat,
    AppRoutes.profile,
  };

  static bool isHomeRouteName(String? name) =>
      name != null && homeRouteNames.contains(name);

  bool get hasHomeRoute =>
      _routes.any((route) => isHomeRouteName(route.settings.name));

  @visibleForTesting
  void resetForTesting() {
    _routes.clear();
    _syncGeneration++;
    currentRoute.value = AppRoutes.splash;
  }

  void _sync() {
    final generation = ++_syncGeneration;
    final routeName =
        _routes.isEmpty ? AppRoutes.splash : _routes.last.settings.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _syncGeneration || currentRoute.value == routeName) {
        return;
      }
      currentRoute.value = routeName;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_routes.contains(route)) _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _routes.remove(oldRoute);
    if (newRoute != null && !_routes.contains(newRoute)) _routes.add(newRoute);
    _sync();
  }
}

final shellRouteObserver = ShellRouteObserver();

/// Makes the horizontal shell state available below the root Navigator.
class WideShellScope extends InheritedWidget {
  final bool isWide;

  const WideShellScope({
    super.key,
    required this.isWide,
    required super.child,
  });

  static bool isWideOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WideShellScope>()?.isWide ??
      false;

  @override
  bool updateShouldNotify(WideShellScope oldWidget) =>
      isWide != oldWidget.isWide;
}

/// Persistent authenticated two-column shell for landscape viewports.
class AuthenticatedShell extends ConsumerWidget {
  final Widget child;

  const AuthenticatedShell({super.key, required this.child});

  NavigatorState? get _navigator => ApiClient.navigatorKey.currentState;

  void _selectTab(WidgetRef ref, int index) {
    final navigator = _navigator;
    if (navigator == null || index < 0 || index > 3) return;

    if (shellRouteObserver.hasHomeRoute) {
      navigator.popUntil(
        (route) => ShellRouteObserver.isHomeRouteName(route.settings.name),
      );
      ref.read(currentTabIndexProvider.notifier).state = index;
      return;
    }

    ref.read(currentTabIndexProvider.notifier).state = index;
    navigator.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
  }

  void _pushPage(Widget page, String routeName) {
    _navigator?.push(
      AppTransitions.slide(
        page: page,
        settings: RouteSettings(name: routeName),
      ),
    );
  }

  void _openCompose() {
    final navigator = _navigator;
    if (navigator == null) return;
    navigator.push(AppTransitions.bottomSheet(page: const CreatePostScreen()));
  }

  void _selectMenu(String id) {
    switch (id) {
      case WideNavigationMenuIds.editProfile:
        _pushPage(const EditProfileScreen(), AppRoutes.editProfile);
        break;
      case WideNavigationMenuIds.friendRequests:
        _pushPage(const FriendRequestsScreen(), AppRoutes.friends);
        break;
      case WideNavigationMenuIds.identityCenter:
        _navigator?.pushNamed(
          AppRoutes.identityCenter,
          arguments: const <String, dynamic>{'wideTransition': true},
        );
        break;
      case WideNavigationMenuIds.topics:
        _pushPage(const MyTopicsScreen(), AppRoutes.topics);
        break;
      case WideNavigationMenuIds.communities:
        _pushPage(const CommunityListScreen(), AppRoutes.communityList);
        break;
      case WideNavigationMenuIds.comicTimeline:
        _pushPage(const ComicTimelinePage(), AppRoutes.comicTimeline);
        break;
      case WideNavigationMenuIds.myComics:
        _pushPage(const ComicMyEventsPage(), AppRoutes.comicMyEvents);
        break;
      case WideNavigationMenuIds.settings:
        _pushPage(const SettingsScreen(), AppRoutes.settings);
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final unreadMessages = ref.watch(unreadMessagesCountProvider);
    final notifications = ref.watch(notificationsProvider).notifications;
    final friendRequests = notifications
        .where((notification) =>
            notification.parsedType == NotificationType.friendRequest &&
            !notification.isRead)
        .length;

    return AnimatedBuilder(
      animation: shellRouteObserver.currentRoute,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = AppBreakpoints.isLandscape(
                  constraints.maxWidth,
                  constraints.maxHeight,
                ) &&
                auth.isLoggedIn &&
                !shellRouteObserver.isPublicRoute;
            final scopedChild = WideShellScope(
              isWide: isWide,
              child: isWide
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppBreakpoints.contentMaxWidth,
                        ),
                        child: SizedBox(width: double.infinity, child: child),
                      ),
                    )
                  : child,
            );

            if (!isWide) return scopedChild;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WideNavigationColumn(
                  currentIndex: ref.watch(currentTabIndexProvider),
                  totalBadge: unreadMessages,
                  friendRequestBadge: friendRequests,
                  user: auth.user,
                  onTabSelected: (index) => _selectTab(ref, index),
                  onCompose: _openCompose,
                  onUserTap: () => _selectTab(ref, 3),
                  menuItems: const [
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.editProfile,
                      label: '编辑个人资料',
                      icon: Icons.edit_outlined,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.friendRequests,
                      label: '好友申请',
                      icon: Icons.person_add_outlined,
                      usesFriendRequestBadge: true,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.identityCenter,
                      label: '我的身份',
                      icon: Icons.verified_outlined,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.topics,
                      label: '我的话题',
                      icon: Icons.tag,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.communities,
                      label: '社群',
                      icon: Icons.groups_outlined,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.comicTimeline,
                      label: '漫展时间线',
                      icon: Icons.event_outlined,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.myComics,
                      label: '我的漫展',
                      icon: Icons.bookmark_border,
                    ),
                    WideNavigationMenuItem(
                      id: WideNavigationMenuIds.settings,
                      label: '设置',
                      icon: Icons.settings_outlined,
                    ),
                  ],
                  onMenuSelected: _selectMenu,
                  onLogout: () => ref.read(authProvider.notifier).logout(),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.borderLight,
                ),
                Expanded(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: scopedChild,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
