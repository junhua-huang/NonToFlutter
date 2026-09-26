import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/explore_notifier.dart';
import 'package:nonto/providers/feed_notifier.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/screens/auth/login_screen.dart';
import 'package:nonto/screens/home/home_screen.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/app_runtime_info.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 闪屏页 — 职责单一：校验 token 有效性，放行前不做任何业务网络请求。
///
/// 流程：
///   1. 读 SharedPreferences 中的 token
///   2. 无 token → 直接进登录页
///   3. 有 token → 设置到 ApiClient → 调 /auth/profile 校验
///   4. 校验通过 → 进首页（Provider 自行初始化数据）
///   5. 校验失败（401/网络错误）→ 清除 token → 进登录页
///
/// 在确定 token 有效/无效之前，闪屏不消失。
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  bool _navigated = false;
  bool _showCookieConsent = false;
  static bool _validating = false; // 防止重入

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    _controller.forward();
    _validateAndNavigate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ═══════════════════════════════════════════════════════
  ///  核心：校验 token → 放行
  /// ═══════════════════════════════════════════════════════

  Future<void> _validateAndNavigate() async {
    if (_validating) return;
    _validating = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final userId = prefs.getString('current_user_id');

      // 无 token → 直接进登录，不等动画
      if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
        if (mounted) _doNavigate(false);
        return;
      }

      // 有 token → 设置到全局；DB/Provider/WS 改为后台启动，避免阻塞首屏。
      ApiClient.setToken(token, connectWs: false);

      // 仅发一个请求：校验 token
      final valid = await _verifyToken();

      if (!mounted) return;

      if (valid) {
        debugPrint('[Splash] ✅ HTTP token 验证通过');
        _startLoggedInBackgroundServices(userId);
        await _checkCookieAndGo(true);
      } else {
        // Token 无效 → 清除，进登录
        await _clearLocalAuth(prefs);
        if (mounted) _doNavigate(false);
      }
    } catch (e) {
      debugPrint('SplashScreen validate error: $e');
      if (mounted) _doNavigate(false);
    }
  }

  /// 发一个 /auth/profile 确认 token 是否有效
  Future<bool> _verifyToken() async {
    try {
      final resp = await ApiClient()
          .get<Map<String, dynamic>>('/auth/profile')
          .timeout(const Duration(seconds: 10));
      if (resp.success && resp.data != null) {
        // 顺便缓存用户信息到 DataLayer，AuthNotifier 恢复时可直接读
        final userId = SharedPreferences.getInstance()
            .then((p) => p.getString('current_user_id'));
        final uid = await userId;
        if (uid != null && mounted) {
          DataLayer().write('user:$uid:profile', resp.data);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _startLoggedInBackgroundServices(String userId) {
    unawaited(DataLayer().initDb(userId).catchError((e) {
      debugPrint('[Splash] background DB init failed: $e');
    }));
    unawaited(_warmHomeProvidersInBackground());
  }

  /// 预热首页 Provider 放到首屏导航之后后台执行，避免阻塞 Web 首次进入。
  Future<void> _warmHomeProvidersInBackground() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    ref.invalidate(feedProvider);
    ref.invalidate(exploreProvider);
    ref.invalidate(conversationsProvider);
    ref.invalidate(notificationsProvider);
    ref.read(feedProvider);
    ref.read(exploreProvider);
    ref.read(conversationsProvider);
    ref.read(notificationsProvider);
  }

  Future<void> _clearLocalAuth(SharedPreferences prefs) async {
    // 必须等待 WS 断开，防止旧连接导致新登录时服务端返回 duplicate_connection
    await WebSocketService().disconnect();
    ApiClient.setToken(null);
    await prefs.remove('access_token');
    await prefs.remove('current_user_id');
    await prefs.remove('current_user_json');
    // 清除 DataLayer 和数据库，防止下次同用户登录复用脏 DB
    DataLayer().clearAll();
    // 取消所有在途 / 排队中的 HTTP 请求，避免旧 token 的请求结果在
    // RequestManager TTL 内被新账号复用（典型表现：登录后看到上一个账号的列表）
    ApiClient.requestManager.clearAll();
    await DataLayer().closeDb();
  }

  Future<void> _checkCookieAndGo(bool isLoggedIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasConsent = prefs.getBool('cookie_consent') ?? false;
      if (!hasConsent && mounted) {
        setState(() => _showCookieConsent = true);
      } else {
        if (mounted) _doNavigate(isLoggedIn);
      }
    } catch (_) {
      if (mounted) _doNavigate(isLoggedIn);
    }
  }

  void _doNavigate(bool isLoggedIn) {
    if (!mounted || _navigated) return;
    _navigated = true;

    // 触发 AuthNotifier 读取 prefs 中的用户缓存
    if (isLoggedIn) {
      ref.read(authProvider);
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        settings: RouteSettings(
          name: isLoggedIn ? AppRoutes.home : AppRoutes.login,
        ),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: isLoggedIn ? const HomeScreen() : const LoginScreen(),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Cookie 同意弹窗
  // ═══════════════════════════════════════════════════════

  void _onCookieResult(bool accepted) {
    setState(() => _showCookieConsent = false);
    if (accepted) {
      SharedPreferences.getInstance()
          .then((p) => p.setBool('cookie_consent', true));
    }
    _doNavigate(true);
  }

  void _showCookieConsentDialog(BuildContext context) async {
    _showCookieConsent = false;
    await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
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
                    color: AppColors.dragHandle,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
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
              Text('Cookie 偏好设置',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3)),
              const SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text('我们使用 Cookie 和类似技术来改善您的体验。继续使用即表示您同意。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.6)),
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
                        foregroundColor: AppColors.background,
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
                      child: const Text('查看隐私政策',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((value) {
      if (value != null) {
        _onCookieResult(value);
      } else {
        _onCookieResult(false);
      }
    });
  }

  // ═══════════════════════════════════════════════════════
  //  UI
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Cookie 弹窗
    if (_showCookieConsent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showCookieConsent) {
          _showCookieConsentDialog(context);
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo: 蓝色圆底 + 大写 N
                Transform.scale(
                  scale: 0.5 +
                      0.5 *
                          Curves.elasticOut
                              .transform(progress.clamp(0.0, 0.6) / 0.6),
                  child: Opacity(
                    opacity: (progress.clamp(0.0, 0.4) / 0.4),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Center(
                        child: Text('N',
                            style: TextStyle(
                                fontSize: 46,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // App name
                Opacity(
                  opacity: ((progress - 0.35).clamp(0.0, 0.25) / 0.25),
                  child: Text('NonTo',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -1)),
                ),
                const SizedBox(height: 10),
                // Subtitle
                Opacity(
                  opacity: ((progress - 0.5).clamp(0.0, 0.3) / 0.3),
                  child: Text('连接你的异次元世界',
                      style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 32),
                // 版本号
                Text('v${AppRuntimeInfo.current.version}',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        letterSpacing: 1)),
              ],
            );
          },
        ),
      ),
    );
  }
}
