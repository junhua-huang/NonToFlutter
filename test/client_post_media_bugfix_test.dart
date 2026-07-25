import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/services/api/upload_service.dart';

void main() {
  test('post image upload names match detected image byte format', () {
    expect(UploadService.detectImageUploadFormat([0xFF, 0xD8, 0xFF])?.extension,
        'jpg');
    expect(
        UploadService.detectImageUploadFormat(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        )?.extension,
        'png');
    expect(UploadService.detectImageUploadFormat([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])?.extension,
        'webp');
    expect(UploadService.detectImageUploadFormat([0x00, 0x01]), isNull);

    expect(UploadService.uploadFileNameForFormat('IMG_0001.HEIC', 'png'),
        'IMG_0001.png');
    expect(UploadService.uploadFileNameForFormat('picked-image', 'jpg'),
        'picked-image.jpg');
    expect(UploadService.uploadFileNameForFormat('', 'webp'), startsWith('image_'));
    expect(UploadService.uploadFileNameForFormat('', 'webp'), endsWith('.webp'));
  });

  test('post service does not send legacy single image_url field', () {
    final source = File('lib/services/api/post_service.dart').readAsStringSync();

    expect(source, isNot(contains('imageUrl: uploadedUrl')));
    expect(source, contains('imageUrls: [uploadedUrl.toString()]'));
    expect(source, isNot(contains("'image_url'")));
  });

  test('create post source disables video upload entry and logs create failures', () {
    final source = File('lib/screens/post/create_post_screen.dart').readAsStringSync();

    expect(source, isNot(contains("label: '视频'")));
    expect(source, contains("debugPrint('Create post error:"));
    expect(source, contains('debugPrintStack(stackTrace: stackTrace)'));
  });

  test('publish button is not blocked by default visibility loading', () {
    final source = File('lib/screens/post/create_post_screen.dart').readAsStringSync();
    final canSubmitStart = source.indexOf('bool get _canSubmitPost =>');
    final canSubmitEnd = source.indexOf('bool get _isEditing', canSubmitStart);
    expect(canSubmitStart, greaterThanOrEqualTo(0));
    expect(canSubmitEnd, greaterThan(canSubmitStart));

    final canSubmitSource = source.substring(canSubmitStart, canSubmitEnd);
    expect(canSubmitSource, isNot(contains('_isDefaultVisibilityLoading')));
  });
}
