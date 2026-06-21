import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/utils/date_utils.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/nonto/nonto_conversation_helpers.dart';

class NontoConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const NontoConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    final isCommunity = conversation.isCommunity;
    final hasUnread = conversation.unreadCount > 0;
    final communityName = conversation.communityName?.trim();
    final displayName = other?.displayName?.trim();
    final username = other?.username.trim();
    final name = isCommunity
        ? (communityName != null && communityName.isNotEmpty
            ? communityName
            : '社群群聊')
        : (displayName != null && displayName.isNotEmpty
            ? displayName
            : (username != null && username.isNotEmpty ? username : '未知用户'));

    return Material(
      color: hasUnread
          ? AppColors.primary.withValues(alpha: 0.03)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _buildConversationAvatar(conversation),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.lastMessageAt != null)
                          Text(
                            AppDateUtils.formatTimeAgo(
                                conversation.lastMessageAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: hasUnread
                                  ? AppColors.primary
                                  : AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nontoConversationPreview(conversation),
                            style: TextStyle(
                              fontSize: 14,
                              color: hasUnread
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: conversation.unreadCount),
                        ],
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

  Widget _buildConversationAvatar(Conversation conversation) {
    if (!conversation.isCommunity) {
      return ImageUtils.buildAvatar(conversation.otherUser, radius: 24);
    }

    final avatar = conversation.communityAvatar;
    if (avatar != null && avatar.isNotEmpty) {
      final url = ImageUtils.resolveUrl(conversation.communityAvatar);
      return ImageUtils.buildCircularRemoteImage(
        url,
        radius: 24,
        backgroundColor: AppColors.backgroundSecondary,
        fallback: Icon(
          Icons.groups_3_outlined,
          color: AppColors.textSecondary,
        ),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: const Icon(Icons.groups_3_outlined, color: AppColors.primary),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: AppColors.likeRed,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
