import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/data/constants/database_constants.dart';

/// קריאת גרסת הספרייה מהמסד
class DataCollectionService {
  DataCollectionService({
    @visibleForTesting String? Function(String dbPath)? versionQuery,
  }) : _versionQuery = versionQuery ?? _readDbVersion;

  /// חייבת להיות sendable: היא רצה ב-isolate.
  final String? Function(String dbPath) _versionQuery;

  /// Read library version from the database (schema_meta).
  /// Returns "unknown" if not found or cannot be read.
  ///
  /// [databasePath] — נתיב ה-DB לקריאה. ברירת המחדל נגזרת מ-Settings.
  Future<String> readLibraryVersion({String? databasePath}) async {
    try {
      // הבדיקה על הנתיב שנפתח כאן ולא על SqliteDataProvider, שה-_dbPath שלו
      // מאוכלס רק ב-initialize() — תהליך headless לא מאתחל אותו.
      final dbPath = databasePath ?? DatabaseConstants.getDatabasePath();
      if (!await File(dbPath).exists()) return 'unknown';
      final query = _versionQuery;
      // פתיחת המסד חוסמת, וב-Windows ה-UI isolate הוא ה-platform thread.
      final version = await Isolate.run(() => query(dbPath));
      // גרסת הספרייה מגיעה רק מ-schema_meta; קובץ "גירסת ספריה.txt" הוסר ב-v3.
      return version ?? 'unknown';
    } catch (e) {
      debugPrint('Error reading library version: $e');
      return 'unknown';
    }
  }

  /// קורא את `schema_meta.db_version`; null כשהוא חסר או לא קריא.
  static String? _readDbVersion(String dbPath) {
    sqlite3.Database? db;
    try {
      // קריאה בלבד — נפתח read-only כדי לתמוך ב-seforim.db על מדיה
      // לקריאה-בלבד ולא ליצור קובצי WAL צדדיים.
      db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      final result = db.select(
        'SELECT value FROM schema_meta WHERE key = ? LIMIT 1',
        ['db_version'],
      );
      if (result.isEmpty) return null;
      final version = result.first['value']?.toString();
      if (version == null || version.isEmpty) return null;
      debugPrint('Library version from schema_meta: $version');
      return version;
    } catch (e) {
      debugPrint('Error reading library version from schema_meta: $e');
      return null;
    } finally {
      db?.close();
    }
  }
}
