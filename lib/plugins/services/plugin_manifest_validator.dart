import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';

class PluginManifestValidator {
  /// דרגות היציבות המותרות בשדה `stability` (נגזר ל-status בחנות).
  static const Set<String> validStabilityValues = {
    'stable',
    'beta',
    'experimental',
  };

  /// ערכי השדה `platforms` — בדיוק מה ש-`Platform.operatingSystem` מחזיר
  /// בפלטפורמות שאוצריא נבנית להן, ומה שמגיע לתוסף ב-`payload.app.platform`.
  static const Set<String> validPlatformValues = {
    'windows',
    'linux',
    'macos',
    'android',
    'ios',
  };

  /// בודק שמזהה התוסף תקין. המזהה מרכיב נתיבי תיקייה (`getPluginDataPath`),
  /// ולכן `.` ו-`..` — וכל רצף נקודות — נדחים גם כשהתו עצמו מותר.
  static bool isValidPluginId(String id) {
    if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(id)) return false;
    return !RegExp(r'^\.+$').hasMatch(id);
  }

  /// מאמת מניפסט וזורק חריגה אם נמצאה בעיה כלשהי. שומר על חוזה ה-throw של
  /// הקוראים הקיימים, אך אוסף את *כל* השגיאות ומצרף אותן להודעה אחת כדי
  /// שמפתח יראה את כולן בבת אחת (כמו manifestValidator.js).
  static Future<void> validateManifest({
    required PluginManifest manifest,
    required String directoryPath,
    String? currentAppVersion,
    String? currentPlatform,
    bool skipAppVersionValidation = false,
    bool skipFileValidation = false,
  }) async {
    final errors = await collectManifestErrors(
      manifest: manifest,
      directoryPath: directoryPath,
      currentAppVersion: currentAppVersion,
      currentPlatform: currentPlatform,
      skipAppVersionValidation: skipAppVersionValidation,
      skipFileValidation: skipFileValidation,
    );
    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }
  }

  /// השגיאות שנובעות מטווח גרסאות האפליקציה שהתוסף מצהיר עליו.
  static List<String> appVersionErrors(
    PluginManifest manifest,
    String currentAppVersion,
  ) {
    final errors = <String>[];
    if (PluginVersionUtils.compareCoreVersions(
          currentAppVersion,
          manifest.minAppVersion,
        ) <
        0) {
      errors.add(
        'התוסף דורש אוצריא בגרסה ${manifest.minAppVersion} לפחות, אך מותקנת $currentAppVersion',
      );
    }
    if (manifest.maxAppVersion != null &&
        PluginVersionUtils.compareCoreVersions(
              currentAppVersion,
              manifest.maxAppVersion!,
            ) >
            0) {
      errors.add(
        'התוסף מיועד לאוצריא עד גרסה ${manifest.maxAppVersion} בלבד, אך מותקנת $currentAppVersion',
      );
    }
    return errors;
  }

  /// מאמת מניפסט ומחזיר את רשימת כל השגיאות (ריקה = תקין). אינו זורק.
  ///
  /// [currentPlatform] משמש לבדיקת התאימות יחד עם הגרסה (ברירת מחדל:
  /// `Platform.operatingSystem`); מדולג יחד איתה ב-[skipAppVersionValidation].
  static Future<List<String>> collectManifestErrors({
    required PluginManifest manifest,
    required String directoryPath,
    String? currentAppVersion,
    String? currentPlatform,
    bool skipAppVersionValidation = false,
    bool skipFileValidation = false,
  }) async {
    final errors = <String>[];

    if (manifest.schemaVersion != 1) {
      errors.add('גרסת סכמה ${manifest.schemaVersion} של התוסף אינה נתמכת');
    }

    if (!isValidPluginId(manifest.id)) {
      errors.add('מזהה התוסף אינו תקין');
    }

    // שם התוסף מוצג בראש לשונית התוסף ב"כלים" — מעבר ל-14 תווים גולש מהכרטיסייה.
    if (manifest.name.trim().length > 14) {
      errors.add('שם התוסף חייב להכיל לכל היותר 14 תווים');
    }

    // description הוא התיאור הקצר שמוצג בכרטיס התוסף בחנות — מוגבל ל-150 תווים.
    if (manifest.description.trim().length > 150) {
      errors.add('תיאור קצר חייב להכיל לכל היותר 150 תווים');
    }

    // stability נגזר ל-status בחנות — חייב להיות אחד מהערכים המותרים.
    if (!validStabilityValues.contains(manifest.stability)) {
      errors.add(
        'שדה stability אינו תקין ("${manifest.stability}"). '
        'ערכים מותרים: ${validStabilityValues.join(', ')}',
      );
    }

    // platforms — אופציונלי; אם הוצהר: מערך לא ריק, בלי כפילויות, מערכים מוכרים.
    // אותן הודעות כמו src/platforms.js ב-otzaria-plugin-validator.
    errors.addAll(platformsFieldErrors(manifest));

    // הכותרת המוצגת בטאב חייבת להיות זהה ל-name (גם כותרת ריקה נחסמת — היא
    // תציג טאב בלי טקסט). title חסר נופל ל-name ב-fromJson ולכן עובר.
    if (manifest.toolTabTitle.trim() != manifest.name.trim()) {
      errors.add(
        'שם התוסף ("${manifest.name}") שונה מכותרת הטאב ב-contributes.toolTab.title ("${manifest.toolTabTitle}"). השמות חייבים להיות זהים',
      );
    }

    if (!RegExp(r'^\d+\.\d+\.\d+(?:\+.*)?$').hasMatch(manifest.version)) {
      errors.add('גרסת התוסף במניפסט אינה חוקית. נדרש פורמט SemVer חוקיות.');
    }

    if (!skipAppVersionValidation) {
      if (currentAppVersion == null) {
        errors.add(
          'currentAppVersion is required when skipAppVersionValidation is false',
        );
      } else {
        errors.addAll(appVersionErrors(manifest, currentAppVersion));
      }
      final platform = currentPlatform ?? Platform.operatingSystem;
      final declared = manifest.platforms;
      if (declared != null &&
          declared.isNotEmpty &&
          validPlatformValues.contains(platform) &&
          !declared.contains(platform)) {
        errors.add(
          'התוסף אינו תומך ב-$platform. פלטפורמות נתמכות: ${declared.join(', ')}',
        );
      }
    }

    for (final perm in manifest.permissions) {
      if (!pluginValidPermissions.contains(perm)) {
        final hint = apiCallToPermissionHint[perm];
        if (hint != null) {
          errors.add('הרשאה לא חוקית: "$perm". האם התכוונת ל-"$hint"?');
        } else if (apiCallsWithoutPermission.contains(perm)) {
          errors.add(
            '"$perm" היא קריאת API ולא שם של הרשאה, והיא אינה דורשת הרשאה '
            'במניפסט. הסירו אותה מ-permissions — הקריאה עצמה תמשיך לעבוד',
          );
        } else {
          errors.add('הרשאה לא חוקית שנדרשת על ידי התוסף: $perm');
        }
      }
    }

    if (manifest.databaseSources.isNotEmpty &&
        !manifest.permissions.contains('database.read')) {
      errors.add(
        'התוסף מצהיר על contributes.databaseSources אך לא מבקש את ההרשאה database.read',
      );
    }

    for (final source in manifest.databaseSources) {
      final unknownFields = source.keys
          .where((key) => !const {'id', 'label', 'required'}.contains(key))
          .toList();
      if (unknownFields.isNotEmpty) {
        errors.add(
          'שדות לא מוכרים ב-contributes.databaseSources: '
          '${unknownFields.join(', ')}',
        );
      }
      final id = source['id'];
      final label = source['label'];
      final required = source['required'];

      if (id is! String || id.isEmpty) {
        errors.add(
          'כל ערך ב-contributes.databaseSources חייב לכלול id מסוג string',
        );
      } else if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(id)) {
        errors.add('מזהה מקור מסד נתונים אינו תקין: "$id"');
      }
      if (label != null && label is! String) {
        errors.add(
          'השדה label ב-contributes.databaseSources חייב להיות string',
        );
      }
      if (required != null && required is! bool) {
        errors.add(
          'השדה required ב-contributes.databaseSources חייב להיות bool',
        );
      }
    }

    final iconName = manifest.toolTabIconName;
    if (iconName != null &&
        !PluginManifest.toolTabIconNamePattern.hasMatch(iconName)) {
      errors.add(
        'toolTab.iconName חייב להיות שם אייקון FluentUI או אוצריא בגודל 24px '
        '(למשל "book_24_regular", "calendar_24_filled" או '
        '"fluent:book_24_regular")',
      );
    }

    if (manifest.headless) {
      if (p.extension(manifest.entrypoint).toLowerCase() != '.js') {
        errors.add(
          'בתוסף ללא ממשק (headless) קובץ הכניסה חייב להיות קובץ JS, '
          'ולא "${manifest.entrypoint}"',
        );
      }
      if (manifest.backgroundEntrypoint != null) {
        errors.add(
          'תוסף ללא ממשק (headless) אינו יכול להצהיר על '
          'contributes.background.entrypoint — קובץ הכניסה עצמו רץ ברקע',
        );
      }
    }

    if (!skipFileValidation) {
      final entrypointPath = p.normalize(
        p.join(directoryPath, manifest.entrypoint),
      );
      if (!p.isWithin(directoryPath, entrypointPath)) {
        errors.add(
          'נתיב קובץ הכניסה ${manifest.entrypoint} חורג מגבולות תיקיית התוסף',
        );
      } else if (!File(entrypointPath).existsSync()) {
        errors.add('קובץ הכניסה ${manifest.entrypoint} לא נמצא בתיקייה');
      }

      final backgroundEntrypoint = manifest.backgroundEntrypoint;
      if (backgroundEntrypoint != null) {
        final backgroundPath = p.normalize(
          p.join(directoryPath, backgroundEntrypoint),
        );
        if (!p.isWithin(directoryPath, backgroundPath)) {
          errors.add(
            'נתיב קובץ הרקע $backgroundEntrypoint חורג מגבולות תיקיית התוסף',
          );
        } else if (!File(backgroundPath).existsSync()) {
          errors.add('קובץ הרקע $backgroundEntrypoint לא נמצא בתיקייה');
        }
      }
    }

    return errors;
  }

  /// שגיאות צורה בשדה `platforms` (ריק = תקין או לא הוצהר).
  static List<String> platformsFieldErrors(PluginManifest manifest) {
    final values = manifest.platforms;
    if (values == null) return const [];
    final allowed = validPlatformValues.join(', ');
    if (!manifest.platformsIsList) {
      return ['השדה "platforms" חייב להיות מערך של פלטפורמות ($allowed)'];
    }
    if (values.isEmpty) {
      return [
        'השדה "platforms" ריק. השמיטו אותו כדי לציין את כל הפלטפורמות, או פרטו לפחות פלטפורמה אחת',
      ];
    }
    final errors = <String>[];
    final seen = <String>{};
    for (final value in values) {
      if (!validPlatformValues.contains(value)) {
        errors.add(
          'ערך לא חוקי ב-"platforms": "$value". ערכים מותרים: $allowed',
        );
        continue;
      }
      if (!seen.add(value)) {
        errors.add('הפלטפורמה "$value" מופיעה פעמיים ב-"platforms"');
      }
    }
    return errors;
  }
}
