import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/providers/chat_notifiers.dart';
import 'package:nonto/screens/community/community_detail_screen.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/services/api/upload_service.dart';

/// 创建社群 — 两步表单
/// Step 1: 名称、简介、规则与视觉资料。
/// Step 2: 加群方式，默认审核制。
class CommunityCreateScreen extends ConsumerStatefulWidget {
  const CommunityCreateScreen({super.key});

  @override
  ConsumerState<CommunityCreateScreen> createState() =>
      _CommunityCreateScreenState();
}

class _CommunityCreateScreenState extends ConsumerState<CommunityCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();
  String _joinPolicy = 'approval';
  bool _isSubmitting = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;
  int _step = 1;
  final ImagePicker _picker = ImagePicker();
  Uint8List? _avatarBytes;
  Uint8List? _coverBytes;
  String? _avatarUrl;
  String? _bannerUrl;

  final List<Map<String, String>> _joinOptions = [
    {'value': 'approval', 'label': '需要审核', 'desc': '申请后由管理员审核通过才能加入'},
    {'value': 'open', 'label': '开放加入', 'desc': '任何人可直接加入'},
    {'value': 'invite', 'label': '仅邀请', 'desc': '只能通过邀请链接加入'},
  ];

  bool get _canContinue => _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_refreshNameState);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_refreshNameState);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _rulesCtrl.dispose();
    super.dispose();
  }

  void _refreshNameState() => setState(() {});

  Future<void> _pickCommunityAvatar() async {
    await _pickCommunityImage(isAvatar: true);
  }

  Future<void> _pickCommunityCover() async {
    await _pickCommunityImage(isAvatar: false);
  }

  Future<void> _pickCommunityImage({required bool isAvatar}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: isAvatar ? 720 : 1600,
      imageQuality: 90,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (isAvatar) {
        _isUploadingAvatar = true;
        _avatarBytes = bytes;
      } else {
        _isUploadingCover = true;
        _coverBytes = bytes;
      }
    });
    try {
      final resp = await UploadService().uploadImage(picked);
      final data = resp.data;
      final url = data is Map ? data['url'] ?? data['avatar_url'] : null;
      if (!mounted) return;
      if (resp.success && url != null) {
        setState(() {
          if (isAvatar) {
            _avatarUrl = url.toString();
          } else {
            _bannerUrl = url.toString();
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message ?? '上传失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isAvatar) {
            _isUploadingAvatar = false;
          } else {
            _isUploadingCover = false;
          }
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_canContinue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入社群名称')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final api = CommunityApiService();
      final resp = await api.create({
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'rules': _rulesCtrl.text.trim(),
        'join_policy': _joinPolicy,
        'avatar_url': _avatarUrl,
        'banner_url': _bannerUrl,
      });
      if (resp.data is Map && resp.data['community'] != null) {
        final community = resp.data['community'];
        final id = community is Map ? community['id'] : null;
        if (id != null && mounted) {
          ref.read(conversationsProvider.notifier).loadConversations();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CommunityDetailScreen(communityId: id),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? '创建一个有温度的社群' : '加群设置'),
        actions: [
          if (_step == 1)
            TextButton(
              onPressed: _canContinue ? () => setState(() => _step = 2) : null,
              child: const Text('下一步'),
            )
          else
            TextButton(
              onPressed: _isSubmitting ? null : () => setState(() => _step = 1),
              child: const Text('上一步'),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStepProgress(),
          Expanded(child: _step == 1 ? _buildStep1() : _buildStep2()),
        ],
      ),
    );
  }

  Widget _buildStepProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          _buildStepDot(1, '基础资料'),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: _step == 2
                  ? AppColors.primary
                  : AppColors.textTertiary.withValues(alpha: 0.22),
            ),
          ),
          _buildStepDot(2, '加入方式'),
        ],
      ),
    );
  }

  Widget _buildStepDot(int step, String label) {
    final active = _step >= step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 28,
          width: 28,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: active ? AppColors.primary : AppColors.textTertiary,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(
                color: active ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: active ? AppColors.primary : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        const Text(
          '创建一个有温度的社群',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '清晰的主题和友好的规则，会让第一批成员更愿意留下来。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 24),
        Center(
          child: InkWell(
            onTap: _isUploadingAvatar ? null : _pickCommunityAvatar,
            customBorder: const CircleBorder(),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.surface,
                  backgroundImage:
                      _avatarBytes != null ? MemoryImage(_avatarBytes!) : null,
                  child: _isUploadingAvatar
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : _avatarBytes == null
                          ? Icon(
                              Icons.camera_alt,
                              size: 32,
                              color: AppColors.textTertiary,
                            )
                          : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '上传头像',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: '社群名称 *',
            hintText: '例如：独立开发者咖啡馆',
            border: OutlineInputBorder(),
          ),
          maxLength: 64,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descCtrl,
          decoration: const InputDecoration(
            labelText: '社群简介',
            hintText: '用一两句话说明这里适合谁、讨论什么',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          maxLength: 200,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _rulesCtrl,
          decoration: const InputDecoration(
            labelText: '社群规则（可选）',
            hintText: '例如：真诚交流、尊重差异、原创优先',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 24),
        Text(
          '封面图（可选）',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _isUploadingCover ? null : _pickCommunityCover,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 112,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
              image: _coverBytes != null
                  ? DecorationImage(
                      image: MemoryImage(_coverBytes!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Center(
              child: _isUploadingCover
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : _coverBytes == null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              color: AppColors.textTertiary,
                              size: 32,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '上传封面图',
                              style: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _canContinue ? () => setState(() => _step = 2) : null,
            child: const Text('继续设置加入方式'),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      itemCount: _joinOptions.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择成员加入方式',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '先保证交流质量，再逐步扩大规模。默认推荐审核制。',
                style: TextStyle(color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 18),
            ],
          );
        }
        if (index <= _joinOptions.length) {
          final option = _joinOptions[index - 1];
          final selected = _joinPolicy == option['value'];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: selected
                    ? AppColors.primary
                    : AppColors.textTertiary.withValues(alpha: 0.16),
              ),
            ),
            child: ListTile(
              leading: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
              title: Text(option['label']!),
              subtitle:
                  Text(option['desc']!, style: const TextStyle(fontSize: 13)),
              onTap: () => setState(() => _joinPolicy = option['value']!),
            ),
          );
        }
        if (index == _joinOptions.length + 1) {
          return const SizedBox(height: 24);
        }
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('创建社群'),
          ),
        );
      },
    );
  }
}
