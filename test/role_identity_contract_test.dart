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

    test('User ignores legacy role labels when verified identity fields are absent', () {
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

    test('PostService createPost sends identity form fields', () {
      final source = File('lib/services/api/post_service.dart').readAsStringSync();

      expect(source, contains('String? contentCategory'));
      expect(source, contains('String? displayRoleType'));
      expect(source, contains("'content_category': contentCategory"));
      expect(source, contains("'display_role_type': displayRoleType"));
    });

    test('CreatePostScreen exposes hide-identity option and sends selected identity', () {
      final source = File('lib/screens/post/create_post_screen.dart').readAsStringSync();

      expect(source, contains("_selectedDisplayRoleType"));
      expect(source, contains('不展示身份'));
      expect(source, contains("_hideIdentityValue"));
      expect(source, isNot(contains('value: null,\n              child: Text(\'不展示身份\')')));
      expect(source, contains('displayRoleType: _selectedDisplayRoleType'));
      expect(source, contains('contentCategory: _selectedContentCategory'));
      expect(source, contains('serverPost?.displayRoleLabel == null'));
    });

    test('Identity application screen is routable from settings', () {
      final routeSource = File('lib/routes/app_routes.dart').readAsStringSync();
      final generatorSource = File('lib/routes/route_generator.dart').readAsStringSync();
      final settingsSource = File('lib/screens/profile/settings_screen.dart').readAsStringSync();
      final screenFile = File('lib/screens/profile/identity_application_screen.dart');

      expect(routeSource, contains('identityApplication'));
      expect(generatorSource, contains('IdentityApplicationScreen'));
      expect(settingsSource, contains('身份认证'));
      expect(settingsSource, contains('AppRoutes.identityApplication'));
      expect(screenFile.existsSync(), isTrue);
    });

    test('PostCard renders reusable identity badge for post display role', () {
      final badgeFile = File('lib/widgets/identity_badge.dart');
      expect(badgeFile.existsSync(), isTrue);

      final cardSource = File('lib/widgets/post_card.dart').readAsStringSync();
      expect(cardSource, contains("identity_badge.dart"));
      expect(cardSource, contains('IdentityBadge(label: post.displayRoleLabel'));
    });
  });
}
