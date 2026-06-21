import 'package:nonto/models/user.dart';

/// Immutable auth state used by [AuthNotifier].
class AuthState {
  final User? user;
  final String? token;
  final bool isLoading;
  final String? error;

  /// 登录连续失败 ≥ 5 次后，后端返回 429 要求邮箱验证码。
  /// UI（LoginScreen）据此渲染验证码输入框 + 发送验证码按钮，
  /// 并在用户填入 code 后以 [AuthNotifier.login] 的 emailCode 参数重试。
  /// 任何一次成功登录 / 显式清错都会复位为 false。
  final bool requiresEmailCode;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.error,
    this.requiresEmailCode = false,
  });

  bool get isLoggedIn => token != null && user != null;

  static const initial = AuthState();

  AuthState copyWith({
    User? user,
    String? token,
    bool? isLoading,
    String? error,
    bool? requiresEmailCode,
    bool clearUser = false,
    bool clearToken = false,
    bool clearError = false,
    bool clearRequiresEmailCode = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      token: clearToken ? null : (token ?? this.token),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      requiresEmailCode:
          clearRequiresEmailCode ? false : (requiresEmailCode ?? this.requiresEmailCode),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          user == other.user &&
          token == other.token &&
          isLoading == other.isLoading &&
          error == other.error &&
          requiresEmailCode == other.requiresEmailCode;

  @override
  int get hashCode =>
      Object.hash(user, token, isLoading, error, requiresEmailCode);
}
