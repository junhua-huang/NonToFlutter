import 'dart:io';
import 'dart:typed_data';

import 'package:nonto/config/app_config.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/data/emoji_data.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/user.dart';
import 'package:nonto/providers/auth_notifier.dart';
import 'package:nonto/screens/home/home/feed_tab.dart';
import 'package:nonto/screens/profile/profile_tab.dart';
import 'package:nonto/services/api/api_client.dart';
import 'package:nonto/services/api/post_service.dart';
import 'package:nonto/services/api/upload_service.dart';
import 'package:nonto/utils/picker_error_utils.dart';
import 'package:nonto/widgets/mention_topic_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress_ohos/video_compress_ohos.dart';
import 'package:video_thumbnail_ohos/video_thumbnail_ohos.dart';

/// Nonto 创作页：文本、图片、视频、话题与草稿的一体化发布入口。
class CreatePostScreen extends ConsumerStatefulWidget {
  final int? communityId;
  final String? communityName;

  const CreatePostScreen({super.key, this.communityId, this.communityName});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  // 多图支持
  final List<XFile> _selectedImages = [];
  final List<Uint8List> _imageBytesList = [];

  // 视频支持（单视频，与图片互斥）
  XFile? _selectedVideo;
  Uint8List? _videoBytes;
  Uint8List? _thumbnailBytes; // 视频首帧封面
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;

  // 长按删除
  bool _showDeleteButtons = false;

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

  Color get _accentColor => AppColors.primary;
  Color get _primaryTextColor => AppColors.textPrimary;
  Color get _secondaryTextColor => AppColors.textSecondary;

  bool get _hasComposerContent =>
      _controller.text.trim().isNotEmpty ||
      _selectedImages.isNotEmpty ||
      _selectedVideo != null;

  bool get _isOverCharacterLimit => _charCount > _maxChars;

  bool get _canSubmitPost =>
      _hasComposerContent && !_isSubmitting && !_isOverCharacterLimit;

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
    _videoController?.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 恢复草稿（文本 + 图片路径）
  /// Web 平台：blob URL 无法通过 dart:io File 读取，仅恢复文本草稿
  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
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
        if (!mounted) return;
        if (restoredImages.isNotEmpty) {
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
        maxWidth: 1920,
        imageQuality: 92,
      );
      if (picked.isEmpty) return;

      final bytesList = <Uint8List>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        bytesList.add(bytes);
      }
      if (!mounted) return;

      setState(() {
        // 重置视频
        _selectedVideo = null;
        _videoBytes = null;
        // 追加图片（不覆盖已有选择，用户可多次选图累计到上限）
        final remaining = _maxImages - _selectedImages.length;
        final toAdd =
            picked.length > remaining ? picked.sublist(0, remaining) : picked;
        _selectedImages.addAll(toAdd);
        _imageBytesList.addAll(bytesList.take(toAdd.length));
      });
    } catch (e) {
      debugPrint('Pick images error: $e');
      if (mounted) showPickerErrorSnackBar(context, e, target: '相册');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        // 压缩视频（Web 兜底跳过）
        XFile videoFile = picked;
        try {
          if (!kIsWeb) {
            final compressedPath = await compressVideo(
              inputPath: picked.path,
              quality: 'high',
              deleteOrigin: false,
            );
            if (compressedPath != null && compressedPath.isNotEmpty) {
              videoFile = XFile(compressedPath);
              debugPrint('Video compressed: ${picked.path} → $compressedPath');
            }
          }
        } catch (e) {
          debugPrint('Video compression failed, using original: $e');
        }

        final bytes = await videoFile.readAsBytes();
        // 提取首帧作为封面缩略图（320×320 JPEG 75%）
        Uint8List? thumbnail;
        try {
          thumbnail = await extractThumbnail(
            videoPath: videoFile.path,
            maxWidth: 320,
            maxHeight: 320,
            quality: 75,
            positionMs: 500, // 取 0.5s 帧，跳过黑屏片头
          );
        } catch (e) {
          debugPrint('Thumbnail extraction failed: $e');
        }
        if (!mounted) return;
        setState(() {
          _selectedVideo = videoFile;
          _videoBytes = bytes;
          _thumbnailBytes = thumbnail;
          _selectedImages.clear();
          _imageBytesList.clear();
        });
      }
    } catch (e) {
      debugPrint('Pick video error: $e');
      if (mounted) showPickerErrorSnackBar(context, e, target: '视频');
    }
  }

  void _removeImageAt(int index) {
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
      _thumbnailBytes = null;
      _videoController?.dispose();
      _videoController = null;
      _isVideoPlaying = false;
    });
  }

  Future<void> _submitPost() async {
    final content = _controller.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty && _selectedVideo == null) {
      setState(() => _error = '帖子内容或媒体不能为空');
      return;
    }

    final auth = ref.read(authProvider);
    final currentUser = auth.user;
    if (currentUser == null) {
      setState(() => _error = '请先登录');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0;
      _uploadedCount = 0;
      _totalUploadCount =
          _selectedImages.length + (_selectedVideo != null ? 1 : 0);
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

      // 2. 上传视频 + 缩略图
      String? thumbnailUrl;
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

        // 上传视频封面缩略图
        if (_thumbnailBytes != null && _thumbnailBytes!.isNotEmpty) {
          try {
            final thumbResp = await ApiClient().uploadBytes(
              '/upload/post/image',
              _thumbnailBytes!,
              'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            if (thumbResp.success) {
              thumbnailUrl = _extractUrl(thumbResp.data);
            }
          } catch (e) {
            debugPrint('Thumbnail upload failed: $e');
            // 缩略图上传失败不阻塞发帖
          }
        }
      }

      // 3. 创建帖子
      final resp = await PostService().createPost(
        content: content,
        imageUrls: imageUrls.isNotEmpty ? imageUrls : null,
        videoPath: videoUrl,
        thumbnailUrl: thumbnailUrl,
        communityId: widget.communityId,
      );

      if (resp.success) {
        Post? serverPost;
        if (resp.data != null) {
          final postData =
              resp.data is Map ? resp.data as Map<String, dynamic> : null;
          if (postData != null) {
            if (postData.containsKey('post')) {
              serverPost =
                  Post.fromJson(postData['post'] as Map<String, dynamic>);
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
              thumbnailUrl: thumbnailUrl,
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
        // 通知个人主页刷新：发帖后切到个人主页能立即看到新帖，无需手动下拉。
        ProfileTab.newPostNotifier.value = true;
        await _clearDraft();
        if (!mounted) return;
        Navigator.of(context).pop(true);
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

  // ========== 可拖拽图片条（水平拖动排序 + 删除模式切换） ==========

  Widget _buildImageList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 删除模式提示条
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showDeleteButtons
              ? Container(
                  width: double.infinity,
                  height: 36,
                  margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      const SizedBox(width: 6),
                      const Text('点击图片上的 × 删除',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _showDeleteButtons = false),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('完成',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(height: 4),
        ),
        SizedBox(
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
                    child: child!,
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
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _imageBytesList[index],
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                        ),
                      ),
                      // 删除模式下显示 X 按钮
                      if (_showDeleteButtons)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImageAt(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(14)),
                              ),
                              child: const Icon(Icons.close,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      // 序号角标
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${index + 1}/${_selectedImages.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // 普通模式下底部提示
        if (!_showDeleteButtons)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
            child: GestureDetector(
              onTap: () => setState(() => _showDeleteButtons = true),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline,
                      size: 14,
                      color: AppColors.textSecondary.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Text(
                    '长按拖动排序 / 点击进入删除模式',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),
      ],
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
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EmojiPickerPanel(
        onEmojiSelected: (emoji) {
          final text = _controller.text;
          final pos = _controller.selection.baseOffset;
          if (pos < 0) {
            _controller.text = '$text$emoji';
            _controller.selection =
                TextSelection.collapsed(offset: _controller.text.length);
          } else {
            _controller.text =
                '${text.substring(0, pos)}$emoji${text.substring(pos)}';
            _controller.selection =
                TextSelection.collapsed(offset: pos + emoji.length);
          }
          _focusNode.requestFocus();
        },
      ),
    );
  }

  // ========== 话题选择器 ==========

  void _showTopicPicker() {
    // 先取消焦点，让键盘收起
    _focusNode.unfocus();
    // 记录当前光标位置
    final cursorPos = _controller.selection.baseOffset;
    final textBefore = _controller.text;

    MentionTopicPicker.showTopics(
      context,
      onSelected: (topicName) {
        final text = _controller.text;
        final pos = _controller.selection.baseOffset;
        if (pos < 0) {
          _controller.text = '$text#$topicName ';
          _controller.selection =
              TextSelection.collapsed(offset: _controller.text.length);
        } else {
          _controller.text =
              '${text.substring(0, pos)}#$topicName ${text.substring(pos)}';
          _controller.selection =
              TextSelection.collapsed(offset: pos + '#$topicName '.length);
        }
        _focusNode.requestFocus();
      },
      onCancel: (searchText) {
        // 取消弹窗时，将输入框内容插入到帖子中
        if (searchText.isNotEmpty) {
          _controller.text =
              '${textBefore.substring(0, cursorPos < 0 ? textBefore.length : cursorPos)}#${searchText.trim()}${cursorPos < 0 ? '' : textBefore.substring(cursorPos)}';
          _controller.selection = TextSelection.collapsed(
            offset: (cursorPos < 0 ? textBefore.length : cursorPos) +
                '#${searchText.trim()}'.length,
          );
        }
        _focusNode.requestFocus();
      },
    );
  }

  // ========== @用户选择器 ==========

  void _showMentionPicker() {
    _focusNode.unfocus();

    MentionTopicPicker.showMentions(
      context,
      onSelected: (username) {
        final text = _controller.text;
        final pos = _controller.selection.baseOffset;
        if (pos < 0) {
          _controller.text = '$text@$username ';
          _controller.selection =
              TextSelection.collapsed(offset: _controller.text.length);
        } else {
          _controller.text =
              '${text.substring(0, pos)}@$username ${text.substring(pos)}';
          _controller.selection =
              TextSelection.collapsed(offset: pos + '@$username '.length);
        }
        _focusNode.requestFocus();
      },
    );
    // @用户取消弹窗时不做任何插入
  }

  // ========== 视频预览 ==========

  Widget _buildVideoPreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GestureDetector(
              onTap: _toggleVideoPlayback,
              onLongPress: _showDeleteWithTimer,
              child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _isVideoPlaying && _videoController != null
                    ? VideoPlayer(_videoController!)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          // 封面缩略图
                          if (_thumbnailBytes != null)
                            Image.memory(_thumbnailBytes!, fit: BoxFit.cover)
                          else
                            const Icon(Icons.videocam,
                                size: 40, color: Colors.white24),
                          // 播放按钮
                          Center(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow,
                                  size: 36, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          // 删除按钮（长按后显示，3秒后消失）
          if (_showDeleteButtons)
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

  void _toggleVideoPlayback() async {
    if (_videoController == null && _selectedVideo != null) {
      try {
        _videoController = VideoPlayerController.file(
          File(_selectedVideo!.path),
        );
        await _videoController!.initialize();
        if (!mounted) return;
        _videoController!.play();
        _videoController!.addListener(() {
          if (mounted &&
              _videoController!.value.position >=
                  _videoController!.value.duration) {
            setState(() => _isVideoPlaying = false);
            _videoController?.dispose();
            _videoController = null;
          }
        });
        setState(() => _isVideoPlaying = true);
      } catch (_) {}
      return;
    }
    if (_videoController != null) {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        setState(() => _isVideoPlaying = false);
      } else {
        _videoController!.play();
        setState(() => _isVideoPlaying = true);
      }
    }
  }

  void _showDeleteWithTimer() {
    setState(() => _showDeleteButtons = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showDeleteButtons = false);
    });
  }

  Widget _buildSubmitButton() {
    return TextButton(
      onPressed: _canSubmitPost ? _submitPost : null,
      style: TextButton.styleFrom(
        backgroundColor:
            _canSubmitPost ? _accentColor : AppColors.backgroundSecondary,
        foregroundColor: Colors.white,
        disabledForegroundColor: AppColors.textTertiary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        disabledBackgroundColor: AppColors.backgroundSecondary,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: _isSubmitting
            ? const SizedBox(
                key: ValueKey('submitting'),
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                '发布',
                key: ValueKey('publish'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildComposerToolbar({required bool isOverLimit}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
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
              onTap: _showMentionPicker,
            ),
            const SizedBox(width: 4),
            _ToolbarButton(
              icon: Icons.tag,
              label: '#话题',
              onTap: _showTopicPicker,
            ),
            const SizedBox(width: 4),
            _ToolbarButton(
              icon: Icons.emoji_emotions_outlined,
              label: '表情',
              onTap: _showEmojiPicker,
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_charCount/$_maxChars',
                style: TextStyle(
                  color: isOverLimit ? Colors.red : _secondaryTextColor,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close, color: _primaryTextColor, size: 24),
          onPressed: () {
            _saveDraft();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildSubmitButton(),
          ),
        ],
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
                                color: _primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${user?.username ?? ''}',
                              style: TextStyle(
                                  color: _secondaryTextColor, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.communityName != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.groups_3_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '发布到 ${widget.communityName}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Text field
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    maxLines: null,
                    maxLength: _maxChars,
                    style: TextStyle(
                        fontSize: 18, height: 1.4, color: _primaryTextColor),
                    decoration: InputDecoration(
                      hintText: '有什么新鲜事？',
                      hintStyle:
                          TextStyle(color: _secondaryTextColor, fontSize: 18),
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
                      valueColor: AlwaysStoppedAnimation(_accentColor),
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
                      style:
                          TextStyle(color: _secondaryTextColor, fontSize: 12),
                    ),
                  ],
                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
          // Bottom toolbar — horizontally scrollable
          _buildComposerToolbar(isOverLimit: _isOverCharacterLimit),
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
      backgroundColor: _accentColor,
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
                size: 20, color: enabled ? AppColors.primary : Colors.grey),
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

class _EmojiPickerPanel extends StatefulWidget {
  final void Function(String emoji) onEmojiSelected;

  const _EmojiPickerPanel({required this.onEmojiSelected});

  @override
  State<_EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<_EmojiPickerPanel> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final categories = EmojiData.categories;
    final emojis = categories[_tabIndex].value;
    return SafeArea(
      child: Container(
        height: 320,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Category tabs
            SizedBox(
              height: 44,
              child: Row(
                children: List.generate(categories.length, (i) {
                  final isSelected = i == _tabIndex;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tabIndex = i),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(categories[i].key,
                            style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Divider(height: 1, color: AppColors.borderLight),
            // Emoji grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, index) => InkWell(
                  onTap: () {
                    widget.onEmojiSelected(emojis[index]);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Center(
                    child: Text(emojis[index],
                        style: const TextStyle(fontSize: 22)),
                  ),
                ),
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
