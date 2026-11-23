import 'package:equatable/equatable.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_mark.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';

sealed class SemanticResultsEvent extends Equatable {
  const SemanticResultsEvent();

  @override
  List<Object?> get props => [];
}

/// חיפוש חדש; מבטל את הקודם.
class SemanticSearchSubmitted extends SemanticResultsEvent {
  final SemanticQueryOptions options;

  /// סימונים מחיפוש קודם שמכוונים גם את החיפוש הזה, מהעמוד הראשון.
  final List<SemanticMark> marks;

  const SemanticSearchSubmitted(this.options, {this.marks = const []});

  @override
  List<Object?> get props => [options, marks];
}

/// טעינת העמוד הבא.
class SemanticMoreResultsRequested extends SemanticResultsEvent {
  const SemanticMoreResultsRequested();
}

/// "חפש עוד כמו זה": מסמן את התוצאה [index] כרלוונטית ומחפש מחדש לפי כל
/// הסימונים.
class SemanticMoreLikeThisRequested extends SemanticResultsEvent {
  final int index;

  const SemanticMoreLikeThisRequested(this.index);

  @override
  List<Object?> get props => [index];
}

/// המשתמש עצר את החיפוש הרץ.
class SemanticSearchCancelRequested extends SemanticResultsEvent {
  const SemanticSearchCancelRequested();
}

/// לחיצה על אהבתי/לא אהבתי; לחיצה על הסימון הפעיל מבטלת אותו.
class SemanticVoteToggled extends SemanticResultsEvent {
  final int index;

  /// [SearchFeedbackVote.like] או [SearchFeedbackVote.dislike].
  final SearchFeedbackVote vote;

  const SemanticVoteToggled(this.index, this.vote);

  @override
  List<Object?> get props => [index, vote];
}

/// סימון הקטע הקרוב לשאילתה בתוצאות [start]..[end] של החיפוש [searchId],
/// ברקע ואחרי שהעמוד כבר מוצג.
class SemanticHighlightsRequested extends SemanticResultsEvent {
  final int searchId;
  final int start;
  final int end;

  const SemanticHighlightsRequested(this.searchId, this.start, this.end);

  @override
  List<Object?> get props => [searchId, start, end];
}
