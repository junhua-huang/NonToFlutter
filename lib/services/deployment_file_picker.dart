import 'dart:typed_data';
export 'deployment_file_picker_stub.dart'
    if (dart.library.html) 'deployment_file_picker_web.dart';

class DeploymentFile {
  final String name;
  final Uint8List bytes;
  const DeploymentFile(this.name, this.bytes);
}
