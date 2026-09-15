import 'package:flutter/foundation.dart';
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

/// סוגר חיבור כתיבה אחרי מיזוג ה-WAL לקובץ הראשי. בלי המיזוג, חיבור פתוח
/// של חלון מוסתר הופך את הסגירה ללא-אחרונה, והשינויים נשארים בקובץ ה-WAL.
void closeWithCheckpoint(Database db) {
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {}
  db.close();
}

/// מפעיל WAL כשאפשר, ולא מפיל את פתיחת ה-DB כשלא.
///
/// המעבר ל-WAL קוטם את קובץ ה-journal, וקטימה חסומה (נעילה שנשארה מסגירה
/// כפויה, אנטי-וירוס) אינה סיבה שכל התכונה לא תעלה: ה-DB נשאר שמיש במצב
/// ה-journal הקיים. [label] מזהה את הקורא בלוג.
void enableWalBestEffort(Database db, String label) {
  try {
    db.execute('PRAGMA journal_mode=WAL');
  } catch (e) {
    debugPrint('[$label] journal_mode=WAL failed: $e');
  }
}
