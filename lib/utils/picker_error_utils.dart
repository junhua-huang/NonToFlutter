import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String pickerErrorMessage(Object error, {String target = '相册'}) {
  final code = error is PlatformException ? error.code.toLowerCase() : '';
  final message = error is PlatformException
      ? (error.message ?? '').toLowerCase()
      : error.toString().toLowerCase();
  final text = '$code $message';

  if (text.contains('denied') ||
      text.contains('permission') ||
      text.contains('unauthor') ||
      text.contains('not authorized') ||
      text.contains('photo_access') ||
      text.contains('camera_access')) {
    return '无法访问$target，请在系统设置中允许 Nonto 访问$target权限';
  }

  if (text.contains('unavailable') || text.contains('not available')) {
    return '$target暂时不可用，请稍后重试';
  }

  return '无法打开$target，请稍后重试';
}

void showPickerErrorSnackBar(
  BuildContext context,
  Object error, {
  String target = '相册',
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(pickerErrorMessage(error, target: target))),
  );
}
