import '../../models/pdf_anchor_cache_entry.dart';
import 'database.dart';
import 'file_cache_dao.dart';

class PdfAnchorCacheDao extends FileCacheDao<PdfAnchorCacheEntry> {
  PdfAnchorCacheDao(MyDatabase db)
    : super(
        db,
        'PdfAnchorCacheQueries.sq',
        PdfAnchorCacheEntry.fromMap,
        (entry) => [
          entry.filePath,
          entry.fileSize,
          entry.lastModified,
          entry.anchorsJson,
          entry.createdAt,
          entry.accessedAt,
        ],
      );
}
