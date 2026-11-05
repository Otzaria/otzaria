import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/user_content_import/services/user_link_ref_resolver.dart';
import 'package:otzaria/utils/file/text_encoding.dart';

/// שינוי בספרייה, מוחל ב-isolate על חיבור משלו. נבנה בפונקציה סטטית: סגירה
/// שלוכדת את המופע אינה נשלחת בין isolates.
typedef _Change = Future<void> Function(MyDatabase userDb);

typedef _ReadFile = ({
  String name,
  String path,
  UserImportKind kind,
  String content,
});

/// קובץ ייבוא ששמור בספרייה, כפי שהוא מוצג בהגדרות.
@immutable
class UserImportFile {
  final int id;

  /// שם הקובץ — הוא שקובע איך הוא מפוענח, ולכן מוצג כזהות.
  final String name;

  /// הנתיב שממנו יובא, לתצוגה בלבד; הקובץ עצמו כבר לא נדרש קיים.
  final String? originPath;
  final UserImportKind kind;

  /// קובץ מושהה נשאר בספרייה אך אינו משתתף בבנייה.
  final bool enabled;
  final DateTime importedAt;

  const UserImportFile({
    required this.id,
    required this.name,
    required this.originPath,
    required this.kind,
    required this.enabled,
    required this.importedAt,
  });
}

/// תוצאת פעולה על הספרייה: מה נבנה מחדש ואילו שגיאות עלו בדרך.
@immutable
class UserImportLibraryResult {
  final UserImportResult rebuild;
  final List<String> errors;

  const UserImportLibraryResult({
    required this.rebuild,
    this.errors = const [],
  });

  bool get ok => errors.isEmpty && rebuild.errors.isEmpty;

  List<String> get allErrors => [...errors, ...rebuild.errors];
}

/// קובצי הייבוא נשמרים על תוכנם, וכל שינוי בונה מחדש מכלל הפעילים — כך ייצוא
/// והשהיה אינם דורשים מעקב פר-שורה, והמקור יכול להימחק או לזוז.
class UserImportLibrary {
  final MyDatabase _db;
  final UserBooksDatabaseHolder? _holder;

  /// תלויות פתירת-הספרים של הייבוא, להזרקה בבדיקות. בלי הזרקה הפתירה
  /// האמיתית רצה ב-isolate ([UserContentImporter.ingestContentsInBackground]).
  final UserLinkRefResolver? resolveRef;
  final UserLinkSourceChecker? sourceExists;
  final UserLinkBookLocator? locateBook;

  UserImportLibrary(
    this._db, {
    this.resolveRef,
    this.sourceExists,
    this.locateBook,
  }) : _holder =
           identical(
             UserBooksDatabaseHolder.instance.repositoryIfInitialized?.database,
             _db,
           )
           ? UserBooksDatabaseHolder.instance
           : null;

  Future<T> _serial<T>(Future<T> Function() action) =>
      DatabaseLibraryProvider.operationQueue.enqueue(() async {
        final holder = _holder;
        if (holder == null) return action();
        final cancelled = StateError('ספריית המשתמש נסגרת או הוחלפה; נסו שוב.');
        if (!identical(holder.repositoryIfInitialized?.database, _db)) {
          throw cancelled;
        }
        Future<T>? pending;
        // נרשמים רק בראש התור: close שבתור אינו יכול להמתין לפעולה שמאחוריו.
        await holder.trackRead(() async {
          pending = action();
          await pending;
        });
        return pending ?? (throw cancelled);
      });

  /// כל קובצי הייבוא, החדש תחילה, בלי התוכן — הוא נשלף רק בייצוא.
  Future<List<UserImportFile>> list() => _serial(() async {
    final db = await _db.database;
    final rows = db.select(
      'SELECT id, name, originPath, kind, enabled, importedAt '
      'FROM user_import_file ORDER BY importedAt DESC, id DESC',
    );
    return rows.map(_fromRow).toList();
  });

  /// תוכן הקובץ כפי שיובא, או null אם הוסר בינתיים.
  Future<String?> contentOf(int id) => _serial(() async {
    final db = await _db.database;
    final rows = db.select(
      'SELECT content FROM user_import_file WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first['content'] as String;
  });

  /// שומר ובונה מחדש; אותו שם ומקור דורס את קודמו.
  Future<UserImportLibraryResult> addFiles(Iterable<String> filePaths) =>
      _serial(() async {
        final errors = <String>[];
        final files = await _readFiles(filePaths, errors);
        if (errors.isNotEmpty) {
          return UserImportLibraryResult(
            rebuild: const UserImportResult(),
            errors: errors,
          );
        }
        return _changeAndRebuild(_insertFiles(files));
      });

  static _Change _insertFiles(List<_ReadFile> files) => (userDb) async {
    final db = await userDb.database;
    if (db.select('SELECT 1 FROM user_import_file LIMIT 1').isEmpty) {
      await UserContentRepository(userDb).captureManualBaseline();
    }
    for (final file in files) {
      db.execute(
        'INSERT INTO user_import_file '
        '(name, originPath, kind, content, enabled, importedAt) '
        'VALUES (?, ?, ?, ?, 1, ?) '
        'ON CONFLICT(name, originPath) DO UPDATE SET '
        'kind = excluded.kind, content = excluded.content, '
        'enabled = 1, importedAt = excluded.importedAt',
        [
          file.name,
          file.path,
          file.kind.name,
          file.content,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
    }
  };

  Future<List<_ReadFile>> _readFiles(
    Iterable<String> filePaths,
    List<String> errors,
  ) async {
    final files = <_ReadFile>[];
    for (final path in filePaths) {
      final file = File(path);
      final name = _baseName(path);
      if (!await file.exists()) {
        errors.add('$name: הקובץ לא נמצא');
        continue;
      }
      final kind = UserContentImporter.kindOf(name);
      if (kind == null) {
        errors.add('$name: $kUnrecognizedImportFileMessage');
        continue;
      }
      final String content;
      try {
        content = await readTextFileSmart(file);
      } catch (e) {
        errors.add('$name: קריאת הקובץ נכשלה ($e)');
        continue;
      }
      files.add((name: name, path: path, kind: kind, content: content));
    }
    return files;
  }

  /// שינוי ובנייה מחדש נכתבים יחד, כולל טבלאות הבסיס הידני. הפענוח ארוך ורץ
  /// בלי טרנזקציה פתוחה, ולכן השינוי מוחל פעם כדי לדעת מה ייבנה ופעם לכתיבה.
  Future<UserImportLibraryResult> _changeAndRebuild(_Change change) async {
    final files = await _onOwnConnection(_enabledFilesAfter(change));
    final ingest = files.isEmpty ? null : await _ingest(files);
    if (ingest != null && ingest.errors.isNotEmpty) {
      return UserImportLibraryResult(
        rebuild: const UserImportResult(),
        errors: ingest.errors,
      );
    }
    final rebuild = await _onOwnConnection(_rebuildWith(change, ingest));
    return UserImportLibraryResult(rebuild: rebuild);
  }

  static Future<List<ImportedFile>> Function(MyDatabase) _enabledFilesAfter(
    _Change change,
  ) =>
      (userDb) => _inTransaction(userDb, () async {
        await change(userDb);
        return _enabledFiles(await userDb.database);
      }, commit: false);

  static Future<UserImportResult> Function(MyDatabase) _rebuildWith(
    _Change change,
    UserImportIngest? ingest,
  ) =>
      (userDb) => _inTransaction(userDb, () async {
        await change(userDb);
        final repo = UserContentRepository(userDb);
        await repo.clearAllUserContent();
        await repo.restoreManualBaseline();
        return ingest == null
            ? const UserImportResult()
            : await UserContentImporter.applyIngest(ingest, userDb);
      }, commit: true);

  /// כתיבה ב-isolate על חיבור משלה: על החיבור הראשי, המתנה לנעילה שמחזיק
  /// חיבור אחר תוקעת את התוכנה עד busy_timeout בכל פקודה (#4106, #4152).
  Future<T> _onOwnConnection<T>(Future<T> Function(MyDatabase) action) async {
    await QueryLoader.initialize();
    return compute(_runOnConnection<T>, (
      dbPath: _db.path,
      queries: QueryLoader.cacheSnapshot,
      action: action,
    ), debugLabel: 'UserImportLibraryWrite');
  }

  static Future<T> _runOnConnection<T>(
    ({
      String dbPath,
      Map<String, Map<String, String>> queries,
      Future<T> Function(MyDatabase) action,
    })
    args,
  ) async {
    QueryLoader.seedCache(args.queries);
    final userDb = MyDatabase.withPath(args.dbPath);
    try {
      return await args.action(userDb);
    } finally {
      userDb.close();
    }
  }

  /// ⚠️ IMMEDIATE: טרנזקציה שקראה לפני שכתבה נכשלת מיד על נעילה של חיבור
  /// אחר, בלי busy_timeout.
  static Future<T> _inTransaction<T>(
    MyDatabase userDb,
    Future<T> Function() action, {
    required bool commit,
  }) async {
    final db = await userDb.database;
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = await action();
      db.execute(commit ? 'COMMIT' : 'ROLLBACK');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// משהה או מחזיר קובץ. השהיה אינה מוחקת אותו — התוכן נשאר לייצוא ולהחזרה.
  Future<UserImportLibraryResult> setEnabled(int id, bool enabled) =>
      _serial(() => _changeAndRebuild(_setFileEnabled(id, enabled)));

  static _Change _setFileEnabled(int id, bool enabled) => (userDb) async {
    (await userDb.database).execute(
      'UPDATE user_import_file SET enabled = ? WHERE id = ?',
      [enabled ? 1 : 0, id],
    );
  };

  /// מסיר קובץ מהספרייה לצמיתות, והנתונים שלו יורדים איתו בבנייה מחדש.
  Future<UserImportLibraryResult> remove(int id) =>
      _serial(() => _changeAndRebuild(_deleteFile(id)));

  static _Change _deleteFile(int id) => (userDb) async {
    (await userDb.database).execute(
      'DELETE FROM user_import_file WHERE id = ?',
      [id],
    );
  };

  /// מסיר את כל הקבצים ומנקה את כל הנתונים הידניים, גם אלה שקדמו לספרייה.
  Future<UserImportLibraryResult> removeAll() => _serial(() async {
    await _onOwnConnection(_removeAllFiles);
    return const UserImportLibraryResult(rebuild: UserImportResult());
  });

  static Future<void> _removeAllFiles(MyDatabase userDb) =>
      _inTransaction(userDb, () async {
        (await userDb.database).execute('DELETE FROM user_import_file');
        final repo = UserContentRepository(userDb);
        await repo.dropManualBaseline();
        await repo.clearAllUserContent();
      }, commit: true);

  static List<ImportedFile> _enabledFiles(sqlite3.Database db) => [
    for (final row in db.select(
      'SELECT name, content FROM user_import_file WHERE enabled = 1 '
      'ORDER BY id',
    ))
      ImportedFile(
        name: row['name'] as String,
        content: row['content'] as String,
      ),
  ];

  Future<UserImportIngest> _ingest(List<ImportedFile> files) {
    if (resolveRef == null && sourceExists == null && locateBook == null) {
      return UserContentImporter.ingestContentsInBackground(files, _db);
    }
    return UserContentImporter.ingestContents(
      files,
      _db,
      resolveRef: resolveRef ?? resolveUserLinkTargetLine,
      sourceExists: sourceExists ?? userLinkSourceBookExists,
      locateBook: locateBook ?? locateUserLinkBook,
    );
  }

  static UserImportFile _fromRow(Map<String, Object?> row) => UserImportFile(
    id: row['id'] as int,
    name: row['name'] as String,
    originPath: row['originPath'] as String?,
    kind: UserImportKind.values.firstWhere(
      (k) => k.name == row['kind'],
      orElse: () => UserImportKind.links,
    ),
    enabled: (row['enabled'] as int? ?? 1) == 1,
    importedAt: DateTime.fromMillisecondsSinceEpoch(
      row['importedAt'] as int? ?? 0,
    ),
  );

  static String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}
