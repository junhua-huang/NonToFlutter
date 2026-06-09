import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// App-wide page transition animations
class AppTransitions {
  AppTransitions._();

  /// Standard page push with slide + fade
  static PageRouteBuilder slide({
    required Widget page,
    Duration duration = const Duration(milliseconds: 280),
    Offset begin = const Offset(0.12, 0.0),
  }) {
    return PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        // single AnimatedBuilder wrapping both transitions — one rebuild per tick
        return AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            return Transform.translate(
              offset: Offset((1.0 - curved.value) * 48, 0),
              child: Opacity(
                opacity: curved.value,
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  /// Bottom sheet style (slide up)
  static PageRouteBuilder bottomSheet({
    required Widget page,
    Duration duration = const Duration(milliseconds: 320),
  }) {
    return PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            return Transform.translate(
              offset: Offset(0, (1.0 - curved.value) * 60),
              child: child,
            );
          },
        );
      },
    );
  }

  /// Fade with slight scale (gentle pop-in)
  static PageRouteBuilder fade({
    required Widget page,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      opaque: false,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  static Future<T?> push<T>(BuildContext context, Widget page) =>
      Navigator.push<T>(context, slide(page: page) as Route<T>);

  static Future<T?> pushBottom<T>(BuildContext context, Widget page) =>
      Navigator.push<T>(context, bottomSheet(page: page) as Route<T>);

  static Future<T?> pushFade<T>(BuildContext context, Widget page) =>
      Navigator.push<T>(context, fade(page: page) as Route<T>);
}

/// Lightweight staggered fade-in using ImplicitlyAnimatedWidget — no per-item AnimationController.
class StaggeredWidget extends StatefulWidget {
  final Widget child;
  final int index;
  final int delayMs;

  const StaggeredWidget({
    super.key,
    required this.child,
    this.index = 0,
    this.delayMs = 50,
  });

  @override
  State<StaggeredWidget> createState() => _StaggeredWidgetState();
}

class _StaggeredWidgetState extends State<StaggeredWidget> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.index * widget.delayMs), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.04),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Animated counter for unread badges
class AnimatedCounter extends StatelessWidget {
  final int count;
  final TextStyle style;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.count,
    this.style = const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: count, end: count),
      duration: duration,
      builder: (context, value, child) {
        return Text(
          value > 99 ? '99+' : '$value',
          style: style,
        );
      },
    );
  }
}

/// IntTween for animating integer values
class IntTween extends Tween<int> {
  IntTween({super.begin, super.end});
  @override
  int lerp(double t) => (begin! + (end! - begin!) * t).round();
}

// Backward-compatible alias
@Deprecated('Use StaggeredWidget instead')
typedef StaggeredAnimation = StaggeredWidget;

