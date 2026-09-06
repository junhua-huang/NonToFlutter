import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/config/layout_breakpoints.dart';
import 'package:nonto/widgets/wide_navigation_column.dart';

void main() {
  testWidgets('renders the fixed two-column navigation column', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selectedIndex = -1;
    var composeCount = 0;
    var userTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SizedBox(
            width: 1440,
            height: 900,
            child: Align(
              alignment: Alignment.topLeft,
              child: WideNavigationColumn(
                currentIndex: 0,
                totalBadge: 12,
                user: null,
                onTabSelected: (index) => selectedIndex = index,
                onMenuSelected: (_) {},
                onCompose: () => composeCount++,
                onUserTap: () => userTapCount++,
                onLogout: () {},
                menuItems: const [
                  WideNavigationMenuItem(
                    id: WideNavigationMenuIds.settings,
                    label: '设置',
                    icon: Icons.settings_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(WideNavigationColumn)).width,
        AppBreakpoints.navigationWidth);
    expect(find.text('nonto'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('发布'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wide_navigation_1')));
    await tester.tap(find.text('发布'));
    await tester.tap(find.byKey(const ValueKey('wide_navigation_user')));

    expect(selectedIndex, 1);
    expect(composeCount, 1);
    expect(userTapCount, 1);
  });

  testWidgets('keeps compose action available outside the feed tab',
      (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: WideNavigationColumn(
            currentIndex: 2,
            totalBadge: 100,
            user: null,
            onTabSelected: (_) {},
            onMenuSelected: (_) {},
            onCompose: () {},
            onUserTap: () {},
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发布'), findsOneWidget);
    expect(find.text('100'), findsNothing);
    expect(find.text('99+'), findsOneWidget);
    expect(AppColors.primary, isNotNull);
  });
}
