import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/product_tour/bloc/product_tour_event.dart';
import 'package:otzaria/product_tour/bloc/product_tour_state.dart';
import 'package:otzaria/product_tour/data/product_tour_specs.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';
import 'package:otzaria/product_tour/repository/product_tour_repository.dart';

class ProductTourBloc extends Bloc<ProductTourEvent, ProductTourState> {
  final ProductTourRepository _repository;

  final List<TourInteraction> _recentInteractions = <TourInteraction>[];
  int _textSelectionCount = 0;
  bool _commentaryOpportunityOpen = false;
  int _commentaryOpportunityScore = 0;
  String? _commentaryOpportunityBook;

  ProductTourBloc({
    required ProductTourRepository repository,
  })  : _repository = repository,
        super(ProductTourState.initial()) {
    on<BootstrapTour>(_onBootstrapTour);
    on<StartIntroTour>(_onStartIntroTour);
    on<NextTourStep>(_onNextTourStep);
    on<PreviousTourStep>(_onPreviousTourStep);
    on<SkipActiveTourStep>(_onSkipActiveTourStep);
    on<DismissActiveOverlay>(_onDismissActiveOverlay);
    on<CompleteIntroTour>(_onCompleteIntroTour);
    on<RecordInteraction>(_onRecordInteraction);
    on<ResetProductTourProgress>(_onResetProductTourProgress);
  }

  Future<void> _onBootstrapTour(
    BootstrapTour event,
    Emitter<ProductTourState> emit,
  ) async {
    final status = await _repository.loadStatus();
    final lastStep = await _repository.loadLastStep();
    final shownTips = await _repository.loadShownTips();
    final resolvedTips = await _repository.loadResolvedTips();

    emit(
      state.copyWith(
        isBootstrapped: true,
        status: status,
        lastPersistedStepIndex: lastStep,
        shownTips: shownTips,
        resolvedTips: resolvedTips,
      ),
    );

    await _maybeAutoStartIntro(emit);
  }

  Future<void> _onStartIntroTour(
    StartIntroTour event,
    Emitter<ProductTourState> emit,
  ) async {
    if (!state.isBootstrapped) {
      return;
    }

    if (!event.manual && state.status != ProductTourStatus.unseen) {
      return;
    }

    await _repository.saveLastStep(0);
    emit(
      state.copyWith(
        activeIntroStepIndex: 0,
        lastPersistedStepIndex: 0,
        clearLiveTip: true,
      ),
    );
  }

  Future<void> _onNextTourStep(
    NextTourStep event,
    Emitter<ProductTourState> emit,
  ) async {
    final currentIndex = state.activeIntroStepIndex;
    if (currentIndex == null) {
      return;
    }

    final nextIndex = currentIndex + 1;
    if (nextIndex >= kIntroTourSteps.length) {
      await _completeIntroTour(emit);
      return;
    }

    await _repository.saveLastStep(nextIndex);
    emit(
      state.copyWith(
        activeIntroStepIndex: nextIndex,
        lastPersistedStepIndex: nextIndex,
      ),
    );
  }

  Future<void> _onPreviousTourStep(
    PreviousTourStep event,
    Emitter<ProductTourState> emit,
  ) async {
    final currentIndex = state.activeIntroStepIndex;
    if (currentIndex == null || currentIndex <= 0) {
      return;
    }

    final previousIndex = currentIndex - 1;
    await _repository.saveLastStep(previousIndex);
    emit(
      state.copyWith(
        activeIntroStepIndex: previousIndex,
        lastPersistedStepIndex: previousIndex,
      ),
    );
  }

  Future<void> _onSkipActiveTourStep(
    SkipActiveTourStep event,
    Emitter<ProductTourState> emit,
  ) async {
    await _onNextTourStep(const NextTourStep(), emit);
  }

  Future<void> _onDismissActiveOverlay(
    DismissActiveOverlay event,
    Emitter<ProductTourState> emit,
  ) async {
    if (state.hasActiveIntroTour) {
      final nextStatus = state.status == ProductTourStatus.completed
          ? ProductTourStatus.completed
          : ProductTourStatus.dismissed;

      if (nextStatus != state.status) {
        await _repository.saveStatus(nextStatus);
      }

      emit(
        state.copyWith(
          status: nextStatus,
          clearIntro: true,
          clearLiveTip: true,
        ),
      );
      return;
    }

    if (state.hasActiveLiveTip) {
      emit(state.copyWith(clearLiveTip: true));
    }
  }

  Future<void> _onCompleteIntroTour(
    CompleteIntroTour event,
    Emitter<ProductTourState> emit,
  ) async {
    await _completeIntroTour(emit);
  }

  Future<void> _onRecordInteraction(
    RecordInteraction event,
    Emitter<ProductTourState> emit,
  ) async {
    _rememberInteraction(event.interaction);

    if (event.interaction.type == TourInteractionType.libraryReady &&
        !state.isLibraryReady) {
      emit(state.copyWith(isLibraryReady: true));
    }

    await _updateDerivedSignals(event.interaction, emit);
    await _maybeAutoStartIntro(emit);
    await _maybeShowLiveTip(emit);
  }

  Future<void> _onResetProductTourProgress(
    ResetProductTourProgress event,
    Emitter<ProductTourState> emit,
  ) async {
    _recentInteractions.clear();
    _textSelectionCount = 0;
    _commentaryOpportunityOpen = false;
    _commentaryOpportunityScore = 0;
    _commentaryOpportunityBook = null;

    await _repository.resetAll();
    emit(
      ProductTourState.initial().copyWith(
        isBootstrapped: state.isBootstrapped,
        isLibraryReady: state.isLibraryReady,
      ),
    );
  }

  Future<void> _completeIntroTour(Emitter<ProductTourState> emit) async {
    await _repository.saveStatus(ProductTourStatus.completed);
    emit(
      state.copyWith(
        status: ProductTourStatus.completed,
        clearIntro: true,
        clearLiveTip: true,
      ),
    );
  }

  void _rememberInteraction(TourInteraction interaction) {
    _recentInteractions.add(interaction);
    final cutoff = interaction.timestamp.subtract(const Duration(seconds: 30));
    _recentInteractions.removeWhere(
      (savedInteraction) => savedInteraction.timestamp.isBefore(cutoff),
    );
  }

  Future<void> _updateDerivedSignals(
    TourInteraction interaction,
    Emitter<ProductTourState> emit,
  ) async {
    switch (interaction.type) {
      case TourInteractionType.textSelected:
        if (!state.resolvedTips.contains(LiveTipId.dictionaryContextMenuHint)) {
          _textSelectionCount++;
        }
        if (_commentaryOpportunityOpen) {
          _commentaryOpportunityScore++;
        }
        break;
      case TourInteractionType.dictionaryUsed:
        _textSelectionCount = 0;
        await _markTipResolved(
          LiveTipId.dictionaryContextMenuHint,
          emit,
        );
        break;
      case TourInteractionType.sideBySideEnabled:
        await _markTipResolved(
          LiveTipId.sideBySideSuggestion,
          emit,
        );
        break;
      case TourInteractionType.commentaryAvailable:
        if (state.resolvedTips.contains(LiveTipId.commentaryHint)) {
          break;
        }
        _commentaryOpportunityOpen = true;
        _commentaryOpportunityScore = 0;
        _commentaryOpportunityBook = interaction.primaryValue;
        break;
      case TourInteractionType.commentaryUsed:
        _commentaryOpportunityOpen = false;
        _commentaryOpportunityScore = 0;
        _commentaryOpportunityBook = null;
        await _markTipResolved(
          LiveTipId.commentaryHint,
          emit,
        );
        break;
      case TourInteractionType.currentTabChanged:
      case TourInteractionType.openedTextBook:
        if (_commentaryOpportunityOpen &&
            (_commentaryOpportunityBook == null ||
                _commentaryOpportunityBook == interaction.primaryValue)) {
          _commentaryOpportunityScore++;
        }
        break;
      case TourInteractionType.libraryReady:
        break;
    }
  }

  Future<void> _markTipResolved(
    LiveTipId tipId,
    Emitter<ProductTourState> emit,
  ) async {
    if (state.resolvedTips.contains(tipId)) {
      return;
    }

    final nextResolvedTips = <LiveTipId>{
      ...state.resolvedTips,
      tipId,
    };
    await _repository.saveResolvedTips(nextResolvedTips);
    emit(
      state.copyWith(
        resolvedTips: nextResolvedTips,
        clearLiveTip: state.activeLiveTipId == tipId,
      ),
    );
  }

  Future<void> _maybeAutoStartIntro(Emitter<ProductTourState> emit) async {
    if (!state.isBootstrapped ||
        !state.isLibraryReady ||
        state.status != ProductTourStatus.unseen ||
        state.hasActiveOverlay) {
      return;
    }

    await _repository.saveLastStep(0);
    emit(
      state.copyWith(
        activeIntroStepIndex: 0,
        lastPersistedStepIndex: 0,
      ),
    );
  }

  Future<void> _maybeShowLiveTip(Emitter<ProductTourState> emit) async {
    if (!state.isBootstrapped || state.hasActiveOverlay) {
      return;
    }

    final nextTipId = _resolveNextLiveTip();
    if (nextTipId == null) {
      return;
    }

    final nextShownTips = <LiveTipId>{
      ...state.shownTips,
      nextTipId,
    };
    await _repository.saveShownTips(nextShownTips);
    emit(
      state.copyWith(
        activeLiveTipId: nextTipId,
        shownTips: nextShownTips,
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
