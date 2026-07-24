import 'dart:io';

import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/services/plugin_packager.dart';

/// קודי יציאה סטנדרטיים של ה-CLI.
class PluginPackagerCliExitCode {
  static const int success = 0;
  static const int blockingError = 1;
  static const int usageError = 64;
}

/// CLI משותף לאריזת תוסף. נקודת כניסה אחת ש:
///   1. `lib/main.dart` מפעיל כשמזוהה `otzaria.exe pack-plugin ...`
///   2. `tool/plugins/package_plugin.dart` מפעיל ב-`dart run`
///
/// קיומה של פונקציה אחת מבטיח התנהגות זהה (אותם דגלים, אותה הודעת
/// usage, אותם קודי יציאה) בשני המסלולים שהתיעוד מציג כשקולים.
class PluginPackagerCli {
  /// מריץ את הפקודה ומחזיר exit code.
  ///
  /// [args] — הארגומנטים אחרי שם הפקודה (כלומר *לא* כולל `pack-plugin`).
  /// [out] / [err] — יעדי כתיבה לפלט. ברירת מחדל: stdout / stderr.
  /// [currentDirectory] — מותאם לטסטים; ברירת מחדל: `Directory.current.path`.
  static Future<int> run(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    String? currentDirectory,
  }) async {
    final outSink = out ?? stdout;
    final errSink = err ?? stderr;

    String? dirPath;
    String? outputPath;
    var force = false;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--help' || a == '-h') {
        printUsage(outSink);
        return PluginPackagerCliExitCode.success;
      } else if (a == '--force') {
        force = true;
      } else if (a == '--output' || a == '-o') {
        if (i + 1 >= args.length) {
          errSink.writeln('שגיאה: ל-$a חסר ערך (נתיב פלט).');
          printUsage(errSink);
          return PluginPackagerCliExitCode.usageError;
        }
        outputPath = args[++i];
      } else if (a.startsWith('--output=')) {
        outputPath = a.substring('--output='.length);
      } else if (a.startsWith('-')) {
        errSink.writeln('שגיאה: דגל לא מוכר: $a');
        printUsage(errSink);
        return PluginPackagerCliExitCode.usageError;
      } else {
        if (dirPath != null) {
          errSink.writeln(
            'שגיאה: ניתן לציין נתיב תיקיית תוסף אחד בלבד (קיבלתי "$dirPath" ועוד "$a").',
          );
          return PluginPackagerCliExitCode.usageError;
        }
        dirPath = a;
      }
    }

    final resolvedDir = dirPath ?? currentDirectory ?? Directory.current.path;

    try {
      final result = await PluginPackager.packDirectory(
        directoryPath: resolvedDir,
        outputPath: outputPath,
        force: force,
        onLog: outSink.writeln,
      );
      _printValidationReport(result.validation, outSink);
      outSink.writeln('הושלם בהצלחה! נארז ל: ${result.outputPath}');
      final excludedNote = result.excludedCount > 0
          ? ', ${result.excludedCount} מוחרגים (.otzignore)'
          : '';
      outSink.writeln(
        '  קבצים: ${result.fileCount}$excludedNote, גודל: ${result.bytes} בייטים',
      );
      return PluginPackagerCliExitCode.success;
    } on PluginPackagerException catch (e) {
      errSink.writeln('שגיאה: ${e.message}');
      return PluginPackagerCliExitCode.blockingError;
    } catch (e, st) {
      errSink.writeln('שגיאה לא צפויה: $e');
      errSink.writeln(st);
      return PluginPackagerCliExitCode.blockingError;
    }
  }

  static void printUsage(StringSink out) {
    out.writeln(
      'שימוש: otzaria pack-plugin [נתיב-לתיקיית-תוסף] [--force] [--output <file>]\n'
      '\n'
      'אורז תיקיית תוסף לקובץ ‎.otzplugin תקני.\n'
      '\n'
      'אם נתיב לא ניתן — נעשה שימוש בתיקייה הנוכחית.\n'
      '\n'
      'אופציות:\n'
      '  --force                לדרוס קובץ ‎.otzplugin קיים\n'
      '  --output <file>, -o    נתיב פלט מפורש (ברירת מחדל: '
      '{id}-{version}.otzplugin בצמוד לתיקיית התוסף)\n'
      '  --help, -h             הצגת מסך עזרה זה',
    );
  }

  static void _printValidationReport(
    PluginValidationReport report,
    StringSink out,
  ) {
    if (report.hasWarnings) {
      out.writeln('');
      out.writeln('אזהרות (לא חוסמות):');
      for (final w in report.warnings) {
        out.writeln('  ⚠ $w');
      }
    }
    if (!report.design.compliant) {
      out.writeln('');
      out.writeln('תאימות עיצוב (DESIGN_GUIDE):');
      if (report.design.violations.isEmpty) {
        out.writeln('  ⚠ העיצוב לא סומן כתואם לאוצריא');
      } else {
        for (final v in report.design.violations) {
          out.writeln('  ⚠ $v');
        }
      }
    } else {
      out.writeln('');
      out.writeln('✓ העיצוב תואם לתיעוד (DESIGN_GUIDE).');
    }
    out.writeln('');
  }
}
