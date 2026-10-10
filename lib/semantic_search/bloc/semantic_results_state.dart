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

  /// האם המקור דיווח על עמוד נוסף.
  final bool morePages;
  final bool isLoadingMore;

  /// תבנית הודעת הכשל (עם `{name}`; מפתח תרגום) — מוצגת דרך settingsText.
  final String? message;
  final bool isDebugPreview;

  /// הסימון לפי מיקום ברשימה; בלי ערך = לא סומן.
  final Map<int, SearchFeedbackVote> votes;

  /// מזהה החיפוש, לאיפוס הגלילה בחיפוש חדש.
  final int searchId;

  /// קטע מסומן לפי עניין, לפי מיקום ברשימה — לתצוגה בלבד. נשמר בנפרד מ-[items]
  /// כדי שהטלמטריה תיבנה תמיד מהקטע המקורי של המנוע.
  final Map<int, String> passageHighlights;

  const SemanticResultsState({
    this.status = SemanticResultsStatus.initial,
    this.options,
    this.items = const [],
    this.morePages = false,
    this.isLoadingMore = false,
    this.message,
    this.isDebugPreview = false,
    this.votes = const {},
    this.searchId = 0,
    this.passageHighlights = const {},
  });

  bool get hasMore => status == SemanticResultsStatus.loaded && morePages;

  SemanticResultsState copyWith({
    SemanticResultsStatus? status,
    SemanticQueryOptions? options,
    List<SemanticResultItem>? items,
    bool? morePages,
    bool? isLoadingMore,
    String? message,
    bool clearMessage = false,
    bool? isDebugPreview,
    Map<int, SearchFeedbackVote>? votes,
    int? searchId,
    Map<int, String>? passageHighlights,
  }) => SemanticResultsState(
    status: status ?? this.status,
    options: options ?? this.options,
    items: items ?? this.items,
    morePages: morePages ?? this.morePages,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    message: clearMessage ? null : message ?? this.message,
    isDebugPreview: isDebugPreview ?? this.isDebugPreview,
    votes: votes ?? this.votes,
    searchId: searchId ?? this.searchId,
    passageHighlights: passageHighlights ?? this.passageHighlights,
  );

  @override
  List<Object?> get props => [
    status,
    options,
    items,
    morePages,
    isLoadingMore,
    message,
    isDebugPreview,
    votes,
    searchId,
    passageHighlights,
  ];
}
