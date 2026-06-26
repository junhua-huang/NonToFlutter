import 'package:flutter/material.dart';

/// 消息高亮包装器：被激活时背景色从淡黄渐变到透明，持续约 1.5s。
///
/// 用途：点击引用预览条定位到原消息后，给目标气泡一个微信/Telegram 风格的
/// "闪一下"反馈，让用户清楚知道是哪一条。
///
/// 用法：
/// ```dart
/// MessageHighlightWrapper(
///   active: state.highlightMessageId == msg.id,
///   onCompleted: () => ref.read(...).clearHighlight(),
///   child: bubble,
/// )
/// ```
class MessageHighlightWrapper extends StatefulWidget {
  final bool active;
  final VoidCallback? onCompleted;
  final Widget child;

  const MessageHighlightWrapper({
    super.key,
    required this.active,
    this.onCompleted,
    required this.child,
  });

  @override
  State<MessageHighlightWrapper> createState() =>
      _MessageHighlightWrapperState();
}

class _MessageHighlightWrapperState extends State<MessageHighlightWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _wasActive = false;

  static const Duration _duration = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _animation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onCompleted?.call();
        }
      });
    if (widget.active) {
      _wasActive = true;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant MessageHighlightWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_wasActive) {
      _wasActive = true;
      _controller.forward(from: 0.0);
    } else if (!widget.active && _wasActive) {
      // 外部清掉了 active，重置状态
      _wasActive = false;
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 未激活过时不绘制任何装饰，避免每条消息都带黄色背景。
    // 仅在 _wasActive 为 true（动画已触发）时才叠高亮层。
    if (!_wasActive) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final alpha = _animation.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: alpha > 0
                ? Color(0xFFFFEB3B).withValues(alpha: 0.35 * alpha)
                : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
