import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('Phase 5B media viewer source regressions', () {
    test('viewer uses Nonto-owned wording and keeps immersive behavior', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('Nonto 图片浏览页'));
      expect(source, contains('沉浸查看帖子图片、作者信息与正文上下文'));
      expect(source, contains('PageView.builder'));
      expect(source, contains('InteractiveViewer'));
      expect(source, contains('CachedNetworkImage'));
      expect(source, contains('Hero('));
    });

    test('top chrome is extracted without eager image creation', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('Widget _buildCloseButton()'));
      expect(source,
          contains('Widget _buildPageIndicator(int safeIndex, int total)'));
      expect(source, contains('if (resolved.length > 1)'));
      expect(
          source, contains('_buildPageIndicator(safeIndex, resolved.length)'));
      expect(source, contains('itemBuilder: (context, index)'));
    });

    test('info bar visibility is centralized and keeps post context', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('bool get _hasInfoBarContent'));
      expect(source, contains('if (_hasInfoBarContent)'));
      expect(source, contains('UserProfileScreen(user: author)'));
      expect(source, contains('_ExpandablePostContent(content: content)'));
      expect(source, contains('AnimatedPositioned'));
    });

    test(
        'targeted analyzer cleanup removes obsolete state and redundant checks',
        () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, isNot(contains('bool _isCurrentZoomed()')));
      expect(source, isNot(contains('_verticalDragOffset')));
      expect(source, isNot(contains('if (author != null) {')));
    });

    test('empty and invalid media lists still close safely', () {
      final source = read('lib/screens/post/image_viewer_screen.dart');

      expect(source, contains('if (urls.isEmpty) return;'));
      expect(source, contains('if (resolved.isEmpty)'));
      expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
      expect(source, contains('if (mounted) Navigator.pop(context);'));
    });
  });
}
