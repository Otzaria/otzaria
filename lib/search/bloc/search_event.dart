import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

abstract class SearchEvent {
  const SearchEvent();
}

class UpdateFilterQuery extends SearchEvent {
  final String query;
  UpdateFilterQuery(this.query);
}

class ClearFilter extends SearchEvent {
  ClearFilter();
}

/// הרצה מחדש של החיפוש הנוכחי אחרי שינוי הגדרה. שולחים אותו — ולא
/// [UpdateSearchQuery] חשוף — כדי שהאפשרויות המתקדמות (ובראשן "ניקוד",
/// שמעבירה לשדה המנוקד) לא יאבדו ויחזירו תוצאות של שאילתה אחרת.
class RerunSearch extends SearchEvent {
  const RerunSearch();
}

class UpdateSearchQuery extends SearchEvent {
  final String query;
  final String? negativeQuery;
  final Map<String, String>? customSpacing;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, Map<String, bool>>? searchOptions;
  final Map<String, String>? negativeCustomSpacing;
  final Map<int, List<String>>? negativeAlternativeWords;
  final Map<String, Map<String, bool>>? negativeSearchOptions;
  UpdateSearchQuery(
    this.query, {
    this.negativeQuery,
    this.customSpacing,
    this.alternativeWords,
    this.searchOptions,
    this.negativeCustomSpacing,
    this.negativeAlternativeWords,
    this.negativeSearchOptions,
  });
}

class UpdateDistance extends SearchEvent {
  final int distance;
  UpdateDistance(this.distance);
}

class UpdateDistanceWithoutSearch extends SearchEvent {
  final int distance;
  UpdateDistanceWithoutSearch(this.distance);
}

/// עדכון טווח הקרבה בין מילות החיפוש (מרווח מילים / פסקה / כותרת).
class UpdateProximityScope extends SearchEvent {
  final SearchScope scope;
  UpdateProximityScope(this.scope);
}

class UpdateProximityScopeWithoutSearch extends SearchEvent {
  final SearchScope scope;
  UpdateProximityScopeWithoutSearch(this.scope);
}

/// עדכון מצב התאמת המילים (כל המילים / מילה אחת / רוב / לפחות X).
/// [count] רלוונטי רק ל-atLeast; null משאיר את הערך הקיים.
class UpdateWordMatchMode extends SearchEvent {
  final WordMatchMode mode;
  final int? count;
  UpdateWordMatchMode(this.mode, {this.count});
}

class UpdateWordMatchModeWithoutSearch extends SearchEvent {
  final WordMatchMode mode;
  final int? count;
  UpdateWordMatchModeWithoutSearch(this.mode, {this.count});
}

class ToggleSearchMode extends SearchEvent {}

class SetSearchMode extends SearchEvent {
  final SearchMode searchMode;
  SetSearchMode(this.searchMode);
}

class SetSearchModeWithoutSearch extends SearchEvent {
  final SearchMode searchMode;
  SetSearchModeWithoutSearch(this.searchMode);
}

class UpdateBooksToSearch extends SearchEvent {
  final Set<Book> books;
  UpdateBooksToSearch(this.books);
}

class AddFacet extends SearchEvent {
  final String facet;
  AddFacet(this.facet);
}

class RemoveFacet extends SearchEvent {
  final String facet;
  RemoveFacet(this.facet);
}

class SetFacet extends SearchEvent {
  final String facet;
  final Map<String, String>? customSpacing;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, Map<String, bool>>? searchOptions;
  SetFacet(
    this.facet, {
    this.customSpacing,
    this.alternativeWords,
    this.searchOptions,
  });
}

/// הגדרת מספר facets בבת אחת ללא הפעלת חיפוש
class SetFacetsWithoutSearch extends SearchEvent {
  final List<String> facets;
  const SetFacetsWithoutSearch(this.facets);
}

class UpdateSortOrder extends SearchEvent {
  final ResultsOrder order;
  UpdateSortOrder(this.order);
}

/// שינוי מצב איחוד התוצאות (ללא / לפי סעיף / טקסט זהה) — מריץ את החיפוש
/// מחדש, כי הקיבוץ מתבצע במנוע.
class UpdateResultGrouping extends SearchEvent {
  final ResultGroupingMode grouping;
  UpdateResultGrouping(this.grouping);
}

class UpdateNumResults extends SearchEvent {
  final int numResults;
  UpdateNumResults(this.numResults);
}

class ResetSearch extends SearchEvent {}

// Events חדשים להגדרות רגקס
class ToggleRegex extends SearchEvent {}

class ToggleCaseSensitive extends SearchEvent {}

class ToggleMultiline extends SearchEvent {}

class ToggleDotAll extends SearchEvent {}

class ToggleUnicode extends SearchEvent {}

// Event פנימי לעדכון facet counts
class UpdateFacetCounts extends SearchEvent {
  final Map<String, int> facetCounts;
  UpdateFacetCounts(this.facetCounts);
}

class ReplaceFacetCounts extends SearchEvent {
  final Map<String, int> facetCounts;

  /// מזהה החיפוש שעבורו חושבו הספירות. נבדק שוב בזמן עיבוד ה-event —
  /// הבדיקה לפני ה-add לא מספיקה, כי חיפוש חדש יכול להתחיל בזמן שה-event
  /// ממתין בתור, ואז ספירות ישנות היו דורסות את החדשות.
  final int requestId;

  /// חתימת החיפוש שעבורו חושבו הספירות (ראו SearchBloc._facetRecountSignature).
  final String? signature;
  ReplaceFacetCounts(
    this.facetCounts, {
    required this.requestId,
    this.signature,
  });
}

// Event לטעינת תוצאות נוספות
class LoadMoreResults extends SearchEvent {
  final Map<String, String>? customSpacing;
  final Map<int, List<String>>? alternativeWords;
  final Map<String, Map<String, bool>>? searchOptions;
  final Map<String, String>? negativeCustomSpacing;
  final Map<int, List<String>>? negativeAlternativeWords;
  final Map<String, Map<String, bool>>? negativeSearchOptions;
  LoadMoreResults({
    this.customSpacing,
    this.alternativeWords,
    this.searchOptions,
    this.negativeCustomSpacing,
    this.negativeAlternativeWords,
    this.negativeSearchOptions,
  });
}
