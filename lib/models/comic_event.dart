class ComicCity {
  final int id;
  final String name;
  final String province;
  final int sortOrder;

  ComicCity({
    required this.id,
    required this.name,
    this.province = '广西',
    this.sortOrder = 0,
  });

  factory ComicCity.fromJson(Map<String, dynamic> json) {
    return ComicCity(
      id: json['id'],
      name: json['name'] ?? '',
      province: json['province'] ?? '广西',
      sortOrder: json['sortOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'province': province,
        'sortOrder': sortOrder,
      };
}

class ComicTag {
  final int id;
  final String name;
  final String tagType;

  ComicTag({
    required this.id,
    required this.name,
    required this.tagType,
  });

  factory ComicTag.fromJson(Map<String, dynamic> json) {
    return ComicTag(
      id: json['id'],
      name: json['name'] ?? '',
      tagType: json['tagType'] ?? 'type',
    );
  }
}

class ComicEventImage {
  final int id;
  final String imageUrl;
  final bool isCover;
  final int sortOrder;

  ComicEventImage({
    required this.id,
    required this.imageUrl,
    this.isCover = false,
    this.sortOrder = 0,
  });

  factory ComicEventImage.fromJson(Map<String, dynamic> json) {
    return ComicEventImage(
      id: json['id'] ?? 0,
      imageUrl: json['imageUrl'] ?? '',
      isCover: json['isCover'] ?? false,
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
}

class ComicEvent {
  final int id;
  final String name;
  final String cityName;
  final int cityId;
  final String venue;
  final String? startDate;
  final String? endDate;
  final String? startTime;
  final String? endTime;
  final String? ticketInfo;
  final String? website;
  final String? intro;
  final int status;
  final String statusText;
  final List<String> tags;
  final String? coverImage;
  final int followCount;
  final bool isFollowed;
  final bool isOwner;
  final List<ComicEventImage> images;

  // 发布者信息（推特卡片风格头部）
  final String? creatorName;
  final String? creatorAvatar;
  final String? createdAt;

  ComicEvent({
    required this.id,
    required this.name,
    this.cityName = '',
    this.cityId = 0,
    this.venue = '',
    this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.ticketInfo,
    this.website,
    this.intro,
    this.status = 0,
    this.statusText = '即将开始',
    this.tags = const [],
    this.coverImage,
    this.followCount = 0,
    this.isFollowed = false,
    this.isOwner = false,
    this.images = const [],
    this.creatorName,
    this.creatorAvatar,
    this.createdAt,
  });

  factory ComicEvent.fromListJson(Map<String, dynamic> json) {
    return ComicEvent(
      id: json['id'],
      name: json['name'] ?? '',
      cityName: json['cityName'] ?? '',
      cityId: json['cityId'] ?? 0,
      venue: json['venue'] ?? '',
      startDate: json['startDate'],
      endDate: json['endDate'],
      ticketInfo: json['ticketInfo'],
      status: json['status'] ?? 0,
      statusText: json['statusText'] ?? '即将开始',
      tags: List<String>.from(json['tags'] ?? []),
      coverImage: json['coverImage'],
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => ComicEventImage.fromJson(e))
              .toList() ??
          [],
      followCount: json['followCount'] ?? 0,
      isFollowed: json['isFollowed'] ?? json['is_following'] ?? false,
      isOwner: json['isOwner'] ?? json['is_owner'] ?? false,
      creatorName: json['creatorName'] ?? json['creator_name'],
      creatorAvatar: json['creatorAvatar'] ?? json['creator_avatar'],
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  factory ComicEvent.fromJson(Map<String, dynamic> json) =>
      ComicEvent.fromListJson(json);

  factory ComicEvent.fromDetailJson(Map<String, dynamic> json) {
    return ComicEvent(
      id: json['id'],
      name: json['name'] ?? '',
      cityName: json['cityName'] ?? '',
      cityId: json['cityId'] ?? 0,
      venue: json['venue'] ?? '',
      startDate: json['startDate'],
      endDate: json['endDate'],
      startTime: json['startTime'],
      endTime: json['endTime'],
      ticketInfo: json['ticketInfo'],
      website: json['website'],
      intro: json['intro'],
      status: json['status'] ?? 0,
      statusText: json['statusText'] ?? '即将开始',
      tags: List<String>.from(json['tags'] ?? []),
      coverImage: json['coverImage'],
      followCount: json['followCount'] ?? 0,
      isFollowed: json['isFollowed'] ?? json['is_following'] ?? false,
      isOwner: json['isOwner'] ?? json['is_owner'] ?? false,
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => ComicEventImage.fromJson(e))
              .toList() ??
          [],
      creatorName: json['creatorName'] ?? json['creator_name'],
      creatorAvatar: json['creatorAvatar'] ?? json['creator_avatar'],
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  ComicEvent copyWith({
    bool? isFollowed,
    int? followCount,
    bool? isOwner,
  }) {
    return ComicEvent(
      id: id,
      name: name,
      cityName: cityName,
      cityId: cityId,
      venue: venue,
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      ticketInfo: ticketInfo,
      website: website,
      intro: intro,
      status: status,
      statusText: statusText,
      tags: tags,
      coverImage: coverImage,
      followCount: followCount ?? this.followCount,
      isFollowed: isFollowed ?? this.isFollowed,
      isOwner: isOwner ?? this.isOwner,
      images: images,
      creatorName: creatorName,
      creatorAvatar: creatorAvatar,
      createdAt: createdAt,
    );
  }
}

class ComicEventsPage {
  final List<ComicEvent> records;
  final int total;
  final int page;
  final int size;
  final int pages;

  ComicEventsPage({
    required this.records,
    required this.total,
    required this.page,
    required this.size,
    required this.pages,
  });

  factory ComicEventsPage.fromJson(Map<String, dynamic> json) {
    return ComicEventsPage(
      records: (json['records'] as List<dynamic>)
          .map((e) => ComicEvent.fromListJson(e))
          .toList(),
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      size: json['size'] ?? 10,
      pages: json['pages'] ?? 0,
    );
  }
}