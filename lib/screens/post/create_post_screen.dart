import 'dart:typed_data';

import 'package:facebook_clone/config/app_config.dart';
import 'package:facebook_clone/config/app_theme.dart';
import 'package:facebook_clone/models/post.dart';
import 'package:facebook_clone/models/user.dart';
import 'package:facebook_clone/providers/auth_provider.dart';
import 'package:facebook_clone/screens/home/home/feed_tab.dart';
import 'package:facebook_clone/services/api/api_client.dart';
import 'package:facebook_clone/services/api/post_service.dart';
import 'package:facebook_clone/services/api/upload_service.dart';
import 'package:facebook_clone/widgets/mention_topic_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 发帖页面 — 支持 1-9 张图片、压缩、上传进度、草稿恢复
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  // 多图支持
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _imageBytesList = [];

  // 视频支持（单视频，与图片互斥）
  XFile? _selectedVideo;
  Uint8List? _videoBytes;

  bool _isSubmitting = false;
  double _uploadProgress = 0.0;
  int _uploadedCount = 0;
  int _totalUploadCount = 0;
  String? _error;
  int _charCount = 0;
  static const int _maxChars = 500;
  static const int _maxImages = 9;

  // 草稿 key
  static const String _draftTextKey = 'create_post_draft_text';
  static const String _draftImagePathsKey = 'create_post_draft_image_paths';

  Color get _xBlue => AppColors.primary;
  Color get _xBlack => AppColors.textPrimary;
  Color get _xDarkGrey => AppColors.textSecondary;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _charCount = _controller.text.length);
    });
    _restoreDraft();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 恢复草稿（文本 + 图片路径）
  /// Web 平台：blob URL 无法通过 dart:io File 读取，仅恢复文本草稿
  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedText = prefs.getString(_draftTextKey);

      if (savedText != null && savedText.isNotEmpty) {
        _controller.text = savedText;
        _charCount = savedText.length;
      }

      // Web 上 blob URL 无法恢复为本地文件，跳过图片草稿恢复
      if (kIsWeb) return;

      final savedPaths = prefs.getStringList(_draftImagePathsKey);
      if (savedPaths != null && savedPaths.isNotEmpty) {
        final restoredImages = <XFile>[];
        final restoredBytes = <Uint8List>[];
        for (final path in savedPaths) {
          final file = XFile(path);
          try {
            final bytes = await file.readAsBytes();
            restoredImages.add(file);
            restoredBytes.add(bytes);
          } catch (_) {
            // 文件已不存在，跳过
          }
        }
        if (restoredImages.isNotEmpty && mounted) {
          setState(() {
            _selectedImages.addAll(restoredImages);
            _imageBytesList.addAll(restoredBytes);
          });
        }
      }
    } catch (_) {}
  }

  /// 保存草稿
  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = _controller.text.trim();
      if (text.isNotEmpty) {
        await prefs.setString(_draftTextKey, text);
      } else {
        await prefs.remove(_draftTextKey);
      }
      if (_selectedImages.isNotEmpty) {
        await prefs.setStringList(
          _draftImagePathsKey,
          _selectedImages.map((f) => f.path).toList(),
        );
      } else {
        await prefs.remove(_draftImagePathsKey);
      }
    } catch (_) {}
  }

  /// 清除草稿
  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftTextKey);
      await prefs.remove(_draftImagePathsKey);
    } catch (_) {}
  }

  /// 选择多张图片（1-9 张）
  Future<void> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage(
        limit: _maxImages,
        maxWidth: 1920,
        imageQuality: 92,
      );
      if (picked.isEmpty) return;

      final bytesList = <Uint8List>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        bytesList.add(bytes);
      }

      setState(() {
        // 重置视频
        _selectedVideo = null;
        _videoBytes = null;
        // 追加图片（不覆盖已有选择，用户可多次选图累计到上限）
        final remaining = _maxImages - _selectedImages.length;
        final toAdd = picked.length > remaining ? picked.sublist(0, remaining) : picked;
        _selectedImages.addAll(toAdd);
        _imageBytesList.addAll(bytesList.take(toAdd.length));
      });
    } catch (e) {
      debugPrint('Pick images error: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _selectedVideo = picked;
          _videoBytes = bytes;
          _selectedImages.clear();
          _imageBytesList.clear();
        });
      }
    } catch (e) {
      debugPrint('Pick video error: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _imageBytesList.removeAt(index);
    });
  }

  void _removeMedia() {
    setState(() {
      _selectedImages.clear();
      _imageBytesList.clear();
      _selectedVideo = null;
      _videoBytes = null;
    });
  }

  Future<void> _submitPost() async {
    final content = _controller.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty && _selectedVideo == null) {
      setState(() => _error = '帖子内容或媒体不能为空');
      return;
    }

    final auth = context.read<AuthProvider>();
    final currentUser = auth.user;
    if (currentUser == null) {
      setState(() => _error = '请先登录');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0;
      _uploadedCount = 0;
      _totalUploadCount = _selectedImages.length + (_selectedVideo != null ? 1 : 0);
      _error = null;
    });

    final List<String> imageUrls = <String>[];
    String? videoUrl;

    try {
      // 1. 压缩并上传多图
      if (_selectedImages.isNotEmpty && _imageBytesList.isNotEmpty) {
        for (int i = 0; i < _selectedImages.length; i++) {
          if (!mounted) return;
          final file = _selectedImages[i];

          // 使用 UploadService 压缩
          final compressed = await UploadService.compressXFile(file);

          final uploadResp = await ApiClient().uploadBytes(
            '/upload/post/image',
            await compressed.readAsBytes(),
            compressed.name,
            onSendProgress: (sent, total) {
              if (total > 0 && mounted) {
                setState(() {
                  final perImage = 1.0 / _totalUploadCount;
                  _uploadProgress = (_uploadedCount + sent / total) * perImage;
                });
              }
            },
          );

          if (!uploadResp.success) {
            // 上传失败：保存草稿
            await _saveDraft();
            if (mounted) {
              setState(() {
                _isSubmitting = false;
                _error = '第 ${i + 1} 张图片上传失败: ${uploadResp.message}（草稿已保存）';
              });
            }
            return;
          }

          final url = _extractUrl(uploadResp.data);
          if (url != null) imageUrls.add(url);

          setState(() => _uploadedCount++);
        }
      }

      // 2. 上传视频
      if (_selectedVideo != null && _videoBytes != null) {
        setState(() => _uploadProgress = 0);
        final uploadResp = await ApiClient().uploadBytes(
          '/upload/post/video',
          _videoBytes!,
          _selectedVideo!.name,
          onSendProgress: (sent, total) {
            if (total > 0 && mounted) {
              setState(() => _uploadProgress = sent / total);
            }
          },
        );
        if (!uploadResp.success) {
          await _saveDraft();
          if (mounted) {
            setState(() {
              _isSubmitting = false;
              _error = '视频上传失败: ${uploadResp.message}（草稿已保存）';
            });
          }
          return;
        }
        videoUrl = _extractUrl(uploadResp.data);
        setState(() => _uploadedCount++);
      }

      // 3. 创建帖子
      final resp = await PostService().createPost(
        content: content,
        imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
        videoPath: videoUrl,
      );

      if (resp.success) {
        Post? serverPost;
        if (resp.data != null) {
          final postData = resp.data is Map ? resp.data as Map<String, dynamic> : null;
          if (postData != null) {
            if (postData.containsKey('post')) {
              serverPost = Post.fromJson(postData['post'] as Map<String, dynamic>);
            } else if (postData.containsKey('id')) {
              serverPost = Post.fromJson(postData);
            }
          }
        }

        final optimisticPost = serverPost ??
            Post(
              id: -DateTime.now().millisecondsSinceEpoch,
              content: content,
              videoUrl: videoUrl,
              userId: currentUser.id,
              user: currentUser,
              likeCount: 0,
              commentCount: 0,
              isLiked: false,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              images: imageUrls.isNotEmpty ? imageUrls : null,
            );

        FeedTab.newPostNotifier.value = optimisticPost;
        await _clearDraft();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        await _saveDraft();
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _error = resp.message ?? '发布失败（草稿已保存）';
          });
        }
      }
    } catch (e) {
      await _saveDraft();
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = '网络错误，请稍后重试（草稿已保存）';
        });
      }
    }
  }

  String? _extractUrl(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      return data['url']?.toString() ??
          data['image_url']?.toString() ??
          data['video_url']?.toString() ??
          data['file_url']?.toString();
    }
    return data.toString();
  }

  // ========== Reorderable image list (tap to preview, drag to reorder) ==========

  Widget _buildImageList() {
    return SizedBox(
      height: 120,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 12),
        itemCount: _selectedImages.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final img = _selectedImages.removeAt(oldIndex);
            _selectedImages.insert(newIndex, img);
            final bytes = _imageBytesList.removeAt(oldIndex);
            _imageBytesList.insert(newIndex, bytes);
          });
        },
        buildDefaultDragHandles: true,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    child!,
                    // 拖动时显示删除按钮
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    // 拖动时显示序号
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${index + 1}/${_selectedImages.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            child: child,
          );
        },
        itemBuilder: (context, index) {
          return Container(
            key: ValueKey('img_grid_$index'),
            width: 120,
            height: 120,
            margin: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _previewImage(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytesList[index],
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _previewImage(int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImagePreviewPage(
            imageBytesList: _imageBytesList,
            initialIndex: index,
          );
        },
      ),
    );
  }

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _EmojiPickerPanel(
        onEmojiSelected: (emoji) {
          final text = _controller.text;
          final pos = _controller.selection.baseOffset;
          if (pos < 0) {
            _controller.text = '$text$emoji';
            _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
          } else {
            _controller.text = '${text.substring(0, pos)}$emoji${text.substring(pos)}';
            _controller.selection = TextSelection.collapsed(offset: pos + emoji.length);
          }
          _focusNode.requestFocus();
        },
      ),
    );
  }

  // ========== 视频预览 ==========

  Widget _buildVideoPreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.videocam, size: 40, color: Colors.white54),
                  Icon(Icons.play_arrow, size: 48, color: Colors.white),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _removeMedia,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final hasContent = _controller.text.trim().isNotEmpty ||
        _selectedImages.isNotEmpty ||
        _selectedVideo != null;
    final canPost = hasContent && !_isSubmitting;
    final isOverLimit = _charCount > _maxChars;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close, color: _xBlack, size: 24),
          onPressed: () {
            _saveDraft();
            Navigator.of(context).pop();
          },
        ),
        centerTitle: false,
        title: TextButton(
          onPressed: canPost && !isOverLimit ? _submitPost : null,
          style: TextButton.styleFrom(
            backgroundColor: canPost && !isOverLimit ? _xBlue : Colors.grey[300],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            disabledBackgroundColor: Colors.grey[300],
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('发帖',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.borderLight),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildUserAvatar(user),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? '未知用户',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _xBlack,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${user?.username ?? ''}',
                              style: TextStyle(color: _xDarkGrey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Text field
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLines: null,
                    maxLength: _maxChars,
                    style: TextStyle(fontSize: 18, height: 1.4, color: _xBlack),
                    decoration: InputDecoration(
                      hintText: '有什么新鲜事？',
                      hintStyle: TextStyle(color: _xDarkGrey, fontSize: 18),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
          // Image grid preview (tap to preview)
                  if (_selectedImages.isNotEmpty && _imageBytesList.isNotEmpty)
                    _buildImageList(),
                  // Video preview
                  if (_selectedVideo != null) _buildVideoPreview(),
                  // Upload progress
                  if (_isSubmitting) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      backgroundColor: AppColors.borderLight,
                      valueColor: AlwaysStoppedAnimation(_xBlue),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _totalUploadCount > 1
                          ? '上传中 $_uploadedCount/$_totalUploadCount (${(_uploadProgress * 100).toInt()}%)'
                          : _uploadProgress > 0
                              ? '上传中 ${(_uploadProgress * 100).toInt()}%'
                              : '发布中...',
                      style: TextStyle(color: _xDarkGrey, fontSize: 12),
                    ),
                  ],
                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          MentionTopicPicker(
            controller: _controller,
            focusNode: _focusNode,
          ),
          // Bottom toolbar — horizontally scrollable
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderLight)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolbarButton(
                    icon: Icons.image_outlined,
                    label: '图片 (${_selectedImages.length}/$_maxImages)',
                    onTap: _selectedImages.length >= _maxImages ? null : _pickImages,
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: Icons.videocam_outlined,
                    label: '视频',
                    onTap: _selectedImages.isNotEmpty ? null : _pickVideo,
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: Icons.alternate_email,
                    label: '@好友',
                    onTap: () {
                      final text = _controller.text;
                      final pos = _controller.selection.baseOffset;
                      if (pos < 0) return;
                      _controller.text =
                          '${text.substring(0, pos)}@${text.substring(pos)}';
                      _controller.selection = TextSelection.collapsed(offset: pos + 1);
                      _focusNode.requestFocus();
                    },
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: Icons.tag,
                    label: '#话题',
                    onTap: () {
                      final text = _controller.text;
                      final pos = _controller.selection.baseOffset;
                      if (pos < 0) return;
                      _controller.text =
                          '${text.substring(0, pos)}#${text.substring(pos)}';
                      _controller.selection = TextSelection.collapsed(offset: pos + 1);
                      _focusNode.requestFocus();
                    },
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: Icons.emoji_emotions_outlined,
                    label: '表情',
                    onTap: _showEmojiPicker,
                  ),
                  const SizedBox(width: 12),
                  // Character counter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_charCount/$_maxChars',
                      style: TextStyle(
                        color: isOverLimit ? Colors.red : _xDarkGrey,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(User? user) {
    final avatarUrl = user?.avatarUrl;
    const radius = 20.0;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final url = avatarUrl.startsWith('http')
          ? avatarUrl
          : '${AppConfig.baseUrl.replaceFirst('/api', '')}$avatarUrl';
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(url),
        backgroundColor: Colors.grey[200],
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _xBlue,
      child: Text(
        user?.initials ?? '?',
        style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolbarButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 20,
                color: enabled ? AppColors.primary : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: enabled ? AppColors.primary : Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== Emoji picker panel ==========

class _EmojiPickerPanel extends StatelessWidget {
  final void Function(String emoji) onEmojiSelected;

  const _EmojiPickerPanel({required this.onEmojiSelected});

  static const _emojis = [
    // Smileys & Emotion
    '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊',
    '😇', '🙂', '😉', '😌', '😍', '🥰', '😘', '😗',
    '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭',
    '🤔', '🤐', '😐', '😑', '😶', '😏', '😒', '🙄',
    '😬', '🤥', '😪', '😴', '🤤', '😷', '🤒', '🤕',
    '🤢', '🤮', '🥴', '😵', '🤯', '🥳', '😎', '🤓',
    // Gestures & People
    '👍', '👎', '👏', '🙌', '🤝', '💪', '✌️', '🤞',
    '👋', '🤚', '🖐️', '✋', '👉', '👈', '👇', '🖖',
    '🙏', '💅', '🤳', '🙆', '🙅', '💁', '🤷', '🙋',
    // Hearts & Symbols
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '💔', '💕', '💖', '💗', '💓', '💝', '💘', '💌',
    '🔥', '⭐', '✨', '💯', '✅', '❌', '💫', '💥',
    // Misc
    '🎉', '🎊', '🎂', '🍰', '☕', '🍺', '🎵', '🎶',
    '🌈', '☀️', '🌙', '⚡', '💧', '🌊', '🌸', '🌺',
    '🐱', '🐶', '🐼', '🦊', '🐰', '🐨', '🐸', '🦄',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(
              height: 280,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _emojis.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      onEmojiSelected(_emojis[index]);
                      Navigator.pop(context);
                    },
                    child: Center(
                      child: Text(
                        _emojis[index],
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== Full-screen image preview ==========

class _ImagePreviewPage extends StatelessWidget {
  final List<Uint8List> imageBytesList;
  final int initialIndex;

  const _ImagePreviewPage({
    required this.imageBytesList,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: imageBytesList.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 5.0,
            child: Center(
              child: Image.memory(
                imageBytesList[index],
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          );
        },
      ),
    );
  }
}
