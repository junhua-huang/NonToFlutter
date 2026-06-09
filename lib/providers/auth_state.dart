import 'package:facebook_clone/models/user.dart';

/// Immutable auth state used by [AuthNotifier].
class AuthState {
  final User? user;
  final String? token;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.error,
  });

  bool get isLoggedIn => token != null && user != null;

  static const initial = AuthState();

  AuthState copyWith({
    User? user,
    String? token,
    bool? isLoading,
    String? error,
    bool clearUser = false,
    bool clearToken = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      token: clearToken ? null : (token ?? this.token),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          user == other.user &&
          token == other.token &&
          isLoading == other.isLoading &&
          error == other.error;

  @override
  int get hashCode => Object.hash(user, token, isLoading, error);
}
