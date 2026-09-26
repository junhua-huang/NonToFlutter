import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/models/identity_application.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('identity center contracts', () {
    test('IdentityApplication parses role status and submitted materials', () {
      final app = IdentityApplication.fromJson({
        'id': 42,
        'role_id': 7,
        'role': {'name': 'coser', 'label': 'Coser'},
        'status': 'pending',
        'application_text': '我长期发布角色作品',
        'proof_images': ['https://example.com/proof.jpg'],
        'portfolio_links': ['https://example.com/work'],
        'contact_info': 'wechat:alice',
        'extra_note': '补充说明',
        'review_comment': '请等待审核',
        'created_at': '2026-07-25T10:00:00',
        'reviewed_at': '2026-07-26T10:00:00',
      });

      expect(app.id, 42);
      expect(app.roleId, 7);
      expect(app.roleName, 'coser');
      expect(app.roleLabel, 'Coser');
      expect(app.status, 'pending');
      expect(app.statusLabel, '审核中');
      expect(app.applicationText, '我长期发布角色作品');
      expect(app.proofImages, ['https://example.com/proof.jpg']);
      expect(app.portfolioLinks, ['https://example.com/work']);
      expect(app.contactInfo, 'wechat:alice');
      expect(app.extraNote, '补充说明');
      expect(app.reviewComment, '请等待审核');
      expect(app.createdAt, isNotNull);
      expect(app.reviewedAt, isNotNull);
    });

    test('IdentityApplication status helpers normalize backend aliases', () {
      expect(IdentityApplication.fromJson({'status': 'pending'}).statusLabel, '审核中');
      expect(IdentityApplication.fromJson({'status': 'verified'}).statusLabel, '已认证');
      expect(IdentityApplication.fromJson({'status': 'approved'}).statusLabel, '已认证');
      expect(IdentityApplication.fromJson({'status': 'rejected'}).statusLabel, '未通过');
      expect(IdentityApplication.fromJson({'status': 'suspended'}).statusLabel, '已暂停');
      expect(IdentityApplication.fromJson({'status': 'needs_more_info'}).statusLabel, '需补充材料');
      expect(IdentityApplication.fromJson({'status': 'verified'}).isVerified, isTrue);
      expect(IdentityApplication.fromJson({'status': 'pending'}).isPending, isTrue);
      expect(IdentityApplication.fromJson({'status': 'rejected'}).isRejected, isTrue);
      expect(IdentityApplication.fromJson({'status': 'suspended'}).isSuspended, isTrue);
      expect(IdentityApplication.fromJson({'status': 'needs_more_info'}).needsMoreInfo, isTrue);
    });

    test('identity center routes and entry points are wired', () {
      final routes = read('lib/routes/app_routes.dart');
      final generator = read('lib/routes/route_generator.dart');
      final settings = read('lib/screens/profile/settings_screen.dart');
      final home = read('lib/screens/home/home_screen.dart');

      expect(routes, contains('identityCenter'));
      expect(routes, contains('identityDetail'));
      expect(generator, contains('IdentityCenterScreen'));
      expect(generator, contains('IdentityDetailScreen'));
      expect(settings, contains('我的身份'));
      expect(settings, contains('AppRoutes.identityCenter'));
      expect(home, contains('我的身份'));
      expect(home, contains('AppRoutes.identityCenter'));
    });

    test('identity center screen surfaces statuses and application actions', () {
      final source = read('lib/screens/profile/identity_center_screen.dart');

      expect(source, contains('RoleService().listRoles()'));
      expect(source, contains('RoleService().listMyApplications'));
      expect(source, contains('让你的作品更可信'));
      expect(source, contains('我的认证'));
      expect(source, contains('可申请身份'));
      expect(source, contains('IdentityStatusCard'));
      expect(source, contains('IdentityRoleGrid'));
      expect(source, contains('身份信息加载失败'));
    });

    test('profile and composer expose identity management entry points', () {
      final profile = read('lib/screens/profile/profile_tab.dart');
      final otherProfile = read('lib/screens/profile/user_profile_screen.dart');
      final composer = read('lib/screens/post/create_post_screen.dart');

      expect(profile, contains('ProfileIdentitySection'));
      expect(profile, contains('AppRoutes.identityCenter'));
      expect(otherProfile, contains('ProfileIdentitySection'));
      expect(composer, contains('以什么身份发布'));
      expect(composer, contains('认证身份可让你的作品更可信'));
      expect(composer, contains('AppRoutes.identityCenter'));
    });
  });
}
