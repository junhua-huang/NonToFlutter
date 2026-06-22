import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:nonto/config/app_config.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/local_db_service.dart';

// jpush_flutter 3.x：JPush 是工厂类（主包），通过 newJPush() 取实现（Android/iOS → JPush_A_I，其它 → 鸿蒙 no-op）。
// JPushFlutterInterface / NotificationSettingsIOS 在 jpush_interface.dart，需显式导入。
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';

/// 极光推送封装。
///
/// 仅在 Android（含华为/小米/OPPO/vivo/魅族厂商通道）/iOS 上生效。
/// Web、HarmonyOS、桌面端 init() 直接返回（jpush_flutter 在这些平台返回 no-op 实现，
/// 但为避免 Web 上 dart:io 依赖问题，仍用 _supported 闸门跳过）。
///
/// 触发链路：
///   服务端检测用户离线 → 调极光 REST API 推送 → 厂商通道下发到设备 →
///   用户点击通知 → onOpenNotification 回调 → 解析 extras 跳转对应页面。
class PushService {
  PushService._();
  static final PushService _instance = PushService._();
  factory PushService() => _instance;

  // jpush_flutter 3.x：JPush.newJPush() 返回 JPushFlutterInterface。
  // 在非 Android/iOS 平台返回鸿蒙 no-op 实现，调用安全。
  late final JPushFlutterInterface _jpush = JPush.newJPush();

  bool _initialized = false;
  bool _permissionRequested = false;
  // registrationId 缓存 + 等待 future，避免登录后重复获取
  String? _registrationId;
  Completer<String?>? _regIdCompleter;

  /// 极光 AppKey（与 AndroidManifest / build.gradle 的 manifestPlaceholders 一致）。
  /// 客户端只持有 AppKey，Master Secret 仅服务端使用。
  static const String _appKey = 'c9c5db77d7cb1a466951e774';
  static const String _channel = 'nonto-default';

  /// 是否支持极光推送（仅 Android/iOS）。
  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 初始化极光 SDK。应在 main() 的 WidgetsFlutterBinding.ensureInitialized() 之后调用。
  /// 幂等：重复调用不会重复 setup。
  Future<void> init() async {
    if (_initialized) return;
    if (!_supported) {
      debugPrint('[Push] platform not supported, skip init');
      // 标记 initialized，避免非支持平台反复进入此分支
      _initialized = true;
      return;
    }
    try {
      _jpush.setup(
        appKey: _appKey,
        channel: _channel,
        production: true, // iOS: 生产环境 APNs；Android 忽略此参数
        debug: kDebugMode,
      );
      // iOS 申请推送权限；Android 13+ 通知权限用 requestRequiredPermission
      _jpush.applyPushAuthority(
        const NotificationSettingsIOS(sound: true, alert: true, badge: true),
      );
      _registerEventHandlers();
      _initialized = true;
      debugPrint('[Push] JPush setup done');
    } catch (e) {
      debugPrint('[Push] init failed: $e');
    }
  }

  /// 申请 Android 13+ 通知权限。应在用户首次交互后调用。
  /// 幂等：已授权则无副作用。
  Future<void> requestPermission() async {
    if (!_supported || !_initialized || _permissionRequested) return;
    _permissionRequested = true;
    try {
      _jpush.requestRequiredPermission();
    } catch (e) {
      debugPrint('[Push] requestPermission failed: $e');
    }
  }

  void _registerEventHandlers() {
    _jpush.addEventHandler(
      onReceiveNotification: (Map<String, dynamic> message) async {
        debugPrint('[Push] onReceiveNotification: $message');
        return null;
      },
      onOpenNotification: (Map<String, dynamic> message) async {
        debugPrint('[Push] onOpenNotification: $message');
        _handleNotificationOpen(message);
        return null;
      },
      onReceiveNotificationAuthorization: (Map<String, dynamic> message) async {
        debugPrint('[Push] onReceiveNotificationAuthorization: $message');
        return null;
      },
    );
  }

  /// 点击通知 → 解析 extras 跳转对应页面。
  /// extras 约定：{type: message|like|comment|friend_request|..., related_id, related_type}
  void _handleNotificationOpen(Map<String, dynamic> message) {
    final extras = _extractExtras(message);
    final type = (extras['type'] ?? '').toString();
    final relatedId = (extras['related_id'] ?? '').toString();
    final nav = ApiClient.navigatorKey.currentState;
    if (nav == null) {
      debugPrint('[Push] navigator not ready, skip deep-link');
      return;
    }
    switch (type) {
      case 'message':
        // 私信 → 聊天室（related_id = conversation_id）
        if (relatedId.isNotEmpty) {
          nav.pushNamed(AppRoutes.chatRoomId(relatedId));
        } else {
          nav.pushNamed(AppRoutes.home);
        }
        break;
      case 'friend_request':
      case 'friend_accept':
        // 好友相关 → 好友页
        nav.pushNamed(AppRoutes.friends);
        break;
      case 'like':
      case 'comment':
      case 'mention':
        // 互动类 → 帖子详情（related_id = post_id）
        if (relatedId.isNotEmpty) {
          nav.pushNamed(AppRoutes.postDetailId(relatedId));
        } else {
          nav.pushNamed(AppRoutes.notifications);
        }
        break;
      case 'community_join_request':
        // 社群入群申请 → 管理页待审核
        if (relatedId.isNotEmpty) {
          nav.pushNamed(AppRoutes.communityManageId(relatedId));
        } else {
          nav.pushNamed(AppRoutes.notifications);
        }
        break;
      default:
        // 其它通知 → 通知页
        nav.pushNamed(AppRoutes.notifications);
    }
  }

  /// 极光回调里 extras 位置因平台而异，统一抽取。
  Map<String, dynamic> _extractExtras(Map<String, dynamic> message) {
    final extras = message['extras'];
    if (extras is Map) {
      // Android: extras 是 {cn.jpush.android.EXTRA: {...}} 或直接平铺
      final inner = extras['cn.jpush.android.EXTRA'];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return Map<String, dynamic>.from(extras);
    }
    // 兜底：extras 可能直接平铺在 message 顶层
    return message;
  }

  /// 获取 registrationId（带 5s 超时 + 缓存）。
  /// 登录成功后调用，用于上报给服务端。
  Future<String?> getRegistrationId() async {
    if (!_supported || !_initialized) return null;
    if (_registrationId != null) return _registrationId;
    // 已有进行中的请求 → 复用
    if (_regIdCompleter != null && !_regIdCompleter!.isCompleted) {
      return _regIdCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    }
    _regIdCompleter = Completer<String?>();
    try {
      final rid = await _jpush.getRegistrationID().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[Push] getRegistrationID timeout');
          return '';
        },
      );
      if (rid.isNotEmpty) {
        _registrationId = rid;
        if (!_regIdCompleter!.isCompleted) _regIdCompleter!.complete(rid);
        return rid;
      }
    } catch (e) {
      debugPrint('[Push] getRegistrationID error: $e');
    }
    if (!_regIdCompleter!.isCompleted) _regIdCompleter!.complete(null);
    return null;
  }

  /// 设置 alias（用 user_id），便于服务端定向推送。可选。
  Future<void> setAlias(int userId) async {
    if (!_supported || !_initialized) return;
    try {
      await _jpush.setAlias(userId.toString());
      debugPrint('[Push] alias set: ${userId.toString()}');
    } catch (e) {
      debugPrint('[Push] setAlias failed: $e');
    }
  }

  /// 删除 alias（注销时调用）。
  Future<void> deleteAlias() async {
    if (!_supported || !_initialized) return;
    try {
      await _jpush.deleteAlias();
    } catch (e) {
      debugPrint('[Push] deleteAlias failed: $e');
    }
  }

  /// 登录后上报 registrationId 到服务端（完整流程）。
  /// 获取 rid → 上报 → 设 alias。失败静默，不阻塞登录。
  Future<void> registerAfterLogin() async {
    if (!_supported || !_initialized) return;
    final token = ApiClient.token;
    if (token == null || token.isEmpty) return;
    final userId = LocalDbService().currentUserId;
    try {
      final rid = await getRegistrationId();
      if (rid == null || rid.isEmpty) {
        debugPrint('[Push] no registrationId, skip upload');
        return;
      }
      // 上报（PushApiService 内部走 ApiClient，自动带 JWT）
      final ok = await PushApiService().register(
        registrationId: rid,
        platform: Platform.isIOS ? 'ios' : 'android',
        appVersion: AppConfig.appVersion,
      );
      debugPrint('[Push] register upload ok=$ok rid=$rid');
      if (userId != null) {
        final uid = int.tryParse(userId);
        if (uid != null) await setAlias(uid);
      }
    } catch (e) {
      debugPrint('[Push] registerAfterLogin error: $e');
    }
  }

  /// 注销时调用：删除 alias + 通知服务端注销设备。
  Future<void> unregisterOnLogout() async {
    if (!_supported || !_initialized) return;
    final rid = _registrationId;
    try {
      await deleteAlias();
      if (rid != null && rid.isNotEmpty) {
        await PushApiService().unregister(registrationId: rid);
      }
    } catch (e) {
      debugPrint('[Push] unregisterOnLogout error: $e');
    }
    // 清缓存，下次登录重新获取
    _registrationId = null;
    _regIdCompleter = null;
  }
}

/// 上报/注销 registrationId 的 HTTP 封装。
/// 走 ApiClient，Dio 拦截器自动带 access_token。
class PushApiService {
  Future<bool> register({
    required String registrationId,
    required String platform,
    String? appVersion,
  }) async {
    try {
      final resp = await ApiClient().post(
        '/push/register',
        data: {
          'registration_id': registrationId,
          'platform': platform,
          if (appVersion != null) 'app_version': appVersion,
        },
      );
      return resp.success;
    } catch (e) {
      debugPrint('[PushApi] register error: $e');
      return false;
    }
  }

  Future<bool> unregister({required String registrationId}) async {
    try {
      final resp = await ApiClient().post(
        '/push/unregister',
        data: {'registration_id': registrationId},
      );
      return resp.success;
    } catch (e) {
      debugPrint('[PushApi] unregister error: $e');
      return false;
    }
  }
}
