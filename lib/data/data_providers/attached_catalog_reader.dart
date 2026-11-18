import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/attached_libraries/utils/attached_file_path.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/category_dao.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';

/// קטלוג מסד מצורף כפי שנקרא ב-isolate. [missing] — הקובץ אינו קיים.
typedef AttachedCatalogRows = ({
  bool missing,
  List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> categories,
  Map<int, String> authors,
  List<Map<String, dynamic>> versionLinks,
});

/// תקרת שורות book_version_link שנקראות ממסד מצורף אחד.
const kMaxAttachedVersionLinks = 100000;

/// קורא את הקטלוג של מסד מצורף על חיבור מוקשח משלו — רץ ב-isolate, כך
/// שקובץ איטי או כונן רשת מת אינם חוסמים את בניית העץ.
AttachedCatalogRows readAttachedCatalogSync(ReadOnlyDbTarget target) {
  if (!File(target.path).existsSync()) {
    return (
      missing: true,
      books: const [],
      categories: const [],
      authors: {},
      versionLinks: const [],
    );
  }
  final db = openReadOnlyTarget(target);
  try {
    final capabilities = DbCapabilities.probe(db);
    late final List<Map<String, dynamic>> books;
    late final List<Map<String, dynamic>> categories;
    late final Map<int, String> authors;
    var versionLinks = const <Map<String, dynamic>>[];
    withTransaction(db, () {
      books = [
        for (final row in BookDao.selectBooksMinimal(
          db,
          capabilities,
          withFileColumns: true,
        ))
          {...row, 'resolvedFilePath': _existingAttachedFile(target, row)},
      ];
      categories = CategoryDao.selectCategoryRows(db, capabilities);
      authors = BookDao.selectBookAuthorsMap(db, capabilities);
      if (capabilities.hasBookVersionLinks) {
        String column(String name) =>
            capabilities.column('book_version_link', name);
        versionLinks = db
            .select(
              'SELECT versionBookId, ${column('primarySource')}, primaryTitle, '
              '${column('primaryCategoryPath')}, ${column('versionTitle')}, '
              '${column('versionNotes')}, ${column('priority')} '
              'FROM book_version_link LIMIT $kMaxAttachedVersionLinks',
            )
            .toMapList();
      }
    });
    return (
      missing: false,
      books: books,
      categories: categories,
      authors: authors,
      versionLinks: versionLinks,
    );
  } finally {
    db.close();
  }
}

/// הקובץ של ספר מבוסס-קובץ במסד מצורף, כשהנתיב מותר והקובץ קיים.
String? _existingAttachedFile(
  ReadOnlyDbTarget target,
  Map<String, dynamic> row,
) {
  final resolved = resolveAttachedBookFilePath(
    target.path,
    row['filePath'] as String?,
  );
  return resolved != null && File(resolved).existsSync() ? resolved : null;
}

Future<AttachedCatalogRows> readAttachedCatalogInIsolate(
  ReadOnlyDbTarget target,
) => Isolate.run(() => readAttachedCatalogSync(target));
