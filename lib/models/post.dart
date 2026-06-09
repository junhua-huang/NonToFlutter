import 'user.dart';

enum PostVisibility { public, friends, private, custom }

class Post {
  final int id;
  final String? content;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? postType;
  final int userId;
  final String? visibility;
  final bool? isPublic;
  final User? user;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final bool? isLiked;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> topics;
  final List<String>? images;

  Post({
    required this.id,
    this.content,
    this.videoUrl,
    this.thumbnailUrl,
    this.postType,
    required this.userId,
    this.visibility,
    this.isPublic,
    this.user,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.isLiked = false,
    this.createdAt,
    this.updatedAt,
    this.topics = const [],
    this.images,
  });

  bool get hasImage => images != null && images!.isNotEmpty;
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get hasMedia => hasImage || hasVideo;

  factory Post.fromJson(Map<String, dynamic> json) {
    // 后端返回 author 字段，但兼容 user 字段
    final userJson = json['author'] ?? json['user'];
    return Post(
      id: _parseInt(json['id']),
      content: json['content'],
      videoUrl: json['video_url'],
      thumbnailUrl: json['thumbnail_url'] ?? json['cover_url'],
      postType: json['post_type'],
      userId: _parseInt(json['user_id']),
      visibility: json['visibility'],
      isPublic: json['is_public'],
      user: userJson != null ? User.fromJson(userJson as Map<String, dynamic>) : null,
      likeCount: _parseInt(json['like_count']),
      commentCount: _parseInt(json['comment_count']),
      viewCount: _parseInt(json['view_count']),
      isLiked: json['is_liked'] ?? false,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      topics: (json['topics'] as List<dynamic>?)?.map((e) {
        if (e is Map) return (e['name'] ?? '').toString();
        return e.toString();
      }).toList() ?? [],
      images: (json['images'] as List<dynamic>?)?.map((e) => e.toString()).toList()
          ?? (json['image_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }

  static int _parseInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '0') ?? 0;

  static DateTime? _parseDate(dynamic value) =>
      value != null ? DateTime.tryParse(value.toString()) : null;

  Map<String, dynamic> toJson() => {
    'id': id, 'content': content,
    'video_url': videoUrl, 'thumbnail_url': thumbnailUrl, 'post_type': postType, 'user_id': userId,
    'visibility': visibility, 'is_public': isPublic, 'author': user?.toJson(),
    'like_count': likeCount, 'comment_count': commentCount,
    'is_liked': isLiked, 'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(), 'topics': topics,
    'images': images, 'image_urls': images,
  };

  Post copyWith({String? content, String? visibility, bool? isLiked,
    int? likeCount, int? commentCount, int? viewCount, List<String>? topics,
    String? videoUrl, String? thumbnailUrl, bool? isPublic, DateTime? updatedAt,
    List<String>? images}) {
    return Post(id: id, content: content ?? this.content,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      postType: postType,
      userId: userId, visibility: visibility ?? this.visibility,
      isPublic: isPublic ?? this.isPublic, user: user,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt,
      topics: topics ?? this.topics,
      images: images ?? this.images);
  }
}
