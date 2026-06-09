import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 监听设备网络状态变化，驱动全局离线 UI 提示。
///
/// 用法：
/// ```dart
/// final svc = ConnectivityService();
/// svc.isOnlineStream.listen((online) { ... });
/// print(svc.isOnline); // 同步查询
/// svc.dispose();       // 销毁监听
/// ```
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;

  final Connectivity _connectivity = Connectivity();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();
  Stream<bool> get isOnlineStream => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  /// 启动监听（幂等，只会启动一次）。
  void start() {
    if (_started) return;
    _started = true;

    _connectivity.checkConnectivity().then((results) {
      _updateStatus(results);
    });

    _sub = _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(online);
      debugPrint('[Connectivity] ${online ? "online" : "offline"}');
    }
  }

  /// 销毁监听（App 退出时调用）。
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}