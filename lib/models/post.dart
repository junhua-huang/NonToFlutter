import 'package:nonto/utils/date_utils.dart';
import 'user.dart';

enum PostVisibility { public, friends, private, custom }

class Post {
  final int id;
  final String? content;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? postType;
  final String? contentCategory;
  final String? displayRoleType;
  final String? displayRoleLabel;
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
  final int? communityId;
  final bool? communityOnly;

  Post({
    required this.id,
    this.content,
    this.videoUrl,
    this.thumbnailUrl,
    this.postType,
    this.contentCategory,
    this.displayRoleType,
    this.displayRoleLabel,
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
    this.communityId,
    this.communityOnly,
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
      contentCategory: json['content_category'],
      displayRoleType: json['display_role_type'],
      displayRoleLabel: json['display_role_label'],
      userId: _parseInt(json['user_id']),
      visibility: json['visibility'],
      isPublic: json['is_public'],
      user: userJson != null
          ? User.fromJson(
              userJson is Map<String, dynamic> ? userJson : <String, dynamic>{},
            )
          : null,
      likeCount: _parseInt(json['like_count']),
      commentCount: _parseInt(json['comment_count']),
      viewCount: _parseInt(json['view_count']),
      isLiked: json['is_liked'] ?? false,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      topics: () {
        final dynamic raw = json['topics'];
        if (raw is List) {
          return raw.map((e) {
            if (e is Map) return (e['name'] ?? '').toString();
            return e.toString();
          }).toList();
        }
        return <String>[];
      }(),
      images: () {
        final dynamic rawImgs = json['images'];
        if (rawImgs is List) {
          return rawImgs.map((e) => e.toString()).toList();
        }
        final dynamic rawUrls = json['image_urls'];
        if (rawUrls is List) {
          return rawUrls.map((e) => e.toString()).toList();
        }
        return null;
      }(),
      communityId: json['community_id'],
      communityOnly: json['community_only'] ?? false,
    );
  }

  static int _parseInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '0') ?? 0;

  static DateTime? _parseDate(dynamic value) =>
      value != null ? AppDateUtils.parseBeijingTime(value.toString()) : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'video_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'post_type': postType,
        'content_category': contentCategory,
        'display_role_type': displayRoleType,
        'display_role_label': displayRoleLabel,
        'user_id': userId,
        'visibility': visibility,
        'is_public': isPublic,
        'author': user?.toJson(),
        'like_count': likeCount,
        'comment_count': commentCount,
        'is_liked': isLiked,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'topics': topics,
        'images': images,
        'image_urls': images,
      };

  Post copyWith(
      {String? content,
      String? visibility,
      bool? isLiked,
      int? likeCount,
      int? commentCount,
      int? viewCount,
      List<String>? topics,
      String? videoUrl,
      String? thumbnailUrl,
      String? contentCategory,
      String? displayRoleType,
      String? displayRoleLabel,
      bool? isPublic,
      DateTime? updatedAt,
      List<String>? images,
      int? communityId,
      bool? communityOnly}) {
    return Post(
      id: id,
      content: content ?? this.content,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      postType: postType,
      contentCategory: contentCategory ?? this.contentCategory,
      displayRoleType: displayRoleType ?? this.displayRoleType,
      displayRoleLabel: displayRoleLabel ?? this.displayRoleLabel,
      userId: userId,
      visibility: visibility ?? this.visibility,
      isPublic: isPublic ?? this.isPublic,
      user: user,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      topics: topics ?? this.topics,
      images: images ?? this.images,
      communityId: communityId ?? this.communityId,
      communityOnly: communityOnly ?? this.communityOnly,
    );
  }
}
