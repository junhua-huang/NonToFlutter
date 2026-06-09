import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web database executor factory.
/// Uses WasmDatabase backed by sqlite3.wasm (IndexedDB).
Future<QueryExecutor> createDatabaseExecutor(String dbName) async {
  final result = await WasmDatabase.open(
    databaseName: dbName,
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}

/// Web 端删除数据库文件为空操作（IndexedDB 由浏览器管理，无法通过文件系统删除）。
/// 账号切换时通过 close() + 重新 open() 实现数据隔离。
Future<void> deleteDatabaseFileImpl(String dbName) async {
  // Web: IndexedDB managed by browser, no-op
}