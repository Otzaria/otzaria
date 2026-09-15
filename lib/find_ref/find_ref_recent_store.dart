import 'dart:convert';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// שאילתות האיתור האחרונות שהובילו לפתיחת מקור, מהחדשה לישנה.
///
/// נשמרות בהגדרות כ-JSON כדי שיישרדו בין הפעלות, ומוצגות בדיאלוג האיתור
/// כהצעות בלחיצה אחת.
class FindRefRecentStore {
  FindRefRecentStore._();

  static const String _key = 'key-find-ref-recent-queries';

  /// מספר השאילתות שנשמרות. הדיאלוג מציג רק את הראשונות שבהן.
  static const int maxEntries = 12;

  /// מחזיר את השאילתות השמורות, מהחדשה לישנה. רשימה ריקה אם אין.
  static List<String> load() {
    final raw = Settings.getValue<String>(_key, defaultValue: '') ?? '';
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is String && entry.trim().isNotEmpty) entry,
      ];
    } catch (_) {
      // ערך פגום בהגדרות לא ימנע את פתיחת הדיאלוג.
      return const [];
    }
  }

  /// מוסיף את [query] לראש הרשימה. שאילתה זהה שכבר קיימת עולה לראש
  /// במקום להיכפל.
  static void remember(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final entries = load().where((entry) => entry != trimmed).toList()
      ..insert(0, trimmed);
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    Settings.setValue<String>(_key, jsonEncode(entries));
  }

  /// מוחק את כל השאילתות השמורות.
  static void clear() => Settings.setValue<String>(_key, jsonEncode(const []));
}
