import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/models/app_update.dart';
import 'package:nonto/services/api/app_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppUpdateStatus { idle, checking, upToDate, available, failed }

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.info = AppUpdateInfo.none,
    this.error,
    this.suppressOptional = false,
  });

  final AppUpdateStatus status;
  final AppUpdateInfo info;
  final String? error;
  final bool suppressOptional;

  bool get shouldPresent =>
      status == AppUpdateStatus.available &&
      info.updateAvailable &&
      (info.forceUpdate || !suppressOptional);

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    AppUpdateInfo? info,
    String? error,
    bool clearError = false,
    bool? suppressOptional,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      error: clearError ? null : error ?? this.error,
      suppressOptional: suppressOptional ?? this.suppressOptional,
    );
  }
}

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  AppUpdateNotifier(this._service) : super(const AppUpdateState());

  static const _lastAutomaticCheckKey = 'app_update_last_automatic_check_at';
  static const _dismissedReleaseKey = 'app_update_dismissed_release_id';
  static const _automaticCheckInterval = Duration(hours: 24);

  final AppUpdateService _service;
  Future<AppUpdateInfo>? _inFlight;

  Future<AppUpdateInfo?> check({bool automatic = false}) async {
    if (automatic && await _automaticCheckIsFresh()) return null;
    final existing = _inFlight;
    if (existing != null) return existing;

    state = state.copyWith(
      status: AppUpdateStatus.checking,
      clearError: true,
      suppressOptional: false,
    );
    final future = _performCheck(automatic: automatic);
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  Future<AppUpdateInfo> _performCheck({required bool automatic}) async {
    try {
      final info = await _service.check();
      final prefs = await SharedPreferences.getInstance();
      final dismissed = info.releaseId != null &&
          prefs.getInt(_dismissedReleaseKey) == info.releaseId;
      if (automatic) {
        await prefs.setInt(
          _lastAutomaticCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      state = state.copyWith(
        status: info.updateAvailable
            ? AppUpdateStatus.available
            : AppUpdateStatus.upToDate,
        info: info,
        suppressOptional: automatic && dismissed && info.isOptional,
      );
      return info;
    } catch (error) {
      state = state.copyWith(
        status: AppUpdateStatus.failed,
        error: '暂时无法检查更新，请稍后重试',
      );
      return AppUpdateInfo.none;
    }
  }

  Future<bool> _automaticCheckIsFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastAutomaticCheckKey);
    if (timestamp == null) return false;
    return DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(timestamp),
        ) <
        _automaticCheckInterval;
  }

  Future<void> dismissOptional() async {
    final releaseId = state.info.releaseId;
    if (releaseId == null || state.info.forceUpdate) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedReleaseKey, releaseId);
    state = state.copyWith(suppressOptional: true);
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateNotifier, AppUpdateState>(
  (ref) => AppUpdateNotifier(AppUpdateService()),
);
