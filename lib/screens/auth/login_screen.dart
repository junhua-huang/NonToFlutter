import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/explore_notifier.dart';
import 'package:nonto/providers/feed_notifier.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/screens/auth/otp_widgets.dart';
import 'package:nonto/screens/auth/register_screen.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoggingIn) return;

    final authNotifier = ref.read(authProvider.notifier);
    final authState = ref.read(authProvider);
    // 当后端已要求验证码（requiresEmailCode=true）时，本次提交必须带 code。
    // 校验放在 submit 前，避免空 code 再次触发 429。
    final requiresEmailCode = authState.requiresEmailCode;
    if (requiresEmailCode && _codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱验证码'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      final success = await authNotifier.login(
        _emailController.text.trim(),
        _passwordController.text,
        emailCode: requiresEmailCode ? _codeController.text.trim() : null,
      );
      if (!mounted) return;
      if (success) {
        // 换号登录后强制重建所有 Provider
        ref.invalidate(feedProvider);
        ref.invalidate(exploreProvider);
        ref.invalidate(conversationsProvider);
        ref.invalidate(notificationsProvider);
        // 等待 WS 认证完成（与闪屏页逻辑一致）
        final wsOk = await _verifyWsConnection();
        if (!mounted) return;
        if (!wsOk) {
          setState(() => _isLoggingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('连接服务器失败，请重试'), backgroundColor: Colors.red),
          );
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        final newError = ref.read(authProvider).error;
        if (newError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(newError), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  /// 建立 WS 连接并等待认证完成（与闪屏页逻辑一致）
  /// 1. await ws.connect() 确保 socket 已建立
  /// 2. 检查 isConnected（auth 可能已在 connect() 期间完成）
  /// 3. 监听 connectionStream 等待认证结果
  Future<bool> _verifyWsConnection() async {
    try {
      final ws = WebSocketService();
      if (ws.isConnected) return true;
      // login() 内部 setToken 已触发 ws.connect()，但那是 fire-and-forget，
      // 这里 await 确保物理连接已建立、auth 帧已发送
      await ws.connect();
      // connect() 返回后 auth 可能已经异步完成
      if (ws.isConnected) return true;
      // 等待 connectionStream 变为 true
      final completer = Completer<bool>();
      final sub = ws.connectionStream.listen((connected) {
        if (connected && !completer.isCompleted) completer.complete(true);
      });
      final result = await completer.future
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      sub.cancel();
      return result;
    } catch (e) {
      debugPrint('[Login] _verifyWsConnection error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Twitter-style: big centered logo
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const Text('N',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Title
                  const Text(
                    '登录 NonTo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F1419),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF0F1419)),
                    decoration: InputDecoration(
                      hintText: '邮箱',
                      hintStyle: TextStyle(color: Color(0xFF536471)),
                      filled: true,
                      fillColor: const Color(0xFFEFF3F4),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? '请输入邮箱' : null,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF0F1419)),
                    decoration: InputDecoration(
                      hintText: '密码',
                      hintStyle: const TextStyle(color: Color(0xFF536471)),
                      filled: true,
                      fillColor: const Color(0xFFEFF3F4),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF536471),
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) =>
                        (v?.isEmpty ?? true) ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 8),

                  // 邮箱验证码行：仅当后端要求（连续失败 ≥ 5 次）时显示。
                  // 使用 Builder 让 ref.watch 在此子树内生效，避免整页 rebuild 浪费。
                  Consumer(
                    builder: (context, ref, _) {
                      final requiresOtp = ref.watch(
                          authProvider.select((s) => s.requiresEmailCode));
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: requiresOtp
                            ? Padding(
                                key: const ValueKey('otp-row'),
                                padding: const EdgeInsets.only(top: 8, bottom: 8),
                                child: OtpFieldRow(
                                  codeController: _codeController,
                                  emailController: _emailController,
                                  purpose: 'login',
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('no-otp')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/forgot_password'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('忘记密码？',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Login Button — full width, rounded, bold
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoggingIn ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoggingIn
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('登录',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Terms
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF536471),
                          height: 1.4),
                      children: [
                        const TextSpan(text: '登录即表示您同意我们的'),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, AppRoutes.termsOfService),
                            child: const Text(
                              '《用户协议》',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const TextSpan(text: '和'),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(
                                context, AppRoutes.privacyPolicy),
                            child: const Text(
                              '《隐私政策》',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Register
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('还没有账号？',
                          style: TextStyle(
                              color: Color(0xFF536471), fontSize: 14)),
                      TextButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const RegisterScreen())),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: const Text('注册',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('v0.2.2',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Color(0xFF8899A6))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
