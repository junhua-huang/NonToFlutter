import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 4D edit profile source regressions', () {
    test('edit profile uses Nonto-owned wording and neutral helper names', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, contains('Nonto 个人资料编辑页'));
      expect(source, isNot(contains('按需编辑模式')));
      expect(source, isNot(contains('_xBlack')));
      expect(source, isNot(contains('_xDarkGrey')));
      expect(source, isNot(contains('_xBlue')));
      expect(source, contains('_primaryTextColor'));
      expect(source, contains('_secondaryTextColor'));
      expect(source, contains('_accentColor'));
    });

    test('edit profile keeps direct image crop upload flow and previews', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, contains('_picker.pickImage'));
      expect(source, contains('ImageCropScreen'));
      expect(source, contains('UploadService().uploadAvatar'));
      expect(source, contains('UploadService().uploadCoverPhoto'));
      expect(source, contains('_localAvatarBytes = finalBytes'));
      expect(source, contains('_localCoverBytes = finalBytes'));
    });

    test('edit profile guards context usage after async image picking', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source,
          contains('final originalBytes = await picked.readAsBytes();'));
      expect(source, contains('if (!mounted) return;'));
      expect(source, contains('Navigator.of(context).push<Uint8List>'));
    });

    test('edit profile keeps optimistic text updates with rollback', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(
        source,
        contains('final optimistic = user.copyWith(displayName: newName)'),
      );
      expect(source, contains('final optimistic = user.copyWith(bio: newBio)'));
      expect(
        source,
        contains('updateUser(user.copyWith(displayName: originalName))'),
      );
      expect(source, contains('updateUser(user.copyWith(bio: originalBio))'));
    });

    test('edit profile removes known unused imports', () {
      final source = read('lib/screens/profile/edit_profile_screen.dart');

      expect(source, isNot(contains("import 'dart:io';")));
      expect(
        source,
        isNot(contains("import 'package:cross_file/cross_file.dart';")),
      );
    });
  });
}
