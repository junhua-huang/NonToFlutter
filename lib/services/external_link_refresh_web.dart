import 'dart:js_interop';

@JS('window.location.reload')
external void _reloadCurrentPage();

Future<bool> refreshCurrentPage() async {
  _reloadCurrentPage();
  return true;
}
