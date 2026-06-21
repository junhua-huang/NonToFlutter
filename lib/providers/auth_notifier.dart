import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_state.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/auth_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/local_db_service.dart';
import 'package:nonto/services/push_service.dart';
import 'package:nonto/services/websocket_service.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthNotifier — follows the three-layer architecture:
///   1. Constructor: read token + cached user from prefs SYNCHRONOUSLY.
///      State is set immediately so HomeScreen sees correct auth on first build.
///      DB init runs in background (unawaited).
///   2. validateSession() → background network: fetch profile, refresh token.
///   3. login() / register() / logout() / updateProfile() → standard actions.
class AuthNotifier extends StateNotifier<AuthState> {
  final SharedPreferences _prefs;
  final AuthService _authService = AuthService();
  StreamSubscription? _authExpiredSub;

  AuthNotifier(this._prefs) : super(AuthState.initial) {
    _restoreFromPrefs();
    // 监听 WebSocket 认证失效事件（JWT 过期 / 被踢下线）
    _authExpiredSub = WebSocketService().authExpiredStream.listen((reason) {
      debugPrint('[AuthNotifier] WS auth expired: $reason — clearing session');
      _clearSession();
    });
    // 监听 HTTP 401 刷新失败事件（token 完全失效）
    ApiClient.onTokenExpired = () {
      debugPrint('[AuthNotifier] HTTP token refresh failed — logging out');
      _clearSession();
    };
    // 监听 token 用户身份变化：每次 setToken 都会触发，保证 LocalDbService
    // 的当前 user ↔ token sub 始终一致，防止跨账号读到上一个用户的本地缓存。
    ApiClient.onUserIdDetected = _onTokenUserIdDetected;
  }

  /// token 中的 sub 与 LocalDbService.currentUserId 不一致时的兜底。
  ///
  /// 触发场景：
  /// - 切换账号过程中，新 token 已经写入但旧 DB 还没来得及关闭/重开
  /// - 冷启动恢复时，prefs 里的 access_token 与 current_user_id 错位
  /// - 任何"setToken 早于 initDb"的并发竞态
  ///
  /// 一致性破坏后，业务请求会带着新 token 但读旧 DB 的 conv_ids，
  /// 服务端必然返回 403。此处的策略是：
  ///   1. 立即 `resetIdentity()` 切断旧 DB 引用（同步），
  ///      让后续 `getConversations()` 等读操作返回空而不是脏数据；
  ///   2. 异步 `initDb(uid)` 把新 user 的库挂上，并清掉 DataLayer 的内存缓存。
  void _onTokenUserIdDetected(String uid) {
    final current = LocalDbService().currentUserId;
    if (current == uid) return; // 一致，无需处理
    debugPrint(
        '[AuthNotifier] token user mismatch: token.sub=$uid, db.user=$current — resetting DB');
    // 1. 同步切断旧 DB 引用，立即生效
    unawaited(LocalDbService().resetIdentity());
    // 2. 清掉跨账号污染的内存缓存（L1 + 在途请求）
    DataLayer().clearAll();
    ApiClient.requestManager.clearAll();
    // 3. 异步挂载新 user 的库
    unawaited(DataLayer().initDb(uid).catchError((e) {
      debugPrint('[AuthNotifier] initDb($uid) after mismatch failed: $e');
    }));
  }

  // ═══════════════════════════════════════════════════════════
  //  Phase 1: Synchronous restore from prefs (no network, no await)
  // ═══════════════════════════════════════════════════════════

  /// Reads token + cached user from prefs synchronously.
  /// State is set before constructor returns → HomeScreen sees it on first build.
  /// DB init + DataLayer write are deferred to background.
  void _restoreFromPrefs() {
    try {
      final token = _prefs.getString('access_token');
      if (token == null || token.isEmpty) {
        state = AuthState.initial;
        return;
      }

      ApiClient.printToken('SharedPreferences (持久层恢复)', token);
      // WS 由闪屏页/登录流程负责连接，这里只恢复 token 内存状态
      ApiClient.setToken(token, connectWs: false);

      final userIdStr = _prefs.getString('current_user_id');
      final userJson = _prefs.getString('current_user_json');

      User? user;
      if (userIdStr != null && userJson != null) {
        try {
          user = User.fromJson(
              jsonDecode(userJson) as Map<String, dynamic>);
        } catch (e) {
          debugPrint('[AuthNotifier] Failed to parse cached user: $e');
        }
      }

      state = AuthState(token: token, user: user, isLoading: false);

      // 冷启动恢复登录后，上报极光 registrationId（让服务端能向离线设备推送）。
      // 后台执行，失败静默，不阻塞启动。
      if (user != null) {
        PushService().registerAfterLogin();
      }

      // Defer DB init + DataLayer write to background
      if (user != null) {
        _initDbAndCache(user.id.toString(), user.toJson());
      }
    } catch (e) {
      debugPrint('[AuthNotifier] restoreFromPrefs error: $e');
      state = AuthState(token: _prefs.getString('access_token'), isLoading: false);
    }
  }

  void _initDbAndCache(String userIdStr, Map<String, dynamic> userJson) {
    // Unawaited — runs in background, failures are silent
    () async {
      try {
        await DataLayer().initDb(userIdStr);
        DataLayer().write('user:$userIdStr:profile', userJson);
      } catch (_) {}
    }();
  }

  // ═══════════════════════════════════════════════════════════
  //  Phase 2: Background network validate (non-blocking)
  // ═══════════════════════════════════════════════════════════

  bool _validating = false;

  Future<void> validateSession() async {
    if (_validating) return;
    if (state.token == null) return;

    _validating = true;
    try {
      final ok = await _fetchProfile().timeout(
        const Duration(seconds: 20),
      );
      if (!ok) {
        final refreshed = await _tryRefreshToken().timeout(
          const Duration(seconds: 20),
        );
        if (!refreshed) {
          await _clearSession();
        }
      }
    } catch (e) {
      debugPrint('[AuthNotifier] validateSession error: $e');
      if (state.user == null) {
        await _clearSession();
      }
    } finally {
      _validating = false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════

  User? _extractUser(Map<String, dynamic> data) {
    final userJson = data['user'];
    if (userJson is Map<String, dynamic>) {
      return User.fromJson(userJson);
    }
    final id = data['id'] ?? data['user_id'];
    if (id != null) {
      return User.fromJson({
        'id': id,
        'username': data['username'] ?? '',
        'email': data['email'] ?? '',
        'display_name': data['display_name'],
        'bio': data['bio'],
        'avatar_url': data['avatar_url'],
        'cover_photo_url': data['cover_photo_url'],
        'created_at': data['created_at'],
      });
    }
    return null;
  }

  Future<bool> _fetchProfile() async {
    try {
      final resp = await _authService.getProfile();
      if (resp.success && resp.data != null) {
        final data = resp.data;
        User? user;
        if (data is Map<String, dynamic>) {
          user = _extractUser(data) ?? User.fromJson(data);
        } else if (data is Map) {
          user = User.fromJson(Map<String, dynamic>.from(data));
        }
        if (user != null) {
          state = state.copyWith(user: user, clearError: true);
          await _saveUserToPrefs(user);
          await DataLayer().initDb(user.id.toString());
          DataLayer().write('user:${user.id}:profile', user.toJson());
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[_fetchProfile] exception: $e');
      return false;
    }
  }

  Future<bool> _tryRefreshToken() async {
    if (state.token == null) return false;
    try {
      final resp = await _authService.refreshToken();
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        if (token == null || token.isEmpty) return false;

        final user = _extractUser(data);
        ApiClient.printToken('HTTP POST /auth/refresh (AuthNotifier 刷新)', token);
        state = state.copyWith(token: token, user: user, clearError: true);
        await _prefs.setString('access_token', token);
        ApiClient.setToken(token);
        if (user != null) {
          await _saveUserToPrefs(user);
          await DataLayer().initDb(user.id.toString());
          DataLayer().write('user:${user.id}:profile', user.toJson());
        }
        return true;
      }
    } catch (e) {
      debugPrint('[_tryRefreshToken] exception: $e');
    }
    return false;
  }

  Future<void> _clearSession() async {
    state = AuthState.initial;
    // 先注销极光推送（此时 token 还在，/push/unregister 需要鉴权），
    // 再清 token。失败静默——推送注销不阻塞登出流程。
    await PushService().unregisterOnLogout();
    ApiClient.setToken(null);
    await WebSocketService().disconnect();
    DataLayer().clearAll();
    ApiClient.requestManager.clearAll();
    await DataLayer().closeDb();
    await _prefs.remove('access_token');
    await _prefs.remove('current_user_id');
    await _prefs.remove('current_user_json');
    // 跳转登录页
    ApiClient.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.login,
      (_) => false,
    );
  }

  Future<void> _saveUserToPrefs(User user) async {
    await _prefs.setString('current_user_id', user.id.toString());
    await _prefs.setString('current_user_json', jsonEncode(user.toJson()));
  }

  // ═══════════════════════════════════════════════════════════
  //  Public auth actions
  // ═══════════════════════════════════════════════════════════

  Future<bool> login(String email, String password, {String? emailCode}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await _authService.login(email, password, emailCode: emailCode);
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        if (token == null || token.isEmpty) {
          state = state.copyWith(
              isLoading: false, error: '登录失败：服务器未返回 token');
          return false;
        }

        User? user = _extractUser(data);
        ApiClient.printToken('HTTP POST /auth/login (网络登录)', token);
        // 在新 token 落地前，先清旧账号的痕迹：
        //   - 旧 WS（避免 duplicate_connection）
        //   - DataLayer 内存缓存 + L2 引用
        //   - RequestManager 队列/TTL（旧 token 的 GET 结果不应被新账号复用）
        //   - LocalDbService 旧 DB 引用（防止 onUserIdDetected 触发前的瞬态读到旧库）
        await WebSocketService().disconnect();
        DataLayer().clearAll();
        ApiClient.requestManager.clearAll();
        await LocalDbService().resetIdentity();
        state = state.copyWith(token: token, user: user, isLoading: true);
        await _prefs.setString('access_token', token);
        // 延迟 WS 连接，由调用方（如 LoginScreen._verifyWsConnection）显式控制
        ApiClient.setToken(token, connectWs: false);

        if (user == null) {
          final ok = await _fetchProfile();
          if (!ok || state.user == null) {
            state = state.copyWith(
                isLoading: false, error: '登录失败：无法获取用户信息');
            return false;
          }
        }

        await _saveUserToPrefs(state.user!);
        await DataLayer().initDb(state.user!.id.toString());
        DataLayer()
            .write('user:${state.user!.id}:profile', state.user!.toJson());

        // 预热会话数据已在闪屏页通过 DataLayer.initDb 完成，此处不再触发网络

        state = state.copyWith(
            isLoading: false, clearError: true, clearRequiresEmailCode: true);
        // 登录/注册成功后上报极光 registrationId（后台执行，不阻塞返回）。
        PushService().registerAfterLogin();
        return true;
      }
      // 后端在连续登录失败 ≥ 5 次后返回 429，要求邮箱验证码。
      // 通过 statusCode + 关键词双重判定，避免与其它 429 语义混淆。
      final requiresOtp = resp.statusCode == 429 &&
          (resp.message ?? '').contains('登录失败次数过多');
      state = state.copyWith(
        isLoading: false,
        error: resp.message ?? 'Login failed',
        requiresEmailCode: requiresOtp,
        // 一旦进入验证码流程，清掉历史 requiresEmailCode=false 的兜底
        clearRequiresEmailCode: !requiresOtp,
      );
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _userFriendlyError(e));
      return false;
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
    required String emailCode,
    String? bio,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await _authService.register({
        'username': username,
        'email': email,
        'password': password,
        'email_code': emailCode,
        if (bio != null) 'bio': bio,
      });
      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        if (token == null || token.isEmpty) {
          state = state.copyWith(
              isLoading: false, error: '注册失败：服务器未返回 token');
          return false;
        }

        User? user = _extractUser(data);
        state = state.copyWith(token: token, user: user, isLoading: true);
        await _prefs.setString('access_token', token);
        ApiClient.setToken(token);

        if (user == null) {
          await _fetchProfile();
          if (state.user == null) {
            state = state.copyWith(
                isLoading: false, error: '注册失败：无法获取用户信息');
            return false;
          }
        }

        await _saveUserToPrefs(state.user!);
        await DataLayer().initDb(state.user!.id.toString());
        DataLayer()
            .write('user:${state.user!.id}:profile', state.user!.toJson());

        // 预热会话数据已在闪屏页通过 DataLayer.initDb 完成，此处不再触发网络

        state = state.copyWith(
            isLoading: false, clearError: true, clearRequiresEmailCode: true);
        // 登录/注册成功后上报极光 registrationId（后台执行，不阻塞返回）。
        PushService().registerAfterLogin();
        return true;
      }
      state = state.copyWith(
          isLoading: false, error: resp.message ?? 'Registration failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _userFriendlyError(e));
      return false;
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final resp = await _authService.updateProfile(data);
      if (resp.success && state.user != null) {
        // 清除旧头像缓存，确保更新后重新下载
        final oldAvatarUrl = state.user!.avatarUrl;
        if (oldAvatarUrl != null && oldAvatarUrl.isNotEmpty) {
          final oldUrl = ImageUtils.resolveUrl(oldAvatarUrl);
          await CachedNetworkImage.evictFromCache(oldUrl);
        }
        final updated = state.user!.copyWith(
          displayName: data['display_name'] ?? data['first_name'],
          bio: data['bio'],
          avatarUrl: data['avatar_url'],
          coverPhotoUrl: data['cover_photo_url'],
        );
        // 清除新头像缓存（确保新 URL 也刷新）
        if (data['avatar_url'] != null && (data['avatar_url'] as String).isNotEmpty) {
          final newUrl = ImageUtils.resolveUrl(
            data['avatar_url'] is String ? data['avatar_url'] as String : data['avatar_url'].toString(),
          );
          await CachedNetworkImage.evictFromCache(newUrl);
        }
        state = state.copyWith(user: updated);
        await _saveUserToPrefs(updated);
        return true;
      }
      return false;
    } catch (e) {
      state = state.copyWith(error: _userFriendlyError(e));
      return false;
    }
  }

  void updateUser(User newUser) {
    state = state.copyWith(user: newUser);
    _saveUserToPrefs(newUser);
  }

  Future<void> logout() async {
    // 先注销极光推送（token 还在，/push/unregister 需要鉴权）
    await PushService().unregisterOnLogout();
    await WebSocketService().disconnect();
    ApiClient.setToken(null);
    DataLayer().clearAll();
    ApiClient.requestManager.clearAll();
    await DataLayer().closeDb();
    await _prefs.remove('access_token');
    await _prefs.remove('current_user_id');
    await _prefs.remove('current_user_json');
    state = AuthState.initial;
    // 跳转登录页
    ApiClient.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.login,
      (_) => false,
    );
  }

  /// 将技术异常映射为用户可读的错误提示
  String _userFriendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socket') || msg.contains('connection') || msg.contains('network')) {
      return '网络连接失败，请检查网络后重试';
    }
    if (msg.contains('timeout')) {
      return '请求超时，请检查网络后重试';
    }
    if (msg.contains('certificate') || msg.contains('handshake') || msg.contains('tls')) {
      return '连接安全验证失败，请重试';
    }
    if (msg.contains('404') || msg.contains('not found')) {
      return '服务暂时不可用，请稍后重试';
    }
    if (msg.contains('500') || msg.contains('server')) {
      return '服务器繁忙，请稍后重试';
    }
    return '操作失败，请稍后重试';
  }

  @override
  void dispose() {
    _authExpiredSub?.cancel();
    super.dispose();
  }
}

// ── Riverpod provider ──

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in main.dart via ProviderScope.overrides');
});

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthNotifier(prefs);
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});
