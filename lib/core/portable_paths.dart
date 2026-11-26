import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
/// שמורה שמתחילה בשורש הישן משוכתבת לשורש החדש. נתיב מחוץ לשורש (למשל
/// ספרייה שיושבת על אותו כונן נייד, ליד תיקיית האפליקציה) משוכתב יחסית
/// לבסיס שזז יחד עם השורש, ורק כשהוא חסר במקומו הישן וקיים במקום החדש.
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

  /// מפתחות settings שמכילים JSON עם נתיבים.
  static const List<String> _jsonPathSettingsKeys = [
    SettingsRepository.keyCustomFolders,
    SettingsRepository.keyAttachedLibraries,
    SettingsRepository.keyAttachedLibraryFolders,
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

    final base = _movedBase(oldRoot, newRoot);
    String rewrite(String value) {
      final underRoot = _rewritePath(value, oldRoot, newRoot);
      if (underRoot != value || base == null) return underRoot;
      final onMovedBase = _rewritePath(value, base.from, base.to);
      if (onMovedBase == value) return value;
      return !_exists(value) && _exists(onMovedBase) ? onMovedBase : value;
    }

    for (final key in [..._pathSettingsKeys, ..._jsonPathSettingsKeys]) {
      final value = Settings.getValue<String>(key);
      if (value == null || value.isEmpty) continue;
      final isJson = _jsonPathSettingsKeys.contains(key);
      try {
        final decoded = isJson ? jsonDecode(value) : value;
        final result = _rewriteDeep(decoded, rewrite);
        if (result.changed) {
          await Settings.setValue<String>(
            key,
            isJson ? jsonEncode(result.value) : result.value as String,
          );
        }
      } catch (e, stackTrace) {
        debugPrint('PortablePaths: failed rewriting $key: $e\n$stackTrace');
      }
    }

    for (final boxName in _hiveBoxNames) {
      if (!Hive.isBoxOpen(boxName)) continue;
      final box = Hive.box(boxName);
      for (final key in box.keys.toList()) {
        final result = _rewriteDeep(box.get(key), rewrite);
        if (result.changed) {
          await box.put(key, result.value);
        }
      }
    }
  }

  /// הבסיס שזז יחד עם שורש הנתונים: [oldRoot] ו-[newRoot] בלי רכיבי
  /// הסיום המשותפים (תיקיית הנתונים ותיקיית האפליקציה, אם שמה לא השתנה).
  /// כשרק אות הכונן התחלפה — שורשי הכוננים עצמם. null כשאין רכיב סיום
  /// משותף, או כשהבסיס לא השתנה.
  static ({String from, String to})? _movedBase(
    String oldRoot,
    String newRoot,
  ) {
    final oldParts = p.split(oldRoot);
    final newParts = p.split(newRoot);
    var common = 0;
    while (common < oldParts.length - 1 &&
        common < newParts.length - 1 &&
        p.equals(
          oldParts[oldParts.length - 1 - common],
          newParts[newParts.length - 1 - common],
        )) {
      common++;
    }
    if (common == 0) return null;
    final from = p.joinAll(oldParts.take(oldParts.length - common));
    final to = p.joinAll(newParts.take(newParts.length - common));
    return p.equals(from, to) ? null : (from: from, to: to);
  }

  static bool _exists(String value) {
    final path = value.startsWith('folder:')
        ? value.substring('folder:'.length)
        : value;
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  /// עובר רקורסיבית על מבנה Hive/JSON ומשכתב כל מחרוזת דרך [rewrite].
  static ({bool changed, dynamic value}) _rewriteDeep(
    dynamic value,
    String Function(String) rewrite,
  ) {
    if (value is String) {
      final rewritten = rewrite(value);
      return (changed: rewritten != value, value: rewritten);
    }
    if (value is Map) {
      var changed = false;
      final out = <dynamic, dynamic>{};
      for (final entry in value.entries) {
        final result = _rewriteDeep(entry.value, rewrite);
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
        final result = _rewriteDeep(element, rewrite);
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
    // מקור של מסד מצורף נשמר כ-"folder:<נתיב>".
    final start = value.startsWith('folder:') ? 'folder:'.length : 0;
    final end = start + oldRoot.length;
    if (value.length < end) return value;
    if (!p.equals(value.substring(start, end), oldRoot)) return value;
    // שורש כונן (E:\) כבר מסתיים במפריד.
    if (value.length > end && !oldRoot.endsWith(p.separator)) {
      final next = value[end];
      // התאמת prefix בלבד אינה מספיקה: D:\otzaria_data2 מתחיל ב-D:\otzaria_data
      // אבל אינו יושב תחתיו.
      if (next != '\\' && next != '/') return value;
    }
    return value.substring(0, start) + newRoot + value.substring(end);
  }
}
