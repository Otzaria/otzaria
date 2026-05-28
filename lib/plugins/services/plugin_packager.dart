import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:path/path.dart' as p;

/// תוצאת אריזה — נתיב הפלט, מספר הקבצים שנארזו, גודל הפלט, ודו"ח ולידציה.
class PluginPackageResult {
  final String outputPath;
  final int fileCount;
  final int bytes;
  final PluginManifest manifest;
  final PluginValidationReport validation;

  const PluginPackageResult({
    required this.outputPath,
    required this.fileCount,
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
          'התיקייה לא קיימת: ${p.absolute(directoryPath)}');
    }

    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw PluginPackagerException(
          'הקובץ manifest.json לא נמצא בתיקייה ${p.absolute(directoryPath)}. '
          'תוסף תקין חייב לכלול manifest.json בשורש.');
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
          'נכשלה קריאת manifest.json לתוך מבנה PluginManifest: $e');
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
      '.git', '.svn', '.hg', '.idea', '.vscode',
      'node_modules', '__pycache__', '.claude',
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
    final blockedDir =
        p.split(entrypointRelativePath).where(skipDirs.contains).firstOrNull;
    if (blockedDir != null) {
      throw PluginPackagerException(
        'קובץ הכניסה "${manifest.entrypoint}" נמצא בתוך תיקייה מוחרגת מאריזה '
        '("$blockedDir"). העבר את ה-entrypoint מחוץ לתיקיות: '
        '${skipDirs.join(', ')}',
      );
    }

    final resolvedOutPath = outputPath ??
        p.join(dir.parent.path, '${manifest.id}-${manifest.version}.otzplugin');
    final outFile = File(resolvedOutPath);

    if (outFile.existsSync() && !force) {
      throw PluginPackagerException('קובץ הפלט כבר קיים: $resolvedOutPath\n'
          'יש להשתמש בדגל --force כדי לדרוס אותו.');
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
    void collectFiles(Directory currentDir) {
      for (final entity in currentDir.listSync(recursive: false)) {
        if (skipDirs.contains(p.basename(entity.path))) continue;
        if (entity is Directory) {
          collectFiles(entity);
        } else if (entity is File) {
          final entityAbs = p.normalize(p.absolute(entity.path));
          if (entityAbs == normalizedOutPath) continue;
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
      bytes: bytes,
      manifest: manifest,
      validation: report,
    );
  }
}
