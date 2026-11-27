import 'dart:convert';

import '../../models/pdf_outline_cache_entry.dart';
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

  Future<void> deleteAllExceptFilePaths(Set<String> keepFilePaths) =>
      writeInBackground([
        (
          queries['deleteAllExceptFilePaths']!,
          [jsonEncode(keepFilePaths.toList())],
        ),
      ]);
}
