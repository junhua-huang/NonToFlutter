import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  String read(String relativePath) =>
      File('$projectRoot/$relativePath').readAsStringSync();

  group('remaining UX, identity, and unread regressions', () {
    test('feed header avatar uses the shared header avatar size', () {
      final feed = read('lib/screens/home/home/feed_tab.dart');
      final header = read('lib/widgets/nonto_header_search_bar.dart');

      expect(header, contains('class NontoHeaderAvatar'));
      expect(header, contains('this.radius = 18'));
      expect(feed, contains('NontoHeaderAvatar('));
      expect(feed, contains('radius: 18'));
      expect(feed, isNot(contains('radius: 10')));
    });

    test('drawer exposes identity application entry', () {
      final home = read('lib/screens/home/home_screen.dart');

      expect(home, contains('身份认证'));
      expect(home, contains('Icons.verified_outlined'));
      expect(home, contains('AppRoutes.identityApplication'));
    });

    test('search results show a left back button that exits search state', () {
      final header = read('lib/widgets/nonto_header_search_bar.dart');
      final search = read('lib/screens/search/search_tab.dart');

      expect(header, contains('Widget? leading'));
      expect(search, contains('_buildSearchLeading'));
      expect(search, contains('Icons.arrow_back'));
      expect(search, contains('_exitSearchMode(clearResults: true)'));
    });

    test('bottom message badge counts chat unread only', () {
      final home = read('lib/screens/home/home_screen.dart');
      final buildStart = home.indexOf('Widget build(BuildContext context)');
      final buildEnd = home.indexOf('Widget? _buildComposeButton', buildStart);
      expect(buildStart, greaterThanOrEqualTo(0));
      expect(buildEnd, greaterThan(buildStart));
      final buildSource = home.substring(buildStart, buildEnd);

      expect(buildSource, contains('ref.watch(unreadMessagesCountProvider)'));
      expect(buildSource, isNot(contains('unreadNotificationsCountProvider) +')));
      expect(buildSource, isNot(contains('+\n            ref.watch(unreadMessagesCountProvider)')));
    });

    test('messages notification entry uses notification provider unread count', () {
      final messages = read('lib/screens/messages/messages_tab.dart');

      expect(messages, isNot(contains('int _unreadNotifications = 0;')));
      expect(messages, isNot(contains('_fetchUnreadNotifications')));
      expect(messages, contains('unreadNotificationsCountProvider'));
    });

    test('unread badges use a shared semantic color token', () {
      final theme = read('lib/config/app_theme.dart');
      final home = read('lib/screens/home/home_screen.dart');
      final messages = read('lib/screens/messages/messages_tab.dart');
      final tile = read('lib/widgets/nonto/nonto_conversation_tile.dart');

      expect(theme, contains('unreadBadge'));
      expect(home, contains('backgroundColor: AppColors.unreadBadge'));
      expect(messages, contains('AppColors.unreadBadge'));
      expect(tile, contains('AppColors.unreadBadge'));
    });

    test('identity application supports image selection instead of proof URL text field', () {
      final identity = read('lib/screens/profile/identity_application_screen.dart');

      expect(identity, contains('ImagePicker'));
      expect(identity, contains('_selectedProofImages'));
      expect(identity, contains('static const int _maxProofImages = 9'));
      expect(identity, contains('UploadService'));
      expect(identity, contains('proofImages: uploadedProofImages'));
      expect(identity, isNot(contains('证明图片链接（每行一个，可选）')));
    });

    test('identity application has optimistic pending state after submit success', () {
      final identity = read('lib/screens/profile/identity_application_screen.dart');

      expect(identity, contains('_submittedApplication'));
      expect(identity, contains('等待管理员审核'));
      expect(identity, contains('setState(() {'));
    });
  });
}
