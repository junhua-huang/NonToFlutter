import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/identity_application.dart';
import 'package:nonto/screens/profile/identity_application_screen.dart';
import 'package:nonto/widgets/identity_badge.dart';

class IdentityDetailScreen extends StatelessWidget {
  final IdentityApplication application;

  const IdentityDetailScreen({super.key, required this.application});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(application.roleLabel),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusHero(),
          const SizedBox(height: 18),
          _section('认证资料'),
          _info('认证说明', application.applicationText),
          _listInfo('作品链接', application.portfolioLinks),
          _listInfo('证明图片', application.proofImages),
          if (application.reviewComment != null && application.reviewComment!.isNotEmpty) ...[
            const SizedBox(height: 18),
            _section('审核反馈'),
            _info('原因', application.reviewComment),
          ],
          if (application.isRejected || application.needsMoreInfo) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IdentityApplicationScreen(
                    initialRoleName: application.roleName,
                  ),
                ),
              ),
              child: Text(application.needsMoreInfo ? '补充材料' : '重新申请'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IdentityBadge(label: application.roleLabel),
              const SizedBox(width: 8),
              Text(
                application.statusLabel,
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            application.isVerified
                ? '该身份已通过平台审核，可展示在主页和帖子中。'
                : application.isPending
                    ? '你的申请正在审核，预计 1-3 个工作日完成。'
                    : application.isRejected
                        ? '你可以根据审核原因补充材料后重新申请。'
                        : '查看该身份当前状态和提交材料。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _section(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      );

  Widget _info(String label, String? value) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(value == null || value.isEmpty ? '未填写' : value,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ],
        ),
      );

  Widget _listInfo(String label, List<String> values) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(values.isEmpty ? '未提交' : values.join('\n'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ],
        ),
      );
}
