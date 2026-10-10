import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

enum SearchQuerySemantics { regular, smart }

/// מדיניות התאמה משותפת לחיפוש הגלובלי, לטאב הקריאה ולחלונית החיפוש בספר.
class SearchMatchPolicy {
  const SearchMatchPolicy({
    this.proximityScope = SearchScope.wordDistance,
    this.wordMatchMode = WordMatchMode.all,
    this.wordMatchCount = 2,
    this.querySemantics = SearchQuerySemantics.regular,
  });

  /// ברירת המחדל: מרווח בין מילים וכל מילות השאילתה.
  static const SearchMatchPolicy standard = SearchMatchPolicy();
  static const SearchMatchPolicy smart = SearchMatchPolicy(
    querySemantics: SearchQuerySemantics.smart,
  );

  final SearchQuerySemantics querySemantics;
  final SearchScope proximityScope;
  final WordMatchMode wordMatchMode;

  /// מספר המילים הנדרש כש-[wordMatchMode] הוא [WordMatchMode.atLeast].
  final int wordMatchCount;

  /// האם המדיניות היא ברירת המחדל. [wordMatchCount] אינו נבדק כאן: הוא
  /// משמעותי רק במצב [WordMatchMode.atLeast], שאינו ברירת המחדל בכל מקרה.
  bool get isStandard =>
      querySemantics == SearchQuerySemantics.regular && hasStandardWordMatching;

  /// האם המילים מחויבות לפי הסדר והמרווח, בלי התאמה חלקית או טווח סעיף.
  bool get hasStandardWordMatching =>
      proximityScope == SearchScope.wordDistance &&
      wordMatchMode == WordMatchMode.all;

  Map<String, dynamic> toJson() => {
    'querySemantics': querySemantics.name,
    'proximityScope': proximityScope.name,
    'wordMatchMode': wordMatchMode.name,
    'wordMatchCount': wordMatchCount,
  };

  /// קריאה סובלנית: קלט חסר או ערך שאינו מוכר חוזר לברירת המחדל, כדי ששמירה
  /// ישנה תיטען בלי לאבד את הטאב.
  factory SearchMatchPolicy.fromJson(Object? json) {
    if (json is! Map) return standard;
    return SearchMatchPolicy(
      querySemantics: SearchQuerySemantics.values.firstWhere(
        (semantics) => semantics.name == json['querySemantics'],
        orElse: () => SearchQuerySemantics.regular,
      ),
      proximityScope: SearchScope.values.firstWhere(
        (scope) => scope.name == json['proximityScope'],
        orElse: () => SearchScope.wordDistance,
      ),
      wordMatchMode: WordMatchMode.values.firstWhere(
        (mode) => mode.name == json['wordMatchMode'],
        orElse: () => WordMatchMode.all,
      ),
      wordMatchCount: json['wordMatchCount'] is int
          ? json['wordMatchCount'] as int
          : 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchMatchPolicy &&
      other.querySemantics == querySemantics &&
      other.proximityScope == proximityScope &&
      other.wordMatchMode == wordMatchMode &&
      other.wordMatchCount == wordMatchCount;

  @override
  int get hashCode => Object.hash(
    querySemantics,
    proximityScope,
    wordMatchMode,
    wordMatchCount,
  );

  @override
  String toString() =>
      'SearchMatchPolicy(querySemantics: $querySemantics, proximityScope: $proximityScope, '
      'wordMatchMode: $wordMatchMode, wordMatchCount: $wordMatchCount)';
}
