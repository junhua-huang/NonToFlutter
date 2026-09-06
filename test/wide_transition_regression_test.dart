import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/routes/route_generator.dart';
import 'package:nonto/utils/app_transitions.dart';

void main() {
  test('wide transition is opt-in for authenticated named routes', () {
    final mobileRoute = RouteGenerator.generateRoute(
      const RouteSettings(name: AppRoutes.identityCenter),
    );
    final wideRoute = RouteGenerator.generateRoute(
      const RouteSettings(
        name: AppRoutes.identityCenter,
        arguments: <String, dynamic>{'wideTransition': true},
      ),
    );

    expect(mobileRoute, isA<MaterialPageRoute<dynamic>>());
    expect(wideRoute, isA<PageRouteBuilder<dynamic>>());
    expect(wideRoute.settings.name, AppRoutes.identityCenter);
  });

  testWidgets('slide transition combines configured horizontal motion and fade',
      (tester) async {
    final pageKey = GlobalKey();
    final route = AppTransitions.slide(
      page: ColoredBox(key: pageKey, color: Colors.red),
      settings: const RouteSettings(name: '/wide-test'),
      begin: const Offset(0.4, 0),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ColoredBox(color: Colors.white),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final slide =
        tester.widgetList<SlideTransition>(find.byType(SlideTransition)).last;
    final fade =
        tester.widgetList<FadeTransition>(find.byType(FadeTransition)).last;

    expect(route.settings.name, '/wide-test');
    expect(route.transitionDuration, AppTransitions.slideDuration);
    expect(slide.position.value.dx, greaterThan(0.2));
    expect(slide.position.value.dx, lessThan(0.4));
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
    expect(find.byKey(pageKey), findsOneWidget);
  });
}
