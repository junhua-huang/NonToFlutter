import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 5A create post source regressions', () {
    test('composer uses Nonto-owned wording and neutral helper names', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('Nonto 创作页'));
      expect(source, contains('文本、图片、视频、话题与草稿'));
      expect(source, isNot(contains('_xBlue')));
      expect(source, isNot(contains('_xBlack')));
      expect(source, isNot(contains('_xDarkGrey')));
      expect(source, contains('_accentColor'));
      expect(source, contains('_primaryTextColor'));
      expect(source, contains('_secondaryTextColor'));
    });

    test('composer state is centralized for submit behavior', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('bool get _hasComposerContent'));
      expect(source, contains('bool get _isOverCharacterLimit'));
      expect(source, contains('bool get _canSubmitPost'));
      expect(source, contains('Widget _buildSubmitButton()'));
      expect(source, contains('AnimatedSwitcher'));
      expect(
          source, contains('onPressed: _canSubmitPost ? _submitPost : null'));
    });

    test('composer toolbar is extracted and keeps existing actions', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(
        source,
        contains('Widget _buildComposerToolbar({required bool isOverLimit})'),
      );
      expect(source, contains("label: '图片 ("));
      expect(source, contains("label: '视频'"));
      expect(source, contains("label: '@好友'"));
      expect(source, contains("label: '#话题'"));
      expect(source, contains("label: '表情'"));
      expect(source, contains('SingleChildScrollView'));
    });

    test('async draft and media flows guard mounted before UI work', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('if (!mounted) return;'));
      expect(source, contains('final picked = await _picker.pickMultiImage'));
      expect(source, contains('final bytes = await videoFile.readAsBytes();'));
      expect(source, contains('await _videoController!.initialize();'));
      expect(source, contains('await _clearDraft();'));
    });

    test('obsolete multi-image null check is removed', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, isNot(contains('picked == null')));
      expect(source, contains('if (picked.isEmpty) return;'));
    });

    test('media preview rendering remains lazy and bounded', () {
      final source = read('lib/screens/post/create_post_screen.dart');

      expect(source, contains('ReorderableListView.builder'));
      expect(source, contains('PageView.builder'));
      expect(source, contains('GridView.builder'));
      expect(source, contains('static const int _maxImages = 9'));
    });
  });
}
