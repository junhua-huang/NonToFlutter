import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('community detail apply state regressions', () {
    String read(String path) => File(path).readAsStringSync();

    test('pending join applications render as already applied and disabled',
        () {
      final source = read('lib/screens/community/community_detail_screen.dart');

      expect(source, contains('community.isPending'));
      expect(source, contains("'已申请'"));
      expect(source, contains("'等待管理员审核'"));
      expect(source, contains('onPressed: null'));
      expect(source, isNot(contains("community.isPending ? '审核中' : '加入社群'")));
    });

    test(
        'successful approval join request updates detail state to pending locally',
        () {
      final screen = read('lib/screens/community/community_detail_screen.dart');
      final notifier = read('lib/providers/community_notifier.dart');

      expect(notifier, contains('void updateMembershipStatus'));
      expect(notifier, contains('community.copyWith('));
      expect(notifier, contains('myStatus: myStatus'));
      expect(screen, contains('updateMembershipStatus('));
      expect(screen, contains("myStatus: 'pending'"));
      expect(screen, contains("申请已提交，等待审核"));
    });
  });
}
