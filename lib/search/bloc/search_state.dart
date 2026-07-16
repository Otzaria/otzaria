import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// סנטינל לזיהוי "פרמטר לא הועבר" ב-copyWith כשהשדה nullable וצריך לאפשר
/// גם איפוס מפורש ל-null. בלי זה, `null` במשמעות "לא הועבר" ו"אפס אותי
/// במפורש" לא ניתנים להבחנה בחתימת copyWith רגילה.
const Object _unset = Object();

class SearchState {
  final String? filterQuery;
  final List<Book>? filteredBooks;
  final List<SearchResult> results;
  final Set<Book> booksToSearch;
  final bool isLoading;
  final String searchQuery;
  final String negativeQuery;
  final int totalResults;

  /// מספר הקבוצות כשהחיפוש רץ עם איחוד תוצאות (group_count מהמנוע);
  /// null בחיפוש שטוח. במצב מאוחד הרשימה והדפדוף נספרים בקבוצות, בעוד
  /// [totalResults] נשאר ספירת התוצאות הגולמית.
  final int? totalGroups;

  // מידע על ספירות לכל facet - מתעדכן עם כל חיפוש
  final Map<String, int> facetCounts;

  // הגדרות החיפוש מרוכזות במחלקה נפרדת
  final SearchConfiguration configuration;

  /// הודעת שגיאה אחרונה בחיפוש (קומפילציית רגקס, FFI וכד׳). null אם החיפוש
  /// האחרון הצליח או לא בוצע. ה-UI מציג את ההודעה במקום "אין תוצאות" כאשר
  /// `results` ריק ו-errorMessage לא null, כדי שתקלה לא תיראה כמו חיפוש ריק
  /// לגיטימי. השדה מתאפס בתחילת חיפוש חדש (clear-then-set), ונשמר אחרת.
  final String? errorMessage;

  /// `true` כאשר שאילתת מילה-יחידה רחבה חרגה מתקציב איסוף הטרמים במנוע, כך
  /// שגם הספירה וגם התוצאות חלקיות (רק ההרחבות בעדיפות הגבוהה הוגשו). ה-UI
  /// מציג באנר "ייתכן שהתוצאות חלקיות — צמצמו את החיפוש". מתאפס בתחילת כל
  /// חיפוש חדש.
  final bool resultsTruncated;

  const SearchState({
    this.results = const [],
    this.booksToSearch = const {},
    this.isLoading = false,
    this.searchQuery = '',
    this.negativeQuery = '',
    this.totalResults = 0,
    this.totalGroups,
    this.filterQuery,
    this.filteredBooks,
    this.facetCounts = const {},
    this.configuration = const SearchConfiguration(),
    this.errorMessage,
    this.resultsTruncated = false,
  });

  SearchState copyWith({
    List<SearchResult>? results,
    Set<Book>? booksToSearch,
    bool? isLoading,
    String? searchQuery,
    String? negativeQuery,
    int? totalResults,
    Object? totalGroups = _unset,
    String? filterQuery,
    List<Book>? filteredBooks,
    Map<String, int>? facetCounts,
    SearchConfiguration? configuration,
    Object? errorMessage = _unset,
    bool? resultsTruncated,
  }) {
    return SearchState(
      results: results ?? this.results,
      booksToSearch: booksToSearch ?? this.booksToSearch,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      negativeQuery: negativeQuery ?? this.negativeQuery,
      totalResults: totalResults ?? this.totalResults,
      totalGroups: identical(totalGroups, _unset)
          ? this.totalGroups
          : totalGroups as int?,
      filterQuery: filterQuery,
      filteredBooks: filteredBooks,
      facetCounts: facetCounts ?? this.facetCounts,
      configuration: configuration ?? this.configuration,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      resultsTruncated: resultsTruncated ?? this.resultsTruncated,
    );
  }

  // Getters לנוחות גישה להגדרות (backward compatibility)
  int get distance => configuration.distance;
  SearchScope get proximityScope => configuration.proximityScope;
  WordMatchMode get wordMatchMode => configuration.wordMatchMode;
  int get wordMatchCount => configuration.wordMatchCount;
  bool get fuzzy => configuration.fuzzy;
  bool get isAdvancedSearchEnabled => configuration.isAdvancedSearchEnabled;
  List<String> get currentFacets => configuration.currentFacets;
  List<String> get searchScopeFacets => configuration.searchScopeFacets;
  bool get hasNoSelectedFacets => searchScopeFacets.isEmpty;
  bool get hasScopedFacetFilter =>
      searchScopeFacets.isNotEmpty && !searchScopeFacets.contains('/');
  ResultsOrder get sortBy => configuration.sortBy;
  int get numResults => configuration.numResults;
  ResultGroupingMode get resultGrouping => configuration.resultGrouping;

  /// המונה שהרשימה והדפדוף נמדדים בו: קבוצות כשהאיחוד פעיל, אחרת תוצאות.
  int get displayTotal => totalGroups ?? totalResults;

  // Getters חדשים לרגקס
  bool get regexEnabled => configuration.regexEnabled;
  bool get caseSensitive => configuration.caseSensitive;
  bool get multiline => configuration.multiline;
  bool get dotAll => configuration.dotAll;
  bool get unicode => configuration.unicode;
}
