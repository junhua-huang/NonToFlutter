import 'user.dart';

class Comment {
  final int id;
  final String content;
  final int userId;
  final int postId;
  final int? parentId;
  final int? replyToUserId;
  final User? replyToUser;
  final User? user;
  final int likeCount;
  final int replyCount;
  final bool isLiked;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<Comment> replies;
  final bool repliesHasMore; // 回复是否还有更多页
  final int repliesPage; // 当前回复页码

  Comment({
    required this.id, required this.content, required this.userId,
    required this.postId, this.parentId, this.replyToUserId,
    this.replyToUser, this.user, this.likeCount = 0, this.replyCount = 0,
    this.isLiked = false,
    this.createdAt, this.updatedAt, this.replies = const [],
    this.repliesHasMore = false,
    this.repliesPage = 1,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    // 后端返回 author 字段，但兼容 user 字段
    final userJson = json['author'] ?? json['user'];
    final replyToUserJson = json['reply_to_user'];
    return Comment(
      id: _p(json['id']), content: json['content'] ?? '',
      userId: _p(json['user_id']), postId: _p(json['post_id']),
      parentId: json['parent_id'] != null ? _p(json['parent_id']) : null,
      replyToUserId: json['reply_to_user_id'] != null ? _p(json['reply_to_user_id']) : null,
      replyToUser: replyToUserJson != null ? User.fromJson(replyToUserJson as Map<String, dynamic>) : null,
      user: userJson != null ? User.fromJson(userJson as Map<String, dynamic>) : null,
      likeCount: _p(json['like_count']),
      replyCount: _p(json['reply_count']),
      isLiked: json['is_liked'] == true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      replies: (json['replies'] as List<dynamic>?)
          ?.map((e) => Comment.fromJson(e)).toList() ?? [],
      repliesHasMore: json['replies_has_more'] == true,
      repliesPage: _p(json['replies_page'] ?? 1),
    );
  }

  static int _p(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

  Comment copyWith({
    int? id, String? content, int? userId, int? postId,
    int? parentId, int? replyToUserId, User? replyToUser, User? user,
    int? likeCount, int? replyCount, bool? isLiked,
    DateTime? createdAt, DateTime? updatedAt, List<Comment>? replies,
    bool? repliesHasMore, int? repliesPage,
  }) => Comment(
    id: id ?? this.id,
    content: content ?? this.content,
    userId: userId ?? this.userId,
    postId: postId ?? this.postId,
    parentId: parentId ?? this.parentId,
    replyToUserId: replyToUserId ?? this.replyToUserId,
    replyToUser: replyToUser ?? this.replyToUser,
    user: user ?? this.user,
    likeCount: likeCount ?? this.likeCount,
    replyCount: replyCount ?? this.replyCount,
    isLiked: isLiked ?? this.isLiked,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    replies: replies ?? this.replies,
    repliesHasMore: repliesHasMore ?? this.repliesHasMore,
    repliesPage: repliesPage ?? this.repliesPage,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'content': content, 'user_id': userId, 'post_id': postId,
    'parent_id': parentId, 'reply_to_user_id': replyToUserId,
    'reply_to_user': replyToUser?.toJson(), 'author': user?.toJson(),
    'like_count': likeCount, 'reply_count': replyCount,
    'is_liked': isLiked,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}
