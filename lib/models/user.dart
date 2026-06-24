import 'package:nonto/utils/date_utils.dart';

/// 用户模型
class User {
  final int id;
  final String username;
  final String email;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final String? coverPhotoUrl;
  final DateTime? createdAt;
  final bool? isOnline;
  final List<String> verifiedRoles;
  final List<String> verifiedRoleLabels;

  /// 头像缓存破坏标记（上传后更新，防止 CachedNetworkImage 使用旧缓存）
  final int? avatarCacheTs;

  /// 背景图缓存破坏标记
  final int? coverCacheTs;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    this.bio,
    this.avatarUrl,
    this.coverPhotoUrl,
    this.createdAt,
    this.isOnline,
    this.verifiedRoles = const [],
    this.verifiedRoleLabels = const [],
    this.avatarCacheTs,
    this.coverCacheTs,
  });

  String get initials {
    return username.isNotEmpty ? username[0].toUpperCase() : '?';
  }

  bool get hasVerifiedIdentity => verifiedRoles.isNotEmpty;

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final verifiedRoles = _parseStringList(json['verified_roles']);
    final rawVerifiedLabels = _parseStringList(json['verified_role_labels']);
    final verifiedRoleLabels = verifiedRoles.isEmpty
        ? const <String>[]
        : rawVerifiedLabels.take(verifiedRoles.length).toList();

    return User(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'],
      bio: json['bio'],
      avatarUrl: json['avatar_url'],
      coverPhotoUrl: json['cover_photo_url'],
      isOnline: json['is_online'],
      verifiedRoles: verifiedRoles,
      verifiedRoleLabels: verifiedRoleLabels,
      avatarCacheTs: json['avatar_cache_ts'],
      coverCacheTs: json['cover_cache_ts'],
      createdAt: json['created_at'] != null
          ? AppDateUtils.parseBeijingTime(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'display_name': displayName,
      'bio': bio,
      'avatar_url': avatarUrl,
      'cover_photo_url': coverPhotoUrl,
      'avatar_cache_ts': avatarCacheTs,
      'cover_cache_ts': coverCacheTs,
      'is_online': isOnline,
      'verified_roles': verifiedRoles,
      'verified_role_labels': verifiedRoleLabels,
      'roles': verifiedRoles,
      'role_labels': verifiedRoleLabels,
    };
  }

  User copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? coverPhotoUrl,
    bool? isOnline,
    int? avatarCacheTs,
    int? coverCacheTs,
    List<String>? verifiedRoles,
    List<String>? verifiedRoleLabels,
  }) {
    return User(
      id: id,
      username: username,
      email: email,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt,
      verifiedRoles: verifiedRoles ?? this.verifiedRoles,
      verifiedRoleLabels: verifiedRoleLabels ?? this.verifiedRoleLabels,
      avatarCacheTs: avatarCacheTs ?? this.avatarCacheTs,
      coverCacheTs: coverCacheTs ?? this.coverCacheTs,
    );
  }
}
