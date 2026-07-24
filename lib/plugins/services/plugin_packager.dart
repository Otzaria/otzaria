import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/services/plugin_ignore.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:path/path.dart' as p;

/// תוצאת אריזה — נתיב הפלט, מספר הקבצים שנארזו, גודל הפלט, ודו"ח ולידציה.
class PluginPackageResult {
  final String outputPath;
  final int fileCount;

  /// מספר הקבצים שהוחרגו ע"י `.otzignore` (0 אם אין קובץ כזה).
  final int excludedCount;
  final int bytes;
  final PluginManifest manifest;
  final PluginValidationReport validation;

  const PluginPackageResult({
    required this.outputPath,
    required this.fileCount,
    this.excludedCount = 0,
    required this.bytes,
    required this.manifest,
    required this.validation,
  });
}

/// חריגה ידידותית עם הודעה בעברית.
class PluginPackagerException implements Exception {
  final String message;
  PluginPackagerException(this.message);

  @override
  String toString() => message;
}

/// כלי אריזה לתוסף Otzaria: מקבל תיקיית תוסף ומפיק `.otzplugin` תקני.
///
/// ניתן להשתמש בכלי משלוש סביבות:
///   1. סקריפט CLI (`tool/plugins/package_plugin.dart`).
///   2. ארגומנטים ל-`otzaria.exe pack-plugin <path>`.
///   3. קוד פנימי בתוכנה (UI עתידי לאריזת תוסף).
class PluginPackager {
  /// אורז תיקייה לקובץ `.otzplugin`.
  ///
  /// [directoryPath] — תיקיית התוסף (חייבת להכיל `manifest.json`).
  /// [outputPath] — נתיב מלא לקובץ הפלט. אם null — ייוצר בתיקיית האב של
  ///                התיקייה הנארזת בשם `{id}-{version}.otzplugin`.
  /// [force] — אם true, יוחלף קובץ פלט קיים. אחרת תיזרק חריגה.
  /// [onLog] — קריאה חוזרת אופציונלית להודעות התקדמות (קובץ-אחר-קובץ).
  static Future<PluginPackageResult> packDirectory({
    required String directoryPath,
    String? outputPath,
    bool force = false,
    void Function(String message)? onLog,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw PluginPackagerException(
        'התיקייה לא קיימת: ${p.absolute(directoryPath)}',
      );
    }

    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw PluginPackagerException(
        'הקובץ manifest.json לא נמצא בתיקייה ${p.absolute(directoryPath)}. '
        'תוסף תקין חייב לכלול manifest.json בשורש.',
      );
    }

    final manifestStr = manifestFile.readAsStringSync();
    Map<String, dynamic> manifestJson;
    try {
      manifestJson = jsonDecode(manifestStr) as Map<String, dynamic>;
    } catch (e) {
      throw PluginPackagerException('הקובץ manifest.json אינו JSON תקין: $e');
    }

    PluginManifest manifest;
    try {
      manifest = PluginManifest.fromJson(manifestJson);
    } catch (e) {
      throw PluginPackagerException(
        'נכשלה קריאת manifest.json לתוך מבנה PluginManifest: $e',
      );
    }

    try {
      await PluginManifestValidator.validateManifest(
        manifest: manifest,
        directoryPath: dir.path,
        skipAppVersionValidation: true,
      );
    } catch (e) {
      throw PluginPackagerException('שגיאת ולידציה: $e');
    }

    final report = PluginExtendedValidator.validate(
      manifest: manifest,
      manifestJson: manifestJson,
      directoryPath: dir.path,
    );

    if (report.hasErrors) {
      final lines = <String>[
        'נמצאו שגיאות ולידציה (חוסמות):',
        ...report.errors.map((e) => '  • $e'),
      ];
      throw PluginPackagerException(lines.join('\n'));
    }

    // תיקיות פיתוח שאין צורך לארוז — שומרות על חבילה רזה ומונעות הדלפת
    // היסטוריית git/הגדרות IDE לתוך ה-‎.otzplugin שמופץ.
    const skipDirs = <String>{
      '.git',
      '.svn',
      '.hg',
      '.idea',
      '.vscode',
      'node_modules',
      '__pycache__',
      '.claude',
    };

    // בדיקת תקינות: ה-entrypoint לא יכול לשבת בתוך תיקייה מוחרגת —
    // אחרת הקובץ לא ייכלל ב-.otzplugin והפלאגין יישבר בשקט.
    // resolve מוחלט ואז relative מבטיח טיפול נכון בנתיבים כמו ./node_modules/...
    // חשוב: בדיקה זו רצה לפני יצירת תיקיות הפלט, כדי שלא ישארו תיקיות ריקות
    // בדיסק אם הבדיקה נכשלת.
    final entrypointRelativePath = p.relative(
      p.normalize(p.absolute(p.join(dir.path, manifest.entrypoint))),
      from: dir.path,
    );
    final blockedDir = p
        .split(entrypointRelativePath)
        .where(skipDirs.contains)
        .firstOrNull;
    if (blockedDir != null) {
      throw PluginPackagerException(
        'קובץ הכניסה "${manifest.entrypoint}" נמצא בתוך תיקייה מוחרגת מאריזה '
        '("$blockedDir"). העבר את ה-entrypoint מחוץ לתיקיות: '
        '${skipDirs.join(', ')}',
      );
    }

    // קובץ החרגה אופציונלי (`.otzignore`) בשורש התוסף — מחריג קבצים נוספים
    // מהארכיון. נטען כאן כדי לבדוק שה-entrypoint לא הוחרג בטעות (אחרת התוסף
    // יישבר בשקט בדיוק כמו entrypoint בתוך תיקייה מוחרגת).
    final ignore = PluginIgnore.load(dir.path);
    final entrypointForIgnore = entrypointRelativePath.replaceAll('\\', '/');
    if (ignore.ignores(entrypointForIgnore)) {
      throw PluginPackagerException(
        'קובץ הכניסה "${manifest.entrypoint}" מוחרג ע"י $kOtzignoreFilename. '
        'הסר את הכלל שמתאים לו מ-$kOtzignoreFilename כדי שייכלל באריזה.',
      );
    }

    // אותה בדיקה לקובץ הרקע (אם הוצהר) — אחרת תוסף רקע יישבר בשקט בעלייה.
    final backgroundEntrypoint = manifest.backgroundEntrypoint;
    if (backgroundEntrypoint != null) {
      final backgroundRelativePath = p.relative(
        p.normalize(p.absolute(p.join(dir.path, backgroundEntrypoint))),
        from: dir.path,
      );
      final blockedBackgroundDir = p
          .split(backgroundRelativePath)
          .where(skipDirs.contains)
          .firstOrNull;
      if (blockedBackgroundDir != null) {
        throw PluginPackagerException(
          'קובץ הרקע "$backgroundEntrypoint" נמצא בתוך תיקייה מוחרגת מאריזה '
          '("$blockedBackgroundDir"). העבר אותו מחוץ לתיקיות: '
          '${skipDirs.join(', ')}',
        );
      }
      if (ignore.ignores(backgroundRelativePath.replaceAll('\\', '/'))) {
        throw PluginPackagerException(
          'קובץ הרקע "$backgroundEntrypoint" מוחרג ע"י $kOtzignoreFilename. '
          'הסר את הכלל שמתאים לו מ-$kOtzignoreFilename כדי שייכלל באריזה.',
        );
      }
    }

    final resolvedOutPath =
        outputPath ??
        p.join(dir.parent.path, '${manifest.id}-${manifest.version}.otzplugin');
    final outFile = File(resolvedOutPath);

    if (outFile.existsSync() && !force) {
      throw PluginPackagerException(
        'קובץ הפלט כבר קיים: $resolvedOutPath\n'
        'יש להשתמש בדגל --force כדי לדרוס אותו.',
      );
    }

    final outParent = Directory(p.dirname(resolvedOutPath));
    if (!outParent.existsSync()) {
      outParent.createSync(recursive: true);
    }

    onLog?.call('אורז את ${p.absolute(directoryPath)} ל-$resolvedOutPath');

    // נורמליזציה של נתיב הפלט בעבור השוואות — אם הוא יושב בתוך תיקיית
    // התוסף, צריך להחריג אותו מהקבצים שמתווספים לארכיון כדי שהארכיון לא
    // יכיל את עצמו (במיוחד כש-force מאפשר דריסה תוך כדי כתיבה).
    final normalizedOutPath = p.normalize(p.absolute(resolvedOutPath));

    // נאסוף את הקבצים *לפני* יצירת ארכיון הפלט, כדי שהקובץ החדש לא
    // יופיע ב-listSync. (גיבוי בנוסף לבדיקת הנתיב למטה.)
    // סריקה ידנית (לא רקורסיבית ב-OS) כדי לדלג לחלוטין על תיקיות מוחרגות
    // ולא לבזבז זמן על סריקת תוכנן (node_modules יכולה להכיל עשרות אלפי קבצים).
    final filesToPack = <File>[];
    var excludedCount = 0;
    void collectFiles(Directory currentDir) {
      for (final entity in currentDir.listSync(recursive: false)) {
        final base = p.basename(entity.path);
        if (skipDirs.contains(base)) continue;
        final rel = p
            .relative(entity.path, from: dir.path)
            .replaceAll('\\', '/');
        if (entity is Directory) {
          // גזימת תיקייה מוחרגת בשלמותה. מדלגים על הקיצור כשיש כללי `!`,
          // כי ייתכן שקובץ-צאצא צריך להיכלל בכל זאת.
          if (!ignore.hasNegation && ignore.ignores('$rel/')) continue;
          collectFiles(entity);
        } else if (entity is File) {
          // ה-.otzignore עצמו לעולם לא נארז.
          if (base == kOtzignoreFilename) continue;
          final entityAbs = p.normalize(p.absolute(entity.path));
          if (entityAbs == normalizedOutPath) continue;
          if (ignore.ignores(rel)) {
            excludedCount++;
            continue;
          }
          filesToPack.add(entity);
        }
      }
    }

    collectFiles(dir);

    final encoder = ZipFileEncoder();
    encoder.create(resolvedOutPath);

    var fileCount = 0;
    try {
      for (final entity in filesToPack) {
        final relativePath = p.relative(entity.path, from: dir.path);
        onLog?.call('  מוסיף: $relativePath');
        encoder.addFileSync(entity, relativePath);
        fileCount++;
      }
    } finally {
      encoder.closeSync();
    }

    final bytes = outFile.lengthSync();
    return PluginPackageResult(
      outputPath: resolvedOutPath,
      fileCount: fileCount,
      excludedCount: excludedCount,
      bytes: bytes,
      manifest: manifest,
      validation: report,
    );
  }
}
