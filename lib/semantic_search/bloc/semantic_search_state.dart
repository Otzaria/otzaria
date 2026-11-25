import 'package:equatable/equatable.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';

/// מצב החיפוש הסמנטי לממשק: הזמינות, הדיוק שנבחר והאם מחיקה רצה.
class SemanticSearchState extends Equatable {
  final SemanticAvailability availability;
  final SemanticQuantization quantization;
  final bool isRemoving;

  const SemanticSearchState({
    this.availability = SemanticAvailability.initial,
    this.quantization = SemanticQuantization.int8,
    this.isRemoving = false,
  });

  SemanticSearchState copyWith({
    SemanticAvailability? availability,
    SemanticQuantization? quantization,
    bool? isRemoving,
  }) => SemanticSearchState(
    availability: availability ?? this.availability,
    quantization: quantization ?? this.quantization,
    isRemoving: isRemoving ?? this.isRemoving,
  );

  @override
  List<Object?> get props => [availability, quantization, isRemoving];
}
