import 'package:equatable/equatable.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';

sealed class SemanticSearchEvent extends Equatable {
  const SemanticSearchEvent();

  @override
  List<Object?> get props => [];
}

/// בודק את הזמינות ומתחיל להאזין לשינויים.
class SemanticSearchStarted extends SemanticSearchEvent {
  const SemanticSearchStarted();
}

/// המשתמש ביקש להוריד את המודל ואת הוקטורים.
class SemanticDownloadRequested extends SemanticSearchEvent {
  const SemanticDownloadRequested();
}

/// המשתמש ביטל את ההורדה.
class SemanticDownloadCancelRequested extends SemanticSearchEvent {
  const SemanticDownloadCancelRequested();
}

/// המשתמש בחר דיוק אחר למודל השאילתות.
class SemanticQuantizationChanged extends SemanticSearchEvent {
  final SemanticQuantization quantization;

  const SemanticQuantizationChanged(this.quantization);

  @override
  List<Object?> get props => [quantization];
}

/// המשתמש ביקש למחוק את נתוני החיפוש הסמנטי.
class SemanticDataRemovalRequested extends SemanticSearchEvent {
  const SemanticDataRemovalRequested();
}

/// המאגר דיווח על מצב זמינות חדש.
class SemanticAvailabilityUpdated extends SemanticSearchEvent {
  final SemanticAvailability availability;

  const SemanticAvailabilityUpdated(this.availability);

  @override
  List<Object?> get props => [availability];
}
