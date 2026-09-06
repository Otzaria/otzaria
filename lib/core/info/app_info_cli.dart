import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/personal_folders_info.dart';
import 'package:otzaria/core/info/settings_snapshot.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

class AppInfoCliExitCode {
  static const int success = 0;
  static const int collectFailed = 1;
  static const int usageError = 64;
}

/// הבקשה שנגזרת מארגומנטי `otzaria info ...`.
class AppInfoCliRequest {
  final InfoTopic topic;
  final int errorLimit;

  /// מספר קובצי הספרים המפורטים לכל תיקייה אישית. `0` = ספירות בלבד.
  final int fileLimit;
  final bool compact;
  final bool help;

  /// כשמוגדר — ה-JSON נכתב לקובץ הזה במקום ל-stdout.
  final String? outPath;

  const AppInfoCliRequest({
    this.topic = InfoTopic.all,
    this.errorLimit = 5,
    this.fileLimit = PersonalFoldersInfo.defaultFileLimit,
    this.compact = false,
    this.help = false,
    this.outPath,
  });
}

/// פקודת headless שמדפיסה את דוח המידע כ-JSON גולמי ל-stdout.
///
/// זהו ערוץ הפלט היחיד שתוכנה חיצונית יכולה לצרוך סינכרונית: הפעלת
/// `otzaria://info/...` דרך ה-OS היא חד-כיוונית ואינה מחזירה דבר לקורא.
///
///     otzaria.exe info                 # דוח מלא
///     otzaria.exe info app             # מקטע אחד
///     otzaria.exe info errors --limit=20
///     otzaria.exe info folders --files=0  # ספירות בלי רשימת קבצים
///     otzaria.exe info --compact       # שורה אחת, ידידותי לצינור
///     otzaria.exe info --out=r.json    # מטען נקי לקובץ
///
/// **stdout אינו נקי לחלוטין ב-Windows**: `irondash_engine_context_plugin.dll`
/// מדפיס `P ATTACH` מ-DllMain בזמן טעינת התהליך, לפני שקוד Dart רץ בכלל.
/// שום דבר אינו מודפס *אחרי* ה-JSON, ולכן עם `--compact` ה-JSON הוא השורה
/// האחרונה. קורא שרוצה מטען מובטח ישתמש ב-`--out=<path>`.
class AppInfoCli {
  const AppInfoCli._();

  static Future<int> run(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    Future<AppInfoReport> Function(AppInfoCliRequest request)? collect,
    Future<void> Function(String path, String json)? writeFile,
  }) async {
    final outSink = out ?? stdout;
    final errSink = err ?? stderr;

    final request = parseArgs(args, errSink);
    if (request == null) return AppInfoCliExitCode.usageError;
    if (request.help) {
      printUsage(outSink);
      return AppInfoCliExitCode.success;
    }

    // stdout הוא חוזה מכונה — רק ה-JSON. כל `print` במהלך האיסוף (debugPrint
    // של האפליקציה, באנרים של תלויות) מנותב ל-stderr כדי שלא ישבור פענוח.
    return runZoned(
      () async {
        try {
          final report = await (collect ?? _collectReport)(request);
          final json = encode(report, compact: request.compact);
          final outPath = request.outPath;
          if (outPath == null) {
            outSink.writeln(json);
          } else {
            await (writeFile ?? _writeJsonFile)(outPath, json);
          }
          return AppInfoCliExitCode.success;
        } catch (error, stackTrace) {
          errSink.writeln('איסוף המידע נכשל: $error');
          errSink.writeln(stackTrace);
          return AppInfoCliExitCode.collectFailed;
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => errSink.writeln(line),
      ),
    );
  }

  /// ה-JSON מודפס עם הזחה כברירת מחדל (קריא גם לאדם) ובשורה אחת עם
  /// `--compact`, לצינור לתוך מפענח.
  static String encode(AppInfoReport report, {bool compact = false}) {
    final json = report.toJson();
    return compact
        ? jsonEncode(json)
        : const JsonEncoder.withIndent('  ').convert(json);
  }

  static Future<void> _writeJsonFile(String path, String json) =>
      File(path).writeAsString(json, flush: true);

  static Future<AppInfoReport> _collectReport(AppInfoCliRequest request) async {
    // נדרש לערוצי הפלטפורמה (PackageInfo, path_provider) — החלון נשאר מוסתר
    // כי main.cpp מזהה את הפקודה ובונה את FlutterWindow במצב headless.
    WidgetsFlutterBinding.ensureInitialized();
    final settingsLoaded = await SettingsSnapshot.initializeReadOnly();

    return AppInfoService.collect(
      request.topic,
      pluginsLoader: () => PluginRegistryRepository().getAllPlugins(),
      errorLimit: request.errorLimit,
      fileLimit: request.fileLimit,
      settingsLoaded: settingsLoaded,
    );
  }

  /// מפענח את הארגומנטים שאחרי `info`. מחזיר null בשגיאת שימוש.
  static AppInfoCliRequest? parseArgs(List<String> args, StringSink err) {
    var topic = InfoTopic.all;
    var topicGiven = false;
    var errorLimit = 5;
    var fileLimit = PersonalFoldersInfo.defaultFileLimit;
    var compact = false;
    String? outPath;

    for (final raw in args) {
      final arg = raw.trim();
      if (arg.isEmpty) continue;

      if (arg == '-h' || arg == '--help') {
        return const AppInfoCliRequest(help: true);
      }
      if (arg == '--compact') {
        compact = true;
        continue;
      }
      if (arg.startsWith('--out=')) {
        final value = arg.substring('--out='.length).trim();
        if (value.isEmpty) {
          err.writeln('ערך --out חייב להיות נתיב קובץ: $arg');
          return null;
        }
        outPath = value;
        continue;
      }
      if (arg.startsWith('--limit=')) {
        final parsed = int.tryParse(arg.substring('--limit='.length).trim());
        if (parsed == null || parsed <= 0) {
          err.writeln('ערך --limit חייב להיות מספר חיובי: $arg');
          return null;
        }
        errorLimit = parsed;
        continue;
      }
      if (arg.startsWith('--files=')) {
        // 0 מותר כאן ומשמעו "ספירות בלבד", בשונה מ---limit שבו 0 חסר משמעות.
        final parsed = int.tryParse(arg.substring('--files='.length).trim());
        if (parsed == null || parsed < 0) {
          err.writeln('ערך --files חייב להיות מספר אי-שלילי: $arg');
          return null;
        }
        fileLimit = parsed;
        continue;
      }
      if (arg.startsWith('-')) {
        err.writeln('דגל לא מוכר: $arg');
        return null;
      }

      if (topicGiven) {
        err.writeln('ניתן לציין נושא אחד בלבד: $arg');
        return null;
      }
      final parsedTopic = InfoTopic.fromSlug(arg);
      if (parsedTopic == null) {
        err.writeln('נושא לא מוכר: $arg');
        return null;
      }
      topic = parsedTopic;
      topicGiven = true;
    }

    return AppInfoCliRequest(
      topic: topic,
      errorLimit: errorLimit,
      fileLimit: fileLimit,
      compact: compact,
      outPath: outPath,
    );
  }

  static void printUsage(StringSink out) {
    out
      ..writeln(
        'שימוש: otzaria info [<נושא>] [--limit=<n>] [--files=<n>] '
        '[--compact] [--out=<path>]',
      )
      ..writeln()
      ..writeln('מדפיס דוח JSON על ההתקנה ל-stdout ויוצא. ללא חלון וללא ממשק.')
      ..writeln()
      ..writeln('נושאים:')
      ..writeln('  all       (ברירת מחדל) כל המקטעים שלהלן')
      ..writeln('  app       גרסה, תאריכי התקנה/עדכון, סוג התקנה וחשבון')
      ..writeln('  library   גרסת ספרייה, תאריך עדכון ומספרי ספרים')
      ..writeln('  folders   תיקיות הספרים האישיים וקובצי הספרים שבהן')
      ..writeln('  plugins   גרסת WebView ורשימת התוספים המותקנים')
      ..writeln('  errors    רשומות השגיאה האחרונות מקובצי הלוג')
      ..writeln()
      ..writeln('דגלים:')
      ..writeln('  --limit=<n>  מספר רשומות השגיאה (ברירת מחדל 5)')
      ..writeln(
        '  --files=<n>  מספר הקבצים לכל תיקייה אישית '
        '(ברירת מחדל ${PersonalFoldersInfo.defaultFileLimit}; 0 = ספירות בלבד)',
      )
      ..writeln('  --compact    JSON בשורה אחת')
      ..writeln('  --out=<path> כתיבת ה-JSON לקובץ במקום ל-stdout')
      ..writeln('  -h, --help   הצגת עזרה זו')
      ..writeln()
      ..writeln(
        'הערה: ב-Windows תלות נייטיב מדפיסה "P ATTACH" ל-stdout בעליית '
        'התהליך. שום דבר אינו מודפס אחרי ה-JSON, ולכן עם --compact ה-JSON '
        'הוא השורה האחרונה. ל-stdout נקי מובטח השתמש ב---out.',
      );
  }
}
