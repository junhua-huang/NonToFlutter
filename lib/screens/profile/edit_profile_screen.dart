import 'dart:io';
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

/// 个人资料编辑页面 —— 按需编辑模式
///
/// 每个字段（头像、背景、名字、简介）独立编辑、独立保存。
/// 头像/背景：点击 → 选择图片 → 裁剪 → 立即上传
/// 名字/简介：点击进入编辑态 → 修改 → 保存/取消
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  // ── 各字段独立加载/上传状态 ──
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;
  bool _isSavingName = false;
  bool _isSavingBio = false;

  // ── 本地预览 ──
  Uint8List? _localAvatarBytes;
  Uint8List? _localCoverBytes;

  // ── 名字编辑态 ──
  bool _isEditingName = false;
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();

  // ── 简介编辑态 ──
  bool _isEditingBio = false;
  late final TextEditingController _bioController;
  final FocusNode _bioFocus = FocusNode();

  Color get _xBlack => AppColors.textPrimary;
  Color get _xDarkGrey => AppColors.textSecondary;
  Color get _xBlue => AppColors.primary;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _nameFocus.dispose();
    _bioFocus.dispose();
    super.dispose();
  }

  // ─── 缓存写入 ──────────────────────────────────────────────

  void _writeUserToCache(User user) {
    DataLayer().write('user:${user.id}:profile', user.toJson());
  }

  // ─── 头像：选择 → 裁剪 → 立即上传 ─────────────────────────

  Future<void> _changeAvatar() async {
    if (_isUploadingAvatar) return;

    try {
      XFile? picked;
      try {
        picked = await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
      } catch (e) {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;

      final originalBytes = await picked.readAsBytes();

      // 裁剪
      final croppedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            imageBytes: originalBytes,
            cropShape: CropShape.circle,
          ),
        ),
      );

      if (!mounted) return;

      final finalBytes = (croppedBytes != null && croppedBytes.isNotEmpty)
          ? croppedBytes
          : originalBytes;

      // 立即显示本地预览
      setState(() {
        _localAvatarBytes = finalBytes;
        _isUploadingAvatar = true;
      });

      // 上传
      final xfile = XFile.fromData(finalBytes, name: 'avatar.png', mimeType: 'image/png');
      final resp = await UploadService().uploadAvatar(xfile);
      if (!mounted) return;

      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final url = data['avatar_url'] ?? data['url'];
        if (url != null) {
          final user = ref.read(authProvider).user;
          if (user != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final updated = user.copyWith(avatarUrl: url, avatarCacheTs: now);
            ref.read(authProvider.notifier).updateUser(updated);
            _writeUserToCache(updated);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('头像更新成功'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '头像上传失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Change avatar error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('头像更新失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
          _localAvatarBytes = null;
        });
      }
    }
  }

  // ─── 背景图：选择 → 裁剪 → 立即上传 ─────────────────────────

  Future<void> _changeCoverPhoto() async {
    if (_isUploadingCover) return;

    try {
      XFile? picked;
      try {
        picked = await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
      } catch (e) {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      }
      if (picked == null) return;

      final originalBytes = await picked.readAsBytes();

      // 裁剪（16:9）
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

      final finalBytes = (croppedBytes != null && croppedBytes.isNotEmpty)
          ? croppedBytes
          : originalBytes;

      // 立即显示本地预览
      setState(() {
        _localCoverBytes = finalBytes;
        _isUploadingCover = true;
      });

      // 上传
      final xfile = XFile.fromData(finalBytes, name: 'cover.png', mimeType: 'image/png');
      final resp = await UploadService().uploadCoverPhoto(xfile);
      if (!mounted) return;

      if (resp.success && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        final url = data['cover_photo_url'] ?? data['url'];
        if (url != null) {
          final user = ref.read(authProvider).user;
          if (user != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final updated = user.copyWith(coverPhotoUrl: url, coverCacheTs: now);
            ref.read(authProvider.notifier).updateUser(updated);
            _writeUserToCache(updated);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('背景图更新成功'), backgroundColor: Colors.green),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '背景图上传失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Change cover error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('背景图更新失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingCover = false;
          _localCoverBytes = null;
        });
      }
    }
  }

  // ─── 名字：进入编辑态 ─────────────────────────────────────

  void _startEditName() {
    setState(() => _isEditingName = true);
    // 延迟聚焦，等 TextField 渲染完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _cancelEditName() {
    final user = ref.read(authProvider).user;
    _nameController.text = user?.displayName ?? '';
    setState(() => _isEditingName = false);
    _nameFocus.unfocus();
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    final user = ref.read(authProvider).user;
    if (user == null) return;

    // 无变化则直接退出编辑态
    if (newName == (user.displayName ?? '')) {
      setState(() => _isEditingName = false);
      _nameFocus.unfocus();
      return;
    }

    setState(() => _isSavingName = true);

    // 乐观写入
    final originalName = user.displayName;
    final optimistic = user.copyWith(displayName: newName);
    ref.read(authProvider.notifier).updateUser(optimistic);
    _writeUserToCache(optimistic);

    try {
      final updateData = <String, dynamic>{'display_name': newName};
      // 附带封面 URL，防止后端全量替换覆盖
      if (user.coverPhotoUrl != null) {
        updateData['cover_photo_url'] = user.coverPhotoUrl;
      }
      if (user.bio != null) {
        updateData['bio'] = user.bio;
      }
      final resp = await AuthService().updateProfile(updateData);
      if (!mounted) return;

      if (resp.success) {
        setState(() {
          _isEditingName = false;
          _isSavingName = false;
        });
        _nameFocus.unfocus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('名称已更新'), backgroundColor: Colors.green),
          );
        }
      } else {
        // 回滚
        ref.read(authProvider.notifier).updateUser(user.copyWith(displayName: originalName));
        _writeUserToCache(user.copyWith(displayName: originalName));
        setState(() => _isSavingName = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '名称更新失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      ref.read(authProvider.notifier).updateUser(user.copyWith(displayName: originalName));
      _writeUserToCache(user.copyWith(displayName: originalName));
      setState(() => _isSavingName = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── 简介：进入编辑态 ─────────────────────────────────────

  void _startEditBio() {
    setState(() => _isEditingBio = true);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _bioFocus.requestFocus();
    });
  }

  void _cancelEditBio() {
    final user = ref.read(authProvider).user;
    _bioController.text = user?.bio ?? '';
    setState(() => _isEditingBio = false);
    _bioFocus.unfocus();
  }

  Future<void> _saveBio() async {
    final newBio = _bioController.text.trim();
    final user = ref.read(authProvider).user;
    if (user == null) return;

    // 无变化则直接退出编辑态
    if (newBio == (user.bio ?? '')) {
      setState(() => _isEditingBio = false);
      _bioFocus.unfocus();
      return;
    }

    setState(() => _isSavingBio = true);

    // 乐观写入
    final originalBio = user.bio;
    final optimistic = user.copyWith(bio: newBio);
    ref.read(authProvider.notifier).updateUser(optimistic);
    _writeUserToCache(optimistic);

    try {
      final updateData = <String, dynamic>{'bio': newBio};
      if (user.coverPhotoUrl != null) {
        updateData['cover_photo_url'] = user.coverPhotoUrl;
      }
      if (user.displayName != null) {
        updateData['display_name'] = user.displayName;
      }
      final resp = await AuthService().updateProfile(updateData);
      if (!mounted) return;

      if (resp.success) {
        setState(() {
          _isEditingBio = false;
          _isSavingBio = false;
        });
        _bioFocus.unfocus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('简介已更新'), backgroundColor: Colors.green),
          );
        }
      } else {
        ref.read(authProvider.notifier).updateUser(user.copyWith(bio: originalBio));
        _writeUserToCache(user.copyWith(bio: originalBio));
        setState(() => _isSavingBio = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(resp.message ?? '简介更新失败'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      ref.read(authProvider.notifier).updateUser(user.copyWith(bio: originalBio));
      _writeUserToCache(user.copyWith(bio: originalBio));
      setState(() => _isSavingBio = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
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
          icon: Icon(Icons.arrow_back, color: _xBlack, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: false,
        title: Text(
          '编辑个人资料',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: _xBlack),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── 背景图 ──
          _buildCoverSection(user),
          const SizedBox(height: 24),

          // ── 头像 ──
          _buildAvatarSection(user),
          const SizedBox(height: 24),

          // ── 分隔线 ──
          Container(height: 8, color: AppColors.surface),

          // ── 名字 ──
          _buildNameSection(user),

          // ── 分隔线 ──
          Container(height: 0.5, color: AppColors.borderLight),

          // ── 简介 ──
          _buildBioSection(user),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ─── 背景图区域 ──────────────────────────────────────────────

  Widget _buildCoverSection(User? user) {
    return GestureDetector(
      onTap: _isUploadingCover ? null : _changeCoverPhoto,
      child: Stack(
        children: [
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
            ),
            child: _buildCoverPreview(user),
          ),
          // 上传中遮罩
          if (_isUploadingCover)
            Container(
              height: 180,
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('上传中...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ),
          // 编辑提示
          if (!_isUploadingCover)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt, size: 14, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('更换', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCoverPreview(User? user) {
    if (_localCoverBytes != null) {
      return ClipRect(
        child: Image.memory(
          _localCoverBytes!,
          width: double.infinity,
          height: 180,
          fit: BoxFit.cover,
        ),
      );
    }
    if (user?.coverPhotoUrl != null && user!.coverPhotoUrl!.isNotEmpty) {
      final url = user.coverPhotoUrl!.startsWith('http')
          ? user.coverPhotoUrl!
          : '${AppConfig.baseUrl.replaceFirst('/api', '')}${user.coverPhotoUrl}';
      return Image.network(
        url,
        width: double.infinity,
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.camera_alt, size: 36, color: Colors.white38),
        ),
      );
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, size: 36, color: Colors.white38),
          SizedBox(height: 8),
          Text('点击添加背景图',
              style: TextStyle(fontSize: 14, color: Colors.white38)),
        ],
      ),
    );
  }

  // ─── 头像区域 ──────────────────────────────────────────────

  Widget _buildAvatarSection(User? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _changeAvatar,
            child: Stack(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderLight, width: 2),
                  ),
                  child: _buildAvatarPreview(user),
                ),
                // 上传中遮罩
                if (_isUploadingAvatar)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black45,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // 相机图标
                if (!_isUploadingAvatar)
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
              '点击更换头像',
              style: TextStyle(fontSize: 14, color: _xDarkGrey),
            ),
          ),
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

  // ─── 名字区域 ──────────────────────────────────────────────

  Widget _buildNameSection(User? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '名称',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _xDarkGrey),
              ),
              const Spacer(),
              if (!_isEditingName)
                GestureDetector(
                  onTap: _startEditName,
                  child: Text(
                    '编辑',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: _xBlue),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isEditingName) ...[
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              maxLength: 50,
              style: TextStyle(fontSize: 16, color: _xBlack, height: 1.3),
              decoration: InputDecoration(
                hintText: '输入显示名称',
                hintStyle: TextStyle(color: _xDarkGrey, fontSize: 16),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _xBlue, width: 1),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                counterStyle: TextStyle(color: _xDarkGrey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSavingName ? null : _cancelEditName,
                  child: Text('取消',
                      style: TextStyle(color: _xDarkGrey, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSavingName ? null : _saveName,
                  style: FilledButton.styleFrom(
                    backgroundColor: _xBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _isSavingName
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('保存',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ] else ...[
            Text(
              user?.displayName ?? user?.username ?? '',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: _xBlack),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 简介区域 ──────────────────────────────────────────────

  Widget _buildBioSection(User? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '个人简介',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _xDarkGrey),
              ),
              const Spacer(),
              if (!_isEditingBio)
                GestureDetector(
                  onTap: _startEditBio,
                  child: Text(
                    '编辑',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: _xBlue),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isEditingBio) ...[
            TextField(
              controller: _bioController,
              focusNode: _bioFocus,
              maxLines: 4,
              maxLength: 160,
              style: TextStyle(fontSize: 15, color: _xBlack, height: 1.4),
              decoration: InputDecoration(
                hintText: '介绍一下你自己',
                hintStyle: TextStyle(color: _xDarkGrey, fontSize: 15),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _xBlue, width: 1),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                counterStyle: TextStyle(color: _xDarkGrey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSavingBio ? null : _cancelEditBio,
                  child: Text('取消',
                      style: TextStyle(color: _xDarkGrey, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSavingBio ? null : _saveBio,
                  style: FilledButton.styleFrom(
                    backgroundColor: _xBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _isSavingBio
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('保存',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ] else ...[
            if (user?.bio != null && user!.bio!.isNotEmpty)
              Text(
                user.bio!,
                style: TextStyle(fontSize: 15, color: _xBlack, height: 1.4),
              )
            else
              Text(
                '未填写',
                style: TextStyle(fontSize: 15, color: _xDarkGrey),
              ),
          ],
        ],
      ),
    );
  }
}
