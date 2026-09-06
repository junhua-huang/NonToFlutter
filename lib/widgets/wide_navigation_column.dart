import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/config/layout_breakpoints.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/utils/image_utils.dart';

class WideNavigationMenuIds {
  WideNavigationMenuIds._();

  static const editProfile = 'edit-profile';
  static const friendRequests = 'friend-requests';
  static const identityCenter = 'identity-center';
  static const topics = 'topics';
  static const communities = 'communities';
  static const comicTimeline = 'comic-timeline';
  static const myComics = 'my-comics';
  static const settings = 'settings';
}

class WideNavigationMenuItem {
  final String id;
  final String label;
  final IconData icon;
  final bool usesFriendRequestBadge;

  const WideNavigationMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.usesFriendRequestBadge = false,
  });
}

/// Persistent two-column shell navigation used on wide screens.
class WideNavigationColumn extends StatelessWidget {
  final int currentIndex;
  final int totalBadge;
  final int friendRequestBadge;
  final User? user;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<String> onMenuSelected;
  final VoidCallback onCompose;
  final VoidCallback onUserTap;
  final VoidCallback onLogout;
  final List<WideNavigationMenuItem> menuItems;

  const WideNavigationColumn({
    super.key,
    required this.currentIndex,
    required this.totalBadge,
    this.friendRequestBadge = 0,
    required this.user,
    required this.onTabSelected,
    required this.onMenuSelected,
    required this.onCompose,
    required this.onUserTap,
    required this.onLogout,
    this.menuItems = const [],
  });

  static const _navigationItems = [
    (
      label: '首页',
      asset: 'assets/icons/未选中首页.svg',
      activeAsset: 'assets/icons/选中首页.svg',
    ),
    (
      label: '发现',
      asset: 'assets/icons/未选中搜索.svg',
      activeAsset: 'assets/icons/选中搜索.svg',
    ),
    (
      label: '消息',
      asset: 'assets/icons/未选中消息.svg',
      activeAsset: 'assets/icons/选中消息.svg',
    ),
    (
      label: '我的',
      asset: 'assets/icons/未选中个人.svg',
      activeAsset: 'assets/icons/选中个人.svg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppBreakpoints.navigationWidth,
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'nonto',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ...List.generate(
                        _navigationItems.length,
                        (index) => _buildNavigationItem(index),
                      ),
                      if (menuItems.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Divider(height: 1, color: AppColors.borderLight),
                        const SizedBox(height: 12),
                        ...menuItems.map(_buildMenuItem),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildLogoutButton(),
                const SizedBox(height: 8),
                _buildComposeButton(),
                const SizedBox(height: 12),
                Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 12),
                _buildUserEntry(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationItem(int index) {
    final item = _navigationItems[index];
    final selected = currentIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Material(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('wide_navigation_$index'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onTabSelected(index),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _buildIcon(
                      asset: selected ? item.activeAsset : item.asset,
                      selected: selected,
                      showBadge: index == 2,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      item.label,
                      style: TextStyle(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(WideNavigationMenuItem item) {
    final badge = item.usesFriendRequestBadge ? friendRequestBadge : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        label: item.label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('wide_menu_${item.id}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onMenuSelected(item.id),
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(item.icon, size: 21, color: AppColors.textSecondary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (badge > 0)
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.likeRed,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _formatBadgeCount(badge),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon({
    required String asset,
    required bool selected,
    required bool showBadge,
  }) {
    final icon = SvgPicture.asset(
      asset,
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(
        selected ? AppColors.primary : AppColors.textSecondary,
        BlendMode.srcIn,
      ),
    );

    if (!showBadge || totalBadge <= 0) return icon;

    return Badge(
      backgroundColor: AppColors.unreadBadge,
      textColor: Colors.white,
      label: Text(_formatBadgeCount(totalBadge)),
      child: icon,
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      height: 42,
      child: TextButton.icon(
        key: const ValueKey('wide_navigation_logout'),
        onPressed: onLogout,
        icon: const Icon(Icons.logout, size: 19),
        label: const Align(
          alignment: Alignment.centerLeft,
          child: Text('退出登录'),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.likeRed,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildComposeButton() {
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        key: const ValueKey('wide_navigation_compose'),
        onPressed: onCompose,
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('发布'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildUserEntry() {
    final displayName = user?.displayName ?? user?.username ?? '用户';
    final username = user?.username ?? 'user';

    return Semantics(
      button: true,
      label: '打开我的主页',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const ValueKey('wide_navigation_user'),
          borderRadius: BorderRadius.circular(10),
          onTap: onUserTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                ImageUtils.buildAvatar(user, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_horiz, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBadgeCount(int count) => count > 99 ? '99+' : '$count';
}
