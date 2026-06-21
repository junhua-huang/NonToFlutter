import 'package:flutter_test/flutter_test.dart';
import 'package:nonto/config/app_config.dart';
import 'package:nonto/utils/image_utils.dart';

void main() {
  group('ImageUtils.resolveUrl', () {
    test('rejects local file URLs instead of sending them to the backend', () {
      expect(ImageUtils.resolveUrl('file:///root/.ssh/id_rsa'), '');
      expect(ImageUtils.resolveUrl('FILE:///C:/Users/test/.ssh/id_rsa'), '');
    });

    test('rejects script and inline data URLs', () {
      expect(ImageUtils.resolveUrl('javascript:alert(1)'), '');
      expect(ImageUtils.resolveUrl('data:text/html,<script>alert(1)</script>'), '');
    });

    test('keeps allowed http URLs and relative paths', () {
      expect(ImageUtils.resolveUrl('https://www.nonto.online/a.png'), 'https://www.nonto.online/a.png');
      final backendRoot = AppConfig.baseUrl.replaceFirst('/api', '');
      expect(ImageUtils.resolveUrl('/uploads/a.png'), '$backendRoot/uploads/a.png');
    });
  });
}
