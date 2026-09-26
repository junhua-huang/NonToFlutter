import 'package:nonto/utils/date_utils.dart';
import 'user.dart';

enum PostVisibility { public, friends }

class PostVisibilityOption {
  final String value;
  final String label;

  const PostVisibilityOption(this.value, this.label);
}

const List<PostVisibilityOption> postVisibilityOptions = [
  PostVisibilityOption('public', '公开'),
  PostVisibilityOption('friends', '仅好友'),
];

/// Canonicalizes the user's saved publishing default.
///
/// The product default is public. Legacy non-canonical restrictive defaults
/// cannot be represented by the current API, so unknown defaults fall back to
/// that product default instead of inventing custom audience semantics.
String normalizeDefaultPostVisibility(String? value) {
  switch (value) {
    case 'friends':
    case 'friends_only':
      return 'friends';
    case 'public':
    default:
      return 'public';
  }
}

/// Chooses a canonical value when editing a legacy post.
///
/// A known public post remains public. Any legacy non-public/unknown value is
/// represented as friends so opening the editor never broadens its audience.
/// The caller only persists this value after an explicit save.
String normalizePostVisibilityForEdit(
  String? value, {
  bool? legacyIsPublic,
}) {
  if (value == 'public') return 'public';
  if (value == null) return legacyIsPublic == false ? 'friends' : 'public';
  return 'friends';
}

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
  final int? quotedPostId;
  final Post? quotedPost;
  final bool quotedPostUnavailable;

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
    this.quotedPostId,
    this.quotedPost,
    this.quotedPostUnavailable = false,
  });

  bool get hasImage => images != null && images!.isNotEmpty;
  bool get hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get hasMedia => hasImage || hasVideo;

  factory Post.fromJson(Map<String, dynamic> json) {
    // 后端返回 author 字段，但兼容 user 字段
    final userJson = json['author'] ?? json['user'];
    final rawQuotedPost = json['quoted_post'] ?? json['quote_post'];
    final quotedUnavailable =
        (rawQuotedPost is Map && rawQuotedPost['unavailable'] == true) ||
            json['quoted_post_unavailable'] == true;
    final Post? quotedPost = rawQuotedPost is Map && !quotedUnavailable
        ? Post.fromJson(Map<String, dynamic>.from(rawQuotedPost))
        : null;
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
      quotedPostId: json.containsKey('quoted_post_id')
          ? (json['quoted_post_id'] == null
              ? null
              : _parseInt(json['quoted_post_id']))
          : null,
      quotedPost: quotedPost,
      quotedPostUnavailable: quotedUnavailable,
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
        'quoted_post_id': quotedPostId,
        'quoted_post': quotedPost?.toJson(),
        'quoted_post_unavailable': quotedPostUnavailable,
      };

  /// Applies a partial API response while preserving every absent field.
  ///
  /// Presence is checked independently from value so an explicit JSON null can
  /// clear nullable fields, while omitted owner/media/community/timestamp data
  /// remains unchanged.
  Post mergeJson(Map<String, dynamic> json) {
    T? nullableValue<T>(String key, T? current) =>
        json.containsKey(key) ? json[key] as T? : current;

    String? nullableString(String key, String? current) =>
        json.containsKey(key) ? json[key]?.toString() : current;

    DateTime? nullableDate(String key, DateTime? current) =>
        json.containsKey(key) ? _parseDate(json[key]) : current;

    List<String>? nullableStringList(String key, List<String>? current) {
      if (!json.containsKey(key)) return current;
      final raw = json[key];
      if (raw == null) return null;
      if (raw is List) return raw.map((value) => value.toString()).toList();
      return current;
    }

    User? mergedUser = user;
    if (json.containsKey('author') || json.containsKey('user')) {
      final rawUser =
          json.containsKey('author') ? json['author'] : json['user'];
      mergedUser = rawUser is Map
          ? User.fromJson(Map<String, dynamic>.from(rawUser))
          : null;
    }

    List<String>? mergedImages = images;
    if (json.containsKey('images')) {
      mergedImages = nullableStringList('images', images);
    } else if (json.containsKey('image_urls')) {
      mergedImages = nullableStringList('image_urls', images);
    }

    Post? mergedQuotedPost = quotedPost;
    var mergedQuotedUnavailable = quotedPostUnavailable;
    if (json.containsKey('quoted_post') || json.containsKey('quote_post')) {
      final rawQuoted = json.containsKey('quoted_post')
          ? json['quoted_post']
          : json['quote_post'];
      if (rawQuoted is Map && rawQuoted['unavailable'] == true) {
        mergedQuotedPost = null;
        mergedQuotedUnavailable = true;
      } else if (rawQuoted is Map) {
        mergedQuotedPost = Post.fromJson(Map<String, dynamic>.from(rawQuoted));
        mergedQuotedUnavailable = false;
      } else if (rawQuoted == null) {
        mergedQuotedPost = null;
        mergedQuotedUnavailable = false;
      }
    }

    final mergedTopics = json.containsKey('topics')
        ? (json['topics'] is List
            ? (json['topics'] as List).map((value) {
                if (value is Map) return (value['name'] ?? '').toString();
                return value.toString();
              }).toList()
            : <String>[])
        : topics;

    return Post(
      id: json.containsKey('id') ? _parseInt(json['id']) : id,
      content: nullableString('content', content),
      videoUrl: nullableString('video_url', videoUrl),
      thumbnailUrl: json.containsKey('thumbnail_url')
          ? json['thumbnail_url']?.toString()
          : nullableString('cover_url', thumbnailUrl),
      postType: nullableString('post_type', postType),
      contentCategory: nullableString('content_category', contentCategory),
      displayRoleType: nullableString('display_role_type', displayRoleType),
      displayRoleLabel: nullableString('display_role_label', displayRoleLabel),
      userId: json.containsKey('user_id') ? _parseInt(json['user_id']) : userId,
      visibility: nullableString('visibility', visibility),
      isPublic: nullableValue<bool>('is_public', isPublic),
      user: mergedUser,
      likeCount: json.containsKey('like_count')
          ? _parseInt(json['like_count'])
          : likeCount,
      commentCount: json.containsKey('comment_count')
          ? _parseInt(json['comment_count'])
          : commentCount,
      viewCount: json.containsKey('view_count')
          ? _parseInt(json['view_count'])
          : viewCount,
      isLiked: nullableValue<bool>('is_liked', isLiked),
      createdAt: nullableDate('created_at', createdAt),
      updatedAt: nullableDate('updated_at', updatedAt),
      topics: mergedTopics,
      images: mergedImages,
      communityId: json.containsKey('community_id')
          ? (json['community_id'] == null
              ? null
              : _parseInt(json['community_id']))
          : communityId,
      communityOnly: nullableValue<bool>('community_only', communityOnly),
      quotedPostId: json.containsKey('quoted_post_id')
          ? (json['quoted_post_id'] == null
              ? null
              : _parseInt(json['quoted_post_id']))
          : quotedPostId,
      quotedPost: mergedQuotedPost,
      quotedPostUnavailable: mergedQuotedUnavailable,
    );
  }

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
      bool? communityOnly,
      int? quotedPostId,
      Post? quotedPost,
      bool? quotedPostUnavailable}) {
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
      quotedPostId: quotedPostId ?? this.quotedPostId,
      quotedPost: quotedPost ?? this.quotedPost,
      quotedPostUnavailable:
          quotedPostUnavailable ?? this.quotedPostUnavailable,
    );
  }
}
