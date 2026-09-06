import 'package:nonto/services/external_link_refresh_stub.dart'
    if (dart.library.html) 'package:nonto/services/external_link_refresh_web.dart'
    as page_refresh;
import 'package:url_launcher/url_launcher.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);
typedef ExternalPageRefresher = Future<bool> Function();

class ExternalLinkService {
  const ExternalLinkService({
    ExternalUrlLauncher? launcher,
    ExternalPageRefresher? pageRefresher,
  })  : _launcher = launcher,
        _pageRefresher = pageRefresher;

  final ExternalUrlLauncher? _launcher;
  final ExternalPageRefresher? _pageRefresher;

  Future<bool> perform({String? action, String? url}) async {
    if (action?.trim().toLowerCase() == 'refresh') {
      try {
        final refresher = _pageRefresher ?? page_refresh.refreshCurrentPage;
        if (await refresher()) return true;
      } catch (_) {
        // Fall through to the HTTPS URL when page refresh is unavailable.
      }
    }
    return open(url);
  }

  Future<bool> open(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return false;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return false;
    }
    try {
      final launcher = _launcher;
      if (launcher != null) return await launcher(uri);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
