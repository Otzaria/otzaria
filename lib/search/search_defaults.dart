import 'dart:convert';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';

/// ברירות מחדל לחיפוש, נפרדות לכל מצב: אפשרויות החיפוש המתקדם (7 תיבות
/// הסימון + ניקוד/טעמים), אפשרויות החיפוש הרגיל (5 תיבות סימון בלבד)
/// והמרווח בין מילים שלו, ומצב החיפוש שבו נפתח הדיאלוג.
/// חיפוש חדש נפתח לפי ברירת המחדל השמורה; שינוי בחלונית נשמר לסשן
/// הנוכחי בלבד וחוזר לברירת המחדל בהפעלה הבאה של התוכנה.
class SearchDefaults {
  static const _settingsKey = 'key-search-default-options';
  static const _exactSettingsKey = 'key-search-default-options-exact';
  static const _distanceKey = 'key-search-default-distance';

  // מטמון הסשן: מצב האפשרויות כפי שהמשתמש השאיר אותן בדיאלוג האחרון,
  // לכל מצב חיפוש בנפרד.
  static Map<String, bool>? _sessionOptions;
  static Map<String, bool>? _sessionExactOptions;

  // מטמון הסשן: מצב החיפוש והמרווח כפי שהמשתמש השאיר אותם בדיאלוג
  // האחרון. בהפעלה הבאה חוזרים לברירת המחדל (חיפוש רגיל / המרווח השמור).
  static SearchMode? _sessionMode;
  static int? _sessionDistance;

  SearchDefaults._();

  /// המפתחות שמותר לשמור כברירת מחדל למצב המתקדם: 7 האפשרויות +
  /// האפשרויות הבלעדיות למתקדם (ארמית, גרשיים, תרגום, ר"ת) +
  /// "ניקוד"/"טעמים".
  static const List<String> _allowedOptionKeys = [
    ...SearchQueryBuilder.availableWordOptionKeys,
    ...SearchQueryBuilder.advancedOnlyWordOptionKeys,
    ...SearchQueryBuilder.vocalizedWordOptionKeys,
  ];

  static Map<String, bool> _loadOptions(String key, List<String> allowedKeys) {
    final raw = Settings.getValue<String>(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (allowedKeys.contains(entry.key.toString()))
            entry.key.toString(): entry.value == true,
      };
    } catch (_) {
      return {};
    }
  }

  // ── חיפוש מתקדם ────────────────────────────────────────────────────

  /// ברירת המחדל השמורה (בין הפעלות) למצב המתקדם. מפתחות לא-מוכרים מסוננים.
  static Map<String, bool> loadDefaults() {
    return _loadOptions(_settingsKey, _allowedOptionKeys);
  }

  /// שומר את [options] כברירת המחדל לחיפושים מתקדמים חדשים.
  static void saveDefaults(Map<String, bool> options) {
    Settings.setValue<String>(_settingsKey, jsonEncode(options));
    _sessionOptions = Map<String, bool>.from(options);
  }

  /// האפשרויות שאיתן ייפתח חיפוש מתקדם חדש: מצב הסשן אם קיים, אחרת
  /// ברירת המחדל.
  static Map<String, bool> initialOptionsForNewSearch() {
    return Map<String, bool>.from(_sessionOptions ?? loadDefaults());
  }

  /// משמר את מצב האפשרויות של המצב המתקדם להמשך הסשן.
  static void rememberSessionOptions(Map<String, bool> options) {
    _sessionOptions = Map<String, bool>.from(options);
  }

  // ── חיפוש רגיל (מדויק) ─────────────────────────────────────────────

  /// ברירת המחדל השמורה (בין הפעלות) למצב הרגיל — רק חמש אפשרויות המילה
  /// שלו (ניקוד/טעמים וקידומות/סיומות כלליות אינם נתמכים בחיפוש הרגיל),
  /// באחסון נפרד לחלוטין מזה של המצב המתקדם.
  static Map<String, bool> loadExactDefaults() {
    return _loadOptions(
      _exactSettingsKey,
      SearchQueryBuilder.exactWordOptionKeys,
    );
  }

  /// שומר את [options] כברירת המחדל לחיפושים רגילים חדשים.
  static void saveExactDefaults(Map<String, bool> options) {
    Settings.setValue<String>(_exactSettingsKey, jsonEncode(options));
    _sessionExactOptions = Map<String, bool>.from(options);
  }

  /// האפשרויות שאיתן ייפתח חיפוש רגיל חדש: מצב הסשן אם קיים, אחרת
  /// ברירת המחדל.
  static Map<String, bool> initialExactOptionsForNewSearch() {
    return Map<String, bool>.from(_sessionExactOptions ?? loadExactDefaults());
  }

  /// משמר את מצב האפשרויות של המצב הרגיל להמשך הסשן.
  static void rememberSessionExactOptions(Map<String, bool> options) {
    _sessionExactOptions = Map<String, bool>.from(options);
  }

  // ── מצב החיפוש ──────────────────────────────────────────────────────

  /// מצב החיפוש שבו נפתח חיפוש חדש: מצב הסשן אם קיים (מעבר ידני למצב
  /// אחר נשמר עד הפעלה מחדש), אחרת חיפוש רגיל (מדויק) — ברירת המחדל
  /// של פתיחת החיפוש בכל הפעלה טרייה.
  static SearchMode initialModeForNewSearch() {
    return _sessionMode ?? SearchMode.exact;
  }

  /// משמר את מצב החיפוש להמשך הסשן (עד הפעלה מחדש של התוכנה).
  static void rememberSessionMode(SearchMode mode) {
    _sessionMode = mode;
  }

  // ── מרווח בין מילים (חיפוש רגיל/מתקדם) ─────────────────────────────

  /// ברירת המחדל השמורה (בין הפעלות) למרווח בין מילים.
  static int loadDistanceDefault() {
    final value = Settings.getValue<int>(_distanceKey) ?? 0;
    return value < 0 ? 0 : value;
  }

  /// שומר את [distance] כברירת המחדל למרווח בחיפושים חדשים.
  static void saveDistanceDefault(int distance) {
    Settings.setValue<int>(_distanceKey, distance);
    _sessionDistance = distance;
  }

  /// המרווח שאיתו ייפתח חיפוש חדש: מצב הסשן אם קיים, אחרת ברירת המחדל.
  /// (חיפוש מקורב אינו משתמש בזה — המרחק שם הוא מרחק עריכה, לא מרווח.)
  static int initialDistanceForNewSearch() {
    return _sessionDistance ?? loadDistanceDefault();
  }

  /// משמר את המרווח להמשך הסשן (נקרא בסגירת דיאלוג החיפוש).
  static void rememberSessionDistance(int distance) {
    _sessionDistance = distance;
  }
}
