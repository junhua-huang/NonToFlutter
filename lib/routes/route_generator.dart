import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_notifier.dart';
import 'package:facebook_clone/routes/app_routes.dart';
import 'package:facebook_clone/screens/auth/forgot_password_screen.dart';
import 'package:facebook_clone/screens/auth/login_screen.dart';
import 'package:facebook_clone/screens/auth/register_screen.dart';
import 'package:facebook_clone/screens/comic/comic_detail_page.dart';
import 'package:facebook_clone/screens/comic/comic_my_events_page.dart';
import 'package:facebook_clone/screens/comic/comic_timeline_page.dart';
import 'package:facebook_clone/screens/comic/comic_upload_page.dart';
import 'package:facebook_clone/screens/friends/friends_screen.dart';
import 'package:facebook_clone/screens/home/home_screen.dart';
import 'package:facebook_clone/screens/post/post_detail_screen.dart';
import 'package:facebook_clone/screens/profile/edit_profile_screen.dart';
import 'package:facebook_clone/screens/profile/open_source_screen.dart';
import 'package:facebook_clone/screens/profile/privacy_policy_screen.dart';
import 'package:facebook_clone/screens/profile/settings_screen.dart';
import 'package:facebook_clone/screens/profile/terms_of_service_screen.dart';
import 'package:facebook_clone/screens/profile/user_profile_screen.dart';
import 'package:facebook_clone/screens/search/search_results_screen.dart';
import 'package:facebook_clone/screens/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class RouteGenerator {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments;
    final name = settings.name;
    if (name == null) return _errorRoute('Route name is null');

    // Exact routes
    switch (name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case AppRoutes.register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case AppRoutes.home:
        return _authGuard(builder: (_) => const HomeScreen());
      case AppRoutes.profile:
        return _authGuard(builder: (_) => const HomeScreen(initialTab: 3));
      case AppRoutes.chat:
        return _authGuard(builder: (_) => const HomeScreen(initialTab: 1));
      case AppRoutes.notifications:
        return _authGuard(builder: (_) => const HomeScreen(initialTab: 2));
      case AppRoutes.search:
        return _authGuard(builder: (_) => const HomeScreen(initialTab: 4));
      case AppRoutes.friends:
        return _authGuard(builder: (_) => const FriendsScreen());
      case AppRoutes.createPost:
        return _authGuard(builder: (_) => const HomeScreen(initialTab: 0));
      case AppRoutes.editProfile:
        return _authGuard(builder: (_) => const EditProfileScreen());
      case AppRoutes.settings:
        return _authGuard(builder: (_) => const SettingsScreen());
      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case AppRoutes.privacyPolicy:
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen());
      case AppRoutes.termsOfService:
        return MaterialPageRoute(builder: (_) => const TermsOfServiceScreen());
      case AppRoutes.openSource:
        return MaterialPageRoute(builder: (_) => const OpenSourceScreen());
      case AppRoutes.comicTimeline:
        return _authGuard(builder: (_) => const ComicTimelinePage());
      case AppRoutes.comicUpload:
        return _authGuard(builder: (_) => const ComicUploadPage());
      case AppRoutes.comicMyEvents:
        return _authGuard(builder: (_) => const ComicMyEventsPage());
    }

    // Parameterized deep-link routes: /profile/:id, /post/:id, /chat/:id, /topics/:topic
    final uri = Uri.tryParse(name);
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

      if (segments.length == 2 && segments[0] == 'profile') {
        if (args is User) {
          return MaterialPageRoute(builder: (_) => UserProfileScreen(user: args));
        }
        return _errorRoute('User argument is required for profile view');
      }

      if (segments.length == 2 && segments[0] == 'post') {
        final postId = int.parse(segments[1]);
        return MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId));
      }

      if (segments.length == 2 && segments[0] == 'chat') {
        return _authGuard(builder: (_) => const HomeScreen(initialTab: 1));
      }

      if (segments.length == 2 && segments[0] == 'topics') {
        final topic = segments[1];
        return MaterialPageRoute(
          builder: (_) => TopicSearchResultsScreen(topicName: topic),
        );
      }

      if (segments.length == 3 && segments[0] == 'comic' && segments[1] == 'detail') {
        final eventId = int.parse(segments[2]);
        return _authGuard(builder: (_) => ComicDetailPage(eventId: eventId));
      }

      if (segments.length == 3 && segments[0] == 'comic' && segments[1] == 'edit') {
        final eventId = int.parse(segments[2]);
        return _authGuard(builder: (_) => ComicUploadPage(eventId: eventId));
      }
    }

    return _errorRoute('Route not found');
  }

  static Route<dynamic> _authGuard({required WidgetBuilder builder}) {
    return MaterialPageRoute(
      builder: (context) {
        final auth = ProviderScope.containerOf(context).read(authProvider);
        if (!auth.isLoggedIn) {
          // 给用户一个提示，而不是静默跳转
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('请先登录'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
          return const LoginScreen();
        }
        return builder(context);
      },
    );
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(message)),
      ),
    );
  }
}