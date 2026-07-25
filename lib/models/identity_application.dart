class IdentityApplication {
  final int id;
  final int roleId;
  final String? roleName;
  final String roleLabel;
  final String status;
  final String? applicationText;
  final List<String> proofImages;
  final List<String> portfolioLinks;
  final String? contactInfo;
  final String? extraNote;
  final String? reviewComment;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const IdentityApplication({
    required this.id,
    required this.roleId,
    this.roleName,
    required this.roleLabel,
    required this.status,
    this.applicationText,
    this.proofImages = const [],
    this.portfolioLinks = const [],
    this.contactInfo,
    this.extraNote,
    this.reviewComment,
    this.createdAt,
    this.reviewedAt,
  });

  factory IdentityApplication.fromJson(Map<String, dynamic> json) {
    final role = json['role'] is Map
        ? Map<String, dynamic>.from(json['role'] as Map)
        : const <String, dynamic>{};
    final roleId = _asInt(json['role_id'] ?? role['id']);
    final roleName = (json['role_name'] ?? role['name'])?.toString();
    final rawRoleLabel = (json['role_label'] ?? role['label'])?.toString();
    return IdentityApplication(
      id: _asInt(json['id']),
      roleId: roleId,
      roleName: roleName != null && roleName.isNotEmpty ? roleName : null,
      roleLabel: rawRoleLabel != null && rawRoleLabel.isNotEmpty
          ? rawRoleLabel
          : roleId > 0
              ? '角色 #$roleId'
              : '认证身份',
      status: json['status']?.toString() ?? 'pending',
      applicationText:
          (json['application_text'] ?? json['reason'])?.toString(),
      proofImages: _asStringList(json['proof_images']),
      portfolioLinks: _asStringList(json['portfolio_links']),
      contactInfo: json['contact_info']?.toString(),
      extraNote: json['extra_note']?.toString(),
      reviewComment:
          (json['review_comment'] ?? json['admin_reason'])?.toString(),
      createdAt: _parseDate(json['created_at']),
      reviewedAt: _parseDate(json['reviewed_at']),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  static DateTime? _parseDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

extension IdentityApplicationStatusX on IdentityApplication {
  String get normalizedStatus => status.trim().toLowerCase();

  bool get isVerified =>
      normalizedStatus == 'verified' || normalizedStatus == 'approved';
  bool get isPending => normalizedStatus == 'pending';
  bool get isRejected => normalizedStatus == 'rejected';
  bool get isSuspended => normalizedStatus == 'suspended';
  bool get needsMoreInfo => normalizedStatus == 'needs_more_info';

  String get statusLabel {
    switch (normalizedStatus) {
      case 'verified':
      case 'approved':
        return '已认证';
      case 'pending':
        return '审核中';
      case 'rejected':
        return '未通过';
      case 'suspended':
        return '已暂停';
      case 'needs_more_info':
        return '需补充材料';
      default:
        return '审核中';
    }
  }
}
