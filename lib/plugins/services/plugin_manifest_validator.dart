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
    bool skipAppVersionValidation = false,
    bool skipFileValidation = false,
  }) async {
    final errors = await collectManifestErrors(
      manifest: manifest,
      directoryPath: directoryPath,
      currentAppVersion: currentAppVersion,
      skipAppVersionValidation: skipAppVersionValidation,
      skipFileValidation: skipFileValidation,
    );
    if (errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }
  }

  /// מאמת מניפסט ומחזיר את רשימת כל השגיאות (ריקה = תקין). אינו זורק.
  static Future<List<String>> collectManifestErrors({
    required PluginManifest manifest,
    required String directoryPath,
    String? currentAppVersion,
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
      }
    }

    for (final perm in manifest.permissions) {
      if (!pluginValidPermissions.contains(perm)) {
        final hint = apiCallToPermissionHint[perm];
        if (hint != null) {
          errors.add('הרשאה לא חוקית: "$perm". האם התכוונת ל-"$hint"?');
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
        'toolTab.iconName חייב להיות שם אייקון FluentUI 24px תקין '
        '(למשל "book_24_regular" או "calendar_24_filled")',
      );
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
}
