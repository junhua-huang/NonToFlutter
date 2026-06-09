/// Web 数据库实现
///
/// 仅在 Web 平台编译加载。Native 平台使用 database_io.dart。
library;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// 创建 Web 数据库（使用 sqlite3.wasm，不使用 sql.js）
Future<QueryExecutor> openWebDatabase(String name) async {
  final result = await WasmDatabase.open(
    databaseName: name,
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}

/// Native 数据库在 Web 平台不可用
QueryExecutor openNativeDatabase(String name) =>
    throw UnsupportedError('NativeDatabase is not available on web');