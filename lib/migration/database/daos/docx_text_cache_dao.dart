import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../models/docx_text_cache_entry.dart';
import '../sql/query_loader.dart';
import '../sql/sqlite3_utils.dart';
import 'database.dart';

/// DAO למטמון התוכן הממומר של קובצי docx חיצוניים (טבלת `docx_text_cache`,
/// מאוכלסת ב-`cache.db`). מקביל ל-[PdfOutlineCacheDao].
class DocxTextCacheDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  DocxTextCacheDao(this._db) {
    _queries = QueryLoader.loadQueries('DocxTextCacheQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<DocxTextCacheEntry?> selectByFilePath(String filePath) async {
    final db = await database;
    final result = db.select(_queries['selectByFilePath']!, [
      filePath,
    ]).toMapList();
    if (result.isEmpty) return null;
    return DocxTextCacheEntry.fromMap(result.first);
  }

  Future<void> upsert(DocxTextCacheEntry entry) async {
    final db = await database;
    db.execute(_queries['upsert']!, [
      entry.filePath,
      entry.fileSize,
      entry.lastModified,
      entry.converterVersion,
      entry.text,
      entry.createdAt,
      entry.accessedAt,
    ]);
  }

  Future<void> updateAccessedAt(String filePath, int accessedAt) async {
    final db = await database;
    db.execute(_queries['updateAccessedAt']!, [accessedAt, filePath]);
  }

  Future<void> deleteByFilePath(String filePath) async {
    final db = await database;
    db.execute(_queries['deleteByFilePath']!, [filePath]);
  }

  Future<void> deleteAccessedBefore(int cutoffMillis) async {
    final db = await database;
    db.execute(_queries['deleteAccessedBefore']!, [cutoffMillis]);
  }
}
