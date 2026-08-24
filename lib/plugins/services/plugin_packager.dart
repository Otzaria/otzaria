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

  /// קבצי המטא-דאטה שהוחרגו (‎*.md‎, LICENSE, dotfiles, ‎screenshots/‎...) ולא
  /// הוחזרו ע"י שורת `!` ב-`.otzignore`.
  final List<String> excludedMetadata;
  final int bytes;
  final PluginManifest manifest;
  final PluginValidationReport validation;

  const PluginPackageResult({
    required this.outputPath,
    required this.fileCount,
    this.excludedCount = 0,
    this.excludedMetadata = const <String>[],
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

    // תיקיות מטא-דאטה של המאגר שאינן חלק מהתוסף (הגדרות CI, צילומי מסך לחנות)
    // וכל תיקייה נסתרת. מוחרגות מעבר ל-skipDirs. חייב להישאר זהה ל-knownApi.js
    // (isMetadataDir) בוולידטור כדי ששתי הסביבות יפיקו אותו ארכיון בדיוק.
    bool isMetadataDir(String base) {
      if (base == '.' || base == '..') return false;
      return base == '.github' || base == 'screenshots' || base.startsWith('.');
    }

    // קבצי מטא-דאטה שאינם נכס של התוסף (תיעוד, רישיונות, dotfiles, lockfiles).
    // זהה ל-knownApi.js (isMetadataFile) בוולידטור.
    bool isMetadataFile(String base) {
      if (base.startsWith('.')) return true;
      final lower = base.toLowerCase();
      if (lower.endsWith('.md')) return true;
      if (lower.startsWith('license') || lower.startsWith('licence')) {
        return true;
      }
      return lower == 'package-lock.json' ||
          lower == 'yarn.lock' ||
          lower == 'pnpm-lock.yaml';
    }

    // קובץ החרגה אופציונלי (`.otzignore`) בשורש התוסף — מחריג קבצים נוספים
    // מהארכיון, ושורת `!` מחזירה קובץ שהוחרג (כולל קובץ מטא-דאטה).
    final ignore = PluginIgnore.load(dir.path);

    // כלל אריזה יחיד: תיקיות פיתוח לעולם אינן נארזות, ומעליהן `!` מפורש
    // ב-.otzignore גובר על החרגת מטא-דאטה (help.md, נכס מ-screenshots/...).
    // מחזיר את סיבת ההחרגה, או null כשהקובץ נארז.
    String? packBlockReason(String rel) {
      final segments = p.split(rel);
      for (var i = 0; i < segments.length - 1; i++) {
        if (skipDirs.contains(segments[i])) {
          return 'נמצא בתוך תיקייה מוחרגת מאריזה ("${segments[i]}")';
        }
      }
      if (ignore.reIncludes(rel)) return null;
      for (var i = 0; i < segments.length - 1; i++) {
        if (isMetadataDir(segments[i])) {
          return 'נמצא בתוך תיקייה מוחרגת מאריזה ("${segments[i]}")';
        }
      }
      if (isMetadataFile(segments.last)) {
        return 'מסווג כקובץ מטא-דאטה ולכן מוחרג מהאריזה';
      }
      if (ignore.ignores(rel)) return 'מוחרג ע"י $kOtzignoreFilename';
      return null;
    }

    // בדיקת תקינות: ה-entrypoint (וקובץ הרקע) חייבים להיכלל בארכיון — אחרת
    // התוסף יישבר בשקט אצל המשתמש.
    // resolve מוחלט ואז relative מבטיח טיפול נכון בנתיבים כמו ./node_modules/...
    // חשוב: בדיקה זו רצה לפני יצירת תיקיות הפלט, כדי שלא ישארו תיקיות ריקות
    // בדיסק אם הבדיקה נכשלת.
    String relOf(String declared) => p
        .relative(
          p.normalize(p.absolute(p.join(dir.path, declared))),
          from: dir.path,
        )
        .replaceAll('\\', '/');

    void assertPacked(String label, String declared) {
      final rel = relOf(declared);
      final reason = packBlockReason(rel);
      if (reason == null) return;
      throw PluginPackagerException(
        '$label "$declared" $reason ולכן לא ייכלל ב-.otzplugin. '
        'הוצא אותו מהתיקיות המוחרגות, או החזר אותו עם השורה "!$rel" '
        'ב-$kOtzignoreFilename.',
      );
    }

    assertPacked('קובץ הכניסה', manifest.entrypoint);
    final backgroundEntrypoint = manifest.backgroundEntrypoint;
    if (backgroundEntrypoint != null) {
      assertPacked('קובץ הרקע', backgroundEntrypoint);
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
    final excludedMetadata = <String>[];
    void collectFiles(Directory currentDir, bool inMetadata) {
      for (final entity in currentDir.listSync(recursive: false)) {
        final base = p.basename(entity.path);
        final rel = p
            .relative(entity.path, from: dir.path)
            .replaceAll('\\', '/');
        if (entity is Directory) {
          // תיקיות פיתוח לעולם אינן נארזות — זהה לכללי הוולידטור.
          if (skipDirs.contains(base)) continue;
          final meta = inMetadata || isMetadataDir(base);
          // בלי כללי `!` שום דבר בתוך תיקיית מטא-דאטה לא יכול לחזור, אז גוזמים
          // אותה — וכך גם תיקייה שהוחרגה במפורש.
          if (meta && !ignore.hasNegation) continue;
          if (!ignore.hasNegation && ignore.ignores('$rel/')) continue;
          collectFiles(entity, meta);
        } else if (entity is File) {
          // ה-.otzignore עצמו לעולם לא נארז.
          if (base == kOtzignoreFilename) continue;
          final entityAbs = p.normalize(p.absolute(entity.path));
          if (entityAbs == normalizedOutPath) continue;
          // קובץ מטא-דאטה (dotfiles, *.md, LICENSE, lockfiles, screenshots/…)
          // נארז רק אם שורת `!` ב-.otzignore מחזירה אותו במפורש.
          if (inMetadata || isMetadataFile(base)) {
            if (!ignore.reIncludes(rel)) {
              excludedMetadata.add(rel);
              continue;
            }
          } else if (ignore.ignores(rel)) {
            excludedCount++;
            continue;
          }
          filesToPack.add(entity);
        }
      }
    }

    collectFiles(dir, false);

    if (excludedMetadata.isNotEmpty) {
      onLog?.call(
        '${excludedMetadata.length} קבצי מטא-דאטה הוחרגו: '
        '${excludedMetadata.join(', ')} '
        '(החזרה לארכיון: שורת "!<נתיב>" ב-$kOtzignoreFilename)',
      );
    }

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
      excludedMetadata: excludedMetadata,
      bytes: bytes,
      manifest: manifest,
      validation: report,
    );
  }
}
