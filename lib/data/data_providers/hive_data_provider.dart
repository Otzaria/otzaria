import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';

/// `<dataRoot>/windows/slot-N`: שורשי Hive ועותקי `pdfium-window-N.dll` שהשאירו
/// גרסאות שבהן כל חלון היה מנוע נפרד. אינה מגובה — ראו [deleteStaleWindowRoots].
const String windowRootsDirName = 'windows';

/// משנה את שם [windowRootsDirName] ומוחק ברקע, כדי שחלון חדש יקבל תיקייה נקייה.
/// קבצים נעולים מדולגים בלי לעכב את העלייה.
Future<void> deleteStaleWindowRoots() async {
  try {
    final dataRoot = await AppPaths.getDataRootPath();
    final root = Directory(p.join(dataRoot, windowRootsDirName));
    if (await root.exists()) {
      final stalePath =
          '${root.path}$_staleSuffix$pid-${DateTime.now().microsecondsSinceEpoch}';
      await root.rename(stalePath);
    }
    pendingStaleRootsDeletion = _deleteRenamedRoots(dataRoot);
  } catch (e) {
    debugPrint('⚠️ deleteStaleWindowRoots failed: $e');
  }
}

const String _staleSuffix = '.stale-';

/// The background deletion started by [deleteStaleWindowRoots].
@visibleForTesting
Future<void>? pendingStaleRootsDeletion;

/// Also removes folders an earlier deletion could not finish.
Future<void> _deleteRenamedRoots(String dataRoot) async {
  try {
    await for (final entity in Directory(dataRoot).list()) {
      if (entity is! Directory ||
          !p
              .basename(entity.path)
              .startsWith('$windowRootsDirName$_staleSuffix')) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } catch (e) {
        debugPrint('⚠️ stale window root not deleted: $e');
      }
    }
  } catch (e) {
    debugPrint('⚠️ stale window roots scan failed: $e');
  }
}

/// A cache access provider class for shared preferences using Hive library
class HiveCache extends CacheProvider {
  Box? _preferences;
  static const String keyName = 'app_preferences';

  @override
  Stream<String> get changes => changedKeys();

  @override
  Future<void> init() async {
    if (!kIsWeb) {
      final defaultDirectory = await AppPaths.getDataRootPath();
      _preferences = await Hive.openBox<dynamic>(
        keyName,
        path: defaultDirectory,
      );
    }
  }

  @override
  bool? getBool(String key, {bool? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  double? getDouble(String key, {double? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  int? getInt(String key, {int? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  String? getString(String key, {String? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    await _preferences?.put(key, value);
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    await _preferences?.put(key, value);
  }

  @override
  Future<void> setInt(String key, int? value) async {
    await _preferences?.put(key, value);
  }

  @override
  Future<void> setString(String key, String? value) async {
    await _preferences?.put(key, value);
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    await _preferences?.put(key, value);
  }

  @override
  bool containsKey(String key) {
    return _preferences?.containsKey(key) ?? false;
  }

  @override
  Set getKeys() {
    return _preferences?.keys.toSet() ?? {};
  }

  @override
  Future<void> remove(String key) async {
    if (containsKey(key)) {
      await _preferences?.delete(key);
    }
  }

  @override
  Future<void> removeAll() async {
    await _preferences?.deleteAll(getKeys().cast<String>());
  }

  /// שם המפתח של כל כתיבה או מחיקה בקובץ ההגדרות, מכל מקור: כל החלונות באותו
  /// תהליך חולקים את הקופסה. ריק כשהקופסה לא פתוחה (בדיקות עם מטמון בזיכרון).
  static Stream<String> changedKeys() {
    if (!Hive.isBoxOpen(keyName)) return const Stream<String>.empty();
    return Hive.box<dynamic>(keyName).watch().map((event) => '${event.key}');
  }

  /// מחיקת כל ההגדרות, בהמתנה לסיומה.
  static Future<void> clearAllPreferences() async {
    if (!Hive.isBoxOpen(keyName)) return;
    await Hive.box<dynamic>(keyName).clear();
  }

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    var value = _preferences?.get(key);
    if (value is T) {
      return value;
    }
    return defaultValue;
  }
}
