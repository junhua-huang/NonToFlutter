class Topic {
  final int id;
  final String name;
  final String? description;
  final String? iconUrl;
  final String? color;
  final int postCount;
  final int followerCount;
  final bool isTrending;
  final bool isFollowing;

  Topic({
    required this.id, required this.name, this.description,
    this.iconUrl, this.color, this.postCount = 0, this.followerCount = 0,
    this.isTrending = false, this.isFollowing = false,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
    id: _p(json['id']), name: json['name'] ?? '',
    description: json['description'], iconUrl: json['icon_url'],
    color: json['color'], postCount: _p(json['post_count']),
    followerCount: _p(json['follower_count']),
    isTrending: json['is_trending'] ?? false,
    isFollowing: json['is_following'] ?? false,
  );

  static int _p(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

  Topic copyWith({
    int? id,
    String? name,
    String? description,
    String? iconUrl,
    String? color,
    int? postCount,
    int? followerCount,
    bool? isTrending,
    bool? isFollowing,
  }) {
    return Topic(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconUrl: iconUrl ?? this.iconUrl,
      color: color ?? this.color,
      postCount: postCount ?? this.postCount,
      followerCount: followerCount ?? this.followerCount,
      isTrending: isTrending ?? this.isTrending,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}
