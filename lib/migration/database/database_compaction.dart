import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;

import 'daos/database.dart';
import 'sql/sqlite3_utils.dart';

/// כיווץ כותב את כל הקובץ מחדש, ולכן רץ רק כשיש מה להרוויח: לפחות 1MB
/// פנוי (256 דפים של 4KB) וגם לפחות רבע מהקובץ.
const int _minFreePages = 256;
const double _minFreeRatio = 0.25;
const int _minCompactableBytes = _minFreePages * 4096;

/// מכווץ את קובץ ה-DB של [database] אם יש מה להרוויח; מחזיר האם כווץ בפועל.
///
/// חיבור read-only חוזר מיד. `seforim.db` נפתח תמיד read-only, ולכן לעולם
/// לא ייכתב מכאן.
Future<bool> compactDatabaseIfFragmented(MyDatabase database) async {
  if (database.isReadOnly) return false;

  final fileBytes = await _fileSizeOrZero(database.path);
  if (fileBytes < _minCompactableBytes) return false;
  // בדיקה זולה על החיבור הפתוח, לפני spawn של isolate.
  if (!needsCompaction(await database.database, fileBytes)) return false;

  return compactSqliteFile(database.path);
}

/// מכווץ את קובץ ה-SQLite שב-[dbPath]; מחזיר האם הקובץ על הדיסק אכן קטן.
///
/// ה-VACUUM רץ ב-isolate נפרד: הוא סינכרוני, ועל קובץ של מאות MB היה מקפיא
/// את ה-UI. אינו יוצר את הקובץ אם אינו קיים.
Future<bool> compactSqliteFile(String dbPath) async {
  if (await _fileSizeOrZero(dbPath) < _minCompactableBytes) return false;
  return Isolate.run(() => _compactFile(dbPath));
}

/// האם שווה לכווץ את [db]. [fileBytes] הוא גודל הקובץ על הדיסק.
///
/// שני מצבים מזכים בכיווץ:
/// - הצטברו מספיק דפים פנויים (מחיקות שלא הוקטנו).
/// - הקובץ גדול מהתוכן הלוגי — סימן ל-VACUUM קודם שה-checkpoint שלו נחסם
///   על ידי קורא. במצב הזה ה-freelist כבר ריק, ולכן בלי הבדיקה הזו הקובץ
///   היה נשאר גדול לנצח.
bool needsCompaction(sqlite3.Database db, int fileBytes) {
  final pageSize = firstIntValue(db.select('PRAGMA page_size')) ?? 4096;
  final pageCount = firstIntValue(db.select('PRAGMA page_count')) ?? 0;
  final freePages = firstIntValue(db.select('PRAGMA freelist_count')) ?? 0;

  if (fileBytes - pageCount * pageSize >= _minCompactableBytes) return true;

  return freePages >= _minFreePages && freePages >= pageCount * _minFreeRatio;
}

/// גוף הכיווץ — רץ ב-isolate של [compactSqliteFile].
///
/// פותח חיבור משלו ב-sqlite3 גולמי, בלי סכמה ובלי DAOs, כדי שלא יידרש
/// QueryLoader (שנשען על assets ואינו זמין ב-isolate נקי).
bool _compactFile(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    // חיבורים אחרים מחזיקים את הקובץ פתוח; בלי המתנה על הנעילה הכיווץ היה
    // נכשל בכל פעם שמישהו קורא במקביל.
    db.execute('PRAGMA busy_timeout=5000');

    if (!needsCompaction(db, File(dbPath).lengthSync())) return false;

    // VACUUM בונה עותק זמני של כל ה-DB; temp_store=MEMORY (ברירת מחדל
    // בחלק מהבילדים) היה ממקם אותו ב-RAM — כגודל הקובץ כולו.
    db.execute('PRAGMA temp_store=FILE');
    db.execute('VACUUM');
    return _truncateWal(db);
  } catch (_) {
    // כיווץ הוא אופטימיזציה בלבד — כשל (נעילה, אין מקום בדיסק) לא אמור
    // להפיל את הפעולה שקראה לו.
    return false;
  } finally {
    db.close();
  }
}

/// מרוקן את יומן ה-WAL לתוך הקובץ הראשי; מחזיר האם הושלם.
///
/// בלי זה תוצאת ה-VACUUM נשארת ביומן והקובץ הראשי לא מתכווץ כלל. ה-PRAGMA
/// אינו זורק כשקורא מקביל חוסם אותו — הוא מחזיר busy=1 בעמודה הראשונה,
/// ולכן חובה לבדוק את התוצאה ולא להניח הצלחה.
bool _truncateWal(sqlite3.Database db) {
  final result = db.select('PRAGMA wal_checkpoint(TRUNCATE)');
  if (result.isEmpty) return true;
  return (result.first.values.first as int? ?? 0) == 0;
}

Future<int> _fileSizeOrZero(String path) async {
  final file = File(path);
  return await file.exists() ? file.length() : 0;
}
