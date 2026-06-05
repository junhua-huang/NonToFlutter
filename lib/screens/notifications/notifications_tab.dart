import 'dart:async';

import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/models/notification.dart' as app_notif;
import 'package:facebook_clone/screens/chat/chat_room_screen.dart';
import 'package:facebook_clone/screens/friends/friend_requests_screen.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});
  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final List<app_notif.AppNotification> _notifications = [];
  final WebSocketService _wsService = WebSocketService();
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _notifSubscription;
  bool _showReadNotifications = false;

  @override
  void initState() {
    super.initState();
    _setupWebSocket();
    _loadNotifications(); // Initial load
  }

  void _setupWebSocket() {
    _wsService.connect();
    _notifSubscription = _wsService.notificationStream.listen((data) {
      try {
        final notif = app_notif.AppNotification.fromJson(data);
        setState(() {
          _notifications.insert(0, notif);
        });
      } catch (e) {
        debugPrint('WS notification parse error: $e');
      }
    });
  }

  List<app_notif.AppNotification> get _unreadNotifications =>
      _notifications.where((n) => n.isRead == false).toList();
  
  List<app_notif.AppNotification> get _readNotifications =>
      _notifications.where((n) => n.isRead == true).toList();

  @override
  void dispose() {
    _notifSubscription?.cancel();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      final resp = await NotificationService().getNotifications(page: _page);
      if (resp.success && resp.data != null) {
        final data = resp.data;
        List items;
        if (data is Map) {
          items = data['notifications'] ?? data['items'] ?? [];
        } else if (data is List) {
          items = data;
        } else {
          items = [];
        }
        final notifs = items.map((e) => app_notif.AppNotification.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          if (_page == 1) _notifications.clear();
          _notifications.addAll(notifs);
          _hasMore = data is Map ? data['has_more'] == true : notifs.length >= 20;
          _page++;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      debugPrint('Notifications load error: $e');
      if (mounted) setState(() => _error = '加载失败，请下拉重试');
    } finally {
      _isLoading = false;
      _refreshController.loadComplete();
    }
  }

  Future<void> _refresh() async {
    _page = 1;
    _hasMore = true;
    _error = null;
    await _loadNotifications();
    _refreshController.refreshCompleted();
    NotificationService().markAllRead();
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
        // 好友申请被通过 → 跳转到对应聊天页面
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatRoomScreen(conversation: conversation),
            ),
          );
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
        final conversation = Conversation.fromJson(convJson as Map<String, dynamic>);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatRoomScreen(conversation: conversation),
        ));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '无法打开聊天'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打开聊天失败'), backgroundColor: Colors.red),
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
      case app_notif.NotificationType.like:
        return Icons.favorite;
      case app_notif.NotificationType.comment:
        return Icons.chat_bubble;
      case app_notif.NotificationType.mention:
        return Icons.alternate_email;
      case app_notif.NotificationType.friendRequest:
        return Icons.person_add;
      case app_notif.NotificationType.friendAccept:
        return Icons.people;
      case app_notif.NotificationType.message:
        return Icons.mail;
    }
  }

  Color _colorForType(app_notif.NotificationType type) {
    switch (type) {
      case app_notif.NotificationType.like:
        return AppColors.likeRed;
      case app_notif.NotificationType.comment:
      case app_notif.NotificationType.mention:
        return AppColors.primary;
      case app_notif.NotificationType.friendRequest:
      case app_notif.NotificationType.friendAccept:
        return const Color(0xFF00BA7C);
      case app_notif.NotificationType.message:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight + MediaQuery.of(context).padding.top + 0.5),
        child: ValueListenableBuilder<bool>(
          valueListenable: HomeScreen.barVisible,
          builder: (_, visible, child) {
            return AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: visible ? Offset.zero : const Offset(0, -1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: visible ? (kToolbarHeight + MediaQuery.of(context).padding.top + 0.5) : 0,
                child: visible ? child! : const SizedBox.shrink(),
              ),
            );
          },
          child: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            title: const Text('通知', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Container(height: 0.5, color: AppColors.borderLight),
            ),
          ),
        ),
      ),
      body: NotificationListener<ScrollUpdateNotification>(
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
        child: SmartRefresher(
        controller: _refreshController,
        enablePullDown: true,
        enablePullUp: _hasMore,
        onRefresh: _refresh,
        onLoading: _loadNotifications,
        child: _error != null
            ? ErrorStateWidget(
                message: _error!,
                onRetry: () {
                  setState(() { _error = null; _page = 1; _hasMore = true; });
                  _loadNotifications();
                },
              )
            : _isLoading && _notifications.isEmpty
            ? const NotificationSkeleton()
            : _notifications.isEmpty
            ? const EmptyStateWidget(
                icon: Icons.notifications_none,
                title: '暂无通知',
                subtitle: '当有人与你互动时会出现在这里',
              )
            : ListView(
                children: [
                  // 未读通知
                  ..._unreadNotifications.map((n) => _buildNotificationTile(n)),
                  // 已读通知（可折叠，带动画）
                  if (_readNotifications.isNotEmpty) ...[
                    InkWell(
                      onTap: () => setState(() => _showReadNotifications = !_showReadNotifications),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        color: AppColors.surface,
                        child: Row(
                          children: [
                            Text(
                              '已读通知 (${_readNotifications.length})',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            ),
                            const Spacer(),
                            AnimatedRotation(
                              turns: _showReadNotifications ? 0.5 : 0,
                              duration: const Duration(milliseconds: 250),
                              child: const Icon(
                                Icons.expand_more,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
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
                          ? Column(children: _readNotifications.map((n) => _buildNotificationTile(n)).toList())
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
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
            // Icon badge
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
            // Avatar
            ImageUtils.buildAvatar(notification.sender, radius: 20),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
                      children: [
                        TextSpan(
                          text: notification.sender?.displayName ?? '未知用户',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' ${notification.title ?? ''}'),
                      ],
                    ),
                  ),
                  if (notification.content != null && notification.content!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notification.content!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    AppDateUtils.formatTimeAgo(notification.createdAt),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Unread dot
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
