import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as p;

/// טיפול בניידות אמיתית של התקנה במצב נייד.
///
/// במצב נייד ([AppPaths.isPortable]) כל הנתונים יושבים בתיקייה ליד
/// ה-executable, אבל נתיבים אבסולוטיים שנשמרו בהגדרות וב-Hive boxes
/// (ספרייה, אינדקס, גיבויים, ספרי PDF בטאבים/היסטוריה/סימניות/סביבות
/// עבודה) נשברים כשאות הכונן משתנה (D: ↔ E:) או כשהתיקייה מועברת.
///
/// המנגנון: קובץ [_rootRecordFileName] בתוך תיקיית הנתונים שומר את נתיב
/// השורש כפי שהיה בריצה הקודמת. בהפעלה, אם השורש הנוכחי שונה — כל מחרוזת
/// שמורה שמתחילה בשורש הישן משוכתבת לשורש החדש.
class PortablePaths {
  static const String _rootRecordFileName = '.otzaria_portable_root';

  /// מפתחות settings שמכילים נתיב אבסולוטי בודד.
  static const List<String> _pathSettingsKeys = [
    SettingsRepository.keyLibraryPath,
    SettingsRepository.keyIndexPath,
    SettingsRepository.keyDatabasesPath,
    SettingsRepository.keyBackupPath,
    SettingsRepository.keyHebrewBooksPath,
    SettingsRepository.keyDbEffectivePath,
  ];

  /// Hive boxes שעלולים להכיל נתיבים בתוך מבני JSON (למשל path של PdfBook).
  static const List<String> _hiveBoxNames = [
    'tabs',
    'workspaces',
    'history',
    'bookmarks',
  ];

  /// משכתב נתיבים שמורים אם שורש הנתונים הנייד זז מאז הריצה הקודמת.
  ///
  /// חייב לרוץ אחרי `Settings.init` ואחרי `initHive` (ה-boxes חייבים
  /// להיות פתוחים), ולפני כל קוד שצורך את הנתיבים השמורים.
  static Future<void> migrateIfMoved() async {
    if (!AppPaths.isPortable) return;

    final currentRoot = p.normalize(await AppPaths.getDataRootPath());
    final recordFile = File(p.join(currentRoot, _rootRecordFileName));

    String? previousRoot;
    try {
      if (await recordFile.exists()) {
        final content = (await recordFile.readAsString()).trim();
        if (content.isNotEmpty) {
          previousRoot = p.normalize(content);
        }
      }
    } catch (e, stackTrace) {
      // קובץ פגום/לא קריא — מתנהגים כריצה ראשונה ורק רושמים מחדש.
      debugPrint('PortablePaths: failed reading root record: $e\n$stackTrace');
    }

    if (previousRoot != null && !p.equals(previousRoot, currentRoot)) {
      await _rewriteAll(previousRoot, currentRoot);
    }

    try {
      await recordFile.parent.create(recursive: true);
      await recordFile.writeAsString(currentRoot, flush: true);
    } catch (e, stackTrace) {
      // כשל בכתיבה רק דוחה את המיגרציה לריצה הבאה — לא חוסם את האתחול.
      debugPrint('PortablePaths: failed writing root record: $e\n$stackTrace');
    }
  }

  static Future<void> _rewriteAll(String oldRoot, String newRoot) async {
    debugPrint(
      'PortablePaths: data root moved "$oldRoot" -> "$newRoot", '
      'rewriting stored paths',
    );

    for (final key in _pathSettingsKeys) {
      final value = Settings.getValue<String>(key);
      if (value == null || value.isEmpty) continue;
      final rewritten = _rewritePath(value, oldRoot, newRoot);
      if (rewritten != value) {
        await Settings.setValue(key, rewritten);
      }
    }

    // תיקיות מותאמות אישית נשמרות כ-JSON עם שדות path.
    final foldersJson = Settings.getValue<String>(
      SettingsRepository.keyCustomFolders,
    );
    if (foldersJson != null && foldersJson.isNotEmpty) {
      try {
        final result = _rewriteDeep(jsonDecode(foldersJson), oldRoot, newRoot);
        if (result.changed) {
          await Settings.setValue(
            SettingsRepository.keyCustomFolders,
            jsonEncode(result.value),
          );
        }
      } catch (e, stackTrace) {
        debugPrint(
          'PortablePaths: failed rewriting custom folders: $e\n$stackTrace',
        );
      }
    }

    for (final boxName in _hiveBoxNames) {
      if (!Hive.isBoxOpen(boxName)) continue;
      final box = Hive.box(boxName);
      for (final key in box.keys.toList()) {
        final result = _rewriteDeep(box.get(key), oldRoot, newRoot);
        if (result.changed) {
          await box.put(key, result.value);
        }
      }
    }
  }

  /// עובר רקורסיבית על מבנה Hive/JSON ומשכתב כל מחרוזת שמתחילה ב-[oldRoot].
  static ({bool changed, dynamic value}) _rewriteDeep(
    dynamic value,
    String oldRoot,
    String newRoot,
  ) {
    if (value is String) {
      final rewritten = _rewritePath(value, oldRoot, newRoot);
      return (changed: rewritten != value, value: rewritten);
    }
    if (value is Map) {
      var changed = false;
      final out = <dynamic, dynamic>{};
      for (final entry in value.entries) {
        final result = _rewriteDeep(entry.value, oldRoot, newRoot);
        changed = changed || result.changed;
        out[entry.key] = result.value;
      }
      return changed
          ? (changed: true, value: out)
          : (changed: false, value: value);
    }
    if (value is List) {
      var changed = false;
      final out = <dynamic>[];
      for (final element in value) {
        final result = _rewriteDeep(element, oldRoot, newRoot);
        changed = changed || result.changed;
        out.add(result.value);
      }
      return changed
          ? (changed: true, value: out)
          : (changed: false, value: value);
    }
    return (changed: false, value: value);
  }

  /// אם [value] הוא נתיב תחת [oldRoot] (או שווה לו) — מחזיר אותו מעוגן
  /// מחדש תחת [newRoot]; אחרת מחזיר אותו כמות שהוא.
  ///
  /// ההשוואה דרך [p.equals] — לא רגישה לאותיות ב-Windows (אות כונן D: מול
  /// d:) ומיישרת הבדלי מפרידים.
  static String _rewritePath(String value, String oldRoot, String newRoot) {
    if (value.length < oldRoot.length) return value;
    if (!p.equals(value.substring(0, oldRoot.length), oldRoot)) return value;
    if (value.length > oldRoot.length) {
      final next = value[oldRoot.length];
      // התאמת prefix בלבד אינה מספיקה: D:\otzaria_data2 מתחיל ב-D:\otzaria_data
      // אבל אינו יושב תחתיו.
      if (next != '\\' && next != '/') return value;
    }
    return newRoot + value.substring(oldRoot.length);
  }
}
