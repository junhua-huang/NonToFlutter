import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/screens/chat/chat_room_screen.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/screens/notifications/notifications_tab.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

/// 统一消息页：顶部通知入口 + 聊天会话列表
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final RefreshController _refreshController = RefreshController();
  final ChatService _chatService = ChatService();
  final NotificationService _notifService = NotificationService();

  List<Conversation> _conversations = [];
  int _unreadNotifications = 0;
  bool _isLoading = true;
  String? _error;
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    TabActivationNotifier.currentTab.addListener(_onTabActivated);
    if (TabActivationNotifier.currentTab.value == 2) {
      _activate();
    }
  }

  @override
  void dispose() {
    TabActivationNotifier.currentTab.removeListener(_onTabActivated);
    _refreshController.dispose();
    super.dispose();
  }

  void _onTabActivated() {
    if (!_activated && TabActivationNotifier.currentTab.value == 2) {
      _activate();
    }
  }

  void _activate() {
    _activated = true;
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _fetchUnreadNotifications(),
        _fetchConversations(),
      ]);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载失败，下拉重试';
        });
      }
    }
  }

  Future<void> _fetchUnreadNotifications() async {
    try {
      final resp = await _notifService.getUnreadCount();
      if (resp.success && resp.data != null && mounted) {
        final data = resp.data;
        int count = 0;
        if (data is Map) {
          count = data['count'] ?? data['unread_count'] ?? 0;
        } else if (data is int) {
          count = data;
        }
        setState(() => _unreadNotifications = count);
      }
    } catch (_) {}
  }

  Future<void> _fetchConversations() async {
    try {
      final resp = await _chatService.getConversations();
      if (!resp.success || resp.data == null) {
        if (_conversations.isEmpty) {
          setState(() => _error = '加载会话失败');
        }
        return;
      }

      final data = resp.data;
      final List<dynamic> list;
      if (data is Map) {
        list = (data['conversations'] as List?) ?? (data['data'] as List?) ?? [];
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }

      if (mounted) {
        setState(() {
          _conversations = list
              .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      if (_conversations.isEmpty && mounted) {
        setState(() => _error = '加载会话失败');
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadAll();
    _refreshController.refreshCompleted();
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsTab()),
    ).then((_) => _fetchUnreadNotifications());
  }

  void _openConversation(Conversation conv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(conversation: conv),
      ),
    ).then((_) => _loadAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight + MediaQuery.of(context).padding.top),
        child: ValueListenableBuilder<bool>(
          valueListenable: HomeScreen.barVisible,
          builder: (_, visible, child) {
            return AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: visible ? Offset.zero : const Offset(0, -1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: visible ? (kToolbarHeight + MediaQuery.of(context).padding.top) : 0,
                child: visible ? child! : const SizedBox.shrink(),
              ),
            );
          },
          child: AppBar(
            title: const Text(
              '消息',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            elevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
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
        onRefresh: _onRefresh,
        header: const WaterDropHeader(
          complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
          waterDropColor: AppColors.primary,
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null && _conversations.isEmpty
                ? _buildErrorState()
                : _buildContent(),
      ),
        ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadAll, child: const Text('重试')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildNotificationEntry(),
        const Divider(height: 1, indent: 72),
        if (_conversations.isEmpty)
          _buildEmptyConversations()
        else
          ..._conversations.map((conv) => _buildConversationItem(conv)),
      ],
    );
  }

  Widget _buildNotificationEntry() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openNotifications,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(Radius.circular(24)),
                ),
                child: const Icon(Icons.notifications_outlined, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '通知消息',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        if (_unreadNotifications > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.likeRed,
                              borderRadius: BorderRadius.all(Radius.circular(10)),
                            ),
                            child: Text(
                              _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点赞、评论、好友请求等通知',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationItem(Conversation conv) {
    final hasUnread = conv.unreadCount > 0;
    final otherUser = conv.otherUser;
    final userName = otherUser?.displayName ?? otherUser?.username ?? '未知用户';
    final avatarUrl = otherUser?.avatarUrl;
    final lastMsgObj = conv.lastMessage;
    final lastMsgText = lastMsgObj?.content ?? '';

    return Material(
      color: hasUnread ? AppColors.primary.withValues(alpha: 0.03) : Colors.transparent,
      child: InkWell(
        onTap: () => _openConversation(conv),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 18),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            userName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conv.lastMessageAt != null)
                          Text(
                            _formatTime(conv.lastMessageAt!),
                            style: TextStyle(
                              fontSize: 12,
                              color: hasUnread ? AppColors.primary : AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMsgText.isEmpty ? '暂无消息' : lastMsgText,
                            style: TextStyle(
                              fontSize: 14,
                              color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: AppColors.likeRed,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                conv.unreadCount > 99 ? '99' : '${conv.unreadCount}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyConversations() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('暂无聊天消息', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            SizedBox(height: 4),
            Text('开始和好友聊天吧', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}
