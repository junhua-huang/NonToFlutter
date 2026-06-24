import 'api_client.dart';

class BusinessIdentityRole {
  final String name;
  final String label;
  final String description;

  const BusinessIdentityRole({
    required this.name,
    required this.label,
    this.description = '',
  });

  factory BusinessIdentityRole.fromJson(Map<String, dynamic> json) {
    return BusinessIdentityRole(
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

class RoleService {
  static final RoleService _instance = RoleService._();
  factory RoleService() => _instance;
  RoleService._();

  final ApiClient _api = ApiClient();

  Future<ApiResponse> listRoles() => _api.getDeduped('/roles');

  Future<ApiResponse> listMyApplications({int page = 1, int perPage = 20}) {
    return _api.getDeduped('/roles/applications', params: {
      'page': page,
      'per_page': perPage,
    });
  }

  Future<ApiResponse> applyIdentity({
    required String roleName,
    required String applicationText,
    List<String> proofImages = const [],
    List<String> portfolioLinks = const [],
    String contactInfo = '',
    String extraNote = '',
  }) {
    return _api.post('/roles/apply', data: {
      'role_name': roleName,
      'application_text': applicationText,
      'reason': applicationText,
      'proof_images': proofImages,
      'portfolio_links': portfolioLinks,
      'contact_info': contactInfo,
      'extra_note': extraNote,
    });
  }
}
