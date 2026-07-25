import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/identity_application.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/screens/profile/identity_application_screen.dart';
import 'package:nonto/screens/profile/identity_detail_screen.dart';
import 'package:nonto/services/api/role_service.dart';
import 'package:nonto/widgets/identity_role_grid.dart';
import 'package:nonto/widgets/identity_status_card.dart';

class IdentityCenterScreen extends StatefulWidget {
  const IdentityCenterScreen({super.key});

  @override
  State<IdentityCenterScreen> createState() => _IdentityCenterScreenState();
}

class _IdentityCenterScreenState extends State<IdentityCenterScreen> {
  bool _loading = true;
  String? _error;
  List<BusinessIdentityRole> _roles = const [];
  List<IdentityApplication> _applications = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rolesResp = await RoleService().listRoles();
      final appsResp = await RoleService().listMyApplications();
      if (!mounted) return;
      final roles = _parseRoles(rolesResp.data);
      final apps = _parseApplications(appsResp.data, roles);
      setState(() {
        _roles = roles;
        _applications = apps;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '身份信息加载失败';
      });
    }
  }

  List<BusinessIdentityRole> _parseRoles(dynamic data) {
    final raw = data is Map ? data['roles'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => BusinessIdentityRole.fromJson(Map<String, dynamic>.from(item)))
        .where((role) => role.name.isNotEmpty && role.label.isNotEmpty)
        .toList();
  }

  List<IdentityApplication> _parseApplications(
    dynamic data,
    List<BusinessIdentityRole> roles,
  ) {
    final raw = data is Map ? (data['applications'] ?? data['items']) : data;
    if (raw is! List) return const [];
    final byId = {for (final role in roles) role.name: role};
    return raw.whereType<Map>().map((item) {
      final json = Map<String, dynamic>.from(item);
      final app = IdentityApplication.fromJson(json);
      if (app.roleName != null && byId.containsKey(app.roleName)) {
        final role = byId[app.roleName]!;
        return IdentityApplication.fromJson({
          ...json,
          'role': {'name': role.name, 'label': role.label},
        });
      }
      return app;
    }).toList();
  }

  Map<String, IdentityApplication> get _applicationsByRole {
    return {
      for (final app in _applications)
        if (app.roleName != null) app.roleName!: app,
    };
  }

  Future<void> _openApplication(BusinessIdentityRole role) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => IdentityApplicationScreen(initialRoleName: role.name),
      ),
    );
    if (changed == true && mounted) _load();
  }

  void _openDetail(IdentityApplication application) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IdentityDetailScreen(application: application),
        settings: const RouteSettings(name: AppRoutes.identityDetail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('我的身份'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeroCard(),
                      const SizedBox(height: 20),
                      _buildSectionTitle('我的认证'),
                      if (_applications.isEmpty)
                        _buildEmptyApplications()
                      else
                        ..._applications.map(
                          (app) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: IdentityStatusCard(
                              application: app,
                              onTap: () => _openDetail(app),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _buildSectionTitle('可申请身份'),
                      IdentityRoleGrid(
                        roles: _roles,
                        applicationsByRole: _applicationsByRole,
                        onApply: _openApplication,
                        onView: _openDetail,
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeroCard() {
    final verified = _applications.where((app) => app.isVerified).length;
    final pending = _applications.where((app) => app.isPending).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '让你的作品更可信',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '认证身份会展示在主页和帖子中，也可作为发帖身份。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Text('已认证 $verified 个 · 审核中 $pending 个',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildEmptyApplications() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Text('还没有认证身份', style: TextStyle(color: AppColors.textSecondary)),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }
}
