import 'package:equatable/equatable.dart';
import 'package:otzaria/marker/models/marker_query.dart';

sealed class MarkerEvent extends Equatable {
  const MarkerEvent();

  @override
  List<Object?> get props => [];
}

/// טעינה ראשונה של המסך.
class MarkerStarted extends MarkerEvent {
  const MarkerStarted();
}

class MarkerQueryChanged extends MarkerEvent {
  final MarkerQuery query;

  const MarkerQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

/// העמוד הבא של הרשימה.
class MarkerMoreRequested extends MarkerEvent {
  const MarkerMoreRequested();
}

/// הסימונים השתנו (בחלון הזה או באחר) — טוען מחדש את מה שמוצג.
class MarkerStoreChanged extends MarkerEvent {
  const MarkerStoreChanged();
}

class MarkerSelectionToggled extends MarkerEvent {
  final String id;

  const MarkerSelectionToggled(this.id);

  @override
  List<Object?> get props => [id];
}

/// בוחר את כל המוצגים, או מנקה כשכולם כבר נבחרו.
class MarkerSelectAllToggled extends MarkerEvent {
  const MarkerSelectAllToggled();
}

class MarkerSelectionCleared extends MarkerEvent {
  const MarkerSelectionCleared();
}
