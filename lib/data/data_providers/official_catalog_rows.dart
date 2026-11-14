import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/book_dao.dart';
import 'package:otzaria/migration/database/daos/category_dao.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';

typedef CatalogRows = ({
  List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> categories,
  Map<int, String> authors,
});

/// שורות הקטלוג של seforim.db: בניית הקטלוג ו-`BooksCache` מצטרפים לאותה
/// קריאה כשהיא כבר רצה, כדי שטבלת `book` לא תיקרא פעמיים. null כשאין נתיב.
Future<CatalogRows?> sharedOfficialCatalogRows(String dbPath) {
  if (dbPath.isEmpty) return Future.value(null);
  final inFlight = _inFlight;
  if (inFlight != null && inFlight.dbPath == dbPath) return inFlight.rows;
  final rows = officialCatalogReader(dbPath);
  _inFlight = (dbPath: dbPath, rows: rows);
  void release(Object? _) {
    if (identical(_inFlight?.rows, rows)) _inFlight = null;
  }

  rows.then(release, onError: release);
  return rows;
}

({String dbPath, Future<CatalogRows> rows})? _inFlight;

/// ביטול חייב להתפשט כדי לא לפתוח חיבור ראשי ששוחרר לכתיבה חיצונית.
@visibleForTesting
Future<CatalogRows> Function(String dbPath) officialCatalogReader =
    _readOfficialCatalogInIsolate;

Future<CatalogRows> _readOfficialCatalogInIsolate(String dbPath) =>
    DbReadWorker.runOnFreshIsolate(
      () => readOfficialCatalogSync(dbPath),
      requestArguments: {'dbPath': dbPath},
    );

@visibleForTesting
CatalogRows readOfficialCatalogSync(String dbPath) {
  final db = openReadOnlyTarget((
    path: dbPath,
    untrusted: false,
    immutable: false,
  ));
  try {
    return readCatalogRows(db, DbCapabilities.probe(db));
  } finally {
    db.close();
  }
}

/// בטרנזקציה אחת, כדי שסנכרון רקע לא ינעל את המסד בין השאילתות.
CatalogRows readCatalogRows(
  sqlite3.Database db,
  DbCapabilities capabilities,
) {
  late final CatalogRows rows;
  withTransaction(db, () {
    rows = (
      books: BookDao.selectBooksMinimal(
        db,
        capabilities,
        withStoredFileColumns: true,
      ),
      categories: CategoryDao.selectCategoryRows(db, capabilities),
      authors: BookDao.selectBookAuthorsMap(db, capabilities),
    );
  });
  return rows;
}
