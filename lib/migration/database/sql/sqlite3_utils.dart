import 'package:otzaria/data/sqlite/sqlite3_api.dart';

/// Converts a sqlite3 [ResultSet] to a list of dynamic maps.
extension ResultSetExt on ResultSet {
  List<Map<String, dynamic>> toMapList() =>
      map((row) => Map<String, dynamic>.from(row)).toList();
}

/// Returns the first integer value from a single-column [ResultSet], or null.
int? firstIntValue(ResultSet result) {
  if (result.isEmpty) return null;
  final value = result.first.values.first;
  if (value == null) return null;
  return value as int;
}

/// כיווץ כותב את כל הקובץ מחדש, ולכן רץ רק כשיש מה להרוויח: לפחות 1MB
/// פנוי (256 דפים של 4KB) וגם לפחות רבע מהקובץ.
const int _minFreePagesToCompact = 256;
const double _minFreeRatioToCompact = 0.25;

/// מריץ VACUUM על [db] אם הצטברו בו מספיק דפים פנויים; מחזיר האם כווץ בפועל.
///
/// מחיקות משחררות דפים ל-freelist אך משאירות את הקובץ בגודל השיא ההיסטורי
/// שלו — רק VACUUM מקטין אותו. הקריאה חייבת להיות מחוץ לטרנזקציה.
bool vacuumIfFragmented(Database db) {
  final freePages = firstIntValue(db.select('PRAGMA freelist_count')) ?? 0;
  final totalPages = firstIntValue(db.select('PRAGMA page_count')) ?? 0;
  if (freePages < _minFreePagesToCompact ||
      freePages < totalPages * _minFreeRatioToCompact) {
    return false;
  }

  // VACUUM בונה עותק זמני של כל ה-DB; temp_store=MEMORY (שחיבורי הקריאה
  // מגדירים) היה ממקם אותו ב-RAM — כגודל הקובץ כולו.
  final previousTempStore = firstIntValue(db.select('PRAGMA temp_store')) ?? 0;
  db.execute('PRAGMA temp_store=FILE');
  try {
    db.execute('VACUUM');
    // ב-WAL תוצאת ה-VACUUM יושבת ביומן; בלי checkpoint הקובץ הראשי נשאר
    // בגודלו הקודם והכיווץ לא נראה כלל.
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    db.execute('PRAGMA temp_store=$previousTempStore');
  }
  return true;
}

/// Runs [fn] inside an explicit SQLite transaction.
/// Commits on success, rolls back on error.
void withTransaction(Database db, void Function() fn) {
  db.execute('BEGIN');
  try {
    fn();
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
