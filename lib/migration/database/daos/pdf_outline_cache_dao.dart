import '../../models/pdf_outline_cache_entry.dart';
import '../sqlite3_utils.dart';
import 'database.dart';
import 'file_cache_dao.dart';

class PdfOutlineCacheDao extends FileCacheDao<PdfOutlineCacheEntry> {
  PdfOutlineCacheDao(MyDatabase db)
    : super(
        db,
        'PdfOutlineCacheQueries.sq',
        PdfOutlineCacheEntry.fromMap,
        (entry) => [
          entry.filePath,
          entry.fileSize,
          entry.lastModified,
          entry.outlineJson,
          entry.createdAt,
          entry.accessedAt,
        ],
      );

  Future<List<String>> selectAllFilePaths() async {
    final db = await database;
    return db
        .select(queries['selectAllFilePaths']!)
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
        db.execute(queries['deleteByFilePath']!, [stalePath]);
      }
    });
  }
}
