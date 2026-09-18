import 'package:otzaria/data/sqlite/sqlite3_api.dart';

// קבועי sqlite3_db_config — https://www.sqlite.org/c3ref/c_dbconfig_defensive.html
const _kDbConfigEnableLoadExtension = 1005;
const _kDbConfigDefensive = 1010;
const _kDbConfigTrustedSchema = 1017;

/// פותח מסד שאינו בשליטת התוכנה (מסד ספרים מצורף) לקריאה בלבד ומוקשח:
/// query_only, בלי סכמה "מהימנה" (VIEW/טריגר לא יריצו פונקציות לא-תמימות),
/// מצב defensive ובלי טעינת הרחבות.
///
/// [immutable] פותח ב-URI עם `immutable=1`: SQLite לא ייגש לקובצי-צד ולא
/// ינעל — לתיקייה שאין בה הרשאת כתיבה או למסד במצב WAL.
Database openUntrustedReadOnlyDatabase(String path, {bool immutable = false}) {
  final db = immutable
      ? sqlite3.open(
          immutableDatabaseUri(path),
          mode: OpenMode.readOnly,
          uri: true,
        )
      : sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    for (final (key, value) in const [
      (_kDbConfigDefensive, 1),
      (_kDbConfigTrustedSchema, 0),
      (_kDbConfigEnableLoadExtension, 0),
    ]) {
      try {
        db.config.setIntConfig(key, value);
      } on Object {
        // גרסת SQLite שאינה מכירה את האפשרות — ה-PRAGMA שלמטה עדיין חל.
      }
    }
    db.execute('PRAGMA trusted_schema=OFF');
    db.execute('PRAGMA query_only=ON');
    // קובץ בכונן נשלף/רשת: שגיאת I/O על mmap היא אות שמפיל את התהליך.
    db.execute('PRAGMA mmap_size=0');
  } catch (_) {
    db.close();
    rethrow;
  }
  return db;
}

/// ה-URI של [path] לפתיחה immutable. תווים שאינם ASCII מקודדים ב-%HH,
/// ו-SQLite מפענח אותם.
String immutableDatabaseUri(String path) => Uri.file(
  path,
).replace(queryParameters: {'mode': 'ro', 'immutable': '1'}).toString();
