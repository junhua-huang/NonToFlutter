import 'user.dart';

/// 社群模型
class Community {
  final int id;
  final String name;
  final String? slug;
  final String? description;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? rules;
  final int ownerId;
  final int? topicId;
  final String visibility;
  final String joinPolicy;
  final int memberCount;
  final int postCount;
  final String status;
  final String? myRole;   // owner/admin/member/null
  final String? myStatus; // active/pending/null
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Community({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.avatarUrl,
    this.bannerUrl,
    this.rules,
    required this.ownerId,
    this.topicId,
    this.visibility = 'public',
    this.joinPolicy = 'approval',
    this.memberCount = 0,
    this.postCount = 0,
    this.status = 'active',
    this.myRole,
    this.myStatus,
    this.createdAt,
    this.updatedAt,
  });

  bool get isOwner => myRole == 'owner';
  bool get isAdmin => myRole == 'admin';
  bool get isManager => isOwner || isAdmin;
  bool get isMember => myStatus == 'active';
  bool get isPending => myStatus == 'pending';
  bool get isApproval => joinPolicy == 'approval';
  bool get isOpen => joinPolicy == 'open';

  factory Community.fromJson(Map<String, dynamic> json) {
    return Community(
      id: _parseInt(json['id']),
      name: json['name'] ?? '',
      slug: json['slug'],
      description: json['description'],
      avatarUrl: json['avatar_url'],
      bannerUrl: json['banner_url'],
      rules: json['rules'],
      ownerId: _parseInt(json['owner_id']),
      topicId: json['topic_id'] != null ? _parseInt(json['topic_id']) : null,
      visibility: json['visibility'] ?? 'public',
      joinPolicy: json['join_policy'] ?? 'approval',
      memberCount: _parseInt(json['member_count']),
      postCount: _parseInt(json['post_count']),
      status: json['status'] ?? 'active',
      myRole: json['my_role'],
      myStatus: json['my_status'],
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'slug': slug, 'description': description,
    'avatar_url': avatarUrl, 'banner_url': bannerUrl, 'rules': rules,
    'owner_id': ownerId, 'topic_id': topicId, 'visibility': visibility,
    'join_policy': joinPolicy, 'member_count': memberCount,
    'post_count': postCount, 'status': status, 'my_role': myRole,
    'my_status': myStatus, 'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  Community copyWith({int? memberCount, int? postCount, String? myRole,
    String? myStatus, String? status, String? description, String? avatarUrl,
    String? bannerUrl, String? rules}) {
    return Community(
      id: id, name: name, slug: slug,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      rules: rules ?? this.rules,
      ownerId: ownerId, topicId: topicId,
      visibility: visibility, joinPolicy: joinPolicy,
      memberCount: memberCount ?? this.memberCount,
      postCount: postCount ?? this.postCount,
      status: status ?? this.status,
      myRole: myRole ?? this.myRole,
      myStatus: myStatus ?? this.myStatus,
      createdAt: createdAt, updatedAt: updatedAt,
    );
  }

  static int _parseInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  static DateTime? _parseDate(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString()) : null;
}

/// 社群成员
class CommunityMember {
  final int id;
  final int communityId;
  final int userId;
  final String role;   // owner/admin/member
  final String status; // active/pending/muted
  final DateTime? joinedAt;
  final User? user;

  const CommunityMember({
    required this.id, required this.communityId, required this.userId,
    this.role = 'member', this.status = 'active', this.joinedAt, this.user,
  });

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';
  bool get isManager => isOwner || isAdmin;

  factory CommunityMember.fromJson(Map<String, dynamic> json) {
    return CommunityMember(
      id: _parseInt(json['id']),
      communityId: _parseInt(json['community_id']),
      userId: _parseInt(json['user_id']),
      role: json['role'] ?? 'member',
      status: json['status'] ?? 'active',
      joinedAt: _parseDate(json['joined_at']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'community_id': communityId, 'user_id': userId,
    'role': role, 'status': status, 'joined_at': joinedAt?.toIso8601String(),
    'user': user?.toJson(),
  };

  CommunityMember copyWith({User? user}) {
    return CommunityMember(
      id: id,
      communityId: communityId,
      userId: userId,
      role: role,
      status: status,
      joinedAt: joinedAt,
      user: user ?? this.user,
    );
  }

  static int _parseInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  static DateTime? _parseDate(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString()) : null;
}

/// 加群申请
class CommunityJoinRequest {
  final int id;
  final int communityId;
  final int userId;
  final String? message;
  final String status; // pending/approved/rejected
  final int? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final User? user;

  const CommunityJoinRequest({
    required this.id, required this.communityId, required this.userId,
    this.message, this.status = 'pending', this.reviewedBy, this.reviewedAt,
    this.createdAt, this.user,
  });

  factory CommunityJoinRequest.fromJson(Map<String, dynamic> json) {
    return CommunityJoinRequest(
      id: _parseInt(json['id']),
      communityId: _parseInt(json['community_id']),
      userId: _parseInt(json['user_id']),
      message: json['message'],
      status: json['status'] ?? 'pending',
      reviewedBy: json['reviewed_by'] != null ? _parseInt(json['reviewed_by']) : null,
      reviewedAt: _parseDate(json['reviewed_at']),
      createdAt: _parseDate(json['created_at']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  static int _parseInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  static DateTime? _parseDate(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString()) : null;
}

/// 社群公告
class CommunityAnnouncement {
  final int id;
  final int communityId;
  final int authorId;
  final String title;
  final String? content;
  final bool isPinned;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final User? author;

  const CommunityAnnouncement({
    required this.id, required this.communityId, required this.authorId,
    required this.title, this.content, this.isPinned = false,
    this.createdAt, this.updatedAt, this.author,
  });

  factory CommunityAnnouncement.fromJson(Map<String, dynamic> json) {
    return CommunityAnnouncement(
      id: _parseInt(json['id']),
      communityId: _parseInt(json['community_id']),
      authorId: _parseInt(json['author_id']),
      title: json['title'] ?? '',
      content: json['content'],
      isPinned: json['is_pinned'] ?? false,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      author: json['author'] != null ? User.fromJson(json['author']) : null,
    );
  }

  static int _parseInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  static DateTime? _parseDate(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString()) : null;
}

/// 社群黑名单
class CommunityBan {
  final int id;
  final int communityId;
  final int userId;
  final int bannedBy;
  final String? reason;
  final DateTime? bannedUntil;
  final DateTime? createdAt;
  final User? user;

  const CommunityBan({
    required this.id, required this.communityId, required this.userId,
    required this.bannedBy, this.reason, this.bannedUntil, this.createdAt,
    this.user,
  });

  factory CommunityBan.fromJson(Map<String, dynamic> json) {
    return CommunityBan(
      id: _parseInt(json['id']),
      communityId: _parseInt(json['community_id']),
      userId: _parseInt(json['user_id']),
      bannedBy: _parseInt(json['banned_by']),
      reason: json['reason'],
      bannedUntil: _parseDate(json['banned_until']),
      createdAt: _parseDate(json['created_at']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  static int _parseInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  static DateTime? _parseDate(dynamic v) =>
      v != null ? DateTime.tryParse(v.toString()) : null;
}
