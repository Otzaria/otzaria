import 'dart:convert';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/search/search_query_builder.dart';

/// מאגר גלובלי של מילים חילופיות שמורות, ממופה מילה -> רשימת חלופות.
/// כל הוספה/הסרה של חלופה בחיפוש נשמרת כאן אוטומטית, וההרחבה מופעלת
/// בחיפוש רק כשהמשתמש מדליק את המתג "חלופות שמורות" (כבוי בכל חיפוש חדש).
class SavedAlternativesStore {
  static const _settingsKey = 'key-saved-alternative-words';

  SavedAlternativesStore._();

  static String? _cachedRaw;
  static Map<String, List<String>> _cached = const {};

  static Map<String, List<String>> loadAll() => {
    for (final entry in _loadSnapshot().entries)
      entry.key: List<String>.of(entry.value),
  };

  static Map<String, List<String>> _loadSnapshot() {
    final raw = Settings.getValue<String>(_settingsKey);
    if (raw == _cachedRaw) return _cached;
    _cachedRaw = raw;
    return _cached = _decode(raw);
  }

  static Map<String, List<String>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is List)
            entry.key.toString(): (entry.value as List)
                .map((e) => e.toString())
                .toList(growable: true),
      };
    } catch (_) {
      return {};
    }
  }

  static void _saveAll(Map<String, List<String>> all) {
    Settings.setValue<String>(_settingsKey, jsonEncode(all));
  }

  /// החלופות השמורות עבור מילה בודדת.
  static List<String> alternativesFor(String word) {
    final saved = _loadSnapshot()[word.trim()];
    return saved == null ? const [] : List<String>.of(saved);
  }

  /// שומר חלופה עבור מילה. כפילויות נבלעות בשקט.
  static void addAlternative(String word, String alternative) {
    final key = word.trim();
    final alt = alternative.trim();
    if (key.isEmpty || alt.isEmpty || key == alt) return;
    final all = loadAll();
    final list = all.putIfAbsent(key, () => []);
    if (list.contains(alt)) return;
    list.add(alt);
    _saveAll(all);
  }

  /// מסיר חלופה שמורה עבור מילה (אם קיימת).
  static void removeAlternative(String word, String alternative) {
    final all = loadAll();
    final list = all[word.trim()];
    if (list == null || !list.remove(alternative.trim())) return;
    if (list.isEmpty) all.remove(word.trim());
    _saveAll(all);
  }

  /// ממזג את החלופות השמורות של מילות [query] לתוך מפת החלופות הידניות
  /// [manual] (אינדקס מילה -> חלופות), ללא כפילויות. המקור אינו משתנה.
  static Map<int, List<String>> mergeIntoQuery(
    String query,
    Map<int, List<String>> manual,
  ) {
    List<String> words;
    try {
      words = SearchQueryBuilder.splitQueryWords(query);
    } catch (_) {
      // המנוע עדיין לא אותחל — אין דרך לפצל; מחזירים את הידניות בלבד.
      return manual;
    }

    final all = _loadSnapshot();
    if (all.isEmpty) return manual;

    final merged = {
      for (final entry in manual.entries)
        entry.key: List<String>.from(entry.value),
    };
    for (var i = 0; i < words.length; i++) {
      final saved = all[words[i].trim()];
      if (saved == null || saved.isEmpty) continue;
      final list = merged.putIfAbsent(i, () => []);
      for (final alt in saved) {
        if (alt != words[i] && !list.contains(alt)) list.add(alt);
      }
    }
    return merged;
  }
}
