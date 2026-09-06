import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/app_update.dart';
import 'package:nonto/providers/app_update_notifier.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/app_update_service.dart';
import 'package:nonto/widgets/app_update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('network failure leaves the app usable', (tester) async {
    final notifier = AppUpdateNotifier(
      _StubAppUpdateService(() => throw StateError('offline')),
    );

    await tester.pumpWidget(_testApp(notifier));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-content')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(notifier.state.status, AppUpdateStatus.failed);
    expect(notifier.state.shouldPresent, isFalse);
  });

  testWidgets(
      'optional update opens from MaterialApp.builder and can be dismissed',
      (tester) async {
    final notifier = AppUpdateNotifier(
      _StubAppUpdateService(() async => _updateInfo(releaseId: 61)),
    );

    await tester.pumpWidget(_testApp(notifier));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(notifier.state.suppressOptional, isTrue);
    expect(find.byKey(const ValueKey('app-content')), findsOneWidget);
  });

  testWidgets('required update cannot be dismissed with back', (tester) async {
    final notifier = AppUpdateNotifier(
      _StubAppUpdateService(
        () async => _updateInfo(releaseId: 62, forceUpdate: true),
      ),
    );

    await tester.pumpWidget(_testApp(notifier));
    await tester.pumpAndSettle();

    expect(find.text('需要更新'), findsOneWidget);
    expect(find.text('稍后'), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('需要更新'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-content')), findsOneWidget);
  });

  testWidgets('manual recheck presents the same previously dismissed release',
      (tester) async {
    final info = _updateInfo(releaseId: 63);
    final service = _StubAppUpdateService(() async => info);
    final notifier = AppUpdateNotifier(service);

    await tester.pumpWidget(_testApp(notifier));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    final check = notifier.check();
    await tester.pump();
    await check;
    await tester.pumpAndSettle();

    expect(service.calls, 2);
    expect(notifier.state.status, AppUpdateStatus.available);
    expect(notifier.state.suppressOptional, isFalse);
    expect(find.text('发现新版本'), findsOneWidget);
  });
}

Widget _testApp(AppUpdateNotifier notifier) {
  return ProviderScope(
    overrides: <Override>[
      appUpdateProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      navigatorKey: ApiClient.navigatorKey,
      builder: (context, child) => AppUpdateGate(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('App content', key: ValueKey('app-content')),
        ),
      ),
    ),
  );
}

AppUpdateInfo _updateInfo({required int releaseId, bool forceUpdate = false}) {
  return AppUpdateInfo(
    platform: 'android',
    channel: 'stable',
    releaseId: releaseId,
    latestVersion: '1.4.0',
    latestBuildNumber: 140,
    minimumSupportedBuildNumber: forceUpdate ? 139 : 100,
    updateAvailable: true,
    forceUpdate: forceUpdate,
    updateAction: 'download',
    downloadUrl: 'https://download.example.test/nonto.apk',
    releaseNotes: const <String>['Update available'],
    publishedAt: DateTime.utc(2026, 9, 4),
    sha256: null,
    fileSize: null,
  );
}

class _StubAppUpdateService extends AppUpdateService {
  _StubAppUpdateService(this._check) : super(platform: 'android');

  final Future<AppUpdateInfo> Function() _check;
  int calls = 0;

  @override
  Future<AppUpdateInfo> check({String channel = 'stable'}) {
    calls += 1;
    return _check();
  }
}
