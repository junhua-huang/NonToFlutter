import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/app_lifecycle_keepalive_service.dart';

void main() {
  AppLifecycleKeepAliveService createService({
    required List<String> calls,
    bool Function()? hasToken,
    Future<void> Function(String state)? reportState,
    Future<void> Function()? disconnect,
    Future<void> Function()? forceReconnect,
  }) {
    return AppLifecycleKeepAliveService.forTesting(
      setAppForeground: (foreground) {
        calls.add('foreground:$foreground');
      },
      reportBackendState: (state) async {
        calls.add('report:$state');
        await reportState?.call(state);
      },
      disconnect: () async {
        calls.add('disconnect');
        await disconnect?.call();
      },
      forceReconnect: () async {
        calls.add('forceReconnect');
        await forceReconnect?.call();
      },
      hasAuthToken: hasToken ?? () => true,
    );
  }

  group('central token handoff', () {
    tearDown(() {
      ApiClient.token = null;
      ApiClient.onTokenActivated = null;
      ApiClient.onTokenCleared = null;
    });

    test('production nonblank token activation invokes lifecycle reconcile',
        () async {
      final calls = <String>[];
      final service = createService(
        calls: calls,
        hasToken: () {
          final token = ApiClient.token;
          return token != null && token.trim().isNotEmpty;
        },
      );
      await service.handleLifecycleState(AppLifecycleState.resumed);
      calls.clear();
      service.installTokenHandoff();

      ApiClient.setToken('  token  ', connectWs: false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        calls,
        <String>['foreground:true', 'report:foreground', 'forceReconnect'],
      );
    });

    test('clearing token disconnects without lifecycle reconcile', () async {
      final calls = <String>[];
      final service = createService(
        calls: calls,
        hasToken: () {
          final token = ApiClient.token;
          return token != null && token.trim().isNotEmpty;
        },
      );
      service.installTokenHandoff();

      ApiClient.setToken(null);
      await Future<void>.delayed(Duration.zero);

      expect(calls, <String>['disconnect']);
    });
  });

  group('AppLifecycleKeepAliveService', () {
    test('background states mark background, report, and disconnect Flutter WS',
        () async {
      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        final calls = <String>[];
        final service = createService(calls: calls);

        await service.handleLifecycleState(state);

        expect(
          calls,
          <String>['foreground:false', 'report:background', 'disconnect'],
          reason:
              '$state must use push plus an explicitly disconnected Flutter WS',
        );
      }
    });

    test('resume marks foreground, reports, and reconnects with a token',
        () async {
      final calls = <String>[];
      final service = createService(calls: calls);

      await service.handleLifecycleState(AppLifecycleState.resumed);

      expect(
        calls,
        <String>['foreground:true', 'report:foreground', 'forceReconnect'],
      );
    });

    test('resume without a token skips backend report and reconnect', () async {
      final calls = <String>[];
      final service = createService(calls: calls, hasToken: () => false);

      await service.handleLifecycleState(AppLifecycleState.resumed);

      expect(calls, <String>['foreground:true']);
    });

    test('repeated resume retries after reconnect throws', () async {
      final calls = <String>[];
      var attempts = 0;
      final service = createService(
        calls: calls,
        forceReconnect: () async {
          attempts++;
          if (attempts == 1) throw StateError('reconnect failed');
        },
      );

      await service.handleLifecycleState(AppLifecycleState.resumed);
      await service.handleLifecycleState(AppLifecycleState.resumed);

      expect(
        calls,
        <String>[
          'foreground:true',
          'report:foreground',
          'forceReconnect',
          'foreground:true',
          'report:foreground',
          'forceReconnect',
        ],
      );
    });

    test('repeated background state retries after disconnect throws', () async {
      final calls = <String>[];
      var attempts = 0;
      final service = createService(
        calls: calls,
        disconnect: () async {
          attempts++;
          if (attempts == 1) throw StateError('disconnect failed');
        },
      );

      await service.handleLifecycleState(AppLifecycleState.paused);
      await service.handleLifecycleState(AppLifecycleState.paused);

      expect(
        calls,
        <String>[
          'foreground:false',
          'report:background',
          'disconnect',
          'foreground:false',
          'report:background',
          'disconnect',
        ],
      );
    });

    test('explicit reconcile connects and reports after token appears',
        () async {
      final calls = <String>[];
      var hasToken = false;
      final service = createService(
        calls: calls,
        hasToken: () => hasToken,
      );

      await service.handleLifecycleState(AppLifecycleState.resumed);
      hasToken = true;
      await service.reconcileCurrentState();

      expect(
        calls,
        <String>[
          'foreground:true',
          'foreground:true',
          'report:foreground',
          'forceReconnect',
        ],
      );
    });

    test('serialized transitions leave the latest lifecycle state in control',
        () async {
      final calls = <String>[];
      final backgroundReport = Completer<void>();
      final service = createService(
        calls: calls,
        reportState: (state) => state == 'background'
            ? backgroundReport.future
            : Future<void>.value(),
      );

      final background = service.handleLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['foreground:false', 'report:background']);

      final resumed = service.handleLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(
        calls,
        <String>['foreground:false', 'report:background', 'foreground:true'],
      );

      backgroundReport.complete();
      await Future.wait(<Future<void>>[background, resumed]);

      expect(
        calls,
        <String>[
          'foreground:false',
          'report:background',
          'foreground:true',
          'report:foreground',
          'forceReconnect',
        ],
        reason:
            'the stale background transition must not disconnect after resume',
      );
    });

    test('coalesces repeated lifecycle states with the same foreground mode',
        () async {
      final calls = <String>[];
      final service = createService(calls: calls);

      final inactive = service.handleLifecycleState(AppLifecycleState.inactive);
      final paused = service.handleLifecycleState(AppLifecycleState.paused);
      final hidden = service.handleLifecycleState(AppLifecycleState.hidden);
      await Future.wait(<Future<void>>[inactive, paused, hidden]);

      expect(
        calls,
        <String>['foreground:false', 'report:background', 'disconnect'],
      );
    });
  });
}
