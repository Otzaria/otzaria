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
    hardenUntrustedConnection(db);
    db.execute('PRAGMA query_only=ON');
    // קובץ בכונן נשלף/רשת: שגיאת I/O על mmap היא אות שמפיל את התהליך.
    db.execute('PRAGMA mmap_size=0');
  } catch (_) {
    db.close();
    rethrow;
  }
  return db;
}

/// מסד לפתיחה read-only ב-isolate — ערכים פשוטים בלבד, כך שעובר את גבול
/// ה-isolate. [untrusted]: מסד מצורף, נפתח דרך [openUntrustedReadOnlyDatabase].
typedef ReadOnlyDbTarget = ({String path, bool untrusted, bool immutable});

/// יעד למסד שבשליטת התוכנה (seforim.db).
ReadOnlyDbTarget trustedDbTarget(String path) =>
    (path: path, untrusted: false, immutable: false);

/// פותח את [target] לקריאה בלבד: מסד מצורף — מוקשח, אחרת פתיחה רגילה.
Database openReadOnlyTarget(ReadOnlyDbTarget target) => target.untrusted
    ? openUntrustedReadOnlyDatabase(target.path, immutable: target.immutable)
    : sqlite3.open(target.path, mode: OpenMode.readOnly);

/// מקשיח חיבור קיים למסד שאינו בשליטת התוכנה: defensive, בלי סכמה "מהימנה"
/// ובלי טעינת הרחבות. חל גם על חיבור כתיבה (החלת יומן על עותק מיובא).
void hardenUntrustedConnection(Database db) {
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
}

/// ה-URI של [path] לפתיחה immutable. תווים שאינם ASCII מקודדים ב-%HH,
/// ו-SQLite מפענח אותם.
String immutableDatabaseUri(String path) => Uri.file(
  path,
).replace(queryParameters: {'mode': 'ro', 'immutable': '1'}).toString();
