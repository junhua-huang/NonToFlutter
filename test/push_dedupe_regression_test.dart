import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const receiverPath =
      'android/app/src/main/kotlin/com/nonto/nonto/NontoAliyunPushMessageReceiver.kt';

  String readReceiver() =>
      File(receiverPath).readAsStringSync().replaceAll('\r\n', '\n');

  String sourceSlice(String source, String startMarker, String endMarker) {
    final start = source.indexOf(startMarker);
    expect(start, isNonNegative, reason: 'Missing $startMarker');

    final end = source.indexOf(endMarker, start + startMarker.length);
    expect(end, greaterThan(start),
        reason: 'Missing $endMarker after $startMarker');
    return source.substring(start, end);
  }

  group('Aliyun push display-boundary dedupe integration', () {
    test(
        'calls the SDK first and delegates lazy extraction and persistent claim',
        () {
      final source = readReceiver();
      final displayBoundary = sourceSlice(
        source,
        'override fun showNotificationNow',
        'private fun extractDedupeKey',
      );

      expect(
        displayBoundary,
        matches(
          RegExp(
            r'val\s+sdkWouldDisplay\s*=\s*super\.showNotificationNow\(context,\s*map\)'
            r'\s*val\s+shouldDisplay\s*=\s*shouldDisplayAliyunPush\('
            r'\s*sdkWouldDisplay\s*=\s*sdkWouldDisplay,'
            r'\s*extractDedupeKey\s*=\s*\{\s*extractDedupeKey\(context,\s*map\)\s*\},'
            r'\s*claim\s*=\s*\{\s*dedupeKey\s*->\s*dedupeStore\(context\)\.claim\(dedupeKey\)\s*\}'
            r'\s*\)',
          ),
        ),
      );
      expect(
        displayBoundary.indexOf('super.showNotificationNow'),
        lessThan(displayBoundary.indexOf('dedupeStore(context).claim')),
      );
      expect(
        displayBoundary.indexOf('dedupeStore(context).claim'),
        lessThan(displayBoundary.indexOf('recordDisplayDecision')),
      );
      expect(
        displayBoundary.indexOf('recordDisplayDecision'),
        lessThan(displayBoundary.indexOf('return shouldDisplay')),
      );
    });

    test('extracts only the raw canonical extension key with map fallback', () {
      final source = readReceiver();
      final extraction = sourceSlice(
        source,
        'private fun extractDedupeKey',
        'override fun onNotification(',
      );

      expect(
        extraction,
        matches(
          RegExp(
            r'val\s+parsedExtraMap\s*=\s*PushData\.parse\(context,\s*map\)\?\.extraMap'
            r'\s*return\s+mapValueAsString\(parsedExtraMap,\s*DEDUPE_KEY\)'
            r'\s*\?:\s*mapValueAsString\(map,\s*DEDUPE_KEY\)',
          ),
        ),
      );
      expect(
        extraction,
        matches(
          RegExp(
            r'return\s+\(map\?\.get\(key\)\s+as\?\s+String\)\?\.takeIf\s*\{\s*it\.isNotBlank\(\)\s*\}',
          ),
        ),
      );
      expect(extraction, isNot(contains('.trim(')));

      for (final forbidden in <String>[
        'title',
        'body',
        'summary',
        'content',
        'notify_id',
        'msg_id',
        'messageId',
        'traceInfo',
      ]) {
        expect(extraction, isNot(contains(forbidden)),
            reason: '$forbidden must not be a fallback dedupe identity');
      }
    });

    test('does not manually display notifications', () {
      final source = readReceiver();

      expect(source, isNot(contains('NotificationManager')));
      expect(source, isNot(contains('.notify(')));
    });

    test('all six callbacks neither claim nor display notifications', () {
      final source = readReceiver();
      const callbackBoundaries = <(String, String)>[
        (
          'override fun onNotification(',
          'override fun onNotificationReceivedInApp('
        ),
        (
          'override fun onNotificationReceivedInApp(',
          'override fun onMessage('
        ),
        ('override fun onMessage(', 'override fun onNotificationOpened('),
        (
          'override fun onNotificationOpened(',
          'override fun onNotificationRemoved('
        ),
        (
          'override fun onNotificationRemoved(',
          'override fun onNotificationClickedWithNoAction('
        ),
        (
          'override fun onNotificationClickedWithNoAction(',
          '@Suppress("UNCHECKED_CAST")'
        ),
      ];

      for (final (signature, nextSignature) in callbackBoundaries) {
        final callback = sourceSlice(source, signature, nextSignature);
        expect(callback, isNot(contains('.claim(')), reason: signature);
        expect(callback, isNot(contains('showNotificationNow(')),
            reason: signature);
        expect(callback, isNot(contains('.notify(')), reason: signature);
      }
    });
  });
}
