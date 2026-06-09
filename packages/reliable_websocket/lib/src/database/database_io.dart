/// Native 平台数据库实现
///
/// 在非 Web 平台编译加载。包含 dart:io / drift/native.dart 等 Web 不可用的依赖。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native 平台不可用，抛异常
QueryExecutor openWebDatabase(String name) =>
    throw UnsupportedError('WebDatabase is not available on this platform');

/// 创建 Native 数据库（SQLite 文件）
QueryExecutor openNativeDatabase(String name) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, '$name.db'));
    return NativeDatabase.createInBackground(file);
  });
}
