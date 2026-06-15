import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/screens/profile/image_crop_screen.dart';
import 'package:nonto/services/api/auth_service.dart';
import 'package:nonto/services/data_layer.dart';
import 'package:nonto/services/api/upload_service.dart';
import 'package:nonto/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 个人资料编辑页面（头像/背景/简介）
///
/// 头像和背景图选择后本地暂存，点击"保存"按钮时统一上传。
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bioController;
  bool _isLoading = false;
  String? _error;
  final ImagePicker _picker = ImagePicker();

  /// 本地暂存的裁剪后头像字节（null 表示未更改）
  Uint8List? _localAvatarBytes;
  /// 本地暂存的裁剪后背景图字节（null 表示未更改）
  Uint8List? _localCoverBytes;

  Color get _xBlack => AppColors.textPrimary;
  Color get _xDarkGrey => AppColors.textSecondary;
  Color get _xBlue => AppColors.primary;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  // ─── 保存（统一上传） ──────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authProvider);
      var user = auth.user;

      // 上传头像（如有本地暂存）
      if (_localAvatarBytes != null) {
        final xfile = XFile.fromData(
          _localAvatarBytes!,
          name: 'avatar.png',
          mimeType: 'image/png',
        );
        final resp = await UploadService().uploadAvatar(xfile);
        if (!mounted) return;

        if (resp.success && resp.data != null && user != null) {
          final data = resp.data as Map<String, dynamic>;
          final url = data['avatar_url'] ?? data['url'];
          if (url != null) {
            user = user.copyWith(avatarUrl: url);
            ref.read(authProvider.notifier).updateUser(user);
            _writeUserToCache(user);
          }
        } else {
          throw Exception(resp.message ?? '头像上传失败');
        }
      }

      // 上传背景图（如有本地暂存）
      if (_localCoverBytes != null) {
        final xfile = XFile.fromData(
          _localCoverBytes!,
          name: 'cover.png',
          mimeType: 'image/png',
        );
        final resp = await UploadService().uploadCoverPhoto(xfile);
        if (!mounted) return;

        if (resp.success && resp.data != null && user != null) {
          final data = resp.data as Map<String, dynamic>;
          final url = data['cover_photo_url'] ?? data['url'];
          if (url != null) {
            user = user.copyWith(coverPhotoUrl: url);
            ref.read(authProvider.notifier).updateUser(user);
            _writeUserToCache(user);
          }
        } else {
          throw Exception(resp.message ?? '背景图上传失败');
        }
      }

      // 更新简介 — 乐观写入 L2+L1 先于网络
      final currentUser = auth.user;
      if (currentUser != null) {
        final originalBio = currentUser.bio;
        final optimistic = currentUser.copyWith(bio: _bioController.text.trim());
        ref.read(authProvider.notifier).updateUser(optimistic);
        _writeUserToCache(optimistic); // L2 + L1 乐观写入
        try {
          final updateData = <String, dynamic>{
            'bio': _bioController.text.trim(),
          };
          // 将已更新的封面 URL 一并发送，防止后端全量替换覆盖
          final u = ref.read(authProvider).user;
          if (u?.coverPhotoUrl != null) {
            updateData['cover_photo_url'] = u!.coverPhotoUrl;
          }
          final bioResp = await AuthService().updateProfile(updateData);
          if (!mounted) return;
          if (bioResp.success) {
            Navigator.of(context).pop(true);
          } else {
            // 失败回滚
            final rolled = optimistic.copyWith(bio: originalBio);
            ref.read(authProvider.notifier).updateUser(rolled);
            _writeUserToCache(rolled);
            setState(() => _error = bioResp.message ?? '简介更新失败');
            setState(() => _isLoading = false);
          }
        } catch (e) {
          if (mounted) {
            final rolled = optimistic.copyWith(bio: originalBio);
            ref.read(authProvider.notifier).updateUser(rolled);
            _writeUserToCache(rolled);
            setState(() { _error = '保存失败: $e'; _isLoading = false; });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '保存失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 将用户数据写入 DataLayer L1，供 splash 预热和 profile_tab 首屏读取
  void _writeUserToCache(User user) {
    DataLayer().write('user:${user.id}:profile', user.toJson());
  }

  // ─── 修改头像（仅本地裁剪 + 暂存） ─────────────────────────

  Future<void> _changeAvatar() async {
    if (_isLoading) return;

    try {
      XFile? picked;
      try {
        picked = await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
      } catch (e) {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;

      // 先读取原始字节，避免 Web 上 dart:io File(path) 不兼容
      final originalBytes = await picked.readAsBytes();

      // 跳转到自定义裁剪页面（圆形模式）
      final croppedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            imageBytes: originalBytes,
            cropShape: CropShape.circle,
          ),
        ),
      );

      if (!mounted) return;

      if (croppedBytes != null && croppedBytes.isNotEmpty) {
        // 使用裁剪结果
        setState(() => _localAvatarBytes = croppedBytes);
      } else {
        // 用户未裁剪（取消 / 返回），使用原图
        setState(() => _localAvatarBytes = originalBytes);
      }
    } catch (e) {
      debugPrint('Change avatar error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('选择图片失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── 修改背景图（仅本地裁剪 + 暂存） ────────────────────────

  Future<void> _changeCoverPhoto() async {
    if (_isLoading) return;

    try {
      XFile? picked;
      try {
        picked = await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
      } catch (e) {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;

      // 先读取原始字节
      final originalBytes = await picked.readAsBytes();

      // 跳转到裁剪页面（矩形模式，16:9）
      final croppedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            imageBytes: originalBytes,
            cropShape: CropShape.rectangle,
            aspectRatio: 16 / 9,
          ),
        ),
      );

      if (!mounted) return;

      if (croppedBytes != null && croppedBytes.isNotEmpty) {
        setState(() => _localCoverBytes = croppedBytes);
      } else {
        // 用户取消裁剪，使用原图
        setState(() => _localCoverBytes = originalBytes);
      }
    } catch (e) {
      debugPrint('Change cover error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('选择图片失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close, color: _xBlack, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: false,
        title: Text(
          '编辑个人资料',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: _xBlack),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: _xBlue, strokeWidth: 2),
                  )
                : Text('保存',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _xBlue)),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 背景图 ──
            _buildLabel('背景图片'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _isLoading ? null : _changeCoverPhoto,
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildCoverPreview(user),
              ),
            ),
            const SizedBox(height: 24),

            // ── 头像 ──
            _buildLabel('头像'),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: _isLoading ? null : _changeAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.borderLight, width: 2),
                        ),
                        child: _buildAvatarPreview(user),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _xBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '点击更换头像，支持裁剪为圆形',
                    style: TextStyle(fontSize: 13, color: _xDarkGrey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── 显示信息 ──
            if (user != null) ...[
              Row(
                children: [
                  Text(
                    '当前名称: ${user.displayName ?? user.username}',
                    style: TextStyle(fontSize: 14, color: _xDarkGrey),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '@${user.username}',
                style: TextStyle(fontSize: 14, color: _xDarkGrey),
              ),
              const SizedBox(height: 24),
            ],

            // ── 简介 ──
            _buildLabel('个人简介'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 160,
              decoration: _inputDecoration('介绍一下你自己'),
              style: TextStyle(fontSize: 15, color: _xBlack, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── 预览组件 ──────────────────────────────────────────────

  Widget _buildCoverPreview(User? user) {
    if (_localCoverBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          _localCoverBytes!,
          width: double.infinity,
          height: 160,
          fit: BoxFit.cover,
        ),
      );
    }
    if (user?.coverPhotoUrl != null && user!.coverPhotoUrl!.isNotEmpty) {
      final url = user.coverPhotoUrl!.startsWith('http')
          ? user.coverPhotoUrl!
          : '${AppConfig.baseUrl.replaceFirst('/api', '')}${user.coverPhotoUrl}';
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: double.infinity,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.camera_alt, size: 36, color: Colors.white38),
          ),
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 36, color: Colors.white38),
          SizedBox(height: 8),
          Text('点击更换背景图',
              style: TextStyle(fontSize: 14, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildAvatarPreview(User? user) {
    if (_localAvatarBytes != null) {
      return ClipOval(
        child: Image.memory(
          _localAvatarBytes!,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
        ),
      );
    }
    if (user != null) {
      return ImageUtils.buildAvatar(user, radius: 40);
    }
    return const Icon(Icons.person, size: 40, color: Colors.white38);
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: _xBlack),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _xDarkGrey, fontSize: 15),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _xBlue, width: 1),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
