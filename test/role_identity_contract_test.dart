import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/post.dart';
import 'package:nonto/models/user.dart';

void main() {
  group('role identity contracts', () {
    test('User parses and serializes verified business identities only', () {
      final user = User.fromJson({
        'id': 1,
        'username': 'alice',
        'email': 'alice@example.com',
        'verified_roles': ['coser', 'photographer'],
        'verified_role_labels': ['Coser', '摄影师'],
      });

      final payload = user.toJson();
      expect(payload['verified_roles'], ['coser', 'photographer']);
      expect(payload['verified_role_labels'], ['Coser', '摄影师']);
      expect(payload['role_labels'], isNot(contains('普通用户')));
    });

    test(
        'User ignores legacy role labels when verified identity fields are absent',
        () {
      final user = User.fromJson({
        'id': 2,
        'username': 'bob',
        'email': 'bob@example.com',
        'roles': ['normal_user'],
        'role_labels': ['普通用户'],
      });

      expect(user.verifiedRoles, isEmpty);
      expect(user.verifiedRoleLabels, isEmpty);
      expect(user.toJson()['verified_role_labels'], isEmpty);
    });

    test('User drops labels that do not have matching verified roles', () {
      final user = User.fromJson({
        'id': 3,
        'username': 'carol',
        'email': 'carol@example.com',
        'verified_roles': [],
        'verified_role_labels': ['普通用户'],
      });

      expect(user.verifiedRoles, isEmpty);
      expect(user.verifiedRoleLabels, isEmpty);
    });

    test('Post parses one optional display identity and content category', () {
      final post = Post.fromJson({
        'id': 9,
        'content': '作品',
        'user_id': 1,
        'content_category': 'cosplay',
        'display_role_type': 'coser',
        'display_role_label': 'Coser',
      });

      final payload = post.toJson();
      expect(payload['content_category'], 'cosplay');
      expect(payload['display_role_type'], 'coser');
      expect(payload['display_role_label'], 'Coser');
    });

    test('PostService createPost sends identity but no content category', () {
      final source =
          File('lib/services/api/post_service.dart').readAsStringSync();

      expect(source, contains('String? displayRoleType'));
      expect(source, contains("'display_role_type': displayRoleType"));
      expect(source, isNot(contains('contentCategory')));
      expect(source, isNot(contains('content_category')));
    });

    test(
        'CreatePostScreen exposes hide-identity option and sends selected identity',
        () {
      final source =
          File('lib/screens/post/create_post_screen.dart').readAsStringSync();

      expect(source, contains('_selectedDisplayRoleType'));
      expect(source, contains('不展示身份'));
      expect(source, contains('_hideIdentityValue'));
      expect(
        source,
        isNot(contains("value: null,\n              child: Text('不展示身份')")),
      );
      expect(source, contains('displayRoleType: _selectedDisplayRoleType'));
      expect(source, isNot(contains('contentCategory')));
      expect(source, contains('serverPost?.displayRoleLabel == null'));
    });

    test(
        'Identity center is routable from settings while application remains available',
        () {
      final routeSource = File('lib/routes/app_routes.dart').readAsStringSync();
      final generatorSource =
          File('lib/routes/route_generator.dart').readAsStringSync();
      final settingsSource =
          File('lib/screens/profile/settings_screen.dart').readAsStringSync();
      final centerFile =
          File('lib/screens/profile/identity_center_screen.dart');
      final screenFile =
          File('lib/screens/profile/identity_application_screen.dart');

      expect(routeSource, contains('identityCenter'));
      expect(routeSource, contains('identityApplication'));
      expect(generatorSource, contains('IdentityCenterScreen'));
      expect(generatorSource, contains('IdentityApplicationScreen'));
      expect(settingsSource, contains('我的身份'));
      expect(settingsSource, contains('AppRoutes.identityCenter'));
      expect(centerFile.existsSync(), isTrue);
      expect(screenFile.existsSync(), isTrue);
    });

    test(
        'PostCard and detail render reusable identity badge for post display role',
        () {
      final badgeFile = File('lib/widgets/identity_badge.dart');
      expect(badgeFile.existsSync(), isTrue);

      final cardSource = File('lib/widgets/post_card.dart').readAsStringSync();
      final detailSource =
          File('lib/screens/post/post_detail_screen.dart').readAsStringSync();
      final authorMetaSource =
          File('lib/widgets/post_author_meta_line.dart').readAsStringSync();
      expect(cardSource, contains("post_author_meta_line.dart"));
      expect(detailSource, contains("post_author_meta_line.dart"));
      expect(authorMetaSource, contains("identity_badge.dart"));
      expect(cardSource, contains('PostAuthorMetaLine('));
      expect(detailSource, contains('PostAuthorMetaLine('));
      expect(authorMetaSource,
          contains('IdentityBadge(label: post.displayRoleLabel'));
    });

    test('comments and profile use compact identity pills', () {
      final badgeSource =
          File('lib/widgets/identity_badge.dart').readAsStringSync();
      final commentsSource =
          File('lib/widgets/comment_section.dart').readAsStringSync();
      final profileSource =
          File('lib/widgets/profile_identity_section.dart').readAsStringSync();

      expect(badgeSource, contains('borderRadius: BorderRadius.circular(999)'));
      expect(commentsSource, contains("identity_badge.dart"));
      expect(commentsSource, contains('user?.verifiedRoleLabels'));
      expect(commentsSource, contains('IdentityBadge(label: identityLabel)'));
      expect(profileSource,
          contains("child: Text(labels.isEmpty ? '申请身份' : '管理')"));
      expect(profileSource, isNot(contains('认证身份会用于主页展示和发帖身份选择')));
      expect(profileSource, isNot(contains('该用户已通过平台身份认证')));
    });
  });
}
