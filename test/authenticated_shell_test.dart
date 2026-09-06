import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/providers/notifications_notifier.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/services/aliyun_push_service.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/widgets/authenticated_shell.dart';
import 'package:nonto/widgets/wide_navigation_column.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    shellRouteObserver.resetForTesting();
  });

  tearDown(() {
    shellRouteObserver.resetForTesting();
  });

  testWidgets('shows the persistent shell for an authenticated landscape route',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _authFixture(authenticated: true);
    await tester.pumpWidget(
      _testApp(fixture, initialRoute: AppRoutes.home),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WideNavigationColumn), findsOneWidget);
    expect(tester.getSize(find.byType(WideNavigationColumn)).width, 224);
    expect(find.byKey(const ValueKey('shell_right_content')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('shell_right_content'))).width,
      960,
    );
  });

  testWidgets('hides the shell for splash, login, and register routes',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final route in <String>[
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.register,
    ]) {
      shellRouteObserver.resetForTesting();
      final fixture = await _authFixture(authenticated: true);
      await tester.pumpWidget(
        _testApp(fixture, initialRoute: route),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(WideNavigationColumn),
        findsNothing,
        reason: 'public route $route must not render the shell',
      );
    }
  });

  testWidgets('hides the landscape shell when the session is not authenticated',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _authFixture(authenticated: false);
    await tester.pumpWidget(
      _testApp(fixture, initialRoute: AppRoutes.home),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WideNavigationColumn), findsNothing);
  });

  testWidgets('shows the landscape shell below the former width breakpoint',
      (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _authFixture(authenticated: true);
    await tester.pumpWidget(
      _testApp(fixture, initialRoute: AppRoutes.home),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WideNavigationColumn), findsOneWidget);
  });

  testWidgets('keeps the portrait shell on a wide portrait viewport',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _authFixture(authenticated: true);
    await tester.pumpWidget(
      _testApp(fixture, initialRoute: AppRoutes.home),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WideNavigationColumn), findsNothing);
  });

  testWidgets('updates the shell while rotating between orientations',
      (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _authFixture(authenticated: true);
    await tester.pumpWidget(
      _testApp(fixture, initialRoute: AppRoutes.home),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WideNavigationColumn), findsNothing);

    tester.view.physicalSize = const Size(900, 600);
    await tester.pumpAndSettle();
    expect(find.byType(WideNavigationColumn), findsOneWidget);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    expect(find.byType(WideNavigationColumn), findsNothing);
  });

  testWidgets('keeps the left rail while opening a menu page', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fixture = await _authFixture(authenticated: true);
    await tester.pumpWidget(
      _testApp(fixture, initialRoute: AppRoutes.home),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('wide_menu_identity-center')));
    await tester.pumpAndSettle();
    expect(find.text('identity-page'), findsOneWidget);
    expect(find.byType(WideNavigationColumn), findsOneWidget);
  });
}

Widget _testApp(_AuthFixture fixture, {required String initialRoute}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(fixture.prefs),
      authProvider.overrideWith((ref) => fixture.notifier),
      conversationsProvider.overrideWith(
        (ref) => ConversationsNotifier(loadOnInit: false),
      ),
      notificationsProvider.overrideWith(
        (ref) => NotificationsNotifier(
          getUnreadCount: () async => const ApiResponse(success: true),
        ),
      ),
    ],
    child: MaterialApp(
      navigatorKey: ApiClient.navigatorKey,
      navigatorObservers: [shellRouteObserver],
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => ColoredBox(
          color: Colors.white,
          child: SizedBox.expand(
            child: settings.name == AppRoutes.identityCenter
                ? const Center(child: Text('identity-page'))
                : Container(
                    key: const ValueKey('shell_right_content'),
                    color: Colors.white,
                  ),
          ),
        ),
      ),
      builder: (context, child) => AuthenticatedShell(
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

class _AuthFixture {
  final SharedPreferences prefs;
  final AuthNotifier notifier;

  const _AuthFixture(this.prefs, this.notifier);
}

Future<_AuthFixture> _authFixture({required bool authenticated}) async {
  final values = <String, Object>{};
  if (authenticated) {
    values.addAll(<String, Object>{
      'access_token': 'shell-test-token',
      'current_user_id': '7',
      'current_user_json': jsonEncode(<String, Object>{
        'id': 7,
        'username': 'shell-user',
        'email': 'shell@example.test',
        'display_name': 'Shell User',
      }),
    });
  }
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final pushService = AliyunPushService.forTesting(
    hasAuthToken: () => authenticated,
    deviceIdProvider: () async => '',
    registerDevice: (_) async => true,
    unregisterDevice: (_) async => true,
  );
  final notifier = AuthNotifier.forTesting(
    prefs,
    pushService: pushService,
  );
  await notifier.restoredSessionReady;
  return _AuthFixture(prefs, notifier);
}
