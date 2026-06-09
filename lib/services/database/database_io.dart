import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Non-Web (IO) database executor factory.
/// Uses NativeDatabase backed by a file on disk.
Future<QueryExecutor> createDatabaseExecutor(String dbName) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(appDir.path, '$dbName.db');
  return LazyDatabase(
    () => NativeDatabase.createInBackground(File(dbPath)),
  );
}

/// 删除指定用户的数据库文件。用于账号切换时清理旧数据。
Future<void> deleteDatabaseFileImpl(String dbName) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(appDir.path, '$dbName.db');
  final file = File(dbPath);
  if (await file.exists()) {
    await file.delete();
  }
  // 同时删除 WAL/Journal 文件
  try {
    final walFile = File('$dbPath-wal');
    if (await walFile.exists()) await walFile.delete();
  } catch (_) {}
  try {
    final journalFile = File('$dbPath-journal');
    if (await journalFile.exists()) await journalFile.delete();
  } catch (_) {}
}