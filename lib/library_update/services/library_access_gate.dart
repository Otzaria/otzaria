import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// החלפת המסד לא התחילה, כי החלפה אחרת כבר רצה. הספרייה נשארה פתוחה.
class LibrarySuspendFailed implements Exception {
  const LibrarySuspendFailed(this.message);

  final String message;

  @override
  String toString() => 'LibrarySuspendFailed: $message';
}

/// מסד הספרייה עדיין פתוח בתהליך אחרי שהחיבורים שלו נסגרו.
class LibraryStillOpenException implements Exception {
  const LibraryStillOpenException(this.path, this.detail);

  final String path;
  final String detail;

  @override
  String toString() =>
      'LibraryStillOpenException: $path is still open in this process '
      '($detail)';
}

/// הסגירה והפתיחה-מחדש של הספרייה.
class LibraryAccessRoutine {
  const LibraryAccessRoutine({required this.suspend, required this.resume});

  /// חייב לחזור רק אחרי שכל ה-handles נסגרו בפועל, ולזרוק אם לא.
  final Future<void> Function() suspend;
  final Future<void> Function(bool dbReplaced) resume;
}

/// החלפה פעילה שהוחזרה מ-[LibraryAccessGate.suspendAll].
class LibrarySuspension {
  LibrarySuspension._();

  bool _resumed = false;
}

/// מאפשר ל-[LibraryAccessGate.runExclusive] לדעת אם המסד הוחלף.
class LibraryExclusiveScope {
  LibraryExclusiveScope._();

  bool _dbReplaced = false;

  bool get dbReplaced => _dbReplaced;

  /// לקרוא מיד אחרי נקודת האל-חזור (למשל ה-rename), כדי שהקורא ירענן.
  void markDbReplaced() => _dbReplaced = true;
}

/// מבטיח שמסד הספרייה סגור בתהליך בזמן שמחליפים אותו, ושרק החלפה אחת רצה.
///
/// כל החלונות הם תצוגות באותו isolate וחולקים חיבור SQLite אחד, ולכן די
/// לסגור אותו ([SqliteDataProvider.closeForExternalWrite]). קוראים שמבקשים את
/// המסד בזמן ההחלפה ממתינים בשער הכתיבה החיצונית של ה-provider.
///
/// שימוש:
/// ```dart
/// await LibraryAccessGate.instance.runExclusive(
///   dbPath: dbPath,
///   body: (scope) async {
///     File(newDbPath).renameSync(dbPath);
///     scope.markDbReplaced();
///   },
/// );
/// ```
/// זורק [LibrarySuspendFailed] או [LibraryStillOpenException] לפני ש-body
/// רץ, ואז הספרייה כבר פתוחה שוב. לא רה-אנטרנטי.
class LibraryAccessGate {
  LibraryAccessGate({
    LibraryAccessRoutine? selfAccess,
    bool? renameProbe,
    void Function(String title, Object error, StackTrace? stackTrace)? logError,
  }) : _logError = logError ?? _appendToErrorLog,
       selfAccess = selfAccess ?? _sqliteSelfAccess,
       _renameProbe = renameProbe ?? Platform.isWindows;

  static LibraryAccessGate instance = LibraryAccessGate();

  final LibraryAccessRoutine selfAccess;
  final bool _renameProbe;
  final void Function(String title, Object error, StackTrace? stackTrace)
  _logError;

  static void _appendToErrorLog(
    String title,
    Object error,
    StackTrace? stackTrace,
  ) {
    try {
      ErrorLogFile.appendInBackground(
        title: 'Library access gate: $title',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}
  }

  static final LibraryAccessRoutine _sqliteSelfAccess = LibraryAccessRoutine(
    suspend: () => SqliteDataProvider.instance.closeForExternalWrite(),
    // הרענון אחרי החלפה נעשה אצל הקורא, עם דיווח ההתקדמות שלו.
    resume: (_) => SqliteDataProvider.instance.reopenAfterExternalWrite(),
  );

  LibrarySuspension? _active;

  /// האם החלפה עדיין פעילה.
  bool get isSuspending => _active != null;

  /// מסמן החלפה פעילה; אינו סוגר את המסד — זה תפקיד [selfAccess] / הקורא.
  ///
  /// זורק [LibrarySuspendFailed] כשהחלפה אחרת (גם מחלון אחר) עדיין רצה.
  Future<LibrarySuspension> suspendAll() async {
    if (_active != null) {
      throw const LibrarySuspendFailed(
        'מסד הספרייה כבר מוחלף בחלון אחר. נסו שוב בעוד רגע.',
      );
    }
    SqliteDataProvider.instance.libraryReplacing = true;
    return _active = LibrarySuspension._();
  }

  /// מסיים את ההחלפה. [dbReplaced] — תוצאתה. אידמפוטנטי ואינו זורק.
  Future<void> resumeAll(
    LibrarySuspension suspension, {
    required bool dbReplaced,
  }) async {
    if (suspension._resumed) return;
    suspension._resumed = true;
    if (identical(_active, suspension)) {
      _active = null;
      SqliteDataProvider.instance.libraryReplacing = false;
    }
  }

  /// זורק [LibraryStillOpenException] אם [dbPath] עדיין פתוח בתהליך.
  ///
  /// ב-Windows נבדק ב-rename שמוחזר מיד, כי SQLite פותח בלי FILE_SHARE_DELETE.
  Future<void> verifyReleased(String dbPath) async {
    if (!_renameProbe) return;
    final file = File(dbPath);
    if (!file.existsSync()) return;
    final probePath = '$dbPath.release-probe';
    try {
      file.renameSync(probePath);
    } on FileSystemException catch (error) {
      _log('verify failed', '$dbPath rename probe: $error');
      throw LibraryStillOpenException(dbPath, 'rename probe: ${error.message}');
    }
    await _restoreProbe(probePath, dbPath);
  }

  Future<void> _restoreProbe(String probePath, String dbPath) async {
    FileSystemException? last;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        File(probePath).renameSync(dbPath);
        return;
      } on FileSystemException catch (error) {
        last = error;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    _log('probe restore failed', '$probePath -> $dbPath: $last');
    throw StateError('מסד הספרייה נשאר בשם $probePath: $last');
  }

  /// סוגר את המסד, מאמת שהוא שוחרר, ומריץ את [body].
  ///
  /// בכל יציאה הספרייה נפתחת מחדש, עם [LibraryExclusiveScope.dbReplaced]
  /// כתוצאה. rollback הוא באחריות [body].
  Future<T> runExclusive<T>({
    required String dbPath,
    required Future<T> Function(LibraryExclusiveScope scope) body,
  }) async {
    final suspension = await suspendAll();
    final scope = LibraryExclusiveScope._();
    try {
      await selfAccess.suspend();
      try {
        await verifyReleased(dbPath);
        return await body(scope);
      } finally {
        await selfAccess.resume(scope.dbReplaced);
      }
    } finally {
      await resumeAll(suspension, dbReplaced: scope.dbReplaced);
    }
  }

  void _log(String title, Object? error, [StackTrace? stackTrace]) {
    debugPrint('[LibraryAccessGate] $title: $error');
    _logError(title, error ?? '', stackTrace);
  }
}
