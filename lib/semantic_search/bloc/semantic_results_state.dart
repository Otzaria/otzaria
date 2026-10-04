import 'package:equatable/equatable.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';

enum SemanticResultsStatus {
  /// עוד לא בוצע חיפוש.
  initial,
  loading,
  loaded,
  failed,

  /// המשתמש עצר את החיפוש.
  cancelled,

  /// המצב אינו שמיש כרגע (אין הסכמה, או שהנתונים לא מוכנים).
  unavailable,
}

/// מצב מסך התוצאות של החיפוש הסמנטי.
class SemanticResultsState extends Equatable {
  final SemanticResultsStatus status;
  final SemanticQueryOptions? options;
  final List<SemanticResultItem> items;

  /// כמה פריטים אפשר לדפדף אליהם בסך הכול.
  final int pageableTotal;
  final bool isLoadingMore;

  /// תבנית הודעת הכשל (עם `{name}`; מפתח תרגום) — מוצגת דרך settingsText.
  final String? message;
  final bool isDebugPreview;

  /// הסימון לפי מיקום ברשימה; בלי ערך = לא סומן.
  final Map<int, SearchFeedbackVote> votes;

  /// מזהה החיפוש, לאיפוס הגלילה בחיפוש חדש.
  final int searchId;

  const SemanticResultsState({
    this.status = SemanticResultsStatus.initial,
    this.options,
    this.items = const [],
    this.pageableTotal = 0,
    this.isLoadingMore = false,
    this.message,
    this.isDebugPreview = false,
    this.votes = const {},
    this.searchId = 0,
  });

  bool get hasMore =>
      status == SemanticResultsStatus.loaded && items.length < pageableTotal;

  SemanticResultsState copyWith({
    SemanticResultsStatus? status,
    SemanticQueryOptions? options,
    List<SemanticResultItem>? items,
    int? pageableTotal,
    bool? isLoadingMore,
    String? message,
    bool clearMessage = false,
    bool? isDebugPreview,
    Map<int, SearchFeedbackVote>? votes,
    int? searchId,
  }) => SemanticResultsState(
    status: status ?? this.status,
    options: options ?? this.options,
    items: items ?? this.items,
    pageableTotal: pageableTotal ?? this.pageableTotal,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    message: clearMessage ? null : message ?? this.message,
    isDebugPreview: isDebugPreview ?? this.isDebugPreview,
    votes: votes ?? this.votes,
    searchId: searchId ?? this.searchId,
  );

  @override
  List<Object?> get props => [
    status,
    options,
    items,
    pageableTotal,
    isLoadingMore,
    message,
    isDebugPreview,
    votes,
    searchId,
  ];
}
