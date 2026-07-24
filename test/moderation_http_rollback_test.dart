import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/api_client.dart';

String _read(String path) => File(path).readAsStringSync();

ApiResponse rejected() => const ApiResponse(
      success: false,
      statusCode: 422,
      errorCode: ApiErrorCodes.contentRejected,
      message: '内容未通过审核',
      isRetryable: false,
    );

ApiResponse unavailable() => const ApiResponse(
      success: false,
      statusCode: 503,
      errorCode: ApiErrorCodes.moderationUnavailable,
      message: '内容审核服务暂不可用，请稍后重试',
      isRetryable: true,
    );

void main() {
  test('apiFailureMessage uses locked moderation copy', () {
    expect(
      apiFailureMessage(
        const ApiResponse(
          success: false,
          errorCode: ApiErrorCodes.contentRejected,
          message: 'regex threshold hit term: badword',
        ),
        fallback: 'fallback',
      ),
      '内容未通过审核',
    );
    expect(
      apiFailureMessage(
        const ApiResponse(
          success: false,
          errorCode: ApiErrorCodes.moderationUnavailable,
          message: 'regex threshold service unavailable',
        ),
        fallback: 'fallback',
      ),
      '内容审核服务暂不可用，请稍后重试',
    );
    expect(
      apiFailureMessage(
        const ApiResponse(success: false, message: 'server message'),
        fallback: 'fallback',
      ),
      'server message',
    );
  });

  test('comment optimistic mutations roll back targeted state on failure', () {
    final source = _read('lib/providers/comment_notifier.dart');
    expect(source, contains('if (!resp.success)'));
    expect(source, contains('void _removeOptimisticComment('));
    expect(source, contains('_removeOptimisticComment(optimisticComment.id'));
    expect(source, contains('void _rollbackLikeMutation('));
    expect(source, contains('likeDelta: likeDelta'));
    expect(source, contains('void _removeDeletedComment(int commentId)'));
    expect(source, contains('_removeDeletedComment(commentId);'));
    final commentSection = _read('lib/widgets/comment_section.dart');
    expect(commentSection, contains('comment.id.toString()'));
    final submitBody = source.substring(
      source.indexOf('Future<String?> submitComment(String content)'),
      source.indexOf('Future<void> toggleLike(int commentId)'),
    );
    expect(submitBody, isNot(contains('final oldState = state;')));
    expect(submitBody, isNot(contains('state = oldState.copyWith')));
    final toggleLikeBody = source.substring(
      source.indexOf('Future<void> toggleLike(int commentId)'),
      source.indexOf('Future<bool> deleteComment(int commentId)'),
    );
    expect(toggleLikeBody, isNot(contains('state = oldState.copyWith')));
    expect(source, contains("apiFailureMessage(resp, fallback: '评论发送失败')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '操作失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '删除失败，请重试')"));
    expect(source, isNot(contains("'评论发送失败: \$")));
  });

  test(
      'community HTTP chat marks optimistic messages failed on structured failure',
      () {
    final source = _read('lib/screens/community/community_chat_screen.dart');
    expect(source, contains('if (!resp.success)'));
    expect(source, contains("apiFailureMessage(resp, fallback: '发送失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '重试失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '撤回失败，请重试')"));
    expect(source, contains("_markOptimisticFailed(optimistic['id'])"));
    expect(source, isNot(contains('发送失败: \$')));
    expect(source, isNot(contains('重试失败: \$')));
    expect(source, isNot(contains('撤回失败: \$')));
  });

  test('post share sheet keeps dialog open and shows safe structured failures',
      () {
    final source = _read('lib/widgets/post_share_to_chat_sheet.dart');
    expect(source, contains('response is ApiResponse'));
    expect(
        source, contains("apiFailureMessage(response, fallback: '发送失败，请重试')"));
    expect(source, contains('if (success) {'));
    expect(source, contains('Navigator.of(context).pop();'));
  });

  test('feed optimistic like rolls back targeted post on structured failure',
      () {
    final source = _read('lib/providers/feed_notifier.dart');
    expect(source,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(source, contains('if (!resp.success)'));
    expect(source, contains('void _rollbackLikeMutation('));
    expect(source, contains('expectedLiked: !wasLiked'));
    expect(source, contains('likeDelta: likeDelta'));
    final toggleLikeBody = source.substring(
      source.indexOf('Future<void> toggleLike(int postId)'),
      source.indexOf('/// Update a single post'),
    );
    expect(toggleLikeBody, isNot(contains('rollbackPosts[idx] = post')));
    expect(toggleLikeBody,
        contains("apiFailureMessage(resp, fallback: '操作失败，请重试')"));
    expect(toggleLikeBody, contains("error: '操作失败，请重试'"));
  });

  test('post detail optimistic post mutations check structured responses', () {
    final source = _read('lib/screens/post/post_detail_screen.dart');
    expect(source,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(source, contains('final resp = wasLiked'));
    expect(source, contains('if (!resp.success)'));
    expect(source, contains('void apply(bool isLiked, int delta'));
    expect(source, contains('onlyIfLiked: !wasLiked'));
    expect(source, isNot(contains('setState(() => _post = oldPost)')));
    expect(source, contains("apiFailureMessage(resp, fallback: '操作失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '删除失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '举报失败，请重试')"));
    expect(source, isNot(contains('操作失败: \$e')));
  });

  test('community screens gate success UI on ApiResponse.success', () {
    final detail = _read('lib/screens/community/community_detail_screen.dart');
    expect(detail,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(detail, contains('if (!resp.success)'));
    expect(detail, contains('final Set<int> _likingPostIds = {}'));
    expect(detail, contains('bool _isMembershipChanging = false'));
    expect(
        detail, contains('_isMembershipChanging ? null : () => _handleJoin'));
    expect(
        detail, contains('_isMembershipChanging ? null : () => _handleLeave'));
    expect(detail, contains('applyPostLikeDelta'));
    expect(detail, contains("apiFailureMessage(resp, fallback: '操作失败，请重试')"));
    expect(detail, contains("apiFailureMessage(resp, fallback: '解散失败，请重试')"));
    expect(detail, isNot(contains('originalCount')));
    expect(detail, isNot(contains('操作失败: \$e')));
    expect(detail, isNot(contains('解散失败: \$e')));

    final notifier = _read('lib/providers/community_notifier.dart');
    expect(notifier, contains('void applyPostLikeDelta('));
    expect(notifier, isNot(contains('error: e.toString()')));

    final create = _read('lib/screens/community/community_create_screen.dart');
    expect(create,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(create, contains('if (!resp.success)'));
    expect(create, contains("apiFailureMessage(resp, fallback: '创建失败，请重试')"));
    expect(create, isNot(contains('创建失败: \$e')));

    final manage = _read('lib/screens/community/community_manage_screen.dart');
    expect(manage,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(manage, contains('if (!resp.success)'));
    expect(manage, contains('final Set<int> _reviewingRequestIds = {}'));
    expect(manage, contains('onPressed: isReviewing ? null'));
    expect(manage, contains("String fallback = '操作失败，请重试'"));
    expect(manage, contains('apiFailureMessage(resp, fallback: fallback)'));
    expect(manage, contains("apiFailureMessage(resp, fallback: '发布失败，请重试')"));
    expect(manage, contains("fallback: '删除失败，请重试'"));
    expect(manage, contains("apiFailureMessage(resp, fallback: '拉黑失败，请重试')"));
    expect(manage, contains("fallback: '解封失败，请重试'"));
    expect(manage, isNot(contains('发布失败: \$e')));
    expect(manage, isNot(contains('删除失败: \$e')));
    expect(manage, isNot(contains('拉黑失败: \$e')));
    expect(manage, isNot(contains('解封失败: \$e')));
  });

  test('profile and search optimistic post/friend mutations roll back safely',
      () {
    for (final path in [
      'lib/screens/profile/user_profile_screen.dart',
      'lib/screens/profile/profile_tab.dart',
      'lib/screens/search/search_results_screen.dart',
      'lib/screens/search/search_tab.dart',
      'lib/widgets/enhanced_media_viewer.dart',
    ]) {
      final source = _read(path);
      expect(source,
          contains("import 'package:nonto/services/api/api_client.dart';"),
          reason: path);
      expect(source, contains('if (!resp.success)'), reason: path);
      expect(source, contains("apiFailureMessage(resp, fallback: '操作失败，请重试')"),
          reason: path);
      expect(source, isNot(contains('操作失败: \$e')), reason: path);
      expect(source, isNot(contains('postList[index] =')), reason: path);
      expect(source, isNot(contains('_posts[index] =')), reason: path);
      expect(source,
          isNot(contains('setState(() => _postStates[post.id] = oldPost')),
          reason: path);
    }

    final searchResults =
        _read('lib/screens/search/search_results_screen.dart');
    expect(searchResults, contains('final Set<int> _likingPostIds = {}'));
    expect(searchResults, isNot(contains('resp.message ??')));
    expect(searchResults, isNot(contains('e.toString()')));

    final searchTab = _read('lib/screens/search/search_tab.dart');
    expect(searchTab, contains('final Set<int> _likingPostIds = {}'));
    expect(searchTab, isNot(contains('resp.message ??')));
    expect(searchTab, isNot(contains('globalSearch exception for query')));

    final userProfile = _read('lib/screens/profile/user_profile_screen.dart');
    expect(userProfile, contains('final Set<int> _likingPostIds = {}'));

    final profileTab = _read('lib/screens/profile/profile_tab.dart');
    expect(profileTab, contains('final Set<int> _likingPostIds = {}'));
    expect(profileTab, contains('void _applyPostLikeDelta('));
    expect(profileTab, isNot(contains('originalCount')));
  });

  test('auth failures use safe structured user-facing messages', () {
    final source = _read('lib/providers/auth_notifier.dart');
    expect(source, contains("apiFailureMessage(resp, fallback: '登录失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '注册失败，请重试')"));
    expect(source, contains("apiFailureMessage(resp, fallback: '资料更新失败，请重试')"));
    expect(source, contains('state = state.copyWith(error: message);'));
    expect(source, contains('if (!resp.success)'));
    expect(source, isNot(contains("error: resp.message ?? 'Login failed'")));
    expect(source,
        isNot(contains("error: resp.message ?? 'Registration failed'")));
  });

  test('task 14 reviewed mutation paths use safe structured failures', () {
    final communityChat =
        _read('lib/screens/community/community_chat_screen.dart');
    expect(communityChat,
        contains("apiFailureMessage(resp, fallback: '发送媒体失败，请重试')"));
    expect(communityChat, contains("_markOptimisticFailed(optimistic['id'])"));
    expect(communityChat, isNot(contains('发送媒体失败: \$')));
    expect(communityChat, isNot(contains('成员加载失败: \$')));
    expect(communityChat, isNot(contains('在线成员加载失败: \$')));

    final createPost = _read('lib/screens/post/create_post_screen.dart');
    expect(createPost,
        contains("apiFailureMessage(uploadResp, fallback: '图片上传失败，请重试')"));
    expect(createPost,
        contains("apiFailureMessage(uploadResp, fallback: '视频上传失败，请重试')"));
    expect(
        createPost, contains("apiFailureMessage(resp, fallback: '发布失败，请重试')"));
    expect(
        createPost, contains("apiFailureMessage(resp, fallback: '保存失败，请重试')"));
    expect(createPost, isNot(contains('uploadResp.message')));
    expect(createPost, isNot(contains('resp.message ??')));

    final editProfile = _read('lib/screens/profile/edit_profile_screen.dart');
    expect(editProfile,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(editProfile,
        contains("apiFailureMessage(resp, fallback: '头像上传失败，请重试')"));
    expect(editProfile,
        contains("apiFailureMessage(resp, fallback: '背景图上传失败，请重试')"));
    expect(editProfile,
        contains("apiFailureMessage(resp, fallback: '名称更新失败，请重试')"));
    expect(editProfile,
        contains("apiFailureMessage(resp, fallback: '简介更新失败，请重试')"));
    expect(editProfile, isNot(contains('更新失败: \$e')));
    expect(editProfile, isNot(contains('保存失败: \$e')));

    final identityApplication =
        _read('lib/screens/profile/identity_application_screen.dart');
    expect(identityApplication,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(identityApplication,
        contains("apiFailureMessage(resp, fallback: '身份列表加载失败')"));
    expect(identityApplication,
        contains("apiFailureMessage(resp, fallback: '证明图片上传失败')"));
    expect(identityApplication,
        contains("apiFailureMessage(resp, fallback: '提交失败')"));
    expect(identityApplication,
        contains('} on _ProofImageUploadException catch (e) {'));
    expect(identityApplication, contains('_error = e.message;'));
    expect(identityApplication, isNot(contains('resp.message ??')));

    final postCard = _read('lib/widgets/post_card.dart');
    expect(postCard,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(postCard, contains("apiFailureMessage(resp, fallback: '举报失败，请重试')"));
    expect(postCard, contains("apiFailureMessage(resp, fallback: '删除失败，请重试')"));
    expect(postCard, isNot(contains('resp.message ??')));

    final friendRequests =
        _read('lib/screens/friends/friend_requests_screen.dart');
    expect(friendRequests,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(friendRequests,
        contains("apiFailureMessage(resp, fallback: '操作失败，请重试')"));
    expect(friendRequests, isNot(contains("resp.message ?? '操作失败，请重试'")));

    final addFriend = _read('lib/widgets/add_friend_button.dart');
    expect(addFriend,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(
        addFriend, contains("apiFailureMessage(resp, fallback: '发送失败，请重试')"));
    expect(addFriend, isNot(contains('resp.message ??')));
  });

  test(
      'apiFailureMessage suppresses unsafe moderation internals without losing normal copy',
      () {
    expect(
      apiFailureMessage(
        const ApiResponse(success: false, message: 'server message'),
        fallback: 'fallback',
      ),
      'server message',
    );
    expect(
      apiFailureMessage(
        const ApiResponse(success: false, message: '内容命中敏感词 badword'),
        fallback: 'fallback',
      ),
      'fallback',
    );
    expect(
      apiFailureMessage(
        const ApiResponse(
            success: false, message: 'regex matched word badword'),
        fallback: 'fallback',
      ),
      'fallback',
    );
    expect(
      apiFailureMessage(
        const ApiResponse(
            success: false, message: 'score exceeded threshold 0.9'),
        fallback: 'fallback',
      ),
      'fallback',
    );
  });

  test('upload wrappers preserve structured failure metadata', () {
    final apiClient = _read('lib/services/api/api_client.dart');
    expect(apiClient, contains('errorCode: result.errorCode'));
    expect(apiClient, contains('isRetryable: result.isRetryable'));
    expect(apiClient, contains('errorCode: presignResp.errorCode'));
    expect(apiClient, contains('statusCode: presignResp.statusCode'));
    expect(apiClient, contains('isRetryable: presignResp.isRetryable'));

    final uploadService = _read('lib/services/api/upload_service.dart');
    expect(uploadService, contains('errorCode: resp.errorCode'));
    expect(uploadService, contains('statusCode: resp.statusCode'));
    expect(uploadService, contains('isRetryable: resp.isRetryable'));
  });

  test('edit profile rolls back text against current user before mounted guard',
      () {
    final source = _read('lib/screens/profile/edit_profile_screen.dart');
    expect(source, contains('final current = ref.read(authProvider).user;'));
    expect(source, isNot(contains('final json = user.toJson()')));
    final nameRollback =
        source.indexOf('_rollbackName(user.id, originalName);');
    final bioRollback = source.indexOf('_rollbackBio(user.id, originalBio);');
    final mountedGuard = source.indexOf('if (!mounted) return;', nameRollback);
    expect(nameRollback, isNonNegative);
    expect(bioRollback, isNonNegative);
    expect(mountedGuard, isNonNegative);
    expect(nameRollback, lessThan(mountedGuard));
    expect(bioRollback,
        lessThan(source.indexOf('if (!mounted) return;', bioRollback)));
  });

  test('comic service failure wrappers preserve structured metadata', () {
    final source = _read('lib/services/comic_service.dart');
    expect(source, contains('ApiResponse<R> _wrapFailure<R>'));
    expect(source, contains('apiFailureMessage(resp, fallback: fallback)'));
    expect(source, contains('statusCode: resp.statusCode'));
    expect(source, contains('errorCode: resp.errorCode'));
    expect(source, contains('isRetryable: resp.isRetryable'));
    expect(source, isNot(contains('resp.message ??')));
    expect(source, contains("return _wrapFailure(resp, '操作失败');"));
    expect(source, contains("return _wrapFailure(resp, '评论发送失败')"));
    expect(source, contains("return _wrapFailure(resp, '操作失败')"));
    expect(source, contains("return _wrapFailure(resp, '删除失败')"));
  });

  test('comic upload aborts safely on upload and submit failures', () {
    final source = _read('lib/screens/comic/comic_upload_page.dart');
    expect(source,
        contains("import 'package:nonto/services/api/api_client.dart';"));
    expect(source, contains("apiFailureMessage(resp, fallback: '提交失败，请重试')"));
    expect(source, contains('Future<List<String>?> _uploadImages()'));
    expect(source, contains("ApiClient().upload<Map<String, dynamic>>"));
    expect(source, isNot(contains('dio.put')));
    expect(source, contains('return null;'));
    expect(source, contains('if (uploadedImageUrls == null) return;'));
    expect(source, isNot(contains(r'上传失败: $')));
    expect(source, isNot(contains(r'提交失败: $')));
    expect(source, isNot(contains('resp.message ??')));
  });
}
