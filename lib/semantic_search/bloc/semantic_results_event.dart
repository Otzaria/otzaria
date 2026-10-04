import 'package:equatable/equatable.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';

sealed class SemanticResultsEvent extends Equatable {
  const SemanticResultsEvent();

  @override
  List<Object?> get props => [];
}

/// חיפוש חדש; מבטל את הקודם.
class SemanticSearchSubmitted extends SemanticResultsEvent {
  final SemanticQueryOptions options;

  const SemanticSearchSubmitted(this.options);

  @override
  List<Object?> get props => [options];
}

/// טעינת העמוד הבא.
class SemanticMoreResultsRequested extends SemanticResultsEvent {
  const SemanticMoreResultsRequested();
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
