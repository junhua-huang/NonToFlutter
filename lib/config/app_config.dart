import 'package:flutter/foundation.dart';
import 'package:flutter_social_video/flutter_social_video.dart';

/// 全局视频播放器复用池，限制同时存活 3 个 Player
final videoPlayerPool = PlayerPool(maxSize: 3);

/// Tab 激活通知器：用于 IndexedStack 懒加载，各 Tab 监听此值来触发首次数据加载
class TabActivationNotifier {
  static final ValueNotifier<int> currentTab = ValueNotifier(0);
}

/// 应用全局配置
class AppConfig {
  // 应用版本号
  static const String appVersion = '1.0.0';

  // 后端 API 基础地址。
  // 本地默认连电脑本机；Android 模拟器/真机/生产环境通过 --dart-define 覆盖。
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5000/api',
  );

  // WebSocket 地址。
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'http://127.0.0.1:5000/ws',
  );

  // 分页默认值
  static const int defaultPageSize = 20;

  // 文件上传最大大小 (50MB)
  static const int maxFileSize = 50 * 1024 * 1024;

  // 图片压缩质量
  static const int imageQuality = 85;

  // 支持的图片格式
  static const List<String> supportedImageFormats = [
    'jpg', 'jpeg', 'png', 'gif', 'webp',
  ];

  // 支持的视频格式
  static const List<String> supportedVideoFormats = [
    'mp4', 'avi', 'mov', 'mkv',
  ];

  // 帖子可见性
  static const String visibilityPublic = 'public';
  static const String visibilityFriends = 'friends';
  static const String visibilityPrivate = 'private';
  static const String visibilityCustom = 'custom';

  // 消息类型
  static const String msgTypeText = 'text';
  static const String msgTypeImage = 'image';
  static const String msgTypeVideo = 'video';
  static const String msgTypeFile = 'file';
  static const String msgTypePost = 'post';
  static const String msgTypeComment = 'comment';

  // 通知类型
  static const String notifTypeLike = 'like';
  static const String notifTypeComment = 'comment';
  static const String notifTypeFriendRequest = 'friend_request';
  static const String notifTypeFriendAccept = 'friend_accept';
  static const String notifTypeMention = 'mention';
  static const String notifTypeMessage = 'message';
}
