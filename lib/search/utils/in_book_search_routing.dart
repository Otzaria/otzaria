import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';

/// פרמטרי החיפוש שנמסרים לטאב הקריאה (ספר טקסט או PDF) בפתיחת תוצאת חיפוש.
class InBookSearchParameters {
  const InBookSearchParameters({
    required this.searchMode,
    required this.distance,
    this.matchPolicy = SearchMatchPolicy.standard,
  });

  final SearchMode searchMode;
  final int distance;
  final SearchMatchPolicy matchPolicy;

  @override
  bool operator ==(Object other) =>
      other is InBookSearchParameters &&
      other.searchMode == searchMode &&
      other.distance == distance &&
      other.matchPolicy == matchPolicy;

  @override
  int get hashCode => Object.hash(searchMode, distance, matchPolicy);

  @override
  String toString() =>
      'InBookSearchParameters(searchMode: $searchMode, distance: $distance, '
      'matchPolicy: $matchPolicy)';
}

/// ניתוב חיפוש בתוך ספר פתוח בין שני המסלולים: המסלול הפשוט (סריקת מחרוזת
/// ליטרלית על שורות הספר) ומסלול מנוע החיפוש. מקור אמת יחיד לפתיחת תוצאה
/// מהחיפוש הגלובלי ולחלוניות החיפוש בספר וב-PDF.
class InBookSearchRouting {
  const InBookSearchRouting._();

  /// האם השאילתה ניתנת להרצה כחיפוש ליטרלי מקומי בספר.
  ///
  /// כל תוספת על שאילתה ליטרלית — מרווח בין מילים, אפשרות פר-מילה, מילה
  /// חלופית, מרווח ידני, מצב מתקדם/מקורב, טווח קרבה או התאמה חלקית — מחייבת
  /// את מסלול המנוע: המסלול הפשוט מחפש את השאילתה כרצף תווים, ולכן על
  /// שאילתה עם תוספות הוא מחזיר "אין תוצאות" גם כשלספר יש התאמות.
  static bool canRunAsSimpleSearch({
    required SearchMode searchMode,
    required int distance,
    Map<String, Map<String, bool>> searchOptions = const {},
    Map<int, List<String>> alternativeWords = const {},
    Map<String, String> spacingValues = const {},
    SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  }) {
    if (searchMode == SearchMode.fuzzy) return false;
    if (distance > 0) return false;
    if (!matchPolicy.isStandard) return false;
    if (hasEnabledOptions(searchOptions)) return false;
    if (hasAlternativeWords(alternativeWords)) return false;
    if (hasSpacingValues(spacingValues)) return false;
    return true;
  }

  /// הפרמטרים שיועברו לטאב הקריאה. שאילתה פשוטה מתנרמלת ל-exact/0 כדי
  /// שהספר יריץ את המסלול המקומי המהיר; שאילתה עם תוספות עוברת כפי שהיא —
  /// המרווח בין המילים ומדיניות ההתאמה — כדי שחלונית החיפוש שבספר תמצא את
  /// אותן התאמות שהחיפוש הגלובלי מצא.
  static InBookSearchParameters resolveForReadingTab({
    required SearchMode searchMode,
    required int distance,
    Map<String, Map<String, bool>> searchOptions = const {},
    Map<int, List<String>> alternativeWords = const {},
    Map<String, String> spacingValues = const {},
    SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
    String? query,
  }) {
    if (query != null) matchPolicy = matchPolicy.forQuery(query);
    final isSimple = canRunAsSimpleSearch(
      searchMode: searchMode,
      distance: distance,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      matchPolicy: matchPolicy,
    );
    if (isSimple) {
      return const InBookSearchParameters(
        searchMode: SearchMode.exact,
        distance: 0,
      );
    }
    return InBookSearchParameters(
      searchMode: searchMode,
      distance: distance < 0 ? 0 : distance,
      matchPolicy: matchPolicy,
    );
  }

  static bool hasEnabledOptions(Map<String, Map<String, bool>> searchOptions) =>
      searchOptions.values.any((options) => options.values.any((on) => on));

  static bool hasAlternativeWords(Map<int, List<String>> alternativeWords) =>
      alternativeWords.values.any(
        (words) => words.any((word) => word.trim().isNotEmpty),
      );

  static bool hasSpacingValues(Map<String, String> spacingValues) =>
      SearchQueryBuilder.hasCustomSpacing(spacingValues);
}
