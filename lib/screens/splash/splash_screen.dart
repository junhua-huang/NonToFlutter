import 'dart:async';

import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/routes/app_routes.dart';
import 'package:facebook_clone/screens/auth/login_screen.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Splash screen with auto-login, permission requests, and X branding animation
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _logoFadeAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<double> _progressAnimation;
  bool _showCookieConsent = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    // Logo scales from 0.5 to 1.0 with bounce
    _logoScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    // Logo fades in
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Text fades in after logo
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      ),
    );

    // Progress bar
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();

    // After animation completes, check cookie consent and navigate
    _checkCookieConsentAndNavigate();
  }

  Future<void> _checkCookieConsentAndNavigate() async {
    // Wait for splash animation
    await Future.delayed(const Duration(milliseconds: 2200));

    // Initialize shared preferences
    final prefs = await SharedPreferences.getInstance();

    // Check if cookie consent has been given
    final hasConsent = prefs.getBool('cookie_consent') ?? false;

    if (!hasConsent && mounted) {
      setState(() {
        _showCookieConsent = true;
      });
    } else {
      // Proceed with normal navigation
      _navigateAfterSplash();
    }
  }

  Future<void> _navigateAfterSplash() async {
    // Request permissions while waiting (non-blocking)
    _requestPermissions();

    if (!mounted) return;

    final auth = context.read<AuthProvider>();

    // If auth is already resolved, navigate immediately
    if (!auth.isLoading || auth.user != null) {
      _doNavigate(auth.isLoggedIn);
      return;
    }

    // AuthProvider is still loading — listen for completion instead of polling
    void onAuthChanged() {
      if (!auth.isLoading) {
        auth.removeListener(onAuthChanged);
        if (mounted) {
          _doNavigate(auth.isLoggedIn);
        }
      }
    }
    auth.addListener(onAuthChanged);
  }

  void _doNavigate(bool isLoggedIn) {
    if (!mounted) return;
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

  void _requestPermissions() async {
    // Request permissions here (non-blocking)
    // For web, we don't need to request permissions
    // For mobile, you would add:
    // - Camera permission
    // - Photo library permission
    // - Notifications permission
    // Using permission_handler package
    try {
      // Notification permissions would go here on mobile
      // Camera permissions for image/video upload
      // Photo library permissions
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show cookie consent if needed
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

              // Animated X Logo
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

              // App name text
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

              // Loading progress bar
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
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
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
              // Drag handle
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
              // Cookie icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cookie_outlined, size: 26, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cookie 偏好设置',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '我们使用 Cookie 和类似技术来改善您的体验，包括记住您的偏好设置、保障账户安全和服务分析。继续使用本应用即表示您同意我们使用 Cookie。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                ),
              ),
              const SizedBox(height: 28),
              // Buttons
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('接受全部', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      child: const Text(
                        '查看隐私政策',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
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
      // User chose "查看隐私政策" - navigate to privacy policy
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.pushNamed(context, AppRoutes.privacyPolicy);
      // Show consent again after returning
      final prefs = await SharedPreferences.getInstance();
      final hasConsent = prefs.getBool('cookie_consent') ?? false;
      if (!hasConsent) {
        // ignore: use_build_context_synchronously
        _showCookieConsentDialog(context);
      }
    } else {
        // User accepted - save consent
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('cookie_consent', true);
        if (mounted) {
          _navigateAfterSplash();
        }
      }
  }
}
