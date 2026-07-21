import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../models/pdf_anchor_cache_entry.dart';
import '../sql/query_loader.dart';
import '../sql/sqlite3_utils.dart';
import 'database.dart';

class PdfAnchorCacheDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PdfAnchorCacheDao(this._db) {
    _queries = QueryLoader.loadQueries('PdfAnchorCacheQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<PdfAnchorCacheEntry?> selectByFilePath(String filePath) async {
    final db = await database;
    final result = db.select(_queries['selectByFilePath']!, [
      filePath,
    ]).toMapList();
    if (result.isEmpty) return null;
    return PdfAnchorCacheEntry.fromMap(result.first);
  }

  Future<void> upsert(PdfAnchorCacheEntry entry) async {
    final db = await database;
    db.execute(_queries['upsert']!, [
      entry.filePath,
      entry.fileSize,
      entry.lastModified,
      entry.anchorsJson,
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
