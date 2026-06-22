import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/chat_room_state.dart';
import 'package:nonto/providers/core_providers.dart';
import 'package:nonto/screens/chat/chat_room_screen.dart';
import 'package:nonto/screens/community/community_chat_screen.dart';
import 'package:nonto/screens/notifications/notifications_tab.dart';
import 'package:nonto/services/api/notification_service.dart';
import 'package:nonto/services/cache_keys.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/local_db_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_tile.dart';
import 'package:nonto/widgets/nonto_header_search_bar.dart';
import 'package:nonto/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';
import 'package:nonto/utils/bar_scroll_handler.dart';

/// 统一消息页：顶部通知入口 + 聊天会话列表
class MessagesTab extends ConsumerStatefulWidget {
  const MessagesTab({super.key});

  /// 已迁移到 [ChatRoomState.currentChatRoomConvId]。
  /// 保留此 getter 仅为向后兼容（部分旧代码可能仍读 MessagesTab.currentChatRoomConvId）。
  static String? get currentChatRoomConvId =>
      ChatRoomState.currentChatRoomConvId;
  static set currentChatRoomConvId(String? v) =>
      ChatRoomState.currentChatRoomConvId = v;

  @override
  ConsumerState<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends ConsumerState<MessagesTab> {
  final RefreshController _refreshController = RefreshController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final WebSocketService _wsService = WebSocketService();
  final NotificationService _notifService = NotificationService();

  int _unreadNotifications = 0;
  String _searchQuery = '';

  StreamSubscription? _wsNotifSub;

  @override
  void initState() {
    super.initState();
    _wsNotifSub = _wsService.notificationStream.listen(_onWsNotification);
    _fetchUnreadNotifications();
    // 每次进入消息 Tab 主动刷新会话列表（网络）。
    // 覆盖「好友被通过但 WS 推送（friend_accepted_chat）未到达」的场景——
    // 发起方 A 的会话创建原本完全依赖 WS 推送，A 若 WS 未连上就看不到新会话，
    // 直到手动下拉。这里在进入 Tab 时静默刷新，保证会话列表始终最新。
    Future.microtask(
        () => ref.read(conversationsProvider.notifier).loadConversations());
    // 从闪屏/登录进入主页后，只预热最近少量会话，避免拖慢消息页首屏。
    _preloadRecentChatMessages();
  }

  /// 预加载最近少量会话的最近一页聊天记录
  void _preloadRecentChatMessages() {
    final auth = ref.read(authProvider);
    final userId = auth.user?.id.toString();
    if (userId == null) return;
    // 延迟一帧，避免阻塞 UI 首次渲染
    Future.microtask(
        () => LocalDbService().preloadRecentConversationMessages());
  }

  @override
  void dispose() {
    _wsNotifSub?.cancel();
    _refreshController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onWsNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    final event = data['event'] as String?;
    if (event == 'new_notification' || event == 'notifications_read') {
      final val = data['unread_count'];
      final count = val is int ? val : (val is double ? val.toInt() : 0);
      setState(() => _unreadNotifications = count);
    }
  }

  Future<void> _fetchUnreadNotifications() async {
    try {
      final result = await DataLayer().query(
        CacheKeys.notifUnreadCount,
        () => _notifService.getUnreadCount(),
      );
      if (!mounted) return;
      final data = result.data;
      int count = 0;
      if (data is int) {
        count = data;
      } else if (data is Map) {
        count = data['count'] ?? data['unread_count'] ?? 0;
      }
      setState(() => _unreadNotifications = count);
    } catch (_) {}
  }

  Future<void> _onRefresh() async {
    await ref.read(conversationsProvider.notifier).loadConversations();
    _fetchUnreadNotifications();
    // 会话列表非空时才批量预取聊天记录
    final convs = ref.read(conversationsProvider).conversations;
    if (convs.isNotEmpty) {
      LocalDbService().preloadRecentConversationMessages().catchError((_) {});
    }
    _refreshController.refreshCompleted();
  }

  void _openNotifications() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const NotificationsTab()));
  }

  Future<void> _openConversation(Conversation conv) async {
    if (conv.isCommunity && conv.communityId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommunityChatScreen(
            communityId: conv.communityId!,
            communityName: conv.communityName,
          ),
        ),
      );
      if (mounted) {
        await ref.read(conversationsProvider.notifier).loadConversations();
      }
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatRoomScreen(conversation: conv)),
    );
    if (mounted) {
      await ref.read(conversationsProvider.notifier).loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeScaffoldContext = context;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
            kToolbarHeight + MediaQuery.of(context).padding.top),
        child: Consumer(
          builder: (context, ref, _) {
            final barVisible = ref.watch(barVisibleProvider);
            return AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: barVisible ? Offset.zero : const Offset(0, -1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: barVisible
                    ? (kToolbarHeight + MediaQuery.of(context).padding.top)
                    : 0,
                child: barVisible
                    ? Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: NontoHeaderSearchBar(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          user: ref.watch(authProvider).user,
                          hintText: '搜索会话',
                          onAvatarTap: () =>
                              Scaffold.of(homeScaffoldContext).openDrawer(),
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.close,
                                      size: 18, color: AppColors.textSecondary),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _searchFocusNode.unfocus(),
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notif) {
            handleBarScrollNotification(notif, ref);
            return false;
          },
          child: Consumer(
            builder: (context, ref, _) {
              final convState = ref.watch(conversationsProvider);
              final conversations = convState.conversations;
              return SmartRefresher(
                controller: _refreshController,
                enablePullDown: true,
                onRefresh: _onRefresh,
                header: const WaterDropHeader(
                  complete:
                      Text('刷新成功', style: TextStyle(color: AppColors.primary)),
                  waterDropColor: AppColors.primary,
                ),
                child: convState.isLoading && conversations.isEmpty
                    ? const ConversationSkeleton()
                    : convState.error != null && conversations.isEmpty
                        ? _buildError(convState.error!)
                        : _buildContent(conversations),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildError(String error) {
    return ListView(children: [
      const SizedBox(height: 120),
      Center(
        child: Column(children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(error,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _onRefresh, child: const Text('重试')),
        ]),
      ),
    ]);
  }

  Widget _buildContent(List<Conversation> conversations) {
    final visibleConversations =
        filterNontoConversations(conversations, _searchQuery);
    final showEmpty = conversations.isEmpty;
    final showSearchEmpty =
        conversations.isNotEmpty && visibleConversations.isEmpty;
    final itemCount =
        2 + (showEmpty || showSearchEmpty ? 1 : visibleConversations.length);

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) return _buildNotificationEntry();
        if (index == 1) return const Divider(height: 1, indent: 72);

        if (showEmpty) return _buildEmpty();
        if (showSearchEmpty) return _buildSearchEmpty();

        final conversation = visibleConversations[index - 2];
        return NontoConversationTile(
          conversation: conversation,
          onTap: () => _openConversation(conversation),
        );
      },
    );
  }

  Widget _buildNotificationEntry() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openNotifications,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.all(Radius.circular(24)),
              ),
              child: const Icon(Icons.notifications_outlined,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('通知消息',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      if (_unreadNotifications > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: const BoxDecoration(
                            color: AppColors.likeRed,
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          child: Text(
                            _unreadNotifications > 99
                                ? '99+'
                                : '$_unreadNotifications',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text('点赞、评论、好友请求等通知',
                        style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.8))),
                  ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchEmpty() {
    return Padding(
      padding: EdgeInsets.only(top: 72),
      child: Center(
        child: Column(children: [
          Icon(Icons.search_off, size: 44, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('没有找到相关会话',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          SizedBox(height: 4),
          Text('换个关键词试试',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: Column(children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('暂无会话',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          SizedBox(height: 4),
          Text('开始和好友聊天吧',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        ]),
      ),
    );
  }
}
