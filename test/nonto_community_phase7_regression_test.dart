import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('community create and chrome polish regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test(
        'community create avatar and cover upload surfaces are tappable and submitted',
        () {
      final source = read('lib/screens/community/community_create_screen.dart');

      expect(source, contains('final ImagePicker _picker = ImagePicker();'));
      expect(source, contains('Future<void> _pickCommunityAvatar()'));
      expect(source, contains('Future<void> _pickCommunityCover()'));
      expect(source, contains('UploadService().uploadImage'));
      expect(source, contains("'avatar_url': _avatarUrl"));
      expect(source, contains("'banner_url': _bannerUrl"));
      expect(source, contains('InkWell('));
      expect(source,
          contains('onTap: _isUploadingAvatar ? null : _pickCommunityAvatar'));
      expect(source,
          contains('onTap: _isUploadingCover ? null : _pickCommunityCover'));
    });

    test(
        'community create cover placeholder uses Nonto semantic colors for dark mode',
        () {
      final source = read('lib/screens/community/community_create_screen.dart');

      expect(source, contains('AppColors.surface'));
      expect(source, contains('AppColors.borderLight'));
      expect(source, isNot(contains('Colors.grey[100]')));
      expect(source, isNot(contains('Colors.grey[300]!')));
    });

    test('community plaza create action lives in top app bar instead of fab',
        () {
      final source = read('lib/screens/community/community_list_screen.dart');

      expect(source, contains("tooltip: '创建社群'"));
      expect(source, contains('Icons.group_add_outlined'));
      expect(source, contains('CommunityCreateScreen'));
      expect(source, isNot(contains('floatingActionButton:')));
      expect(source, isNot(contains('FloatingActionButton.extended')));
    });

    test(
        'community detail back and menu controls overlay the cover without title app bar',
        () {
      final source = read('lib/screens/community/community_detail_screen.dart');

      expect(source, contains('extendBodyBehindAppBar: true'));
      expect(source, contains('appBar: null'));
      expect(source, contains('Widget _buildCoverOverlayControls'));
      expect(source, contains('SafeArea('));
      expect(source, contains('Icons.arrow_back'));
      expect(source, contains('_buildCoverOverlayControls(community)'));
    });

    test(
        'other user profile back and menu controls overlay the cover without title app bar',
        () {
      final source = read('lib/screens/profile/user_profile_screen.dart');

      expect(source, contains('extendBodyBehindAppBar: true'));
      expect(source, contains('appBar: null'));
      expect(source, contains('Widget _buildProfileOverlayControls'));
      expect(source, contains('SafeArea('));
      expect(source, contains('_buildProfileOverlayControls()'));
      expect(source,
          isNot(contains('title: Text(user.displayName ?? user.username')));
    });
  });
}
