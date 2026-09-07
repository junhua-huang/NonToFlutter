// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'deployment_file_picker.dart';

// file_picker is not a dependency in this workspace; keep the picker Web-only.
Future<DeploymentFile?> pickDeploymentFile({required bool manifest}) async {
  final input = html.FileUploadInputElement()
    ..accept = manifest ? '.json' : '.tar.gz';
  final result = Completer<html.File?>();
  final change = input.onChange.listen((_) {
    if (!result.isCompleted) result.complete(input.files?.firstOrNull);
  });
  final cancel = input.on['cancel'].listen((_) {
    if (!result.isCompleted) result.complete(null);
  });
  try {
    input.click();
    final file = await result.future
        .timeout(const Duration(minutes: 5), onTimeout: () => null);
    if (file == null) return null;
    final reader = html.FileReader();
    final loaded = reader.onLoadEnd.first;
    reader.readAsArrayBuffer(file);
    await loaded;
    if (reader.error != null) throw const FormatException('File read failed');
    final data = reader.result;
    return DeploymentFile(
        file.name, data is ByteBuffer ? data.asUint8List() : data as Uint8List);
  } finally {
    await change.cancel();
    await cancel.cancel();
    input.remove();
  }
}
