import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מצבי החיפוש השונים
enum SearchMode {
  advanced, // חיפוש מתקדם (slop/word-distance)
  exact, // חיפוש מדוייק
  fuzzy, // חיפוש מקורב (slop/word-distance)
}

extension SearchModePresentation on SearchMode {
  String get shortLabel => switch (this) {
    SearchMode.advanced => 'מתקדם',
    SearchMode.exact => 'מדויק',
    SearchMode.fuzzy => 'מקורב',
  };

  String get tooltip => switch (this) {
    SearchMode.advanced =>
      'חיפוש מתקדם מאפשר קידומות, סיומות, מילים חילופיות ומרווחים בין מילים.',
    SearchMode.exact =>
      'חיפוש מדויק מחפש את המילים כפי שהוקלדו, בלי התאמות מקורבות.',
    SearchMode.fuzzy =>
      'חיפוש מקורב מרשה התאמות דומות ושיבושי כתיב קלים לפי מרחק החיפוש.',
  };
}

extension SearchScopePresentation on SearchScope {
  String get label => switch (this) {
    SearchScope.wordDistance => 'מרווח בין מילים',
    SearchScope.sameParagraph => 'באותה פסקה',
    SearchScope.sameSection => 'תחת אותה כותרת',
  };

  String get tooltip => switch (this) {
    SearchScope.wordDistance =>
      'המילים מופיעות לפי הסדר, עם מגבלת מילים ביניהן.',
    SearchScope.sameParagraph =>
      'כל מילות החיפוש נמצאות באותה פסקה, בכל סדר ובכל מרחק.',
    SearchScope.sameSection =>
      'כל מילות החיפוש נמצאות תחת אותה כותרת (סעיף/פרק), גם בפסקאות שונות.',
  };
}

extension WordMatchModePresentation on WordMatchMode {
  String get label => switch (this) {
    WordMatchMode.all => 'כל המילים',
    WordMatchMode.anyWord => 'מילה אחת לפחות',
    WordMatchMode.mostWords => 'רוב המילים',
    WordMatchMode.atLeast => 'לפחות X מילים',
  };

  String get tooltip => switch (this) {
    WordMatchMode.all => 'כל מילות החיפוש חייבות להופיע (ברירת המחדל).',
    WordMatchMode.anyWord => 'די בהופעה של מילה אחת ממילות החיפוש.',
    WordMatchMode.mostWords => 'רוב מילות החיפוש מופיעות (יותר ממחצית).',
    WordMatchMode.atLeast => 'לפחות מספר מילים שתבחר מופיעות בתוצאה.',
  };
}

/// מצב איחוד תוצאות (עטיפת אפליקציה ל-[ResultGrouping] של המנוע,
/// עם ערך "ללא" שאינו קיים שם).
enum ResultGroupingMode {
  none, // רשימה שטוחה — ההתנהגות הרגילה
  sameSection, // איחוד תוצאות מאותו סעיף/כותרת עם מונה "בטווח"
  identicalText, // איחוד שורות זהות גם בין ספרים שונים
}

extension ResultGroupingModePresentation on ResultGroupingMode {
  String get label => switch (this) {
    ResultGroupingMode.none => 'ללא איחוד',
    ResultGroupingMode.sameSection => 'לפי טווח (סעיף)',
    ResultGroupingMode.identicalText => 'טקסט זהה',
  };

  String get tooltip => switch (this) {
    ResultGroupingMode.none => 'כל תוצאה מוצגת בנפרד.',
    ResultGroupingMode.sameSection =>
      'תוצאות מאותו סעיף (תחת אותה כותרת) מתאחדות לכרטיס אחד עם מונה.',
    ResultGroupingMode.identicalText =>
      'קטעים זהים שמופיעים בכמה ספרים מתאחדים לתוצאה אחת.',
  };

  /// ערך המנוע המקביל; null במצב "ללא".
  ResultGrouping? get engineGrouping => switch (this) {
    ResultGroupingMode.none => null,
    ResultGroupingMode.sameSection => ResultGrouping.sameSection,
    ResultGroupingMode.identicalText => ResultGrouping.identicalText,
  };
}

/// מחלקה שמרכזת את כל הגדרות החיפוש במקום אחד
/// כוללת הגדרות קיימות והגדרות עתידיות לרגקס
class SearchConfiguration {
  // הגדרות חיפוש קיימות
  final int distance;

  /// טווח הקרבה בין מילות החיפוש במצב מתקדם: מרווח מילים (ברירת מחדל),
  /// כל המילים באותה פסקה, או כל המילים תחת אותה כותרת (סעיף/פרק).
  final SearchScope proximityScope;
  final SearchMode searchMode;
  final ResultsOrder sortBy;
  final int numResults;
  final List<String> currentFacets;

  /// טווח החיפוש המקורי שנקבע בדיאלוג (לא משתנה ע"י לחיצה בעץ התוצאות)
  /// משמש לספירת facets ולבאנר חיווי
  final List<String> searchScopeFacets;

  /// איחוד תוצאות: ללא / לפי סעיף ("נמצאו X תוצאות בטווח") / טקסט זהה.
  final ResultGroupingMode resultGrouping;

  /// כמה ממילות השאילתה חייבות להופיע (מצב מתקדם בלבד): כולן (ברירת
  /// המחדל), מילה אחת, רוב, או לפחות [wordMatchCount].
  final WordMatchMode wordMatchMode;

  /// מספר המילים הנדרש כש-[wordMatchMode] הוא atLeast.
  final int wordMatchCount;

  // חיפוש מנוקד (ניקוד/טעמים) אינו דגל גלובלי: הוא אפשרות פר-מילה במפות
  // searchOptions של הטאב, כמו שאר אפשרויות החיפוש המתקדם — ראה
  // SearchQueryBuilder.vocalizedWordOptionKeys.

  // הגדרות רגקס עתידיות (מוכנות להרחבה)
  final bool regexEnabled;
  final bool caseSensitive;
  final bool multiline;
  final bool dotAll;
  final bool unicode;

  const SearchConfiguration({
    // ערכי ברירת מחדל קיימים
    this.distance = 0,
    this.proximityScope = SearchScope.wordDistance,
    this.searchMode = SearchMode.advanced,
    this.sortBy = ResultsOrder.catalogue,
    this.numResults = 100,
    this.currentFacets = const ["/"],
    this.searchScopeFacets = const ["/"],
    this.resultGrouping = ResultGroupingMode.none,
    this.wordMatchMode = WordMatchMode.all,
    this.wordMatchCount = 2,
    // ערכי ברירת מחדל לרגקס
    this.regexEnabled = false,
    this.caseSensitive = false,
    this.multiline = false,
    this.dotAll = false,
    this.unicode = true,
  });

  /// יוצר עותק עם שינויים
  SearchConfiguration copyWith({
    int? distance,
    SearchScope? proximityScope,
    SearchMode? searchMode,
    ResultsOrder? sortBy,
    int? numResults,
    List<String>? currentFacets,
    List<String>? searchScopeFacets,
    ResultGroupingMode? resultGrouping,
    WordMatchMode? wordMatchMode,
    int? wordMatchCount,
    bool? regexEnabled,
    bool? caseSensitive,
    bool? multiline,
    bool? dotAll,
    bool? unicode,
  }) {
    return SearchConfiguration(
      distance: distance ?? this.distance,
      proximityScope: proximityScope ?? this.proximityScope,
      searchMode: searchMode ?? this.searchMode,
      sortBy: sortBy ?? this.sortBy,
      numResults: numResults ?? this.numResults,
      currentFacets: currentFacets ?? this.currentFacets,
      searchScopeFacets: searchScopeFacets ?? this.searchScopeFacets,
      resultGrouping: resultGrouping ?? this.resultGrouping,
      wordMatchMode: wordMatchMode ?? this.wordMatchMode,
      wordMatchCount: wordMatchCount ?? this.wordMatchCount,
      regexEnabled: regexEnabled ?? this.regexEnabled,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      multiline: multiline ?? this.multiline,
      dotAll: dotAll ?? this.dotAll,
      unicode: unicode ?? this.unicode,
    );
  }

  /// המרה למפה לשמירה או העברה
  Map<String, dynamic> toMap() {
    return {
      'distance': distance,
      'proximityScope': proximityScope.index,
      'searchMode': searchMode.index,
      'sortBy': sortBy.index,
      'numResults': numResults,
      'currentFacets': currentFacets,
      'searchScopeFacets': searchScopeFacets,
      'resultGrouping': resultGrouping.index,
      'wordMatchMode': wordMatchMode.index,
      'wordMatchCount': wordMatchCount,
      'regexEnabled': regexEnabled,
      'caseSensitive': caseSensitive,
      'multiline': multiline,
      'dotAll': dotAll,
      'unicode': unicode,
    };
  }

  /// יצירה ממפה. אינדקסי enum שאינם בטווח (כולל שליליים או לא-מספריים)
  /// נופלים לברירת המחדל במקום לזרוק RangeError.
  factory SearchConfiguration.fromMap(Map<String, dynamic> map) {
    T enumFrom<T>(List<T> values, Object? raw, T fallback) {
      return raw is int && raw >= 0 && raw < values.length
          ? values[raw]
          : fallback;
    }

    return SearchConfiguration(
      distance: map['distance'] ?? 0,
      proximityScope: enumFrom(
        SearchScope.values,
        map['proximityScope'],
        SearchScope.wordDistance,
      ),
      searchMode: enumFrom(
        SearchMode.values,
        map['searchMode'],
        SearchMode.advanced,
      ),
      sortBy: enumFrom(
        ResultsOrder.values,
        map['sortBy'],
        ResultsOrder.catalogue,
      ),
      numResults: map['numResults'] ?? 100,
      currentFacets: List<String>.from(map['currentFacets'] ?? ["/"]),
      searchScopeFacets: List<String>.from(map['searchScopeFacets'] ?? ["/"]),
      resultGrouping: enumFrom(
        ResultGroupingMode.values,
        map['resultGrouping'],
        ResultGroupingMode.none,
      ),
      wordMatchMode: enumFrom(
        WordMatchMode.values,
        map['wordMatchMode'],
        WordMatchMode.all,
      ),
      wordMatchCount: switch (map['wordMatchCount']) {
        final int count when count >= 1 => count,
        _ => 2,
      },
      regexEnabled: map['regexEnabled'] ?? false,
      caseSensitive: map['caseSensitive'] ?? false,
      multiline: map['multiline'] ?? false,
      dotAll: map['dotAll'] ?? false,
      unicode: map['unicode'] ?? true,
    );
  }

  /// בדיקה אם החיפוש במצב רגקס
  bool get isRegexMode => regexEnabled;

  /// קבלת דגלי רגקס כמחרוזת (לשימוש עתידי)
  String get regexFlags {
    String flags = '';
    if (!caseSensitive) flags += 'i';
    if (multiline) flags += 'm';
    if (dotAll) flags += 's';
    if (unicode) flags += 'u';
    return flags;
  }

  // Getters לתאימות לאחור
  bool get fuzzy => searchMode == SearchMode.fuzzy;
  bool get isAdvancedSearchEnabled => searchMode == SearchMode.advanced;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchConfiguration &&
        other.distance == distance &&
        other.proximityScope == proximityScope &&
        other.searchMode == searchMode &&
        other.sortBy == sortBy &&
        other.numResults == numResults &&
        other.currentFacets.toString() == currentFacets.toString() &&
        other.searchScopeFacets.toString() == searchScopeFacets.toString() &&
        other.resultGrouping == resultGrouping &&
        other.wordMatchMode == wordMatchMode &&
        other.wordMatchCount == wordMatchCount &&
        other.regexEnabled == regexEnabled &&
        other.caseSensitive == caseSensitive &&
        other.multiline == multiline &&
        other.dotAll == dotAll &&
        other.unicode == unicode;
  }

  @override
  int get hashCode {
    return Object.hash(
      distance,
      proximityScope,
      searchMode,
      sortBy,
      numResults,
      currentFacets,
      searchScopeFacets,
      resultGrouping,
      wordMatchMode,
      wordMatchCount,
      regexEnabled,
      caseSensitive,
      multiline,
      dotAll,
      unicode,
    );
  }

  @override
  String toString() {
    return 'SearchConfiguration('
        'distance: $distance, '
        'proximityScope: $proximityScope, '
        'searchMode: $searchMode, '
        'sortBy: $sortBy, '
        'numResults: $numResults, '
        'facets: $currentFacets, '
        'scope: $searchScopeFacets, '
        'regex: $regexEnabled, '
        'caseSensitive: $caseSensitive, '
        'multiline: $multiline, '
        'dotAll: $dotAll, '
        'unicode: $unicode'
        ')';
  }
}
