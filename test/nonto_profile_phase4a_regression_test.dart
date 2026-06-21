import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4A profile source regressions', () {
    late String source;

    setUpAll(() {
      source = File('lib/screens/profile/profile_tab.dart').readAsStringSync();
    });

    test('profile tab uses Nonto-owned naming instead of Twitter/X labels', () {
      expect(source, contains('Nonto 个人资料页'));
      expect(source, isNot(contains('Twitter/X 风格个人资料页')));
    });

    test('profile tab has reusable loading and empty states', () {
      expect(source, contains('Widget _buildProfileLoadingState()'));
      expect(source, contains('Widget _buildProfileEmptyState({'));
      expect(source, contains('_buildProfileEmptyState('));
      expect(source, contains('icon: Icons.article_outlined'));
      expect(source, contains('icon: Icons.favorite_border'));
      expect(source, contains('icon: Icons.photo_library_outlined'));
    });

    test('profile tab keeps lazy rendering and nested profile scroll structure',
        () {
      expect(source, contains('NestedScrollView('));
      expect(source, contains('SliverAppBar('));
      expect(source, contains('TabBarView('));
      expect(source, contains('return ListView.builder('));
      expect(source, contains('return GridView.builder('));
    });

    test(
        'profile tab removes known unused imports and unused avatar preview fields',
        () {
      expect(source, isNot(contains("package:cross_file/cross_file.dart")));
      expect(source, isNot(contains("package:nonto/config/app_config.dart")));
      expect(source,
          isNot(contains("package:nonto/providers/core_providers.dart")));
      expect(
          source, isNot(contains("package:path_provider/path_provider.dart")));
      expect(
          source, isNot(contains("screens/profile/edit_profile_screen.dart")));
      expect(source, isNot(contains('_navigateToEditProfile')));
      expect(source, isNot(contains('String? _localAvatarPreview')));
      expect(source, isNot(contains('Uint8List? _localAvatarBytes')));
    });

    test('profile edit affordances use direct avatar and cover update actions',
        () {
      expect(source, contains('onTap: () => _changeCoverPhoto()'));
      expect(source, contains('onTap: () => _changeAvatar()'));
      expect(source, contains('Directory.systemTemp'));
    });
  });
}
