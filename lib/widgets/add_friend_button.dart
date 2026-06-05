import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/services/api/friend_service.dart';
import 'package:flutter/material.dart';

class AddFriendButton extends StatefulWidget {
  final int userId;
  final double height;
  final EdgeInsetsGeometry padding;

  const AddFriendButton({
    super.key,
    required this.userId,
    this.height = 32,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });

  @override
  State<AddFriendButton> createState() => _AddFriendButtonState();
}

class _AddFriendButtonState extends State<AddFriendButton> {
  bool _isLoading = false;
  bool _requested = false;
  bool _isFriend = false;

  @override
  void initState() {
    super.initState();
    _initStatus();
  }

  Future<void> _initStatus() async {
    try {
      final resp = await FriendService().checkStatus(widget.userId);
      if (!mounted) return;
      if (resp.success && resp.data != null) {
        final status = resp.data['status'] as String? ?? 'none';
        if (status == 'accepted') {
          setState(() => _isFriend = true);
        } else if (status == 'pending') {
          setState(() => _requested = true);
        }
      }
    } catch (_) {
      // 状态查询失败不影响按钮展示，保持默认"添加好友"
    }
  }

  Future<void> _sendRequest() async {
    if (_isLoading || _requested) return;
    setState(() => _isLoading = true);
    try {
      final resp = await FriendService().sendRequest(widget.userId);
      if (!mounted) return;
      if (resp.success) {
        setState(() => _requested = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('好友请求已发送'), duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message ?? '发送失败'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 已经是好友则不显示按钮
    if (_isFriend) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _sendRequest,
      child: Container(
        height: widget.height,
        padding: widget.padding,
        decoration: BoxDecoration(
          border: Border.all(
            color: _requested ? AppColors.borderLight : const Color(0xFFC4CDD4),
          ),
          borderRadius: BorderRadius.circular(20),
          color: _requested ? AppColors.backgroundSecondary : null,
        ),
        alignment: Alignment.center,
        child: _isLoading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                _requested ? '已发送' : '添加好友',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _requested ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
      ),
    );
  }
}