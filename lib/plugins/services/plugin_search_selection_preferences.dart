import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

/// זיכרון הבחירה האחרונה בשורות החיפוש הסטטיות של תוספים.
///
/// המפתח הוא `<pluginId>/<itemId>`, וערך שמור גובר על `defaultValue` שבמניפסט —
/// אלא בשורה עם `persist: false`, שאינה נשמרת ואינה נקראת מכאן.
class PluginSearchSelectionPreferences {
  static const String _key = 'key-plugin-search-selections';

  PluginSearchSelectionPreferences._();

  /// ערך השורה: בחירה בטאב הנוכחי ([tabValue]) גוברת על הבחירה השמורה
  /// ([persistedValue], רק כש-`item.persist`), וזו על `defaultValue`.
  static bool resolveSelection(
    PluginSearchDialogItem item, {
    bool? tabValue,
    bool? persistedValue,
  }) => tabValue ?? (item.persist ? persistedValue : null) ?? item.defaultValue;

  /// הבחירות השמורות אחרי ש-[key] קיבל את [value]; `null` כשאין מה לשמור
  /// (שורה עם `persist: false`).
  static Map<String, bool>? persistedAfterChange(
    Map<String, bool> persisted,
    String key,
    PluginSearchDialogItem item,
    bool value,
  ) => item.persist ? {...persisted, key: value} : null;

  static Map<String, bool> load() {
    final String? raw;
    try {
      raw = Settings.getValue<String>(_key);
    } catch (e) {
      // Settings לא אותחל (בדיקות ווידג'ט / אתחול מוקדם) — אין העדפות.
      debugPrint('[PluginSearchSelections] settings unavailable: $e');
      return const {};
    }
    if (raw == null || raw.trim().isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is bool)
            entry.key as String: entry.value as bool,
      };
    } catch (e) {
      debugPrint('[PluginSearchSelections] JSON parse failed: $e');
      return const {};
    }
  }

  static Future<void> save(Map<String, bool> selections) async {
    try {
      await Settings.setValue<String>(_key, jsonEncode(selections));
    } catch (e) {
      debugPrint(
        '[PluginSearchSelections] settings unavailable, not saved: $e',
      );
    }
  }
}
