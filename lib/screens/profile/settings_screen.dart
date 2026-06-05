import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/providers/theme_provider.dart';
import 'package:facebook_clone/routes/app_routes.dart';
import 'package:facebook_clone/screens/auth/login_screen.dart';
import 'package:facebook_clone/services/api/auth_service.dart';
import 'package:facebook_clone/services/api/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ═══════════════════════════════════════════════════════════════
// 共享 UI 构建方法
// ═══════════════════════════════════════════════════════════════
Widget _buildSettingsSection(String title, List<Widget> children) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight, width: 1),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

Widget _buildSettingsDivider() {
  return const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.borderLight);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 通知设置
  bool _pushNotifications = false;
  bool _messageAlerts = false;
  bool _soundEnabled = false;
  bool _isNotifSettingsLoaded = false;

  // 通用设置
  double _fontSize = 1.0; // 1.0 = 100%

  // 账号注销加载状态
  bool _isDeleting = false;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final resp = await NotificationService().getSettings();
      if (resp.success && resp.data != null && mounted) {
        final data = resp.data as Map<String, dynamic>;
        setState(() {
          _pushNotifications = data['push_notifications'] == true;
          _messageAlerts = data['message_alerts'] == true;
          _soundEnabled = data['sound_enabled'] == true;
          _isNotifSettingsLoaded = true;
        });
      } else {
        if (mounted) setState(() => _isNotifSettingsLoaded = true);
      }
    } catch (e) {
      debugPrint('Failed to load notification settings: $e');
      if (mounted) setState(() => _isNotifSettingsLoaded = true);
    }
  }

  Future<void> _updateNotificationSetting(String key, bool value) async {
    if (!_isNotifSettingsLoaded) return;
    try {
      await NotificationService().updateSettings({key: value});
    } catch (e) {
      debugPrint('Failed to update notification setting $key: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '设置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 账号与安全
          _buildSettingsSection('账号与安全', [
            _buildListTile(
              title: '修改密码',
              icon: Icons.lock_outline,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showChangePasswordDialog(context),
            ),
            _buildSettingsDivider(),
            _buildListTile(
              title: '隐私设置',
              icon: Icons.privacy_tip_outlined,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showPrivacySettings(context),
            ),
            _buildSettingsDivider(),
            _buildListTile(
              title: '账号注销',
              icon: Icons.delete_outline,
              iconColor: Colors.red,
              titleColor: Colors.red,
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.red),
              onTap: () => _showAccountDeletionDialog(context, authProvider),
            ),
          ]),

          const SizedBox(height: 24),

          // 通知设置
          _buildSettingsSection('通知设置', [
            _buildSwitchTile(
              title: '推送通知',
              icon: Icons.notifications_outlined,
              value: _pushNotifications,
              onChanged: (v) {
                setState(() => _pushNotifications = v);
                _updateNotificationSetting('push_notifications', v);
              },
            ),
            _buildSettingsDivider(),
            _buildSwitchTile(
              title: '消息提醒',
              icon: Icons.message_outlined,
              value: _messageAlerts,
              onChanged: (v) {
                setState(() => _messageAlerts = v);
                _updateNotificationSetting('message_alerts', v);
              },
            ),
            _buildSettingsDivider(),
            _buildSwitchTile(
              title: '声音',
              icon: Icons.volume_up_outlined,
              value: _soundEnabled,
              onChanged: (v) {
                setState(() => _soundEnabled = v);
                _updateNotificationSetting('sound_enabled', v);
              },
            ),
          ]),

          const SizedBox(height: 24),

          // 通用
          _buildSettingsSection('通用', [
            _buildSwitchTile(
              title: '深色模式',
              icon: themeProvider.isDark ? Icons.dark_mode : Icons.light_mode,
              value: themeProvider.isDark,
              onChanged: (v) => themeProvider.toggleTheme(),
            ),
            _buildSettingsDivider(),
            _buildListTile(
              title: '语言设置',
              icon: Icons.language,
              trailing: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('简体中文', style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20),
                ],
              ),
              onTap: () => _showLanguageDialog(context),
            ),
            _buildSettingsDivider(),
            _buildSliderTile(
              title: '字体大小',
              icon: Icons.format_size,
              value: _fontSize,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              onChanged: (v) => setState(() => _fontSize = v),
            ),
          ]),

          const SizedBox(height: 24),

          // 关于
          _buildSettingsSection('关于', [
            _buildListTile(
              title: '版本号',
              icon: Icons.info_outline,
              trailing: Text(
                'v${AppConfig.appVersion}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              onTap: null,
            ),
            _buildSettingsDivider(),
            _buildListTile(
              title: '用户协议',
              icon: Icons.description_outlined,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.pushNamed(context, AppRoutes.termsOfService),
            ),
            _buildSettingsDivider(),
            _buildListTile(
              title: '隐私政策',
              icon: Icons.security_outlined,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.pushNamed(context, AppRoutes.privacyPolicy),
            ),
            _buildSettingsDivider(),
            _buildListTile(
              title: '开源许可',
              icon: Icons.code_outlined,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.pushNamed(context, AppRoutes.openSource),
            ),
          ]),

          const SizedBox(height: 32),

          // 退出登录
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showLogoutConfirmation(context, authProvider),
              icon: const Icon(Icons.logout, size: 20),
              label: const Text(
                '退出登录',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── UI helpers ───

  Widget _buildListTile({
    required String title,
    required IconData icon,
    Color? iconColor,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.textPrimary),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? AppColors.textPrimary,
          fontSize: 16,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 32,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary.withValues(alpha: 0x80),
        activeThumbColor: AppColors.primary,
      ),
      onTap: () => onChanged(!value),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 32,
    );
  }

  Widget _buildSliderTile({
    required String title,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: AppColors.textPrimary),
          title: Text(title, style: const TextStyle(fontSize: 16)),
          trailing: Text(
            '${(value * 100).round()}%',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          minLeadingWidth: 32,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.borderLight,
          ),
        ),
      ],
    );
  }

  // 修改密码对话框
  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPasswordController,
              decoration: const InputDecoration(
                labelText: '当前密码',
                hintText: '请输入当前密码',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              decoration: const InputDecoration(
                labelText: '新密码',
                hintText: '请输入新密码（至少6位）',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              decoration: const InputDecoration(
                labelText: '确认新密码',
                hintText: '请再次输入新密码',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('新密码至少需要6位')),
                );
                return;
              }
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次输入的新密码不一致')),
                );
                return;
              }

              final result = await _authService.changePassword(
                currentPassword: oldPasswordController.text,
                newPassword: newPasswordController.text,
              );

              if (result.success) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密码修改成功'), backgroundColor: Colors.green),
                  );
                  Navigator.pop(context);
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('密码修改失败: ${result.message}'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }

  // 隐私设置
  void _showPrivacySettings(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _PrivacySettingsPage()));
  }

  // 账号注销确认 (GDPR "被遗忘权" 流程)
  void _showAccountDeletionDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                  SizedBox(width: 8),
                  Text('账号注销', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                ],
              ),
              content: _isDeleting
                  ? const SizedBox(
                      height: 60,
                      child: Center(child: CircularProgressIndicator(color: Colors.red)),
                    )
                  : const Text(
                      '此操作将永久删除您的账号、所有帖子、评论和私信。此操作不可撤销。',
                      style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
                    ),
              actions: _isDeleting
                  ? null
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('我再想想', style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          setDialogState(() => _isDeleting = true);
                          final result = await _authService.deleteAccount();
                          if (result.success) {
                            await authProvider.logout();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('账号已注销'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (_) => const LoginScreen()),
                                (route) => false,
                              );
                            }
                          } else {
                            setDialogState(() => _isDeleting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('注销失败: ${result.message}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('确认注销'),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  // 语言设置
  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('语言设置'),
        content: const Text('语言设置功能正在开发中，当前仅支持简体中文。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 退出登录确认
  void _showLogoutConfirmation(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('确认退出'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 隐私设置子页面
// ═══════════════════════════════════════════════════════════════
class _PrivacySettingsPage extends StatefulWidget {
  const _PrivacySettingsPage();

  @override
  State<_PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<_PrivacySettingsPage> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isSaving = false;

  // 设置项
  String _profileVisibility = 'public';
  String _postDefaultVisibility = 'public';
  bool _showEmail = false;
  bool _allowSearch = true;
  String _allowFriendRequests = 'everyone';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final resp = await _authService.getPrivacy();
      if (resp.success && resp.data != null) {
        setState(() {
          _profileVisibility = resp.data['profile_visibility'] ?? 'public';
          _postDefaultVisibility = resp.data['post_default_visibility'] ?? 'public';
          _showEmail = resp.data['show_email'] ?? false;
          _allowSearch = resp.data['allow_search'] ?? true;
          _allowFriendRequests = resp.data['allow_friend_requests'] ?? 'everyone';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final resp = await _authService.updatePrivacy({
        'profile_visibility': _profileVisibility,
        'post_default_visibility': _postDefaultVisibility,
        'show_email': _showEmail,
        'allow_search': _allowSearch,
        'allow_friend_requests': _allowFriendRequests,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resp.success ? '隐私设置已保存' : (resp.message ?? '保存失败')),
            backgroundColor: resp.success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误，请重试'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildSettingsSection('个人主页', [
                  _buildOptionTile(
                    title: '谁可以查看你的主页',
                    subtitle: _profileVisibilityLabel(_profileVisibility),
                    icon: Icons.visibility_outlined,
                    onTap: () => _showPicker(
                      title: '谁可以查看你的主页',
                      options: [
                        const _Option('public', '所有人', '任何人都可以看到你的主页'),
                        const _Option('friends_only', '仅好友', '只有你的好友可以看到你的主页'),
                        const _Option('private', '仅自己', '只有你自己可以看到你的主页'),
                      ],
                      currentValue: _profileVisibility,
                      onSelected: (v) => setState(() => _profileVisibility = v),
                    ),
                  ),
                  _buildSettingsDivider(),
                  _buildSwitchTileFull(
                    title: '在主页展示邮箱',
                    subtitle: '开启后你的邮箱将对他人可见',
                    icon: Icons.email_outlined,
                    value: _showEmail,
                    onChanged: (v) => setState(() => _showEmail = v),
                  ),
                ]),
                const SizedBox(height: 24),
                _buildSettingsSection('帖子', [
                  _buildOptionTile(
                    title: '默认帖子可见范围',
                    subtitle: _postVisibilityLabel(_postDefaultVisibility),
                    icon: Icons.public_outlined,
                    onTap: () => _showPicker(
                      title: '默认帖子可见范围',
                      options: [
                        const _Option('public', '公开', '所有人可见'),
                        const _Option('friends_only', '仅好友', '仅好友可见'),
                      ],
                      currentValue: _postDefaultVisibility,
                      onSelected: (v) => setState(() => _postDefaultVisibility = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _buildSettingsSection('社交', [
                  _buildOptionTile(
                    title: '谁可以向你发送好友请求',
                    subtitle: _friendRequestLabel(_allowFriendRequests),
                    icon: Icons.person_add_outlined,
                    onTap: () => _showPicker(
                      title: '谁可以向你发送好友请求',
                      options: [
                        const _Option('everyone', '所有人', '任何人都可以向你发送好友请求'),
                        const _Option('friends_of_friends', '好友的好友', '仅好友的好友可以向你发送请求'),
                        const _Option('none', '关闭', '不接受任何好友请求'),
                      ],
                      currentValue: _allowFriendRequests,
                      onSelected: (v) => setState(() => _allowFriendRequests = v),
                    ),
                  ),
                  _buildSettingsDivider(),
                  _buildSwitchTileFull(
                    title: '允许通过搜索找到我',
                    subtitle: '关闭后，其他用户无法通过用户名或邮箱搜索到你',
                    icon: Icons.search_outlined,
                    value: _allowSearch,
                    onChanged: (v) => setState(() => _allowSearch = v),
                  ),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ─── Picker dialog ───
  void _showPicker({
    required String title,
    required List<_Option> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: const BoxDecoration(color: AppColors.dragHandle, borderRadius: BorderRadius.all(Radius.circular(2))),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              ...options.map((opt) {
                final isSelected = opt.value == currentValue;
                return GestureDetector(
                  onTap: () {
                    onSelected(opt.value);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.selectionHighlight : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opt.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isSelected ? AppColors.primary : AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text(opt.description, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        if (isSelected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Labels ───
  String _profileVisibilityLabel(String v) {
    switch (v) {
      case 'friends_only': return '仅好友';
      case 'private': return '仅自己';
      default: return '所有人';
    }
  }

  String _postVisibilityLabel(String v) => v == 'friends_only' ? '仅好友' : '公开';

  String _friendRequestLabel(String v) {
    switch (v) {
      case 'friends_of_friends': return '好友的好友';
      case 'none': return '关闭';
      default: return '所有人';
    }
  }

  // ─── Shared widgets ───
  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 32,
    );
  }

  Widget _buildSwitchTileFull({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary.withValues(alpha: 0x80),
        activeThumbColor: AppColors.primary,
      ),
      onTap: () => onChanged(!value),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 32,
    );
  }
}

class _Option {
  final String value;
  final String label;
  final String description;
  const _Option(this.value, this.label, this.description);
}