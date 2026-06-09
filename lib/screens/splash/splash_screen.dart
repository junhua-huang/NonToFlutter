import 'dart:async';

import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/routes/app_routes.dart';
import 'package:facebook_clone/screens/auth/login_screen.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/data_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Splash screen — follows the three-layer architecture:
///   1. Read token from SharedPreferences (local, <10ms) → decide login/home
///   2. If logged in → warmup DataLayer from SQLite L2 (50-100ms, no network)
///   3. Navigate immediately, auth.validateSession() runs in background
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _logoFadeAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<double> _progressAnimation;
  late final TickerFuture _animationDone;
  bool _showCookieConsent = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _logoScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      ),
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOut),
      ),
    );

    _animationDone = _controller.forward();
    _checkCookieConsentAndNavigate();
  }

  Future<void> _checkCookieConsentAndNavigate() async {
    try {
      // Wait for animation to complete (3000ms)
      await _animationDone;

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final hasConsent = prefs.getBool('cookie_consent') ?? false;

      if (!hasConsent && mounted) {
        setState(() => _showCookieConsent = true);
      } else {
        _navigateAfterSplash();
      }
    } catch (e) {
      debugPrint('SplashScreen error: $e');
      if (mounted) _doNavigate(false);
    }
  }

  /// Read token from SharedPreferences (<10ms).
  /// If logged in → warmup SQLite cache → navigate to home.
  /// If not → navigate to login.
  /// Network profile validation runs in background via auth.validateSession().
  Future<void> _navigateAfterSplash() async {
    if (_navigated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final userId = prefs.getString('current_user_id');
      final isLoggedIn = token != null &&
          token.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty;

      if (!mounted) return;

      if (isLoggedIn) {
        // 预热前必须设置 token，否则网络请求全部 403
        ApiClient.setToken(token);
        // DB 初始化 + 预热由 AuthNotifier._initDbAndCache() 统一触发，闪屏不重复做
        DataLayer().initDb(userId).catchError((_) {});

        if (mounted) _doNavigate(true);
      } else {
        if (mounted) _doNavigate(false);
      }
    } catch (e) {
      debugPrint('SplashScreen._navigateAfterSplash error: $e');
      if (mounted) _doNavigate(false);
    }
  }

  void _doNavigate(bool isLoggedIn) {
    if (!mounted || _navigated) return;
    _navigated = true;

    // Trigger auth initialization now (reads cached user from prefs)
    // so HomeScreen sees auth state on first build.
    if (isLoggedIn) {
      ref.read(authProvider);
      Future.microtask(() {
        ref.read(authProvider.notifier).validateSession();
      });
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: isLoggedIn ? const HomeScreen() : const LoginScreen(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cookie consent dialog
    if (_showCookieConsent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCookieConsentDialog(context);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              FadeTransition(
                opacity: _logoFadeAnimation,
                child: ScaleTransition(
                  scale: _logoScaleAnimation,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text(
                        'N',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeTransition(
                opacity: _textFadeAnimation,
                child: const Text(
                  'nonto',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FadeTransition(
                opacity: _textFadeAnimation,
                child: const Text(
                  '发现世界的动态',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return LinearProgressIndicator(
                          value: _progressAnimation.value,
                          backgroundColor: AppColors.borderLight,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary),
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 3,
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCookieConsentDialog(BuildContext context) async {
    _showCookieConsent = false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).padding.bottom + 24,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCED5DC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cookie_outlined,
                    size: 26, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cookie 偏好设置',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '我们使用 Cookie 和类似技术来改善您的体验。继续使用即表示您同意。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.6),
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: AppColors.textPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('接受全部',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22)),
                      ),
                      child: const Text(
                        '查看隐私政策',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (result == false) {
      Navigator.pushNamed(context, AppRoutes.privacyPolicy);
      final prefs = await SharedPreferences.getInstance();
      final hasConsent = prefs.getBool('cookie_consent') ?? false;
      if (!hasConsent && mounted) {
        _showCookieConsentDialog(context);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cookie_consent', true);
      if (mounted) _navigateAfterSplash();
    }
  }
}
