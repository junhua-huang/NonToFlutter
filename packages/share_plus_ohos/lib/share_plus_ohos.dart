/// 跨端分享（nonto）
///
/// - 鸿蒙端：通过 Want 启动系统分享面板（Share Kit）
/// - iOS/Android 端：委托给 share_plus 包
library;

import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' as sp;

/// 分享文本
Future<void> shareText(String text, {String? subject}) async {
  if (Platform.operatingSystem == 'ohos') {
    await _ohosShare(text: text, subject: subject);
  } else {
    await sp.Share.share(text, subject: subject);
  }
}

/// 分享文件
Future<void> shareFile(String filePath, {String? text, String? subject}) async {
  if (Platform.operatingSystem == 'ohos') {
    await _ohosShare(filePath: filePath, text: text, subject: subject);
  } else {
    final files = <sp.XFile>[sp.XFile(filePath)];
    await sp.Share.shareXFiles(files, text: text, subject: subject);
  }
}

Future<void> _ohosShare({
  String? text,
  String? subject,
  String? filePath,
}) async {
  const channel = MethodChannel('nonto_share');
  await channel.invokeMethod('share', {
    'text': text,
    'subject': subject,
    'filePath': filePath,
  });
}
