import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/routes/app_routes.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscure = true;
  bool _privacyAccepted = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_privacyAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先同意用户协议和隐私政策'), backgroundColor: Colors.orange));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次密码不一致'), backgroundColor: Colors.red));
      return;
    }
    final authNotifier = ref.read(authProvider.notifier);
    final ok = await authNotifier.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      final error = ref.read(authProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号'), leading: IconButton(
        icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(children: [
              TextFormField(controller: _usernameController,
                decoration: const InputDecoration(labelText: '用户名', prefixIcon: Icon(Icons.alternate_email)),
                validator: (v) => (v?.length ?? 0) < 3 ? '用户名至少3个字符' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: '邮箱', prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) => v?.contains('@') != true ? '请输入有效邮箱' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _passwordController, obscureText: _obscure,
                decoration: InputDecoration(labelText: '密码', prefixIcon: Icon(Icons.lock_outline),
                  suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure))),
                validator: (v) {
                if ((v?.length ?? 0) < 8) return '密码至少8个字符';
                return null;
              }),
              const SizedBox(height: 16),
              TextFormField(controller: _confirmPasswordController, obscureText: true,
                decoration: const InputDecoration(labelText: '确认密码', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => v != _passwordController.text ? '密码不一致' : null),
              const SizedBox(height: 24),

              // 隐私同意复选框 (GDPR 合规)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24, height: 24,
                    child: Checkbox(
                      value: _privacyAccepted,
                      onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _privacyAccepted = !_privacyAccepted),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                          children: [
                            const TextSpan(text: '我已阅读并同意'),
                            WidgetSpan(
                              child: GestureDetector(
                                onTap: () => Navigator.pushNamed(context, AppRoutes.termsOfService),
                                child: const Text(
                                  '《用户协议》',
                                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                                ),
                              ),
                            ),
                            const TextSpan(text: '和'),
                            WidgetSpan(
                              child: GestureDetector(
                                onTap: () => Navigator.pushNamed(context, AppRoutes.privacyPolicy),
                                child: const Text(
                                  '《隐私政策》',
                                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (_) {
                  final authState = ref.watch(authProvider);
                  return ElevatedButton(
                    onPressed: authState.isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _privacyAccepted ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('注册', style: TextStyle(fontSize: 16)));
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
