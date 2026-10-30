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

const _sqliteDbConfigNoCheckpointOnClose = 1006;

/// כמו [closeWithCheckpoint], אבל המיזוג רץ ב-isolate: fsync איטי או נעילה
/// של כותב אחר תוקעים אותו לשניות. החיבור עצמו נסגר כאן, בלי מיזוג.
Future<void> closeWithCheckpointInBackground(Database db, String path) async {
  try {
    db.config.setIntConfig(_sqliteDbConfigNoCheckpointOnClose, 1);
  } catch (_) {
    closeWithCheckpoint(db);
    return;
  }
  db.close();
  try {
    await compute(_checkpointAndClose, path, debugLabel: 'WalCheckpoint');
  } catch (e) {
    debugPrint('[WalCheckpoint] $path: $e');
  }
}

void _checkpointAndClose(String path) =>
    closeWithCheckpoint(openSecondaryWritableConnection(path, 'WalCheckpoint'));

/// פותח DB כתיב עם הכוונון האחיד לכל מסדי הנתונים של האפליקציה: המתנה
/// לנעילה, ו-WAL כשהאחסון תומך בו. [label] מזהה את הקורא בלוג.
Database openWritableDatabase(
  String path,
  String label, {
  int busyTimeoutMs = 5000,
}) {
  final db = sqlite3.open(path);
  _setBusyTimeout(db, label, busyTimeoutMs);
  if (enableWalBestEffort(db, label)) return db;
  db.close();
  return _openInRollbackJournal(path, label, busyTimeoutMs);
}

/// חיבור נוסף למסד ש-[openWritableDatabase] כבר הכין: בלי בדיקת WAL, שנכשלת
/// מול כותב אחר ומשאירה את החיבור ב-fsync מלא.
Database openSecondaryWritableConnection(
  String path,
  String label, {
  int busyTimeoutMs = 5000,
}) {
  final db = sqlite3.open(path);
  _setBusyTimeout(db, label, busyTimeoutMs);
  _relaxSyncIfWal(db, label);
  return db;
}

void _setBusyTimeout(Database db, String label, int busyTimeoutMs) {
  try {
    // המתנה במקום כישלון מיידי ב-SQLITE_BUSY: מופע שני של התוכנה או נעילה
    // שנשארה מסגירה כפויה היו מפילים את ה-DDL הראשון.
    db.execute('PRAGMA busy_timeout=$busyTimeoutMs');
  } catch (e) {
    debugPrint('[$label] busy_timeout failed: $e');
  }
}

/// מנסה להפעיל WAL; מחזיר `false` כשכשל באחסון מצריך ניסיון פתיחה
/// מחדש ב-journal רגיל. כשל חולף אינו משנה את החיבור.
bool enableWalBestEffort(Database db, String label) {
  try {
    db.execute('PRAGMA journal_mode=WAL');
    _probeWalWriteWithoutWaiting(db);
  } catch (e) {
    debugPrint('[$label] journal_mode=WAL failed: $e');
    // רק כשל של האחסון מעיד על WAL שאינו שמיש. BUSY וכשלים חולפים לא, ופתיחה
    // מחדש בגללם הייתה נתקעת בנעילה של חיבור אחר ונשארת ב-EXCLUSIVE.
    if (e is! SqliteException) return true;
    return e.resultCode != SqlError.SQLITE_IOERR &&
        e.resultCode != SqlError.SQLITE_CANTOPEN &&
        e.resultCode != SqlError.SQLITE_READONLY;
  }
  _relaxSyncIfWal(db, label);
  return true;
}

// קריאה עשויה להצליח גם כש-shm אינו כתיב. בודקים כתיבה ללא המתנה
// כדי שחיבור אחר שכותב לא יעכב את הפתיחה; ROLLBACK אינו משנה נתונים.
void _probeWalWriteWithoutWaiting(Database db) {
  final timeout = firstIntValue(db.select('PRAGMA busy_timeout'))!;
  try {
    db.execute('PRAGMA busy_timeout=0');
    db.execute('BEGIN IMMEDIATE');
    db.execute('ROLLBACK');
  } finally {
    db.execute('PRAGMA busy_timeout=$timeout');
  }
}

/// NORMAL חוסך fsync בכל commit, ורק ב-WAL הוא לא משחית את המסד: בנפילת
/// חשמל לכל היותר הטרנזקציה האחרונה אובדת. ב-journal רגיל נשאר FULL.
void _relaxSyncIfWal(Database db, String label) {
  try {
    final mode = db.select('PRAGMA journal_mode').first.values.first;
    if (mode == 'wal') db.execute('PRAGMA synchronous=NORMAL');
  } catch (e) {
    debugPrint('[$label] synchronous=NORMAL failed: $e');
  }
}

/// משחרר את מטמון הדפים של חיבור שכבר פתוח; `false` כשאין חיבור.
bool shrinkMemoryBestEffort(Database? db) {
  if (db == null) return false;
  try {
    db.releaseMemory();
    return true;
  } catch (_) {
    return false;
  }
}

/// חיבור שכבר נכשל בפתיחת ה-shm אינו מצליח לעזוב WAL. חיבור טרי שננעל
/// בלעדית לפני הגישה הראשונה עוזב אותו בלי shm, ואז חוזר לנעילה רגילה.
Database _openInRollbackJournal(String path, String label, int busyTimeoutMs) {
  final db = sqlite3.open(path);
  _setBusyTimeout(db, label, busyTimeoutMs);
  try {
    db.execute('PRAGMA locking_mode=EXCLUSIVE');
    db.execute('PRAGMA journal_mode=DELETE');
    db.execute('PRAGMA locking_mode=NORMAL');
    // הנעילה הבלעדית משתחררת רק בגישה הבאה; בלעדיה חיבור אחר ממתין לה.
    db.execute('SELECT count(*) FROM sqlite_schema');
  } catch (e) {
    debugPrint('[$label] fallback to rollback journal failed: $e');
    // המרה שנכשלה אינה מתירה להשאיר חיבור שעלול לנעול את שאר הקוראים.
    db.close();
    final normal = sqlite3.open(path);
    _setBusyTimeout(normal, label, busyTimeoutMs);
    return normal;
  }
  return db;
}
