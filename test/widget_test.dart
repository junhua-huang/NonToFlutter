import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:facebook_clone/main.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/providers/theme_provider.dart';

void main() {
  testWidgets('App renders login screen when not logged in', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'cookie_consent': true});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const FacebookCloneApp(),
      ),
    );
    await tester.pumpAndSettle();
    // Splash screen uses Future.delayed(~2.5s) before checking cookie consent, then another ~4.5s
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsWidgets);
  });
}
