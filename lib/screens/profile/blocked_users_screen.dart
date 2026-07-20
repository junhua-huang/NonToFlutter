import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/blocking_notifier.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:nonto/widgets/empty_state_widget.dart';
import 'package:nonto/widgets/error_state_widget.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final state = ref.read(blockedUsersProvider);
    if (state.unblockingUserIds.contains(user.id)) return;

    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(blockedUsersProvider.notifier).unblock(user.id);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? '已取消屏蔽 ${user.displayName ?? user.username}'
              : result.error ?? '取消屏蔽失败',
        ),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('已屏蔽用户'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    BlockedUsersState state,
  ) {
    if (state.isLoading && state.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.users.isEmpty) {
      return ErrorStateWidget(
        message: state.error!,
        onRetry: () => ref.read(blockedUsersProvider.notifier).load(),
      );
    }
    if (state.users.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.block_outlined,
        title: '暂无已屏蔽用户',
        subtitle: '你屏蔽的用户会显示在这里',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(blockedUsersProvider.notifier).load(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.users.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 72,
          color: AppColors.borderLight,
        ),
        itemBuilder: (context, index) {
          final user = state.users[index];
          final isUnblocking = state.unblockingUserIds.contains(user.id);
          return ListTile(
            leading: ImageUtils.buildAvatar(user, radius: 22),
            title: Text(
              user.displayName ?? user.username,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '@${user.username}',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            trailing: OutlinedButton(
              onPressed:
                  isUnblocking ? null : () => _unblock(context, ref, user),
              child: isUnblocking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('取消屏蔽'),
            ),
          );
        },
      ),
    );
  }
}
