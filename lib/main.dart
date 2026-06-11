import 'dart:ui' show PlatformDispatcher;

import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/providers/theme_notifier.dart';
import 'package:facebook_clone/routes/app_routes.dart';
import 'package:facebook_clone/routes/route_generator.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/sound_service.dart';
import 'package:facebook_clone/services/connectivity_service.dart';
import 'package:facebook_clone/services/web_utils.dart'
    if (dart.library.html) 'package:facebook_clone/services/web_utils_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Logging: all logs to console (including reliable_websocket internal logs) ──
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final prefix = '[${record.loggerName}] ${record.level.name}';
    if (record.error != null) {
      debugPrint('$prefix: ${record.message} | ${record.error}');
    } else {
      debugPrint('$prefix: ${record.message}');
    }
  });

  // ── Global error handlers ──
  // On Web, any unhandled exception during initialization will leave the
  // HTML loading overlay stuck forever. These handlers force-hide it so the
  // user at least sees the red error screen instead of a frozen spinner.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    hideWebLoadingOverlay();
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    hideWebLoadingOverlay();
    return true;
  };

  // Drift Web 初始化：加载 sqlite3 WASM
  if (kIsWeb) {
    // Web 端 drift 会自动通过 IndexedDB / WASM 工作
    // 如需自定义 sqlite3.wasm 路径，可在此处配置
  }

  // ── SharedPreferences ──
  // On Web this reads from localStorage; catch any failure to prevent
  // the app from silently dying before runApp().
  SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('SharedPreferences.getInstance() failed: $e');
    hideWebLoadingOverlay();
    // Retry once — localStorage may need an event-loop tick on some browsers
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SharedPreferences retry failed: $e');
      rethrow;
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const FacebookCloneApp(),
    ),
  );

  // Web: 成功初始化后隐藏 HTML loading overlay（与 index.html 双保险）
  hideWebLoadingOverlay();
}

class FacebookCloneApp extends ConsumerWidget {
  const FacebookCloneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // 启动网络监听（幂等）
    ConnectivityService().start();

    return Listener(
      // Web 音频解锁：首次用户指针事件触发后解除浏览器自动播放限制
      onPointerDown: (_) => SoundService().unlockAudio(),
      child: StreamBuilder<bool>(
        stream: ConnectivityService().isOnlineStream,
        initialData: true,
        builder: (context, snapshot) {
          final isOnline = snapshot.data ?? true;

          return MaterialApp(
            title: 'nonto',
            navigatorKey: ApiClient.navigatorKey,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return Column(
                children: [
                  if (!isOnline)
                    SafeArea(
                      bottom: false,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        color: const Color(0xFFE74C3C),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text(
                              '当前无网络连接',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: child ?? const SizedBox.shrink()),
                ],
              );
            },
            theme: ThemeData(
          platform: TargetPlatform.iOS,
          useMaterial3: true,
          colorSchemeSeed: AppColors.primary,
          brightness: Brightness.light,
          scaffoldBackgroundColor: AppColors.background,
          appBarTheme: AppTheme.appBarTheme,
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: AppColors.background,
            selectedItemColor: AppColors.textPrimary,
            unselectedItemColor: AppColors.textSecondary,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
            unselectedLabelStyle: TextStyle(fontSize: 11),
          ),
          dividerColor: AppColors.borderLight,
          cardColor: AppColors.background,
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          highlightColor: AppColors.primary.withValues(alpha: 0.04),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
              TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
            },
          ),
          textTheme: const TextTheme(
            bodyLarge:
                TextStyle(color: AppColors.textPrimary, fontSize: 15),
            bodyMedium:
                TextStyle(color: AppColors.textPrimary, fontSize: 14),
            titleLarge: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: AppColors.primary),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titleTextStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        darkTheme: ThemeData(
          platform: TargetPlatform.iOS,
          useMaterial3: true,
          colorSchemeSeed: AppColors.primary,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF000000),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF000000),
            foregroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0.5,
            shadowColor: Color(0xFF2A2A2A),
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF000000),
            selectedItemColor: Colors.white,
            unselectedItemColor: AppColors.textTertiary,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
            unselectedLabelStyle: TextStyle(fontSize: 11),
          ),
          dividerColor: const Color(0xFF2A2A2A),
          cardColor: const Color(0xFF16181C),
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          highlightColor: AppColors.primary.withValues(alpha: 0.04),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
              TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
            },
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white, fontSize: 15),
            bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
            titleLarge: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: AppColors.primary),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titleTextStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        themeMode: themeMode,
        onGenerateRoute: RouteGenerator.generateRoute,
        initialRoute: AppRoutes.splash,
      );
    },
  ),
    );
  }
}
