import 'package:equatable/equatable.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';

sealed class ProductTourEvent extends Equatable {
  const ProductTourEvent();

  @override
  List<Object?> get props => [];
}

class BootstrapTour extends ProductTourEvent {
  const BootstrapTour();
}

class StartIntroTour extends ProductTourEvent {
  final bool manual;

  const StartIntroTour({
    required this.manual,
  });

  @override
  List<Object?> get props => [manual];
}

class NextTourStep extends ProductTourEvent {
  const NextTourStep();
}

class PreviousTourStep extends ProductTourEvent {
  const PreviousTourStep();
}

class SkipActiveTourStep extends ProductTourEvent {
  const SkipActiveTourStep();
}

class DismissActiveOverlay extends ProductTourEvent {
  const DismissActiveOverlay();
}

class CompleteIntroTour extends ProductTourEvent {
  const CompleteIntroTour();
}

class RecordInteraction extends ProductTourEvent {
  final TourInteraction interaction;

  const RecordInteraction(this.interaction);

  @override
  List<Object?> get props => [interaction];
}

class ResetProductTourProgress extends ProductTourEvent {
  const ResetProductTourProgress();
}
