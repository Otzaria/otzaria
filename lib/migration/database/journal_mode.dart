import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/sqlite/sqlite3_api.dart' show sqlite3;
import 'package:otzaria/migration/database/untrusted_database.dart';

const List<int> _sqliteMagic = [
  0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
  0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
];

/// כותרת קובץ SQLite: האם זה מסד SQLite, והאם הוא במצב WAL.
typedef SqliteHeaderInfo = ({bool isSqlite, bool isWal});

/// קורא את 100 בתי הכותרת בלבד — בלי לפתוח חיבור ובלי לכתוב.
SqliteHeaderInfo readSqliteHeaderSync(String dbPath) {
  final raf = File(dbPath).openSync();
  try {
    final header = raf.readSync(100);
    if (header.length < 100) return (isSqlite: false, isWal: false);
    for (var i = 0; i < _sqliteMagic.length; i++) {
      if (header[i] != _sqliteMagic[i]) return (isSqlite: false, isWal: false);
    }
    // בתים 18/19 (גרסת כתיבה/קריאה): 1 = יומן rollback, 2 = WAL.
    return (isSqlite: true, isWal: header[18] == 2 || header[19] == 2);
  } finally {
    raf.closeSync();
  }
}

/// האם לצד [dbPath] יש יומן שטרם הוחל: `-wal` לא ריק, או `-journal` "חם"
/// שנשאר מכתיבה שנקטעה. פתיחה read-only אינה יכולה להחיל אף אחד מהם.
bool hasPendingJournalSync(String dbPath) {
  bool nonEmpty(String path) {
    final file = File(path);
    return file.existsSync() && file.lengthSync() > 0;
  }

  return nonEmpty('$dbPath-wal') || nonEmpty('$dbPath-journal');
}

/// מעביר את [dbPath] ליומן DELETE ומחיל יומן חם, כדי שייפתח read-only בלי
/// קובצי-צד. פותח חיבור כתיבה — רק לקובץ שבבעלות התוכנה. נכשל בשקט.
///
/// [untrusted] — קובץ שמקורו מחוץ לתוכנה (עותק של מסד מצורף): החיבור מוקשח
/// לפני הגישה הראשונה, שמריצה את ה-rollback.
Future<void> normalizeJournalModeForReadOnly(
  String dbPath, {
  bool untrusted = false,
}) async {
  try {
    final file = File(dbPath);
    if (!await file.exists()) return;

    bool isWal;
    final raf = await file.open();
    try {
      await raf.setPosition(18);
      final header = await raf.read(2);
      isWal = header.length == 2 && (header[0] == 2 || header[1] == 2);
    } finally {
      await raf.close();
    }

    final journal = File('$dbPath-journal');
    final hasHotJournal =
        await journal.exists() && (await journal.length()) > 0;
    if (!isWal && !hasHotJournal) return;

    // הגישה הראשונה בחיבור כתיבה מריצה את ה-rollback של יומן חם.
    final db = sqlite3.open(dbPath);
    try {
      if (untrusted) hardenUntrustedConnection(db);
      try {
        db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}
      db.execute('PRAGMA journal_mode=DELETE');
    } finally {
      db.close();
    }
  } catch (e) {
    debugPrint(
      '[journal_mode] Could not normalise journal mode of $dbPath '
      '(directory may be read-only): $e',
    );
  }
}
