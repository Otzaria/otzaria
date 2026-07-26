import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;

import '../../models/pdf_outline_cache_entry.dart';
import '../sql/query_loader.dart';
import '../sql/sqlite3_utils.dart';
import 'database.dart';

class PdfOutlineCacheDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PdfOutlineCacheDao(this._db) {
    _queries = QueryLoader.loadQueries('PdfOutlineCacheQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<PdfOutlineCacheEntry?> selectByFilePath(String filePath) async {
    final db = await database;
    final result = db.select(_queries['selectByFilePath']!, [
      filePath,
    ]).toMapList();
    if (result.isEmpty) return null;
    return PdfOutlineCacheEntry.fromMap(result.first);
  }

  Future<void> upsert(PdfOutlineCacheEntry entry) async {
    final db = await database;
    db.execute(_queries['upsert']!, [
      entry.filePath,
      entry.fileSize,
      entry.lastModified,
      entry.outlineJson,
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

  Future<List<String>> selectAllFilePaths() async {
    final db = await database;
    return db
        .select(_queries['selectAllFilePaths']!)
        .toMapList()
        .map((row) => row['filePath'] as String)
        .toList();
  }

  Future<void> deleteAllExceptFilePaths(Set<String> keepFilePaths) async {
    final db = await database;
    final allPaths = await selectAllFilePaths();
    final stalePaths = allPaths.where((path) => !keepFilePaths.contains(path));
    withTransaction(db, () {
      for (final stalePath in stalePaths) {
        db.execute(_queries['deleteByFilePath']!, [stalePath]);
      }
    });
  }
}
