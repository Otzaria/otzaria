// לתחזוקת הסיור המודרך והטיפים החיים ראו:
// docs/guided_tour_developer_guide.md

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_steps.dart';

class TourCubit extends Cubit<TourState> {
  TourCubit() : super(_loadInitialState());

  static TourState _loadInitialState() {
    final stored =
        Settings.getValue<String>(LiveTipStorage.resolvedTipsKey);
    final resolved = LiveTipStorage.decode(stored);
    if (resolved.isEmpty) {
      return const TourState.inactive();
    }
    return const TourState.inactive().copyWith(resolvedTips: resolved);
  }

  Timer? _autoPlayTimer;
  final List<TourInteraction> _recentInteractions = <TourInteraction>[];
  int _textSelectionCount = 0;
  bool _hasRegisteredCommentaryOpportunity = false;
  bool _commentaryOpportunityOpen = false;
  int _commentaryOpportunityScore = 0;
  String? _commentaryOpportunityBook;

  bool get hasRegisteredCommentaryOpportunity =>
      _hasRegisteredCommentaryOpportunity;

  bool startIfNeeded({required bool libraryLoaded}) {
    final status = Settings.getValue<String>(TourSteps.statusKey);
    if (state.isActive) {
      return false;
    }
    if (status == null ||
        (libraryLoaded && _wasHandledWithoutLibrary(status))) {
      start(libraryLoaded: libraryLoaded);
      return true;
    }
    return false;
  }

  Future<void> restart({required bool libraryLoaded}) async {
    start(libraryLoaded: libraryLoaded, isRestart: true);
  }

  void start({required bool libraryLoaded, bool isRestart = false}) {
    _cancelAutoPlay();
    emit(
      TourState(
        isActive: true,
        libraryLoaded: libraryLoaded,
        currentIndex: 0,
        steps:
            TourSteps.build(libraryLoaded: libraryLoaded, isRestart: isRestart),
        shownTips: state.shownTips,
        resolvedTips: state.resolvedTips,
      ),
    );
  }

  Future<void> recordInteraction(TourInteraction interaction) async {
    _rememberInteraction(interaction);
    _updateDerivedSignals(interaction);
    _maybeShowLiveTip();
  }

  void dismissLiveTip() {
    if (!state.hasActiveLiveTip) {
      return;
    }
    final dismissedId = state.activeLiveTipId!;
    final updatedResolved = <LiveTipId>{
      ...state.resolvedTips,
      dismissedId,
    };
    emit(state.copyWith(
      resolvedTips: updatedResolved,
      clearLiveTip: true,
    ));
    _persistResolvedTips(updatedResolved);
  }

  void _persistResolvedTips(Set<LiveTipId> resolvedTips) {
    Settings.setValue<String>(
      LiveTipStorage.resolvedTipsKey,
      LiveTipStorage.encode(resolvedTips),
    );
  }

  void goToStep(int index) {
    if (!state.isActive) return;
    if (index < 0 || index >= state.steps.length) return;
    _cancelAutoPlay();
    emit(state.copyWith(currentIndex: index, isAutoPlaying: false));
  }

  void toggleAutoPlay() {
    if (state.isAutoPlaying) {
      _cancelAutoPlay();
      emit(state.copyWith(isAutoPlaying: false));
    } else {
      emit(state.copyWith(isAutoPlaying: true));
      _autoPlayTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        next();
      });
    }
  }

  void _cancelAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  Future<void> next() async {
    if (!state.isActive) return;
    if (state.isLastStep) {
      await complete();
      return;
    }
    emit(
      state.copyWith(
        currentIndex: state.currentIndex + 1,
        clearLiveTip: true,
      ),
    );
  }

  Future<void> skip() async {
    _cancelAutoPlay();
    final status = state.libraryLoaded
        ? TourSteps.skipped
        : TourSteps.skippedWithoutLibrary;
    await Settings.setValue<String>(TourSteps.statusKey, status);
    emit(state.copyWith(isActive: false, clearLiveTip: true));
  }

  Future<void> complete() async {
    _cancelAutoPlay();
    final status = state.libraryLoaded
        ? TourSteps.completed
        : TourSteps.completedWithoutLibrary;
    await Settings.setValue<String>(TourSteps.statusKey, status);
    emit(state.copyWith(isActive: false, clearLiveTip: true));
  }

  @override
  Future<void> close() {
    _cancelAutoPlay();
    return super.close();
  }

  bool _wasHandledWithoutLibrary(String status) {
    return status == TourSteps.completedWithoutLibrary ||
        status == TourSteps.skippedWithoutLibrary;
  }

  void _rememberInteraction(TourInteraction interaction) {
    _recentInteractions.add(interaction);
    final cutoff = interaction.timestamp.subtract(const Duration(seconds: 30));
    _recentInteractions.removeWhere(
      (savedInteraction) => savedInteraction.timestamp.isBefore(cutoff),
    );
  }

  void _updateDerivedSignals(TourInteraction interaction) {
    switch (interaction.type) {
      case TourInteractionType.textSelected:
        if (!state.resolvedTips.contains(LiveTipId.dictionaryContextMenuHint)) {
          _textSelectionCount++;
        }
        if (_isInteractionRelevantToOpportunity(interaction)) {
          _commentaryOpportunityScore++;
        }
        break;
      case TourInteractionType.dictionaryUsed:
        _textSelectionCount = 0;
        _markTipResolved(LiveTipId.dictionaryContextMenuHint);
        break;
      case TourInteractionType.sideBySideEnabled:
        _markTipResolved(LiveTipId.sideBySideSuggestion);
        break;
      case TourInteractionType.commentaryAvailable:
        if (state.resolvedTips.contains(LiveTipId.commentaryHint) ||
            _hasRegisteredCommentaryOpportunity) {
          break;
        }
        _hasRegisteredCommentaryOpportunity = true;
        _commentaryOpportunityOpen = true;
        _commentaryOpportunityScore = 0;
        _commentaryOpportunityBook = interaction.primaryValue;
        break;
      case TourInteractionType.commentaryUsed:
        _commentaryOpportunityOpen = false;
        _commentaryOpportunityScore = 0;
        _commentaryOpportunityBook = null;
        _markTipResolved(LiveTipId.commentaryHint);
        break;
      case TourInteractionType.currentTabChanged:
      case TourInteractionType.openedTextBook:
      case TourInteractionType.readerPositionChanged:
        if (_isInteractionRelevantToOpportunity(interaction)) {
          _commentaryOpportunityScore++;
        }
        break;
    }
  }

  bool _isInteractionRelevantToOpportunity(TourInteraction interaction) {
    return _commentaryOpportunityOpen &&
        (_commentaryOpportunityBook == null ||
            _commentaryOpportunityBook == interaction.primaryValue);
  }

  void _markTipResolved(LiveTipId tipId) {
    if (state.resolvedTips.contains(tipId)) {
      return;
    }

    final updatedResolved = <LiveTipId>{
      ...state.resolvedTips,
      tipId,
    };
    emit(
      state.copyWith(
        resolvedTips: updatedResolved,
        clearLiveTip: state.activeLiveTipId == tipId,
      ),
    );
    _persistResolvedTips(updatedResolved);
  }

  void _maybeShowLiveTip() {
    if (state.isActive || state.hasActiveLiveTip) {
      return;
    }

    final nextTipId = _resolveNextLiveTip();
    if (nextTipId == null) {
      return;
    }

    emit(
      state.copyWith(
        activeLiveTipId: nextTipId,
        shownTips: <LiveTipId>{
          ...state.shownTips,
          nextTipId,
        },
      ),
    );
  }

  LiveTipId? _resolveNextLiveTip() {
    if (_canShowTip(LiveTipId.sideBySideSuggestion) &&
        _shouldShowSideBySideSuggestion()) {
      return LiveTipId.sideBySideSuggestion;
    }

    if (_canShowTip(LiveTipId.dictionaryContextMenuHint) &&
        _textSelectionCount >= 2) {
      return LiveTipId.dictionaryContextMenuHint;
    }

    if (_canShowTip(LiveTipId.commentaryHint) &&
        _commentaryOpportunityOpen &&
        _commentaryOpportunityScore >= 3) {
      return LiveTipId.commentaryHint;
    }

    return null;
  }

  bool _canShowTip(LiveTipId tipId) {
    return !state.shownTips.contains(tipId) &&
        !state.resolvedTips.contains(tipId);
  }

  bool _shouldShowSideBySideSuggestion() {
    final recentTitles = _recentInteractions
        .where((interaction) =>
            interaction.type == TourInteractionType.currentTabChanged)
        .map((interaction) => interaction.primaryValue)
        .whereType<String>()
        .toList();

    if (recentTitles.length < 5) {
      return false;
    }

    final collapsedTitles = <String>[];
    for (final title in recentTitles) {
      if (collapsedTitles.isEmpty || collapsedTitles.last != title) {
        collapsedTitles.add(title);
      }
    }

    if (collapsedTitles.length < 5) {
      return false;
    }

    final firstTitle = collapsedTitles[collapsedTitles.length - 1];
    final secondTitle = collapsedTitles[collapsedTitles.length - 2];
    if (firstTitle == secondTitle) {
      return false;
    }

    var alternatingLength = 2;
    var expectedNext = firstTitle;

    for (var index = collapsedTitles.length - 3; index >= 0; index--) {
      if (collapsedTitles[index] != expectedNext) {
        break;
      }
      alternatingLength++;
      expectedNext = expectedNext == firstTitle ? secondTitle : firstTitle;
    }

    return alternatingLength >= 5;
  }
}
