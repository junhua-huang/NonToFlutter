import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/explore_notifier.dart';
import 'package:nonto/providers/feed_notifier.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/routes/app_routes.dart';
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
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final authNotifier = ref.read(authProvider.notifier);
    final success = await authNotifier.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      // 换号登录后强制重建所有 Provider
      ref.invalidate(feedProvider);
      ref.invalidate(exploreProvider);
      ref.invalidate(conversationsProvider);
      ref.invalidate(notificationsProvider);
      // 预热 Provider + 等待 WS 认证完成（setToken 已触发 connect）
      final ws = WebSocketService();
      // 先设置监听再检查，防止 auth 已经在 setToken 期间完成而漏掉事件
      final completer = Completer<bool>();
      final sub = ws.connectionStream.listen((connected) {
        if (connected && !completer.isCompleted) completer.complete(true);
      });
      if (ws.isConnected) {
        // 已经认证完成，直接放行
        completer.complete(true);
      }
      final wsOk = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
      sub.cancel();
      if (!mounted) return;
      if (!wsOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接服务器失败，请重试'), backgroundColor: Colors.red),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      final error = ref.read(authProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

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
                      onPressed: authState.isLoading ? null : _login,
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
                      child: authState.isLoading
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
