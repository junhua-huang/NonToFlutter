import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/screens/chat/chat_room_screen.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';
import 'package:nonto/widgets/shimmer_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pull_to_refresh_flutter3/pull_to_refresh_flutter3.dart';

class ConversationsTab extends ConsumerStatefulWidget {
  const ConversationsTab({super.key});

  @override
  ConsumerState<ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends ConsumerState<ConversationsTab> {
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationsProvider);
    final conversations = state.conversations;

    return SmartRefresher(
      controller: _refreshController,
      enablePullDown: true,
      onRefresh: () async {
        await ref.read(conversationsProvider.notifier).loadConversations();
        _refreshController.refreshCompleted();
      },
      header: const WaterDropHeader(
        complete:
            Text('刷新成功', style: TextStyle(color: AppColors.primary)),
        waterDropColor: AppColors.primary,
      ),
      child: _buildBody(state, conversations),
    );
  }

  Widget _buildBody(ConversationsState state, List<Conversation> conversations) {
    if (state.isLoading) {
      return const ConversationSkeleton();
    }

    if (state.error != null) {
      return ErrorStateWidget(
        message: state.error!,
        onRetry: () =>
            ref.read(conversationsProvider.notifier).loadConversations(),
      );
    }

    if (conversations.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.chat_bubble_outline,
        title: '暂无会话',
        subtitle: '当你发起或收到消息时会显示在这里',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        return _ConversationTile(
          conversation: conv,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatRoomScreen(conversation: conv),
            ),
          ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    final hasUnread = conversation.unreadCount > 0;

    return ListTile(
      onTap: onTap,
      // 之前直接用 NetworkImage(other.avatarUrl)，但后端头像多为相对路径
      // （如 /uploads/...），未经 ImageUtils.resolveUrl 拼接 baseUrl，
      // 导致 NetworkImage 解析成 file:///... 失败，头像永远不显示。
      // 统一走 ImageUtils.buildAvatar：含 resolveUrl + 缓存 + memCacheWidth 限制解码尺寸。
      leading: ImageUtils.buildAvatar(other, radius: 24),
      title: Row(
        children: [
          Expanded(
            child: Text(
              other?.displayName ?? other?.username ?? '未知',
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conversation.lastMessageAt != null)
            Text(
              AppDateUtils.formatTimeAgo(conversation.lastMessageAt),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
      subtitle: Text(
        conversation.lastMessage?.isRecalled == true
            ? '消息已撤回'
            : (conversation.lastMessage?.content ?? '暂无消息'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }
}
