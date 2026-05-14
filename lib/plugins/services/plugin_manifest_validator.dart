import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';

class PluginManifestValidator {
  static Future<void> validateManifest({
    required PluginManifest manifest,
    required String directoryPath,
    String? currentAppVersion,
    bool skipAppVersionValidation = false,
  }) async {
    if (manifest.schemaVersion != 1) {
      throw Exception(
          'גרסת סכמה ${manifest.schemaVersion} של התוסף אינה נתמכת');
    }

    if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(manifest.id)) {
      throw Exception('מזהה התוסף אינו תקין');
    }

    if (!RegExp(r'^\d+\.\d+\.\d+(?:\+.*)?$').hasMatch(manifest.version)) {
      throw Exception(
          'גרסת התוסף במניפסט אינה חוקית. נדרש פורמט SemVer חוקיות.');
    }

    int compareVersionsStrict(String v1, String v2) {
      return PluginVersionUtils.compareCoreVersions(v1, v2);
    }

    if (!skipAppVersionValidation) {
      if (currentAppVersion == null) {
        throw Exception(
            'currentAppVersion is required when skipAppVersionValidation is false');
      }
      if (compareVersionsStrict(currentAppVersion, manifest.minAppVersion) <
          0) {
        throw Exception(
            'התוסף דורש אוצריא בגרסה ${manifest.minAppVersion} לפחות, אך מותקנת $currentAppVersion');
      }
      if (manifest.maxAppVersion != null &&
          compareVersionsStrict(currentAppVersion, manifest.maxAppVersion!) >
              0) {
        throw Exception(
            'התוסף מיועד לאוצריא עד גרסה ${manifest.maxAppVersion} בלבד, אך מותקנת $currentAppVersion');
      }
    }

    for (final perm in manifest.permissions) {
      if (!pluginValidPermissions.contains(perm)) {
        final hint = apiCallToPermissionHint[perm];
        if (hint != null) {
          throw Exception('הרשאה לא חוקית: "$perm". האם התכוונת ל-"$hint"?');
        }
        throw Exception('הרשאה לא חוקית שנדרשת על ידי התוסף: $perm');
      }
    }

    if (manifest.databaseSources.isNotEmpty &&
        !manifest.permissions.contains('database.read')) {
      throw Exception(
          'התוסף מצהיר על contributes.databaseSources אך לא מבקש את ההרשאה database.read');
    }

    for (final source in manifest.databaseSources) {
      final id = source['id'];
      final label = source['label'];
      final required = source['required'];

      if (id is! String || id.isEmpty) {
        throw Exception(
            'כל ערך ב-contributes.databaseSources חייב לכלול id מסוג string');
      }
      if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(id)) {
        throw Exception('מזהה מקור מסד נתונים אינו תקין: "$id"');
      }
      if (label != null && label is! String) {
        throw Exception(
            'השדה label ב-contributes.databaseSources חייב להיות string');
      }
      if (required != null && required is! bool) {
        throw Exception(
            'השדה required ב-contributes.databaseSources חייב להיות bool');
      }
    }

    final iconName = manifest.toolTabIconName;
    if (iconName != null &&
        !PluginManifest.toolTabIconNamePattern.hasMatch(iconName)) {
      throw Exception(
          'toolTab.iconName חייב להיות שם אייקון FluentUI 24px תקין '
          '(למשל "book_24_regular" או "calendar_24_filled")');
    }

    final entrypointPath =
        p.normalize(p.join(directoryPath, manifest.entrypoint));
    if (!p.isWithin(directoryPath, entrypointPath)) {
      throw Exception(
          'נתיב קובץ הכניסה ${manifest.entrypoint} חורג מגבולות תיקיית התוסף');
    }
    if (!File(entrypointPath).existsSync()) {
      throw Exception('קובץ הכניסה ${manifest.entrypoint} לא נמצא בתיקייה');
    }
  }
}
