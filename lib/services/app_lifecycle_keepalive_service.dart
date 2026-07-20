import 'dart:async';

import 'package:flutter/material.dart';

import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/aliyun_push_service.dart';
import 'package:nonto/services/websocket_service.dart';

/// Coordinates the foreground-only Flutter WebSocket with app lifecycle state.
class AppLifecycleKeepAliveService with WidgetsBindingObserver {
  AppLifecycleKeepAliveService._()
      : _setAppForeground = WebSocketService().setAppForeground,
        _reportBackendState = _defaultReportBackendState,
        _disconnect = WebSocketService().disconnect,
        _forceReconnect = WebSocketService().forceReconnect,
        _hasAuthToken = _defaultHasAuthToken {
    installTokenHandoff();
  }

  AppLifecycleKeepAliveService.forTesting({
    required void Function(bool foreground) setAppForeground,
    required Future<void> Function(String state) reportBackendState,
    required Future<void> Function() disconnect,
    required Future<void> Function() forceReconnect,
    required bool Function() hasAuthToken,
  })  : _setAppForeground = setAppForeground,
        _reportBackendState = reportBackendState,
        _disconnect = disconnect,
        _forceReconnect = forceReconnect,
        _hasAuthToken = hasAuthToken;

  static final AppLifecycleKeepAliveService _instance =
      AppLifecycleKeepAliveService._();
  factory AppLifecycleKeepAliveService() => _instance;

  final void Function(bool foreground) _setAppForeground;
  final Future<void> Function(String state) _reportBackendState;
  final Future<void> Function() _disconnect;
  final Future<void> Function() _forceReconnect;
  final bool Function() _hasAuthToken;

  bool _started = false;
  bool? _requestedForeground;
  bool? _settledForeground;
  int _lifecycleGeneration = 0;
  Future<void> _lifecycleTask = Future<void>.value();
  Future<void>? _pendingReconcile;

  static Future<void> _defaultReportBackendState(String state) {
    return state == 'foreground'
        ? AliyunPushService().updateBackendDeviceState('foreground')
        : AliyunPushService().updateBackendDeviceState('background');
  }

  static bool _defaultHasAuthToken() {
    final token = ApiClient.token;
    return token != null && token.trim().isNotEmpty;
  }

  /// Installs the production token handoff without making [ApiClient] import
  /// lifecycle or WebSocket services.
  void installTokenHandoff() {
    ApiClient.onTokenActivated = reconcileCurrentState;
    ApiClient.onTokenCleared = _disconnect;
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) {
      didChangeAppLifecycleState(state);
    }
  }

  void stop() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _requestedForeground = null;
    _settledForeground = null;
    _pendingReconcile = null;
    _lifecycleGeneration++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(handleLifecycleState(state));
  }

  Future<void> handleLifecycleState(AppLifecycleState state) {
    final foreground = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive ||
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached =>
        false,
    };
    return _requestReconcile(foreground);
  }

  /// Re-runs the current desired state after authentication becomes available.
  Future<void> reconcileCurrentState() {
    final foreground = _requestedForeground;
    if (foreground == null) return Future<void>.value();
    return _requestReconcile(foreground, force: true);
  }

  Future<void> _requestReconcile(bool foreground, {bool force = false}) {
    if (!force && _requestedForeground == foreground) {
      final pending = _pendingReconcile;
      if (pending != null) return pending;
      if (_settledForeground == foreground) return _lifecycleTask;
    }

    _requestedForeground = foreground;
    final generation = ++_lifecycleGeneration;
    // Invalidate WebSocket work before waiting for any older lifecycle task.
    _setAppForeground(foreground);
    final previousTask = _lifecycleTask;

    late final Future<void> task;
    task = _runReconcile(
      foreground: foreground,
      generation: generation,
      previousTask: previousTask,
    ).whenComplete(() {
      if (identical(_pendingReconcile, task)) _pendingReconcile = null;
    });
    _pendingReconcile = task;
    _lifecycleTask = task;
    return task;
  }

  Future<void> _runReconcile({
    required bool foreground,
    required int generation,
    required Future<void> previousTask,
  }) async {
    try {
      await previousTask;
    } catch (error) {
      debugPrint('[AppLifecycle] prior lifecycle task failed: $error');
    }
    if (generation != _lifecycleGeneration) return;

    var succeeded = true;
    if (_hasAuthToken()) {
      try {
        await _reportBackendState(foreground ? 'foreground' : 'background');
      } catch (error) {
        succeeded = false;
        debugPrint('[AppLifecycle] backend state report failed: $error');
      }
    }
    if (generation != _lifecycleGeneration) return;

    try {
      if (foreground) {
        if (_hasAuthToken()) {
          debugPrint('[AppLifecycle] app resumed, reconnecting WebSocket');
          await _forceReconnect();
        }
      } else {
        await _disconnect();
      }
    } catch (error) {
      succeeded = false;
      debugPrint('[AppLifecycle] WebSocket transition failed: $error');
    }
    if (generation != _lifecycleGeneration) return;

    if (succeeded) {
      _settledForeground = foreground;
    } else if (_settledForeground == foreground) {
      _settledForeground = null;
    }
  }
}
