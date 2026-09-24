import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/info/settings_snapshot.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:path/path.dart' as p;

class ErrorReportsCliExitCode {
  static const int success = 0;
  static const int failed = 1;

  /// התור עדיין ב-Hive, ויועבר למסד רק בהפעלה הבאה של אוצריא.
  static const int queueNotMigrated = 2;
  static const int usageError = 64;
}

enum ErrorReportsCliAction { pending, handoff, help }

/// הבקשה שנגזרת מארגומנטי `otzaria reports ...`.
class ErrorReportsCliRequest {
  final ErrorReportsCliAction action;

  /// ב-`pending` — קובץ ה-JSON (ובהיעדרו stdout); ב-`handoff` — תיקיית היעד.
  final String? outPath;

  const ErrorReportsCliRequest(this.action, {this.outPath});
}

/// המיקומים שהמופע הגרפי משתמש בהם. `settingsFound` false = אוצריא לא הופעלה
/// כאן מעולם; `databasePath` null = אין תיקיית מסדים.
typedef ErrorReportsCliPaths = ({
  bool settingsFound,
  bool settingsLoaded,
  String dataRoot,
  String? databasePath,
});

/// פקודת headless שמעבירה את דיווחי הטעויות השמורים ממחשב לא מחובר, בקבצים,
/// למחשב מחובר שישלח אותם לשרת.
///
///     otzaria.exe reports pending --out=count.json  # ספירת התור, בלי שינוי
///     otzaria.exe reports handoff --out=<dir>       # קובץ לכל דיווח
class ErrorReportsCli {
  const ErrorReportsCli._();

  static Future<int> run(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    Future<ErrorReportsCliPaths> Function()? resolvePaths,
  }) async {
    final outSink = out ?? stdout;
    final errSink = err ?? stderr;

    final request = parseArgs(args, errSink);
    if (request == null) return ErrorReportsCliExitCode.usageError;
    if (request.action == ErrorReportsCliAction.help) {
      printUsage(outSink);
      return ErrorReportsCliExitCode.success;
    }

    // stdout של `pending` הוא חוזה מכונה — כל `print` אחר מנותב ל-stderr.
    return runZoned(
      () async {
        UserStateDatabase? database;
        try {
          final paths = await (resolvePaths ?? _resolvePaths)();
          if (paths.settingsFound && !paths.settingsLoaded) {
            errSink.writeln(
              'הגדרות אוצריא לא נקראו, ולכן מיקום התור אינו ידוע.',
            );
            return ErrorReportsCliExitCode.failed;
          }
          // המיגרציה אינה מורצת מכאן: היא משנה שמות קבצים מתחת למופע פתוח.
          final hiveRoot = paths.dataRoot;
          final hiveQueue = File(
            p.join(
              hiveRoot,
              '${DirectErrorReportService.queueBoxName}.hive',
            ),
          );
          if (await hiveQueue.exists()) {
            errSink.writeln(
              'התור עדיין בפורמט הישן: יש לפתוח את אוצריא פעם אחת כדי להעביר '
              'אותו, ולנסות שוב.',
            );
            return ErrorReportsCliExitCode.queueNotMigrated;
          }

          final databasePath = paths.databasePath;
          DirectErrorReportService? reports;
          if (paths.settingsFound &&
              databasePath != null &&
              await File(databasePath).exists()) {
            database = UserStateDatabase.openInSeparateProcess(databasePath);
            reports = DirectErrorReportService(
              reportStore: PendingReportStore(database: database),
            );
          }
          return request.action == ErrorReportsCliAction.pending
              ? await _pending(reports, request.outPath, outSink)
              : await _handoff(reports, request.outPath!, outSink, errSink);
        } catch (error, stackTrace) {
          errSink.writeln('הפעולה על הדיווחים השמורים נכשלה: $error');
          errSink.writeln(stackTrace);
          return ErrorReportsCliExitCode.failed;
        } finally {
          database?.close();
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => errSink.writeln(line),
      ),
    );
  }

  static Future<ErrorReportsCliPaths> _resolvePaths() async {
    // נדרש ל-path_provider — החלון נשאר מוסתר כי main.cpp מזהה את הפקודה.
    WidgetsFlutterBinding.ensureInitialized();
    // תיקיית המסדים נגזרת מההגדרות (ומהמצב הנייד) בדיוק כמו במופע הגרפי.
    final settingsLoaded = await SettingsSnapshot.initializeReadOnly();
    final dataRoot = await AppPaths.getDataRootPath();
    final settingsFound = await File(
      p.join(dataRoot, SettingsSnapshot.boxFileName),
    ).exists();
    // פתרון הנתיב יוצר תיקייה חסרה; תיקייה חסרה ממילא אין בה מסד.
    final databasesDir = Directory(await AppPaths.getDatabasesPath());
    return (
      settingsFound: settingsFound,
      settingsLoaded: settingsLoaded,
      dataRoot: dataRoot,
      databasePath: settingsFound && await databasesDir.exists()
          ? await AppPaths.resolveNotesDbPath('user_state.db')
          : null,
    );
  }

  static Future<int> _pending(
    DirectErrorReportService? reports,
    String? outPath,
    StringSink out,
  ) async {
    final count = await reports?.getSendablePendingReportsCount() ?? 0;
    final json = jsonEncode(DirectErrorReportService.pendingDocument(count));
    if (outPath == null) {
      out.writeln(json);
    } else {
      await File(outPath).writeAsString(json, flush: true);
    }
    return ErrorReportsCliExitCode.success;
  }

  static Future<int> _handoff(
    DirectErrorReportService? reports,
    String outDir,
    StringSink out,
    StringSink err,
  ) async {
    if (reports == null) {
      out.writeln('אין דיווחים שמורים.');
      return ErrorReportsCliExitCode.success;
    }
    await Directory(outDir).create(recursive: true);
    final result = await reports.handOffPendingReports(
      (report) async => _writeAtomically(
        await _targetPath(outDir, report.id),
        jsonEncode(DirectErrorReportService.handoffDocument(report)),
      ),
    );
    for (final id in result.invalidIds) {
      err.writeln('הדיווח $id פסול ולא יתקבל בשרת; הוא נשאר בתור לעריכה.');
    }
    result.failures.forEach((id, error) {
      err.writeln('כתיבת הדיווח $id נכשלה: $error');
    });
    out.writeln(
      'הועברו ${result.handedOff}, השתנו בינתיים באוצריא הפתוחה '
      '${result.changedMeanwhile}, דולגו ${result.invalidIds.length} פסולים, '
      'נכשלו ${result.failures.length}.',
    );
    return result.failures.isEmpty
        ? ErrorReportsCliExitCode.success
        : ErrorReportsCliExitCode.failed;
  }

  /// שם קובץ שתקף בכל מערכת קבצים, גם ב-FAT32 של כונן נייד. [disambiguate]
  /// מוסיף סיומת יציבה מה-hash של המזהה, לשני מזהים שמתנקים לאותו שם.
  static String fileNameFor(String reportId, {bool disambiguate = false}) {
    var name = reportId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (name.isEmpty) name = '_';
    if (disambiguate) {
      final hash = sha256.convert(utf8.encode(reportId)).toString();
      name = '$name-${hash.substring(0, 8)}';
    }
    return '$name.json';
  }

  /// קובץ קיים באותו שם נדרס רק כשהוא של אותו דיווח.
  static Future<String> _targetPath(String dir, String reportId) async {
    final path = p.join(dir, fileNameFor(reportId));
    final existing = File(path);
    if (!await existing.exists()) return path;
    try {
      final decoded = jsonDecode(await existing.readAsString());
      if (decoded is Map && decoded['report_id'] == reportId) return path;
    } on FormatException {
      // קובץ זר — לא נדרס.
    } on FileSystemException {
      // גם קובץ שאינו UTF-8 זר.
    }
    return p.join(dir, fileNameFor(reportId, disambiguate: true));
  }

  /// קורא שמוציא את הכונן באמצע לא ימצא קובץ חלקי בשם הסופי.
  static Future<void> _writeAtomically(String path, String contents) async {
    final temp = File('$path.tmp');
    try {
      await temp.writeAsString(contents, flush: true);
      await temp.rename(path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // הכשל המקורי הוא שמעניין.
      }
      rethrow;
    }
  }

  /// מפענח את הארגומנטים שאחרי `reports`. מחזיר null בשגיאת שימוש.
  static ErrorReportsCliRequest? parseArgs(List<String> args, StringSink err) {
    ErrorReportsCliAction? action;
    String? outPath;

    for (final raw in args) {
      final arg = raw.trim();
      if (arg.isEmpty) continue;

      if (arg == '-h' || arg == '--help') {
        return const ErrorReportsCliRequest(ErrorReportsCliAction.help);
      }
      if (arg.startsWith('--out=')) {
        final value = arg.substring('--out='.length).trim();
        if (value.isEmpty) {
          err.writeln('ערך --out חייב להיות נתיב: $arg');
          return null;
        }
        outPath = value;
        continue;
      }
      if (arg.startsWith('-')) {
        err.writeln('דגל לא מוכר: $arg');
        return null;
      }

      if (action != null) {
        err.writeln('ניתן לציין פעולה אחת בלבד: $arg');
        return null;
      }
      action = switch (arg.toLowerCase()) {
        'pending' => ErrorReportsCliAction.pending,
        'handoff' => ErrorReportsCliAction.handoff,
        _ => null,
      };
      if (action == null) {
        err.writeln('פעולה לא מוכרת: $arg');
        return null;
      }
    }

    if (action == null) {
      err.writeln('חסרה פעולה: pending או handoff');
      return null;
    }
    if (action == ErrorReportsCliAction.handoff && outPath == null) {
      err.writeln('handoff דורש --out=<תיקייה>');
      return null;
    }
    return ErrorReportsCliRequest(action, outPath: outPath);
  }

  static void printUsage(StringSink out) {
    out
      ..writeln('שימוש: otzaria reports <pending|handoff> [--out=<path>]')
      ..writeln()
      ..writeln(
        'מעביר את דיווחי הטעויות השמורים למחשב מחובר. ללא חלון וללא ממשק.',
      )
      ..writeln()
      ..writeln('פעולות:')
      ..writeln(
        '  pending   מספר הדיווחים בתור כ-JSON, ל-stdout או לקובץ --out. '
        'אינו משנה דבר',
      )
      ..writeln(
        '  handoff   קובץ JSON לכל דיווח בתיקייה --out, והעברת הדיווחים '
        'שנכתבו להיסטוריית הנשלחים',
      )
      ..writeln()
      ..writeln('דגלים:')
      ..writeln('  --out=<path> קובץ (pending) או תיקייה (handoff, חובה)')
      ..writeln('  -h, --help   הצגת עזרה זו')
      ..writeln()
      ..writeln(
        'קודי יציאה: 0 הצלחה, 1 כשל, 2 התור עדיין בפורמט הישן '
        '(יש לפתוח את אוצריא פעם אחת), 64 שגיאת שימוש.',
      );
  }
}
