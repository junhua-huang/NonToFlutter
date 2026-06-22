/// 统一缓存键名常量，避免硬编码字符串散落各处。
///
/// 命名规范：`domain:entity[:params]`
/// - domain: 数据域（conv / msg / feed / user / notif / explore / search / post / comic）
/// - entity: 实体类型
/// - params: 可选参数（会话 ID / 用户 ID / 页码等）
///
/// 所有条目的完整描述见 [CacheManifest.entries]。
class CacheKeys {
  CacheKeys._();

  // ── 会话 ──
  static const String convFullList = 'conv:full:list';
  /// 用于 invalidate 的泛匹配模式
  static const String convPattern = 'conv:*:list';

  // ── 聊天消息 ──
  /// 预热缓存（page=1，AppWarmup 写入）
  static String msgWarmup(int convId) => 'msg:$convId:1';
  /// 会话最近消息（运行时标准 key）
  static String msgRecent(int convId) => 'msg:$convId:recent';
  /// 用户维度最近消息（带 userId 前缀）
  static String msgRecentByUser(int convId, String userId) => 'msg:$userId:$convId:recent';
  /// 社群群聊最近消息（进入前尚未知 backing conversationId 时使用）
  static String communityChatRecent(int communityId) => 'community:$communityId:chat:recent';
  /// 社群群聊 backing conversation 元信息
  static String communityChatConversation(int communityId) => 'community:$communityId:conversation';

  // ── Feed ──
  static const String feedPosts = 'feed:1:posts';
  /// 分页 Feed key
  static String feedPage(int page) => 'feed:$page:posts';

  // ── 用户 ──
  static String userProfile(dynamic userId) => 'user:$userId:profile';
  static String userPosts(dynamic userId) => 'user:$userId:posts';
  static String userPostsPage(dynamic userId, int page) => 'user:$userId:posts:$page';
  static String userLiked(dynamic userId) => 'user:$userId:liked:1';

  // ── 通知 ──
  static const String notifList = 'notif:list:1';
  static const String notifPattern = 'notif:*';
  static const String notifUnreadCount = 'notif:unread_count';

  // ── 发现 ──
  static const String exploreTopics = 'explore:trending_topics';
  static const String explorePosts = 'explore:trending_posts';
  static const String exploreUsers = 'explore:suggested_users';

  // ── 搜索 ──
  static String searchGlobal(String query) => 'search:$query:global:1';

  // ── 帖子详情 ──
  static String postDetail(dynamic postId) => 'post:$postId:detail';

  // ── 好友 ──
  /// 好友列表缓存，按最后联系时间排序
  static const String friendList = 'friend:list';

  // ── 漫展 ──
  static String comicEvents() => 'comic:events';
  static String comicDetail(dynamic eventId) => 'comic:$eventId:detail';
}