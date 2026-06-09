import 'dart:async';
import 'dart:html' as html;

/// Calls the browser's hideLoading() function to hide the HTML loading overlay.
/// Called from Flutter's global error handlers to ensure the loading screen
/// never gets stuck when Flutter fails to initialize (e.g. MediaKit crash,
/// SharedPreferences hang, or JS compilation errors).
void hideWebLoadingOverlay() {
  try {
    final overlay = html.document.getElementById('loading-overlay');
    if (overlay != null) {
      overlay.classes.add('hidden');
      Timer(const Duration(milliseconds: 500), () {
        try {
          overlay.remove();
        } catch (_) {}
      });
    }
  } catch (_) {
    // Best-effort; web/index.html fallback timer will also handle this.
  }
}
