import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/user_content_import/services/user_link_ref_resolver.dart';
import 'package:otzaria/utils/file/text_encoding.dart';

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

  /// תלויות פתירת-הספרים של הייבוא, להזרקה בבדיקות. בלי הזרקה הפתירה
  /// האמיתית רצה ב-isolate ([UserContentImporter.ingestContentsInBackground]).
  final UserLinkRefResolver? resolveRef;
  final UserLinkSourceChecker? sourceExists;
  final UserLinkBookLocator? locateBook;

  const UserImportLibrary(
    this._db, {
    this.resolveRef,
    this.sourceExists,
    this.locateBook,
  });

  Future<T> _serial<T>(Future<T> Function() action) =>
      DatabaseLibraryProvider.operationQueue.enqueue(action);

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
        return _changeAndRebuild(() async {
          final db = await _db.database;
          if (db.select('SELECT 1 FROM user_import_file LIMIT 1').isEmpty) {
            await UserContentRepository(_db).captureManualBaseline();
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
        });
      });

  Future<
    List<({String name, String path, UserImportKind kind, String content})>
  >
  _readFiles(
    Iterable<String> filePaths,
    List<String> errors,
  ) async {
    final files =
        <({String name, String path, UserImportKind kind, String content})>[];
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
  Future<UserImportLibraryResult> _changeAndRebuild(
    Future<void> Function() change,
  ) async {
    final db = await _db.database;
    final files = await _inSavepoint(db, () async {
      await change();
      return _enabledFiles(db);
    }, commit: false);
    final ingest = files.isEmpty ? null : await _ingest(files);
    if (ingest != null && ingest.errors.isNotEmpty) {
      return UserImportLibraryResult(
        rebuild: const UserImportResult(),
        errors: ingest.errors,
      );
    }
    final rebuild = await _inSavepoint(db, () async {
      await change();
      final repo = UserContentRepository(_db);
      await repo.clearAllUserContent();
      await repo.restoreManualBaseline();
      return ingest == null
          ? const UserImportResult()
          : await UserContentImporter.applyIngest(ingest, _db);
    }, commit: true);
    return UserImportLibraryResult(rebuild: rebuild);
  }

  static Future<T> _inSavepoint<T>(
    sqlite3.Database db,
    Future<T> Function() action, {
    required bool commit,
  }) async {
    db.execute('SAVEPOINT user_import_library_change');
    try {
      final result = await action();
      if (!commit) db.execute('ROLLBACK TO user_import_library_change');
      db.execute('RELEASE user_import_library_change');
      return result;
    } catch (_) {
      db.execute('ROLLBACK TO user_import_library_change');
      db.execute('RELEASE user_import_library_change');
      rethrow;
    }
  }

  /// משהה או מחזיר קובץ. השהיה אינה מוחקת אותו — התוכן נשאר לייצוא ולהחזרה.
  Future<UserImportLibraryResult> setEnabled(int id, bool enabled) => _serial(
    () => _changeAndRebuild(() async {
      final db = await _db.database;
      db.execute('UPDATE user_import_file SET enabled = ? WHERE id = ?', [
        enabled ? 1 : 0,
        id,
      ]);
    }),
  );

  /// מסיר קובץ מהספרייה לצמיתות, והנתונים שלו יורדים איתו בבנייה מחדש.
  Future<UserImportLibraryResult> remove(int id) => _serial(
    () => _changeAndRebuild(() async {
      final db = await _db.database;
      db.execute('DELETE FROM user_import_file WHERE id = ?', [id]);
    }),
  );

  /// מסיר את כל הקבצים ומנקה את כל הנתונים הידניים, גם אלה שקדמו לספרייה.
  Future<UserImportLibraryResult> removeAll() => _serial(
    () => _changeAndRebuild(() async {
      final db = await _db.database;
      db.execute('DELETE FROM user_import_file');
      await UserContentRepository(_db).dropManualBaseline();
    }),
  );

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
