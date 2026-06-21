import 'api_client.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final ApiClient _api = ApiClient();

  Future<ApiResponse> register(Map<String, dynamic> data) {
    return _api.post('/auth/register', data: data);
  }

  Future<ApiResponse> login(String email, String password, {String? emailCode}) {
    final body = <String, dynamic>{'email': email, 'password': password};
    // 仅在连续登录失败 ≥ 5 次时后端要求验证码；前端正常登录不带 email_code
    if (emailCode != null && emailCode.isNotEmpty) {
      body['email_code'] = emailCode;
    }
    return _api.post('/auth/login', data: body);
  }

  /// 发送邮箱验证码
  /// purpose: register / reset_password / login
  Future<ApiResponse> sendOtp({required String email, required String purpose}) {
    return _api.post('/auth/send-otp', data: {
      'email': email,
      'purpose': purpose,
    });
  }

  /// 前端预校验验证码（不消费，仅检查存在性 + 未过期）
  Future<ApiResponse> verifyOtp({
    required String email,
    required String code,
    required String purpose,
  }) {
    return _api.post('/auth/verify-otp', data: {
      'email': email,
      'code': code,
      'purpose': purpose,
    });
  }

  Future<ApiResponse> getProfile() {
    return _api.getDeduped('/auth/profile');
  }

  Future<ApiResponse> refreshToken() {
    return _api.post('/auth/refresh');
  }

  Future<ApiResponse> updateProfile(Map<String, dynamic> data) {
    return _api.put('/auth/profile', data: data);
  }

  Future<ApiResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _api.post('/auth/change-password', data: {
      'old_password': currentPassword,
      'new_password': newPassword,
    });
  }

  Future<ApiResponse> getUser(int userId) {
    return _api.getDeduped('/auth/users/$userId');
  }

  /// Permanently delete the authenticated user's account (GDPR "Right to be Forgotten").
  Future<ApiResponse> deleteAccount() {
    return _api.delete('/auth/account');
  }

  /// Send a password reset email to the given [email].
  /// 后端会发一封含 6 位验证码的邮件（purpose=reset_password）。
  Future<ApiResponse> forgotPassword(String email) {
    return _api.post('/auth/forgot-password', data: {'email': email});
  }

  /// Reset password using the email + 6-digit OTP code received by email.
  /// 替代旧的 token 方案。
  Future<ApiResponse> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _api.post('/auth/reset-password', data: {
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
  }

  /// Get privacy settings
  Future<ApiResponse> getPrivacy() => _api.getDeduped('/auth/privacy');

  /// Update privacy settings
  Future<ApiResponse> updatePrivacy(Map<String, dynamic> data) =>
      _api.put('/auth/privacy', data: data);
}
