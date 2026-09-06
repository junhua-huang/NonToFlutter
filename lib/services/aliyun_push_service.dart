import 'dart:async';
import 'dart:io';

import 'package:aliyun_push_flutter/aliyun_push_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/push_device_service.dart';
import 'package:nonto/services/app_runtime_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alibaba Cloud Mobile Push setup, diagnostics, and backend device binding.
typedef BackendDeviceOperation = Future<bool> Function(String deviceId);

class AliyunPushService {
  AliyunPushService._()
      : _hasAuthToken = _defaultHasAuthToken,
        _authSessionKey = _defaultAuthSessionKey,
        _deviceIdProvider = null,
        _registerDevice = null,
        _unregisterDevice = null,
        _initializeDevice = null;

  @visibleForTesting
  AliyunPushService.forTesting({
    required bool Function() hasAuthToken,
    String? Function()? authSessionKey,
    required Future<String> Function() deviceIdProvider,
    required BackendDeviceOperation registerDevice,
    required BackendDeviceOperation unregisterDevice,
    Future<String> Function()? initializeDevice,
  })  : _hasAuthToken = hasAuthToken,
        _authSessionKey =
            authSessionKey ?? (() => hasAuthToken() ? 'active' : null),
        _deviceIdProvider = deviceIdProvider,
        _registerDevice = registerDevice,
        _unregisterDevice = unregisterDevice,
        _initializeDevice = initializeDevice;

  static final AliyunPushService _instance = AliyunPushService._();
  factory AliyunPushService() => _instance;

  static const MethodChannel _configChannel =
      MethodChannel('nonto/aliyun_push_config');
  static const _diagnosticKeys = <String>[
    'aliyun_push_supported',
    'aliyun_push_initialized',
    'aliyun_push_init_at',
    'aliyun_push_init_code',
    'aliyun_push_init_error',
    'aliyun_push_third_init_at',
    'aliyun_push_third_init_code',
    'aliyun_push_third_init_error',
    'aliyun_push_device_id',
    'aliyun_push_last_callback_type',
    'aliyun_push_last_callback_at',
    'aliyun_push_last_error',
    'aliyun_push_backend_bind_status',
    'aliyun_push_backend_bind_at',
    'aliyun_push_backend_bind_error',
    'aliyun_push_backend_unbind_at',
    'aliyun_push_backend_unbind_error',
    'aliyun_push_backend_state_status',
    'aliyun_push_backend_state_at',
    'aliyun_push_backend_state_error',
    'aliyun_push_huawei_configured',
    'aliyun_push_oppo_configured',
    'aliyun_push_vivo_configured',
  ];

  final AliyunPushFlutter _plugin = AliyunPushFlutter();
  final bool Function() _hasAuthToken;
  final String? Function() _authSessionKey;
  final Future<String> Function()? _deviceIdProvider;
  final BackendDeviceOperation? _registerDevice;
  final BackendDeviceOperation? _unregisterDevice;
  final Future<String> Function()? _initializeDevice;
  bool _initialized = false;
  bool _receiverAdded = false;
  String _readyDeviceId = '';
  bool _desiredAuthenticated = false;
  bool _backendBound = false;
  String? _desiredSessionKey;
  String? _boundSessionKey;
  bool _unbindSettled = false;
  int _authGeneration = 0;
  Future<void> _bindingQueue = Future<void>.value();

  static bool _defaultHasAuthToken() => _defaultAuthSessionKey() != null;

  static String? _defaultAuthSessionKey() {
    final token = ApiClient.token;
    return token != null && token.trim().isNotEmpty ? token : null;
  }

  Future<void> init() async {
    await _clearLegacySensitiveDiagnostics();
    final initializeDevice = _initializeDevice;
    if (initializeDevice != null) {
      _readyDeviceId = await initializeDevice();
      _initialized = _readyDeviceId.isNotEmpty;
      if (_hasAuthToken()) {
        await reconcileBackendBinding(authenticated: true);
      }
      return;
    }
    if (_initialized || kIsWeb || !Platform.isAndroid) {
      await _recordDiagnostic({
        'aliyun_push_supported': !kIsWeb && Platform.isAndroid,
      });
      return;
    }

    await _recordDiagnostic({
      'aliyun_push_supported': true,
      'aliyun_push_last_error': '',
    });

    try {
      _addReceiversOnce();
      await _plugin.createAndroidChannel(
        'nonto_message_alerts',
        '南图消息提醒',
        4,
        '南图消息与互动提醒',
      );
      final config = await _loadAndroidConfig();
      await _recordDiagnostic({
        'aliyun_push_huawei_configured': config.huaweiConfigured,
        'aliyun_push_oppo_configured': config.oppoConfigured,
        'aliyun_push_vivo_configured': config.vivoConfigured,
      });

      if (config.appKey.isEmpty || config.appSecret.isEmpty) {
        await _recordDiagnostic({
          'aliyun_push_initialized': false,
          'aliyun_push_last_error': 'missing_app_key_or_secret',
        });
        return;
      }

      final initResult = await _plugin.initPush(
        appKey: config.appKey,
        appSecret: config.appSecret,
      );
      await _recordResult(
        prefix: 'aliyun_push_init',
        result: initResult,
      );
      final initCode = initResult['code']?.toString() ?? '';
      if (initCode != kAliyunPushSuccessCode.toString()) {
        await _recordDiagnostic({
          'aliyun_push_initialized': false,
          'aliyun_push_last_error':
              'init_failed:${initResult['errorMsg'] ?? initCode}',
        });
        return;
      }

      final thirdResult = await _plugin.initAndroidThirdPush();
      await _recordResult(
        prefix: 'aliyun_push_third_init',
        result: thirdResult,
      );

      final deviceId = await _plugin.getDeviceId();
      _readyDeviceId = deviceId;
      _initialized = true;
      await _recordDiagnostic({
        'aliyun_push_initialized': true,
        'aliyun_push_device_id': deviceId,
        'aliyun_push_last_error': '',
      });
      if (_hasAuthToken()) {
        await reconcileBackendBinding(authenticated: true);
      }
    } catch (e) {
      await _recordDiagnostic({
        'aliyun_push_initialized': false,
        'aliyun_push_last_error': e.toString(),
      });
      debugPrint('[AliyunPush] init failed: $e');
    }
  }

  Future<Map<String, dynamic>> debugSnapshot() async {
    final supported = !kIsWeb && Platform.isAndroid;
    final result = <String, dynamic>{
      'supported': supported,
      'initialized': _initialized,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _diagnosticKeys) {
        result[key] = prefs.getString(key) ?? '';
      }
    } catch (e) {
      result['aliyun_push_debug_error'] = e.toString();
    }
    return result;
  }

  /// Reconciles the backend device binding to the latest auth generation.
  ///
  /// Operations are serialized because an in-flight HTTP registration cannot be
  /// cancelled. A logout therefore waits for it and always queues unregister
  /// last, so a stale registration cannot leave the device bound.
  Future<void> reconcileBackendBinding({required bool authenticated}) {
    final sessionKey = authenticated ? _authSessionKey() : null;
    final shouldBind = authenticated &&
        sessionKey != null &&
        sessionKey.isNotEmpty &&
        _hasAuthToken();
    final desiredChanged =
        shouldBind != _desiredAuthenticated || sessionKey != _desiredSessionKey;
    if (desiredChanged) {
      _desiredAuthenticated = shouldBind;
      _desiredSessionKey = shouldBind ? sessionKey : null;
      _authGeneration++;
    } else if (shouldBind
        ? _backendBound && _boundSessionKey == sessionKey
        : _unbindSettled) {
      return _bindingQueue;
    }
    if (shouldBind) _unbindSettled = false;

    final requestedGeneration = _authGeneration;
    final requestedSessionKey = _desiredSessionKey;
    _bindingQueue = _bindingQueue.then((_) async {
      if (requestedGeneration != _authGeneration) return;
      if (_desiredAuthenticated) {
        if (!_hasAuthToken() ||
            (_backendBound && _boundSessionKey == requestedSessionKey)) {
          return;
        }
        await _registerCurrentDevice(
          requestedGeneration,
          requestedSessionKey!,
        );
      } else if (!_unbindSettled) {
        await _unregisterCurrentDevice();
      }
    });
    return _bindingQueue;
  }

  Future<void> registerBackendDevice() =>
      reconcileBackendBinding(authenticated: true);

  Future<void> unregisterBackendDevice() =>
      reconcileBackendBinding(authenticated: false);

  Future<String> _resolveDeviceId() async {
    if (_readyDeviceId.isNotEmpty) return _readyDeviceId;
    final injectedProvider = _deviceIdProvider;
    if (injectedProvider != null) {
      _readyDeviceId = await injectedProvider();
      return _readyDeviceId;
    }

    if (kIsWeb || !Platform.isAndroid) return '';
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('aliyun_push_device_id') ?? '';
    if (deviceId.isEmpty && _initialized) {
      deviceId = await _plugin.getDeviceId();
      if (deviceId.isNotEmpty) {
        await prefs.setString('aliyun_push_device_id', deviceId);
      }
    }
    _readyDeviceId = deviceId;
    return deviceId;
  }

  Future<void> _registerCurrentDevice(
    int generation,
    String sessionKey,
  ) async {
    try {
      final deviceId = await _resolveDeviceId();
      if (generation != _authGeneration ||
          !_desiredAuthenticated ||
          _desiredSessionKey != sessionKey ||
          !_hasAuthToken()) {
        return;
      }
      if (deviceId.isEmpty) {
        await _recordDiagnostic({
          'aliyun_push_backend_bind_status': 'skipped',
          'aliyun_push_backend_bind_at': DateTime.now().toIso8601String(),
          'aliyun_push_backend_bind_error': 'missing_device_id',
        });
        return;
      }

      final injectedRegister = _registerDevice;
      late final bool success;
      var error = '';
      if (injectedRegister != null) {
        success = await injectedRegister(deviceId);
        if (!success) error = 'request_failed';
      } else {
        final response = await PushDeviceService().registerDevice(
          deviceId: deviceId,
          manufacturer: Platform.operatingSystem,
          model: '',
          appVersion: AppRuntimeInfo.current.version,
        );
        success = response.success;
        if (!success) {
          error = _limit(
            response.message ?? 'status_${response.statusCode ?? ''}',
          );
        }
      }
      _backendBound = success;
      _boundSessionKey = success ? sessionKey : null;
      await _recordDiagnostic({
        'aliyun_push_backend_bind_status': success ? 'success' : 'failed',
        'aliyun_push_backend_bind_at': DateTime.now().toIso8601String(),
        'aliyun_push_backend_bind_error': error,
      });
    } catch (e) {
      await _recordDiagnostic({
        'aliyun_push_backend_bind_status': 'failed',
        'aliyun_push_backend_bind_at': DateTime.now().toIso8601String(),
        'aliyun_push_backend_bind_error': _limit(e.toString()),
      });
    }
  }

  Future<void> _unregisterCurrentDevice() async {
    try {
      final deviceId = await _resolveDeviceId();
      if (deviceId.isEmpty) {
        await _recordDiagnostic({
          'aliyun_push_backend_unbind_at': DateTime.now().toIso8601String(),
          'aliyun_push_backend_unbind_error': 'missing_device_id',
        });
        _backendBound = false;
        _boundSessionKey = null;
        _unbindSettled = true;
        return;
      }

      final injectedUnregister = _unregisterDevice;
      late final bool success;
      var error = '';
      if (injectedUnregister != null) {
        success = await injectedUnregister(deviceId);
        if (!success) error = 'request_failed';
      } else {
        final response = await PushDeviceService().unregisterDevice(deviceId);
        success = response.success;
        if (!success) {
          error = _limit(
            response.message ?? 'status_${response.statusCode ?? ''}',
          );
        }
      }
      if (success) {
        _backendBound = false;
        _boundSessionKey = null;
        _unbindSettled = true;
      }
      await _recordDiagnostic({
        'aliyun_push_backend_unbind_at': DateTime.now().toIso8601String(),
        'aliyun_push_backend_unbind_error': error,
      });
    } catch (e) {
      await _recordDiagnostic({
        'aliyun_push_backend_unbind_at': DateTime.now().toIso8601String(),
        'aliyun_push_backend_unbind_error': _limit(e.toString()),
      });
    }
  }

  Future<void> updateBackendDeviceState(String appState) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('aliyun_push_device_id') ?? '';
      if (deviceId.isEmpty && _initialized) {
        deviceId = await _plugin.getDeviceId();
        if (deviceId.isNotEmpty) {
          await prefs.setString('aliyun_push_device_id', deviceId);
        }
      }
      if (deviceId.isEmpty) {
        await _recordDiagnostic({
          'aliyun_push_backend_state_status': 'skipped',
          'aliyun_push_backend_state_at': DateTime.now().toIso8601String(),
          'aliyun_push_backend_state_error': 'missing_device_id',
        });
        return;
      }

      final resp = await PushDeviceService().updateDeviceState(
        deviceId: deviceId,
        appState: appState,
      );
      await _recordDiagnostic({
        'aliyun_push_backend_state_status': resp.success ? appState : 'failed',
        'aliyun_push_backend_state_at': DateTime.now().toIso8601String(),
        'aliyun_push_backend_state_error': resp.success
            ? ''
            : _limit(resp.message ?? 'status_${resp.statusCode ?? ''}'),
      });
    } catch (e) {
      await _recordDiagnostic({
        'aliyun_push_backend_state_status': 'failed',
        'aliyun_push_backend_state_at': DateTime.now().toIso8601String(),
        'aliyun_push_backend_state_error': _limit(e.toString()),
      });
    }
  }

  Future<_AliyunPushConfig> _loadAndroidConfig() async {
    final raw = await _configChannel
        .invokeMapMethod<String, dynamic>('getAliyunPushConfig')
        .timeout(const Duration(seconds: 5));
    final map = raw ?? const <String, dynamic>{};
    return _AliyunPushConfig(
      appKey: (map['androidAppKey'] ?? '').toString(),
      appSecret: (map['androidAppSecret'] ?? '').toString(),
      huaweiConfigured: map['huaweiAppIdConfigured'] == true,
      oppoConfigured: map['oppoAppKeyConfigured'] == true &&
          map['oppoAppSecretConfigured'] == true,
      vivoConfigured: map['vivoAppIdConfigured'] == true &&
          map['vivoAppKeyConfigured'] == true,
    );
  }

  void _addReceiversOnce() {
    if (_receiverAdded) return;
    _receiverAdded = true;
    _plugin.addMessageReceiver(
      onNotification: (message) => _recordCallback('notification', message),
      onNotificationOpened: (message) =>
          _recordCallback('notification_opened', message),
      onNotificationRemoved: (message) =>
          _recordCallback('notification_removed', message),
      onMessage: (message) => _recordCallback('message', message),
      onAndroidNotificationReceivedInApp: (message) =>
          _recordCallback('android_notification_received_in_app', message),
      onAndroidNotificationClickedWithNoAction: (message) =>
          _recordCallback('android_notification_clicked_no_action', message),
      onIOSChannelOpened: (message) =>
          _recordCallback('ios_channel_opened', message),
      onIOSRegisterDeviceTokenSuccess: (message) =>
          _recordCallback('ios_register_device_token_success', message),
      onIOSRegisterDeviceTokenFailed: (message) =>
          _recordCallback('ios_register_device_token_failed', message),
    );
  }

  Future<void> _recordResult({
    required String prefix,
    required Map<dynamic, dynamic> result,
  }) async {
    final code = result['code']?.toString() ?? '';
    final error = result['errorMsg']?.toString() ?? '';
    await _recordDiagnostic({
      '${prefix}_at': DateTime.now().toIso8601String(),
      '${prefix}_code': code,
      '${prefix}_error': error,
    });
  }

  Future<void> _recordCallback(String type, Map<dynamic, dynamic> _) async {
    await _recordDiagnostic({
      'aliyun_push_last_callback_type': type,
      'aliyun_push_last_callback_at': DateTime.now().toIso8601String(),
      'aliyun_push_last_error': '',
    });
  }

  Future<void> _clearLegacySensitiveDiagnostics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('aliyun_push_last_payload_summary');
    } catch (error) {
      debugPrint(
        '[AliyunPush] legacy diagnostic cleanup failed '
        '(exception_type=${error.runtimeType})',
      );
    }
  }

  Future<void> _recordDiagnostic(Map<String, Object?> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in values.entries) {
        final value = entry.value;
        if (value == null) {
          await prefs.remove(entry.key);
        } else {
          await prefs.setString(entry.key, value.toString());
        }
      }
    } catch (e) {
      debugPrint('[AliyunPush] diagnostic write failed: $e');
    }
  }

  String _limit(String value) {
    if (value.length <= 240) return value;
    return '${value.substring(0, 240)}...';
  }
}

class _AliyunPushConfig {
  const _AliyunPushConfig({
    required this.appKey,
    required this.appSecret,
    required this.huaweiConfigured,
    required this.oppoConfigured,
    required this.vivoConfigured,
  });

  final String appKey;
  final String appSecret;
  final bool huaweiConfigured;
  final bool oppoConfigured;
  final bool vivoConfigured;
}
