class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String profileView = '/profile/:id';
  static const String postDetail = '/post/:id';
  static const String chat = '/chat';
  static const String chatRoom = '/chat/:id';
  static const String notifications = '/notifications';
  static const String search = '/search';
  static const String topics = '/topics';
  static const String friends = '/friends';
  static const String settings = '/settings';
  static const String createPost = '/create-post';
  static const String editProfile = '/edit-profile';
  static const String forgotPassword = '/forgot_password';
  static const String privacyPolicy = '/privacy_policy';
  static const String termsOfService = '/terms_of_service';
  static const String openSource = '/open_source';
  static const String comicTimeline = '/comic/timeline';
  static const String comicDetail = '/comic/detail/:id';
  static const String comicUpload = '/comic/upload';
  static const String comicEdit = '/comic/edit/:id';
  static const String comicMyEvents = '/comic/my-events';

  // ── 社群 ──
  static const String communityList = '/communities';
  static const String communityDetail = '/communities/:id';
  static const String communityCreate = '/communities/create';
  static const String communityChat = '/communities/:id/chat';
  static const String communityManage = '/communities/:id/manage';

  /// Build a concrete /communities/:id route path
  static String communityDetailId(String id) => '/communities/$id';

  /// Build a concrete /profile/:id route path
  static String profileViewId(String id) => '/profile/$id';

  /// Build a concrete /post/:id route path
  static String postDetailId(String id) => '/post/$id';

  /// Build a concrete /chat/:id route path
  static String chatRoomId(String id) => '/chat/$id';
}
