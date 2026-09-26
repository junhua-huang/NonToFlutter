import 'package:flutter/material.dart';
import 'package:nonto/config/app_theme.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/routes/app_routes.dart';
import 'package:nonto/utils/image_utils.dart';

class QuotedPostPreview extends StatelessWidget {
  final Post? quotedPost;
  final int? quotedPostId;
  final bool unavailable;
  final bool compact;

  const QuotedPostPreview({
    super.key,
    this.quotedPost,
    this.quotedPostId,
    this.unavailable = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final id = quotedPost?.id ?? quotedPostId;
    if (id == null) return const SizedBox.shrink();
    final isUnavailable = unavailable || quotedPost == null;

    return GestureDetector(
      onTap: isUnavailable
          ? null
          : () => Navigator.pushNamed(context, AppRoutes.postDetailId('$id')),
      child: Container(
        margin: EdgeInsets.only(top: compact ? 8 : 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: isUnavailable ? _buildUnavailable(id) : _buildQuoted(context),
      ),
    );
  }

  Widget _buildUnavailable(int id) {
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '原帖不可见或已被隐藏',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }

  String? _firstImageUrl(Post post) {
    final urls = post.images;
    if (urls == null) return null;
    for (final url in urls) {
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  Widget _buildQuoted(BuildContext context) {
    final post = quotedPost!;
    final author = post.user?.displayName ?? post.user?.username ?? '未知用户';
    final imageUrl = _firstImageUrl(post);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (post.content != null && post.content!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  post.content!,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ] else if (post.hasVideo) ...[
                const SizedBox(height: 4),
                Text('视频帖子',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ] else if (post.hasImage) ...[
                const SizedBox(height: 4),
                Text('图片帖子',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ],
          ),
        ),
        if (imageUrl != null) ...[
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ImageUtils.buildPostImage(
              imageUrl,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
            ),
          ),
        ] else if (post.hasVideo) ...[
          const SizedBox(width: 10),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.play_arrow, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
