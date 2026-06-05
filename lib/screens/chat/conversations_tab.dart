import 'dart:convert';

import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/conversation.dart';
import 'package:facebook_clone/screens/chat/chat_room_screen.dart';
import 'package:facebook_clone/services/api/chat_service.dart';
import 'package:facebook_clone/services/local_db_service.dart';
import 'package:facebook_clone/utils/date_utils.dart';
import 'package:facebook_clone/utils/image_utils.dart';
import 'package:facebook_clone/widgets/empty_state_widget.dart';
import 'package:facebook_clone/widgets/error_state_widget.dart';
import 'package:facebook_clone/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class ConversationsTab extends StatefulWidget {
  const ConversationsTab({super.key});

  @override
  State<ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<ConversationsTab> {
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final ChatService _chatService = ChatService();

  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  // Use AppColors from app_theme.dart

  @override
  void initState() {
    super.initState();
    _loadLocalConversations();
  }

  Future<void> _loadLocalConversations() async {
    final localConvs = await LocalDbService().getConversations();
    if (localConvs.isNotEmpty && mounted) {
      setState(() {
        _conversations = localConvs;
        _isLoading = false;
      });
    }
    await _loadConversations();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final response = await _chatService.getConversations();

      if (response.success && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        final List<dynamic> conversationList;
        if (data is Map<String, dynamic>) {
          conversationList = data['conversations'] ?? [];
        } else if (data is List) {
          conversationList = data;
        } else {
          conversationList = [];
        }

        final conversations =
            conversationList.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
        // Save to local DB
        await LocalDbService().insertConversations(conversations);
      } else {
        setState(() {
          _error = response.message ?? '加载失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '网络错误，请稍后重试';
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadConversations();
    _refreshController.refreshCompleted();
  }

  String _getMessagePreview(Conversation conversation) {
    final msg = conversation.lastMessage;
    if (msg == null) return '暂无消息';

    switch (msg.messageType.name) {
      case 'image':
        return '🖼 图片';
      case 'video':
        return '🎬 视频';
      case 'file':
        return '📎 文件';
      case 'post':
        return '📌 帖子';
      case 'comment':
        return '💬 评论';
      default:
        final text = msg.content ?? '';
        if (text.length > 30) return '${text.substring(0, 30)}...';
        return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '消息',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.borderLight,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const ConversationSkeleton();
    }

    if (_error != null) {
      return ErrorStateWidget(
        message: _error!,
        onRetry: _loadConversations,
      );
    }

    if (_conversations.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.chat_bubble_outline,
        title: '暂无消息',
        subtitle: '当你发起或收到消息时会显示在这里',
      );
    }

    return SmartRefresher(
      controller: _refreshController,
      enablePullDown: true,
      enablePullUp: false,
      onRefresh: _onRefresh,
      header: const WaterDropHeader(
        complete: Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      child: ListView.separated(
        itemCount: _conversations.length,
        separatorBuilder: (_, __) => const Divider(
          height: 0.5,
          indent: 80,
          endIndent: 16,
          color: AppColors.borderLight,
        ),
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          return _ConversationTile(
            conversation: conversation,
            messagePreview: _getMessagePreview(conversation),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(conversation: conversation),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String messagePreview;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.messagePreview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = conversation.otherUser;
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            ImageUtils.buildAvatar(user, radius: 24),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: name + time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          user?.displayName ?? '未知用户',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: hasUnread ? FontWeight.w900 : FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppDateUtils.formatTimeAgo(
                          conversation.lastMessage?.createdAt ?? conversation.lastMessageAt,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: hasUnread ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  // Bottom row: username + message preview + unread badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          '@${user?.username ?? ''} · $messagePreview',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 20),
                          child: Center(
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : conversation.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
