import 'package:flutter/material.dart';

/// App-wide page transition animations
class AppTransitions {
  AppTransitions._();

  /// Standard page push with slide + fade
  static PageRouteBuilder slide({
    required Widget page,
    Duration duration = const Duration(milliseconds: 300),
    Offset begin = const Offset(1.0, 0.0),
  }) {
    return PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: begin, end: Offset.zero).chain(
          CurveTween(curve: Curves.easeOutCubic),
        );
        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  /// Bottom sheet style (slide up)
  static PageRouteBuilder bottomSheet({
    required Widget page,
    Duration duration = const Duration(milliseconds: 350),
  }) {
    return PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(0.0, 1.0), end: Offset.zero).chain(
          CurveTween(curve: Curves.easeOutCubic),
        );
        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  /// Fade in/out
  static PageRouteBuilder fade({
    required Widget page,
    Duration duration = const Duration(milliseconds: 250),
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

  /// Scale + fade (for modals / dialogs)
  static PageRouteBuilder scale({
    required Widget page,
    Duration duration = const Duration(milliseconds: 250),
  }) {
    return PageRouteBuilder(
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      opaque: false,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: Tween(begin: 0.85, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  /// Push a named route with standard slide transition
  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(context, slide(page: page) as Route<T>);
  }

  /// Push a bottom-sheet style route
  static Future<T?> pushBottom<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(context, bottomSheet(page: page) as Route<T>);
  }

  /// Push a fade route
  static Future<T?> pushFade<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(context, fade(page: page) as Route<T>);
  }
}

/// Utility widget for staggered list animation
class StaggeredAnimation extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;

  const StaggeredAnimation({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 50),
  });

  @override
  State<StaggeredAnimation> createState() => _StaggeredAnimationState();
}

class _StaggeredAnimationState extends State<StaggeredAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // Stagger based on index
    Future.delayed(Duration(milliseconds: widget.index * widget.delay.inMilliseconds), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
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

