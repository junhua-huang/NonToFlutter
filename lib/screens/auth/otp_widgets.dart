import 'dart:async';

import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/auth_service.dart';
import 'package:flutter/material.dart';

/// 邮箱验证码发送按钮（带 60s 倒计时）。
///
/// 使用方：
/// - RegisterScreen：purpose=register
/// - ForgotPasswordScreen：purpose=reset_password
/// - LoginScreen（429 触发）：purpose=login
///
/// 设计要点：
/// - 倒计时仅本地 UI 状态，与后端频控相互独立（后端另有 60s/1h 限流）。
/// - 发送期间禁用按钮，防止重复点击。
/// - 邮箱非法时不发起请求，由调用方在 [onCodeSent] 前自行校验。
class OtpSendButton extends StatefulWidget {
  final TextEditingController emailController;

  /// register / reset_password / login
  final String purpose;

  /// 验证码发送成功后的回调（用于联动输入框显隐等）
  final VoidCallback? onCodeSent;

  const OtpSendButton({
    super.key,
    required this.emailController,
    required this.purpose,
    this.onCodeSent,
  });

  @override
  State<OtpSendButton> createState() => _OtpSendButtonState();
}

class _OtpSendButtonState extends State<OtpSendButton> {
  static const _cooldown = Duration(seconds: 60);
  Timer? _timer;
  int _remaining = 0;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isCooling => _remaining > 0;
  bool get _busy => _sending || _isCooling;

  String get _email => widget.emailController.text.trim();

  void _startCountdown() {
    setState(() => _remaining = _cooldown.inSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
      }
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_email.isEmpty || !_email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写有效邮箱'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final resp = await AuthService().sendOtp(email: _email, purpose: widget.purpose);
      if (!mounted) return;
      if (resp.success) {
        _startCountdown();
        widget.onCodeSent?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送，请查收邮件'), backgroundColor: Colors.green),
        );
      } else {
        // 后端频控命中时，仍按本地 60s 倒计时降级，避免用户狂点。
        if ((resp.statusCode == 429)) {
          _startCountdown();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message ?? '发送失败，请稍后重试'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('网络错误: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _sending
        ? '发送中...'
        : _isCooling
            ? '${_remaining}s 后重发'
            : '获取验证码';
    return TextButton(
      onPressed: _busy ? null : _send,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(96, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

/// 6 位数字验证码输入框 + 右侧 [OtpSendButton] 的组合行。
/// 直接嵌入邮箱输入下方，避免每个屏幕重复拼装。
class OtpFieldRow extends StatelessWidget {
  final TextEditingController codeController;
  final TextEditingController emailController;
  final String purpose;
  final String? labelText;

  const OtpFieldRow({
    super.key,
    required this.codeController,
    required this.emailController,
    required this.purpose,
    this.labelText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: labelText ?? '邮箱验证码',
              counterText: '',
              prefixIcon: const Icon(Icons.password_outlined),
            ),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return '请输入验证码';
              if (s.length != 6 || int.tryParse(s) == null) return '请输入 6 位数字';
              return null;
            },
          ),
        ),
        OtpSendButton(emailController: emailController, purpose: purpose),
      ],
    );
  }
}

/// 统一的本地预校验：调用 /auth/verify-otp（不消费验证码）。
/// 返回 true 时再继续提交业务请求，减少无效注册/登录提交。
Future<bool> preVerifyOtp(
  BuildContext context, {
  required String email,
  required String code,
  required String purpose,
}) async {
  try {
    final resp = await AuthService().verifyOtp(email: email, code: code, purpose: purpose);
    if (resp.success) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resp.message ?? '验证码校验失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('网络错误: $e'), backgroundColor: Colors.red),
      );
    }
    return false;
  }
}
