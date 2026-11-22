import 'package:equatable/equatable.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';

/// מצב החיפוש הסמנטי לממשק: הזמינות, הדיוק שנבחר והאם מחיקה רצה.
class SemanticSearchState extends Equatable {
  final SemanticAvailability availability;
  final SemanticQuantization quantization;
  final SemanticModelChoice modelChoice;
  final SemanticModelChoice activeModelChoice;
  final bool isRemoving;

  /// מפתחות האינדקס של הספרים שיש להם וקטורים, מכל המקורות.
  final Set<String> coveredBooks;

  const SemanticSearchState({
    this.availability = SemanticAvailability.initial,
    this.quantization = SemanticQuantization.int8,
    this.modelChoice = SemanticModelChoice.meivin,
    this.activeModelChoice = SemanticModelChoice.meivin,
    this.isRemoving = false,
    this.coveredBooks = const {},
  });

  SemanticSearchState copyWith({
    SemanticAvailability? availability,
    SemanticQuantization? quantization,
    SemanticModelChoice? modelChoice,
    SemanticModelChoice? activeModelChoice,
    bool? isRemoving,
    Set<String>? coveredBooks,
  }) => SemanticSearchState(
    availability: availability ?? this.availability,
    quantization: quantization ?? this.quantization,
    modelChoice: modelChoice ?? this.modelChoice,
    activeModelChoice: activeModelChoice ?? this.activeModelChoice,
    isRemoving: isRemoving ?? this.isRemoving,
    coveredBooks: coveredBooks ?? this.coveredBooks,
  );

  @override
  List<Object?> get props => [
    availability,
    quantization,
    modelChoice,
    activeModelChoice,
    isRemoving,
    coveredBooks,
  ];
}
