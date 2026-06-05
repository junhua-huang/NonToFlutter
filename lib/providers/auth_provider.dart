import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/api/auth_service.dart';
import 'package:facebook_clone/services/local_db_service.dart';
import 'package:facebook_clone/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final SharedPreferences? _prefs;
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  bool get isLoggedIn => _token != null && _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AuthProvider({SharedPreferences? prefs}) : _prefs = prefs {
    loadSavedSession();
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  Future<void> loadSavedSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs = await _getPrefs();
      _token = prefs.getString('access_token');
      if (_token != null) {
        ApiClient.setToken(_token);
        final ok = await _fetchProfile();
        if (!ok) {
          // Profile fetch failed (token expired / server unreachable) — try refresh
          final refreshed = await _tryRefreshToken();
          if (!refreshed) {
            await _clearSession();
          }
        } else {
          // Init local DB for current user
          if (_user != null) {
            await LocalDbService().init(_user!.id.toString());
          }
          // WebSocket deferred to HomeScreen post-frame; not connected here
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String username, required String email, required String password,
    String? bio,
  }) async {
    _setLoading(true);
    try {
      final resp = await _authService.register({
        'username': username, 'email': email, 'password': password,
        if (bio != null) 'bio': bio,
      });
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        _token = data['access_token'];
        _user = User.fromJson(data['user']);
        await _saveSession();
        ApiClient.setToken(_token);
        // Init local DB for current user
        await LocalDbService().init(_user!.id.toString());
        WebSocketService().connect();
        _error = null;
        notifyListeners();
        return true;
      }
      _error = resp.message ?? 'Registration failed';
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    try {
      final resp = await _authService.login(email, password);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        _token = data['access_token'];
        _user = data['user'] != null ? User.fromJson(data['user']) : null;
        await _saveSession();
        ApiClient.setToken(_token);
        // Init local DB for current user
        if (_user != null) {
          await LocalDbService().init(_user!.id.toString());
        }
        WebSocketService().connect();
        _error = null;
        notifyListeners();
        return true;
      }
      _error = resp.message ?? 'Login failed';
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Returns true if profile was fetched successfully
  Future<bool> _fetchProfile() async {
    try {
      final resp = await _authService.getProfile();
      if (resp.success && resp.data != null) {
        // 后端返回 { "user": {...} }
        final data = resp.data;
        final userJson = data is Map<String, dynamic>
            ? (data['user'] ?? data)
            : data;
        _user = User.fromJson(userJson as Map<String, dynamic>);
        notifyListeners();
        return true;
      }
      debugPrint('[_fetchProfile] failed: statusCode=${resp.statusCode}, msg=${resp.message}');
      return false;
    } catch (e) {
      debugPrint('[_fetchProfile] exception: $e');
      return false;
    }
  }

  /// Try to refresh the token. Returns true if successful.
  Future<bool> _tryRefreshToken() async {
    if (_token == null) return false;
    try {
      final resp = await _authService.refreshToken();
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        _token = data['access_token'];
        final userJson = data['user'];
        if (userJson != null) {
          _user = User.fromJson(userJson as Map<String, dynamic>);
        }
        await _saveSession();
        ApiClient.setToken(_token);
        if (_user != null) {
          await LocalDbService().init(_user!.id.toString());
        }
        WebSocketService().connect();
        notifyListeners();
        debugPrint('[_tryRefreshToken] success');
        return true;
      }
      debugPrint('[_tryRefreshToken] failed: ${resp.message}');
    } catch (e) {
      debugPrint('[_tryRefreshToken] exception: $e');
    }
    return false;
  }

  /// Clear all saved auth state
  Future<void> _clearSession() async {
    _token = null;
    _user = null;
    ApiClient.setToken(null);
    final prefs = await _getPrefs();
    await prefs.remove('access_token');
    debugPrint('[_clearSession] session cleared');
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final resp = await _authService.updateProfile(data);
      if (resp.success) {
        _user = _user?.copyWith(
          displayName: data['display_name'] ?? data['first_name'],
          bio: data['bio'],
          avatarUrl: data['avatar_url'],
          coverPhotoUrl: data['cover_photo_url'],
        );
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update the current user with a new User object (e.g. after avatar/cover upload)
  void updateUser(User newUser) {
    _user = newUser;
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    ApiClient.setToken(null);
    WebSocketService().disconnect();
    await LocalDbService().close();
    final prefs = await _getPrefs();
    await prefs.remove('access_token');
    notifyListeners();
  }

  Future<void> _saveSession() async {
    final prefs = await _getPrefs();
    await prefs.setString('access_token', _token!);
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
