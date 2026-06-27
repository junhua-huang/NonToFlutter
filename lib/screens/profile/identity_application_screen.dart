import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/role_service.dart';
import 'package:nonto/services/api/upload_service.dart';

class IdentityApplicationScreen extends StatefulWidget {
  const IdentityApplicationScreen({super.key});

  @override
  State<IdentityApplicationScreen> createState() => _IdentityApplicationScreenState();
}

class _IdentityApplicationScreenState extends State<IdentityApplicationScreen> {
  static const int _maxProofImages = 9;

  final _applicationController = TextEditingController();
  final _portfolioController = TextEditingController();
  final _contactController = TextEditingController();
  final _noteController = TextEditingController();
  final _picker = ImagePicker();

  List<BusinessIdentityRole> _roles = const [];
  final List<XFile> _selectedProofImages = [];
  String? _selectedRoleName;
  bool _loading = true;
  bool _submitting = false;
  bool _submittedApplication = false;
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

  Future<void> _pickProofImages() async {
    if (_submitting) return;
    final remaining = _maxProofImages - _selectedProofImages.length;
    if (remaining <= 0) {
      setState(() => _error = '最多只能上传 $_maxProofImages 张证明图片');
      return;
    }

    try {
      final picked = await _picker.pickMultiImage(imageQuality: 92);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _error = null;
        _selectedProofImages.addAll(picked.take(remaining));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '选择图片失败，请重试');
    }
  }

  Future<List<String>> _uploadProofImages() async {
    final uploadedProofImages = <String>[];
    for (final image in _selectedProofImages) {
      final resp = await UploadService().uploadImage(image);
      final data = resp.data;
      final url = data is Map
          ? (data['url'] ?? data['file_url'] ?? data['avatar_url'])?.toString()
          : data?.toString();
      if (!resp.success || url == null || url.isEmpty) {
        throw Exception(resp.message ?? '证明图片上传失败');
      }
      uploadedProofImages.add(url);
    }
    return uploadedProofImages;
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
      final uploadedProofImages = await _uploadProofImages();
      final resp = await RoleService().applyIdentity(
        roleName: roleName,
        applicationText: applicationText,
        proofImages: uploadedProofImages,
        portfolioLinks: _splitLines(_portfolioController.text),
        contactInfo: _contactController.text.trim(),
        extraNote: _noteController.text.trim(),
      );
      if (!mounted) return;
      if (resp.success) {
        setState(() {
          _submitting = false;
          _submittedApplication = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('认证申请已提交，等待管理员审核')),
        );
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
                if (_submittedApplication) ...[
                  _buildPendingCard(),
                  const SizedBox(height: 16),
                ],
                Text(
                  '认证通过后，身份仅作为公开展示标签使用，不影响发布作品权限。证明图片可选，最多上传 $_maxProofImages 张。',
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
                  onChanged: _submitting || _roles.isEmpty
                      ? null
                      : (value) => setState(() => _selectedRoleName = value),
                ),
                const SizedBox(height: 12),
                _buildTextField(_applicationController, '认证说明', maxLines: 5),
                const SizedBox(height: 12),
                _buildTextField(_portfolioController, '作品/主页链接（每行一个，可选）', maxLines: 3),
                const SizedBox(height: 12),
                _buildProofImagesSection(),
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

  Widget _buildPendingCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '认证申请已提交，等待管理员审核。审核结果会在消息通知中更新。',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '证明图片（可选，${_selectedProofImages.length}/$_maxProofImages）',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _submitting ? null : _pickProofImages,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('添加图片'),
            ),
          ],
        ),
        if (_selectedProofImages.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _selectedProofImages.length,
              (index) => _buildPickedImage(index),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPickedImage(int index) {
    final image = _selectedProofImages[index];
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FutureBuilder<Uint8List>(
            future: image.readAsBytes(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container(
                  width: 78,
                  height: 78,
                  color: AppColors.surface,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Image.memory(
                snapshot.data!,
                width: 78,
                height: 78,
                fit: BoxFit.cover,
              );
            },
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: _submitting
                ? null
                : () => setState(() => _selectedProofImages.removeAt(index)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
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
