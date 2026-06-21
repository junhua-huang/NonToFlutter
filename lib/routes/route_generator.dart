import 'package:nonto/models/user.dart';
import 'package:nonto/models/conversation.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/screens/auth/forgot_password_screen.dart';
import 'package:nonto/screens/auth/login_screen.dart';
import 'package:nonto/screens/auth/register_screen.dart';
import 'package:nonto/screens/chat/chat_room_screen.dart';
import 'package:nonto/screens/comic/comic_detail_page.dart';
import 'package:nonto/screens/comic/comic_my_events_page.dart';
import 'package:nonto/screens/comic/comic_timeline_page.dart';
import 'package:nonto/screens/comic/comic_upload_page.dart';
import 'package:nonto/screens/friends/friends_screen.dart';
import 'package:nonto/screens/home/home_screen.dart';
import 'package:nonto/screens/community/community_list_screen.dart';
import 'package:nonto/screens/community/community_detail_screen.dart';
import 'package:nonto/screens/community/community_create_screen.dart';
import 'package:nonto/screens/community/community_chat_screen.dart';
import 'package:nonto/screens/community/community_manage_screen.dart';
import 'package:nonto/screens/post/create_post_screen.dart';
import 'package:nonto/screens/post/post_detail_screen.dart';
import 'package:nonto/screens/profile/edit_profile_screen.dart';
import 'package:nonto/screens/profile/open_source_screen.dart';
import 'package:nonto/screens/profile/privacy_policy_screen.dart';
import 'package:nonto/screens/profile/settings_screen.dart';
import 'package:nonto/screens/profile/terms_of_service_screen.dart';
import 'package:nonto/screens/profile/user_profile_screen.dart';
import 'package:nonto/screens/search/search_results_screen.dart';
import 'package:nonto/screens/splash/splash_screen.dart';
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
        return _authGuard(builder: (_) => const CreatePostScreen());
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
      case AppRoutes.communityList:
        return _authGuard(builder: (_) => const CommunityListScreen());
      case AppRoutes.communityCreate:
        return _authGuard(builder: (_) => const CommunityCreateScreen());
    }

    // Parameterized deep-link routes: /profile/:id, /post/:id, /chat/:id, /topics/:topic
    final uri = Uri.tryParse(name);
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

      if (segments.length == 2 && segments[0] == 'profile') {
        if (args is User) {
          return MaterialPageRoute(
              builder: (_) => UserProfileScreen(user: args));
        }
        return _errorRoute('User argument is required for profile view');
      }

      if (segments.length == 2 && segments[0] == 'post') {
        final postId = int.parse(segments[1]);
        return MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: postId));
      }

      if (segments.length == 2 && segments[0] == 'chat') {
        // 极光推送点击跳转：/chat/:id 打开指定会话。
        // 先进入 HomeScreen(initialTab:1) 保证底部导航回退栈正确，
        // 再用 postFrame 推入 ChatRoomScreen。
        // 用 stub Conversation（仅 id）—— ChatRoomScreen 会通过 messagesProvider
        // 加载该会话的真实数据；otherUser 为 null 时顶栏显示「聊天」占位。
        final convId = int.tryParse(segments[1]);
        return _authGuard(
          builder: (_) => _ChatDeepLinkScreen(conversationId: convId),
        );
      }

      if (segments.length == 2 && segments[0] == 'topics') {
        final topic = segments[1];
        return MaterialPageRoute(
          builder: (_) => TopicSearchResultsScreen(topicName: topic),
        );
      }

      if (segments.length == 3 &&
          segments[0] == 'comic' &&
          segments[1] == 'detail') {
        final eventId = int.parse(segments[2]);
        return _authGuard(builder: (_) => ComicDetailPage(eventId: eventId));
      }

      if (segments.length == 3 &&
          segments[0] == 'comic' &&
          segments[1] == 'edit') {
        final eventId = int.parse(segments[2]);
        return _authGuard(builder: (_) => ComicUploadPage(eventId: eventId));
      }

      // ── 社群参数路由 ──
      if (segments.length == 2 && segments[0] == 'communities') {
        final communityId = int.parse(segments[1]);
        return _authGuard(
            builder: (_) => CommunityDetailScreen(communityId: communityId));
      }
      if (segments.length == 4 &&
          segments[0] == 'communities' &&
          segments[2] == 'chat') {
        final communityId = int.parse(segments[1]);
        return _authGuard(
            builder: (_) => CommunityChatScreen(communityId: communityId));
      }
      if (segments.length == 4 &&
          segments[0] == 'communities' &&
          segments[2] == 'manage') {
        final communityId = int.parse(segments[1]);
        return _authGuard(
            builder: (_) => CommunityManageScreen(communityId: communityId));
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

/// 极光推送点击「私信」通知后的落地页：先建好 HomeScreen（消息 Tab）回退栈，
/// 首帧后推入 ChatRoomScreen。
/// convId 为空时只进入消息 Tab（兼容旧调用）。
class _ChatDeepLinkScreen extends StatefulWidget {
  final int? conversationId;
  const _ChatDeepLinkScreen({this.conversationId});

  @override
  State<_ChatDeepLinkScreen> createState() => _ChatDeepLinkScreenState();
}

class _ChatDeepLinkScreenState extends State<_ChatDeepLinkScreen> {
  bool _pushed = false;

  @override
  Widget build(BuildContext context) {
    // 首帧后推入 ChatRoomScreen，确保底部导航栈完整。
    if (widget.conversationId != null && !_pushed) {
      _pushed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // stub Conversation：仅 id。ChatRoomScreen 通过 messagesProvider 加载真实数据，
        // otherUser 为 null 时顶栏显示「聊天」占位，不会崩。
        final stub = Conversation(
          id: widget.conversationId!,
          user1Id: 0,
          user2Id: 0,
        );
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatRoomScreen(conversation: stub),
        ));
      });
    }
    return const HomeScreen(initialTab: 1);
  }
}
