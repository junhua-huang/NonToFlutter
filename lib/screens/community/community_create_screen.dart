import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/services/api/community_service.dart';
import 'package:nonto/screens/community/community_detail_screen.dart';

/// 创建社群 — 两步表单
/// Step 1: 名称 + 简介 + 头像 + 规则 + 封面
/// Step 2: 加群方式（审核制/开放/邀请，默认审核制）
class CommunityCreateScreen extends StatefulWidget {
  const CommunityCreateScreen({super.key});

  @override
  State<CommunityCreateScreen> createState() => _CommunityCreateScreenState();
}

class _CommunityCreateScreenState extends State<CommunityCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _rulesCtrl = TextEditingController();
  String _joinPolicy = 'approval';
  bool _isSubmitting = false;
  int _step = 1;

  final List<Map<String, String>> _joinOptions = [
    {'value': 'approval', 'label': '需要审核', 'desc': '申请后由管理员审核通过才能加入'},
    {'value': 'open', 'label': '开放加入', 'desc': '任何人可直接加入'},
    {'value': 'invite', 'label': '仅邀请', 'desc': '只能通过邀请链接加入'},
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _rulesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入社群名称')));
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
      });
      if (resp.data is Map && resp.data['community'] != null) {
        final c = resp.data['community'];
        final id = c is Map ? c['id'] : null;
        if (id != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => CommunityDetailScreen(communityId: id)),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? '创建社群' : '加群设置'),
        actions: [
          if (_step == 1)
            TextButton(
              onPressed: () => setState(() => _step = 2),
              child: const Text('下一步'),
            ),
        ],
      ),
      body: _step == 1 ? _buildStep1() : _buildStep2(),
    );
  }

  Widget _buildStep1() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 头像
        Center(
          child: Stack(
            children: [
              CircleAvatar(radius: 48, child: Icon(Icons.camera_alt, size: 32, color: AppColors.textTertiary)),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Center(child: Text('上传头像', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        const SizedBox(height: 24),

        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: '社群名称 *',
            hintText: '请输入社群名称',
            border: OutlineInputBorder(),
          ),
          maxLength: 64,
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _descCtrl,
          decoration: const InputDecoration(
            labelText: '社群简介',
            hintText: '请介绍你的社群（最多200字）',
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
            hintText: '1. 原创优先 2. 尊重他人...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 24),

        Text('封面图（可选）',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_photo_alternate, color: AppColors.textTertiary, size: 32),
                Text('上传封面图', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('加群方式', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ..._joinOptions.map((opt) {
          final selected = _joinPolicy == opt['value'];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
              title: Text(opt['label']!),
              subtitle: Text(opt['desc']!, style: TextStyle(fontSize: 13)),
              onTap: () => setState(() => _joinPolicy = opt['value']!),
            ),
          );
        }),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('创建社群'),
          ),
        ),
      ],
    );
  }
}
