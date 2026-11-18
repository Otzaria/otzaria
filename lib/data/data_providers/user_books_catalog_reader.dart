import 'dart:isolate';

import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/category_dao.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';

/// תמונת מצב של טבלאות הקטלוג במסד הספרים האישיים.
typedef UserBooksCatalogRows = ({
  List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> categories,
  Map<int, String> authors,
  List<Map<String, dynamic>> versions,
  List<Map<String, dynamic>> attachedVersions,
});

/// קורא את כל טבלאות הקטלוג בטרנזקציה אחת דרך חיבור המסד הקיים.
UserBooksCatalogRows selectUserBooksCatalog(
  sqlite3.Database db,
  DbCapabilities capabilities,
) {
  late final UserBooksCatalogRows rows;
  withTransaction(db, () {
    rows = (
      books: BookDao.selectBooksMinimal(
        db,
        capabilities,
        withFileColumns: true,
      ),
      categories: CategoryDao.selectCategoryRows(db, capabilities),
      authors: BookDao.selectBookAuthorsMap(db, capabilities),
      versions: db
          .select(
            'SELECT versionBookId, primaryBookId, primarySource, primaryTitle, '
            'primaryCategoryPath, versionTitle, versionNotes, priority '
            'FROM user_book_version',
          )
          .toMapList(),
      attachedVersions:
          db
              .select(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' "
                "AND name = 'user_attached_book_version'",
              )
              .isEmpty
          ? const []
          : db
                .select(
                  'SELECT versionDb, versionBookTitle, primarySource, '
                  'primaryTitle, primaryCategoryPath, versionTitle, '
                  'versionNotes, priority FROM user_attached_book_version',
                )
                .toMapList(),
    );
  });
  return rows;
}

/// קטלוג user_books.db ופתרון נתיבי הקבצים, על חיבור read-only ב-isolate:
/// פענוח עשרות אלפי שורות על ה-UI isolate תקע את הממשק (#3515).
Future<UserBooksCatalogRows> readUserBooksCatalogInIsolate(
  String dbPath,
  String libraryPath,
) => Isolate.run(() {
  final db = openReadOnlyTarget(trustedDbTarget(dbPath));
  try {
    db.execute('PRAGMA busy_timeout=5000');
    final rows = selectUserBooksCatalog(db, DbCapabilities.probe(db));
    return (
      books: [
        for (final row in rows.books)
          if (row['filePath'] case final String path)
            {
              ...row,
              'filePath': resolveMovedFileBookPath(
                path,
                activeLibraryPath: libraryPath,
              ),
            }
          else
            row,
      ],
      categories: rows.categories,
      authors: rows.authors,
      versions: rows.versions,
      attachedVersions: rows.attachedVersions,
    );
  } finally {
    db.close();
  }
}, debugName: 'readUserBooksCatalog');
