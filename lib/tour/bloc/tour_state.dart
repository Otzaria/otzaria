// לתחזוקת הסיור המודרך והטיפים החיים ראו:
// docs/guided_tour_developer_guide.md

import 'package:equatable/equatable.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_step.dart';

class TourState extends Equatable {
  final bool isActive;
  final bool libraryLoaded;
  final int currentIndex;
  final List<TourStep> steps;
  final bool isAutoPlaying;
  final LiveTipId? activeLiveTipId;
  final Set<LiveTipId> shownTips;
  final Set<LiveTipId> resolvedTips;

  const TourState({
    required this.isActive,
    required this.libraryLoaded,
    required this.currentIndex,
    required this.steps,
    this.isAutoPlaying = false,
    this.activeLiveTipId,
    this.shownTips = const <LiveTipId>{},
    this.resolvedTips = const <LiveTipId>{},
  });

  const TourState.inactive()
    : isActive = false,
      libraryLoaded = true,
      currentIndex = 0,
      steps = const [],
      isAutoPlaying = false,
      activeLiveTipId = null,
      shownTips = const <LiveTipId>{},
      resolvedTips = const <LiveTipId>{};

  TourStep? get currentStep {
    if (!isActive || steps.isEmpty || currentIndex >= steps.length) {
      return null;
    }
    return steps[currentIndex];
  }

  bool get isLastStep => currentIndex >= steps.length - 1;
  int get totalSteps => steps.length;
  bool get hasActiveLiveTip => activeLiveTipId != null;

  List<TourStep> get progressSteps => steps.where((s) => !s.isDialog).toList();

  int get progressIndex {
    final step = currentStep;
    if (step == null || step.isDialog) return -1;
    return progressSteps.indexWhere((s) => s.id == step.id);
  }

  TourState copyWith({
    bool? isActive,
    bool? libraryLoaded,
    int? currentIndex,
    List<TourStep>? steps,
    bool? isAutoPlaying,
    LiveTipId? activeLiveTipId,
    Set<LiveTipId>? shownTips,
    Set<LiveTipId>? resolvedTips,
    bool clearLiveTip = false,
  }) {
    return TourState(
      isActive: isActive ?? this.isActive,
      libraryLoaded: libraryLoaded ?? this.libraryLoaded,
      currentIndex: currentIndex ?? this.currentIndex,
      steps: steps ?? this.steps,
      isAutoPlaying: isAutoPlaying ?? this.isAutoPlaying,
      activeLiveTipId: clearLiveTip
          ? null
          : (activeLiveTipId ?? this.activeLiveTipId),
      shownTips: shownTips ?? this.shownTips,
      resolvedTips: resolvedTips ?? this.resolvedTips,
    );
  }

  @override
  List<Object?> get props => [
    isActive,
    libraryLoaded,
    currentIndex,
    steps,
    isAutoPlaying,
    activeLiveTipId,
    shownTips.map((tip) => tip.name).toList()..sort(),
    resolvedTips.map((tip) => tip.name).toList()..sort(),
  ];
}
