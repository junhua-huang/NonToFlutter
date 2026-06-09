import 'dart:async';

import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/notification.dart' as app_notif;
import 'package:facebook_clone/providers/core_providers.dart';
import 'package:facebook_clone/providers/notifications_notifier.dart';
import 'package:facebook_clone/screens/chat/chat_room_screen.dart';
import 'package:facebook_clone/screens/friends/friend_requests_screen.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class NotificationsTab extends ConsumerStatefulWidget {
  const NotificationsTab({super.key});
  @override
  ConsumerState<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends ConsumerState<NotificationsTab> {
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);
  bool _showReadNotifications = false;

  @override
  void initState() {
    super.initState();
    // 二级兜底：如果 15s 后仍在 initialLoading，强制标记失败
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        final state = ref.read(notificationsProvider);
        if (state.isInitialLoading && state.notifications.isEmpty) {
          ref.read(notificationsProvider.notifier)
              .loadNotifications(refresh: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  List<app_notif.AppNotification> _unread(
          List<app_notif.AppNotification> list) =>
      list.where((n) => n.isRead == false).toList();

  List<app_notif.AppNotification> _read(
          List<app_notif.AppNotification> list) =>
      list.where((n) => n.isRead == true).toList();

  Future<void> _refresh() async {
    await ref.read(notificationsProvider.notifier).loadNotifications(refresh: true);
    _refreshController.refreshCompleted();
    NotificationService().markAllRead();
  }

  Future<void> _loadMore() async {
    await ref.read(notificationsProvider.notifier).loadNotifications();
    _refreshController.loadComplete();
  }

  Future<void> _markRead(int id) async {
    try { await NotificationService().markRead(id); } catch (_) {}
  }

  void _onNotificationTap(app_notif.AppNotification n) {
    if (n.isRead == false) _markRead(n.id);
    switch (n.parsedType) {
      case app_notif.NotificationType.like:
      case app_notif.NotificationType.comment:
      case app_notif.NotificationType.mention:
        if (n.relatedId != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: n.relatedId!),
          ));
        }
        break;
      case app_notif.NotificationType.friendRequest:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const FriendRequestsScreen(),
        ));
        break;
      case app_notif.NotificationType.friendAccept:
        if (n.senderId != null) {
          _startChatFromNotification(n.senderId!);
        }
        break;
      case app_notif.NotificationType.message:
        if (n.sender != null) {
          final conversation = Conversation(
            id: 0,
            user1Id: n.userId,
            user2Id: n.senderId,
            otherUser: n.sender!,
            unreadCount: 0,
            lastMessageAt: n.createdAt,
          );
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatRoomScreen(conversation: conversation),
          ));
        }
        break;
    }
  }

  Future<void> _startChatFromNotification(int otherUserId) async {
    try {
      final resp = await ChatService().getOrCreateConversation(otherUserId);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final convJson = data['conversation'] ?? data;
        final conversation =
            Conversation.fromJson(convJson as Map<String, dynamic>);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatRoomScreen(conversation: conversation),
        ));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(resp.message ?? '无法打开聊天'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('打开聊天失败'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildNotificationTile(app_notif.AppNotification n) {
    return _NotificationTile(
      notification: n,
      icon: _iconForType(n.parsedType),
      iconColor: _colorForType(n.parsedType),
      isUnread: n.isRead == false,
      onTap: () => _onNotificationTap(n),
    );
  }

  IconData _iconForType(app_notif.NotificationType type) {
    switch (type) {
      case app_notif.NotificationType.like: return Icons.favorite;
      case app_notif.NotificationType.comment: return Icons.chat_bubble;
      case app_notif.NotificationType.mention: return Icons.alternate_email;
      case app_notif.NotificationType.friendRequest: return Icons.person_add;
      case app_notif.NotificationType.friendAccept: return Icons.people;
      case app_notif.NotificationType.message: return Icons.mail;
    }
  }

  Color _colorForType(app_notif.NotificationType type) {
    switch (type) {
      case app_notif.NotificationType.like: return AppColors.likeRed;
      case app_notif.NotificationType.comment:
      case app_notif.NotificationType.mention: return AppColors.primary;
      case app_notif.NotificationType.friendRequest:
      case app_notif.NotificationType.friendAccept:
        return const Color(0xFF00BA7C);
      case app_notif.NotificationType.message: return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final barVisible = ref.watch(barVisibleProvider);
    final unread = _unread(state.notifications);
    final read = _read(state.notifications);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
            kToolbarHeight + MediaQuery.of(context).padding.top + 0.5),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          offset: barVisible ? Offset.zero : const Offset(0, -1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: barVisible
                ? (kToolbarHeight + MediaQuery.of(context).padding.top + 0.5)
                : 0,
            child: barVisible
                ? AppBar(
                    backgroundColor: AppColors.background,
                    elevation: 0,
                    surfaceTintColor: Colors.transparent,
                    centerTitle: false,
                    title: const Text('通知',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(0.5),
                      child:
                          Container(height: 0.5, color: AppColors.borderLight),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
      body: SmartRefresher(
        controller: _refreshController,
        enablePullDown: true,
        enablePullUp: state.hasMore,
        onRefresh: _refresh,
        onLoading: _loadMore,
        child: state.isInitialLoading && state.notifications.isEmpty
            ? const NotificationSkeleton()
            : state.error != null && state.notifications.isEmpty
                ? ErrorStateWidget(
                    message: state.error!,
                    onRetry: _refresh,
                  )
                : state.notifications.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.notifications_none,
                        title: '暂无通知',
                        subtitle: '当有人与你互动时会出现在这里',
                      )
                    : ListView(
                        children: [
                          ...unread.map(_buildNotificationTile),
                          if (read.isNotEmpty) ...[
                            InkWell(
                              onTap: () => setState(() =>
                                  _showReadNotifications =
                                      !_showReadNotifications),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                color: AppColors.surface,
                                child: Row(
                                  children: [
                                    Text(
                                      '已读通知 (${read.length})',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary),
                                    ),
                                    const Spacer(),
                                    AnimatedRotation(
                                      turns: _showReadNotifications ? 0.5 : 0,
                                      duration:
                                          const Duration(milliseconds: 250),
                                      child: const Icon(Icons.expand_more,
                                          color: AppColors.textSecondary,
                                          size: 20),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: _showReadNotifications
                                  ? Column(
                                      children: read.map(_buildNotificationTile).toList())
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final app_notif.AppNotification notification;
  final IconData icon;
  final Color iconColor;
  final bool isUnread;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.iconColor,
    required this.isUnread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread ? AppColors.surface : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            ImageUtils.buildAvatar(notification.sender, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textPrimary),
                      children: [
                        TextSpan(
                          text: notification.sender?.displayName ?? '未知用户',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' ${notification.title ?? ''}'),
                      ],
                    ),
                  ),
                  if (notification.content != null &&
                      notification.content!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(notification.content!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                  const SizedBox(height: 4),
                  Text(AppDateUtils.formatTimeAgo(notification.createdAt),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (isUnread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 8, top: 4),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
