import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/role_service.dart';

class IdentityApplicationScreen extends StatefulWidget {
  const IdentityApplicationScreen({super.key});

  @override
  State<IdentityApplicationScreen> createState() => _IdentityApplicationScreenState();
}

class _IdentityApplicationScreenState extends State<IdentityApplicationScreen> {
  final _applicationController = TextEditingController();
  final _portfolioController = TextEditingController();
  final _proofController = TextEditingController();
  final _contactController = TextEditingController();
  final _noteController = TextEditingController();

  List<BusinessIdentityRole> _roles = const [];
  String? _selectedRoleName;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  @override
  void dispose() {
    _applicationController.dispose();
    _portfolioController.dispose();
    _proofController.dispose();
    _contactController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await RoleService().listRoles();
      if (!mounted) return;
      if (resp.success && resp.data is Map) {
        final data = resp.data as Map;
        final rawRoles = data['roles'];
        final roles = rawRoles is List
            ? rawRoles
                .whereType<Map>()
                .map((e) => BusinessIdentityRole.fromJson(Map<String, dynamic>.from(e)))
                .where((role) => role.name.isNotEmpty && role.label.isNotEmpty)
                .toList()
            : <BusinessIdentityRole>[];
        setState(() {
          _roles = roles;
          _selectedRoleName = roles.isNotEmpty ? roles.first.name : null;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = resp.message ?? '身份列表加载失败';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '身份列表加载失败';
      });
    }
  }

  List<String> _splitLines(String value) {
    return value
        .split(RegExp(r'[\n,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _submit() async {
    final roleName = _selectedRoleName;
    final applicationText = _applicationController.text.trim();
    if (roleName == null) {
      setState(() => _error = '请选择要认证的身份');
      return;
    }
    if (applicationText.isEmpty) {
      setState(() => _error = '请填写认证说明');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final resp = await RoleService().applyIdentity(
        roleName: roleName,
        applicationText: applicationText,
        proofImages: _splitLines(_proofController.text),
        portfolioLinks: _splitLines(_portfolioController.text),
        contactInfo: _contactController.text.trim(),
        extraNote: _noteController.text.trim(),
      );
      if (!mounted) return;
      if (resp.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('认证申请已提交，等待管理员审核')),
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _submitting = false;
          _error = resp.message ?? '提交失败';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '提交失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('身份认证'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '认证通过后，身份仅作为公开展示标签使用，不影响发布作品权限。',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRoleName,
                  decoration: const InputDecoration(labelText: '申请身份'),
                  items: _roles
                      .map((role) => DropdownMenuItem<String>(
                            value: role.name,
                            child: Text(role.label),
                          ))
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _selectedRoleName = value),
                ),
                const SizedBox(height: 12),
                _buildTextField(_applicationController, '认证说明', maxLines: 5),
                const SizedBox(height: 12),
                _buildTextField(_portfolioController, '作品/主页链接（每行一个，可选）', maxLines: 3),
                const SizedBox(height: 12),
                _buildTextField(_proofController, '证明图片链接（每行一个，可选）', maxLines: 3),
                const SizedBox(height: 12),
                _buildTextField(_contactController, '联系方式（仅管理员审核使用，可选）'),
                const SizedBox(height: 12),
                _buildTextField(_noteController, '补充说明（可选）', maxLines: 3),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('提交认证申请'),
                ),
              ],
            ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: !_submitting,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
