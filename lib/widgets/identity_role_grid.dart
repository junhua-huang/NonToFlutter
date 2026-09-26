import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/identity_application.dart';
import 'package:nonto/services/api/role_service.dart';

class IdentityRoleGrid extends StatelessWidget {
  final List<BusinessIdentityRole> roles;
  final Map<String, IdentityApplication> applicationsByRole;
  final void Function(BusinessIdentityRole role) onApply;
  final void Function(IdentityApplication application) onView;

  const IdentityRoleGrid({
    super.key,
    required this.roles,
    required this.applicationsByRole,
    required this.onApply,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) {
      return Text('暂无可申请身份', style: TextStyle(color: AppColors.textSecondary));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: roles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      itemBuilder: (context, index) {
        final role = roles[index];
        final app = applicationsByRole[role.name];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => app == null ? onApply(role) : onView(app),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    app?.statusLabel ?? (role.description.isNotEmpty ? role.description : '申请认证身份'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                Text(
                  app == null ? '申请' : '查看',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
