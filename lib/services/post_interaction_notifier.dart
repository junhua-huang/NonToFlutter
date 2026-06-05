import 'dart:async';

/// 帖子点赞状态变更事件
class PostLikeEvent {
  final int postId;
  final bool isLiked;
  final int likeCount;
  PostLikeEvent(this.postId, this.isLiked, this.likeCount);
}

/// 帖子浏览量变更事件
class PostViewEvent {
  final int postId;
  final int viewCount;
  PostViewEvent(this.postId, this.viewCount);
}

/// 全局帖子交互通知器（单例）
/// 用于跨页面同步点赞、浏览量等状态
class PostInteractionNotifier {
  static final PostInteractionNotifier _instance = PostInteractionNotifier._();
  factory PostInteractionNotifier() => _instance;
  PostInteractionNotifier._();

  final _likeController = StreamController<PostLikeEvent>.broadcast();
  final _viewController = StreamController<PostViewEvent>.broadcast();

  Stream<PostLikeEvent> get onLikeChanged => _likeController.stream;
  Stream<PostViewEvent> get onViewChanged => _viewController.stream;

  void notifyLikeChanged(int postId, bool isLiked, int likeCount) {
    _likeController.add(PostLikeEvent(postId, isLiked, likeCount));
  }

  void notifyViewChanged(int postId, int viewCount) {
    _viewController.add(PostViewEvent(postId, viewCount));
  }
}
