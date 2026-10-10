import 'dart:convert';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder;

/// ברירות מחדל לחיפוש, נפרדות לכל מצב: אפשרויות החיפוש המתקדם (7 תיבות
/// הסימון + ניקוד/טעמים), אפשרויות החיפוש הרגיל (5 תיבות סימון בלבד)
/// והמרווח בין מילים שלו, מצב החיפוש שבו נפתח הדיאלוג, ותצוגת התוצאות
/// (מיון ואיחוד).
///
/// חיפוש חדש נפתח לפי ברירת המחדל השמורה. למה שנקבע בדיאלוג יש גם שכבת
/// סשן — `remember*Session*` נשמר עד סגירת התוכנה בלבד — ולעומת זאת
/// תצוגת התוצאות, שנקבעת בסרגל התוצאות, נשמרת ישר לברירת המחדל.
class SearchDefaults {
  static const _settingsKey = 'key-search-default-options';
  static const _exactSettingsKey = 'key-search-default-options-exact';
  static const _distanceKey = 'key-search-default-distance';
  static const _modeKey = 'key-search-default-mode';
  static const _semanticModeKey = 'key-search-default-semantic-mode';

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
  /// אחר נשמר עד הפעלה מחדש), אחרת ברירת המחדל השמורה.
  static SearchMode initialModeForNewSearch() {
    return _sessionMode ?? loadModeDefault();
  }

  /// מצב החיפוש השמור (בין הפעלות) לפתיחת חיפוש חדש.
  static SearchMode loadModeDefault() =>
      _loadEnum(_modeKey, SearchMode.values, SearchMode.exact);

  /// שומר את [mode] כמצב שבו ייפתח כל חיפוש חדש.
  static void saveModeDefault(SearchMode mode) {
    _saveEnum(_modeKey, mode.name);
    _sessionMode = mode;
    if (Settings.isInitialized) {
      Settings.setValue<bool>(_semanticModeKey, false);
    }
    _sessionSemantic = false;
  }

  /// משמר את מצב החיפוש להמשך הסשן (עד הפעלה מחדש של התוכנה).
  static void rememberSessionMode(SearchMode mode) {
    _sessionMode = mode;
  }

  // החיפוש החכם אינו SearchMode: הוא נבחר מעל המצב הלקסיקלי, שנשאר כגיבוי
  // כשהמצב החכם אינו זמין.
  static bool? _sessionSemantic;

  /// האם חיפוש חדש נפתח במצב החכם: מצב הסשן אם קיים, אחרת ברירת המחדל.
  static bool initialSemanticForNewSearch() =>
      _sessionSemantic ?? loadSemanticDefault();

  /// האם המצב החכם נשמר (בין הפעלות) כמצב פתיחת חיפוש חדש.
  static bool loadSemanticDefault() {
    if (!Settings.isInitialized) return false;
    return Settings.getValue<bool>(_semanticModeKey) ?? false;
  }

  /// שומר את המצב החכם כמצב פתיחת חיפוש חדש; [saveModeDefault] מבטל אותו.
  static void saveSemanticDefault() {
    if (Settings.isInitialized) Settings.setValue<bool>(_semanticModeKey, true);
    _sessionSemantic = true;
  }

  /// משמר את בחירת המצב החכם להמשך הסשן.
  static void rememberSessionSemantic(bool semantic) {
    _sessionSemantic = semantic;
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

  // ── תצוגת התוצאות: מיון ואיחוד ──────────────────────────────────────
  // שתי ההעדפות נשמרות בשם הערך ולא באינדקסו, כדי שהוספת ערך באמצע ה-enum
  // לא תהפוך העדפה שמורה לערך אחר. (ה-JSON של הטאב אינדקסי מאז ומתמיד.)

  static const _sortOrderKey = 'key-search-results-sort-order';
  static const _groupingKey = 'key-search-results-grouping';

  /// המיון שאיתו נפתח חיפוש חדש — בחירת המשתמש האחרונה במסך התוצאות.
  static ResultsOrder initialSortOrderForNewSearch() => _loadEnum(
    _sortOrderKey,
    ResultsOrder.values,
    const SearchConfiguration().sortBy,
  );

  /// שומר את המיון שהמשתמש בחר כברירת מחדל לחיפושים הבאים.
  static void saveSortOrderDefault(ResultsOrder order) =>
      _saveEnum(_sortOrderKey, order.name);

  /// מצב איחוד התוצאות שאיתו נפתח חיפוש חדש — בחירת המשתמש האחרונה.
  static ResultGroupingMode initialResultGroupingForNewSearch() => _loadEnum(
    _groupingKey,
    ResultGroupingMode.values,
    const SearchConfiguration().resultGrouping,
  );

  /// שומר את מצב איחוד התוצאות שהמשתמש בחר כברירת מחדל לחיפושים הבאים.
  static void saveResultGroupingDefault(ResultGroupingMode grouping) =>
      _saveEnum(_groupingKey, grouping.name);

  static const _treeOpenKey = 'key-search-results-tree-open';

  /// האם עץ סינון התוצאות ייפתח פתוח בחיפוש חדש — בחירת המשתמש האחרונה.
  static bool initialResultsTreeOpenForNewSearch() {
    if (!Settings.isInitialized) return true;
    return Settings.getValue<bool>(_treeOpenKey) ?? true;
  }

  /// שומר את הסתרת/הצגת עץ התוצאות כברירת מחדל לחיפושים הבאים.
  static void saveResultsTreeOpenDefault(bool isOpen) {
    if (!Settings.isInitialized) return;
    Settings.setValue<bool>(_treeOpenKey, isOpen);
  }

  /// [base] בתוספת ברירות המחדל השמורות לתצוגת התוצאות — מיון ואיחוד —
  /// הדורסות את מה שיש ב-[base]. מסלולי השחזור (JSON, שכפול, היסטוריה)
  /// אינם עוברים כאן, כדי שטאב משוחזר יישאר עם הערכים שנשמרו איתו.
  static SearchConfiguration withResultPreferences([
    SearchConfiguration base = const SearchConfiguration(),
  ]) {
    return base.copyWith(
      sortBy: initialSortOrderForNewSearch(),
      resultGrouping: initialResultGroupingForNewSearch(),
    );
  }

  static T _loadEnum<T extends Enum>(String key, List<T> values, T fallback) {
    // Settings לא אותחל (בדיקות ווידג'ט / אתחול מוקדם) — אין העדפות לקרוא.
    if (!Settings.isInitialized) return fallback;
    final raw = Settings.getValue<String>(key);
    if (raw == null || raw.isEmpty) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }

  static void _saveEnum(String key, String name) {
    if (!Settings.isInitialized) return;
    Settings.setValue<String>(key, name);
  }
}
