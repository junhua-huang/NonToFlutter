import 'api_client.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final ApiClient _api = ApiClient();

  Future<ApiResponse> register(Map<String, dynamic> data) {
    return _api.post('/auth/register', data: data);
  }

  Future<ApiResponse> login(String email, String password) {
    return _api.post('/auth/login', data: {'email': email, 'password': password});
  }

  Future<ApiResponse> getProfile() {
    return _api.get('/auth/profile');
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
    return _api.get('/auth/users/$userId');
  }

  /// Permanently delete the authenticated user's account (GDPR "Right to be Forgotten").
  Future<ApiResponse> deleteAccount() {
    return _api.delete('/auth/account');
  }

  /// Send a password reset email to the given [email].
  Future<ApiResponse> forgotPassword(String email) {
    return _api.post('/auth/forgot-password', data: {'email': email});
  }

  /// Reset password using the [token] received by email.
  Future<ApiResponse> resetPassword({
    required String token,
    required String newPassword,
  }) {
    return _api.post('/auth/reset-password', data: {
      'token': token,
      'new_password': newPassword,
    });
  }

  /// Get privacy settings
  Future<ApiResponse> getPrivacy() => _api.get('/auth/privacy');

  /// Update privacy settings
  Future<ApiResponse> updatePrivacy(Map<String, dynamic> data) =>
      _api.put('/auth/privacy', data: data);
}
