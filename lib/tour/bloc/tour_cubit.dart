// לתחזוקת הסיור המודרך והטיפים החיים ראו:
// docs/guided_tour_developer_guide.md

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_steps.dart';

/// תזמון טיפ "הידעת" מבוסס-ותק: מוצג מההפעלה ה-N ואילך, לאחר זמן שימוש בסשן.
class DelayedTipSchedule {
  final LiveTipId id;
  final int minimumLaunchCount;
  final Duration delay;

  const DelayedTipSchedule({
    required this.id,
    required this.minimumLaunchCount,
    required this.delay,
  });
}

class TourCubit extends Cubit<TourState> {
  TourCubit({
    List<DelayedTipSchedule>? delayedTipSchedules,
    this._printHintMinimumSessionDuration = const Duration(minutes: 3),
  }) : _delayedTipSchedules = delayedTipSchedules ?? defaultDelayedTipSchedules,
       super(_loadInitialState());

  /// סדר הרשימה קובע עדיפות: בכל סשן מתוזמן רק הטיפ הזכאי הראשון.
  static const List<DelayedTipSchedule> defaultDelayedTipSchedules = [
    DelayedTipSchedule(
      id: LiveTipId.customFoldersHint,
      minimumLaunchCount: 3,
      delay: Duration(minutes: 2, seconds: 30),
    ),
    DelayedTipSchedule(
      id: LiveTipId.shortcutsHint,
      minimumLaunchCount: 5,
      delay: Duration(minutes: 2),
    ),
    DelayedTipSchedule(
      id: LiveTipId.backupHint,
      minimumLaunchCount: 10,
      delay: Duration(minutes: 2),
    ),
  ];

  static TourState _loadInitialState() {
    final stored = Settings.getValue<String>(LiveTipStorage.resolvedTipsKey);
    final resolved = LiveTipStorage.decode(stored);
    if (resolved.isEmpty) {
      return const TourState.inactive();
    }
    return const TourState.inactive().copyWith(resolvedTips: resolved);
  }

  /// כמה ספרי טקסט שונים צריך לפתוח לפני שמוצג טיפ "אודות הספר".
  static const int _bookSourceHintMinimumBooks = 3;
  static const int _bookSourceHintMinimumLaunchCount = 3;
  static const int _printHintMinimumLaunchCount = 7;

  final List<DelayedTipSchedule> _delayedTipSchedules;
  final Duration _printHintMinimumSessionDuration;
  final DateTime _sessionStartedAt = DateTime.now();
  bool _sessionRegistered = false;

  /// טיפ אחד לכל היותר בסשן — הופעה של טיפ דוחה את השאר להפעלה הבאה.
  bool _sessionTipShown = false;
  Timer? _delayedTipTimer;
  Timer? _autoPlayTimer;
  final List<TourInteraction> _recentInteractions = <TourInteraction>[];
  final Set<String> _openedTextBooks = <String>{};
  bool _hasOpenedTextBookThisSession = false;
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
        steps: TourSteps.build(
          libraryLoaded: libraryLoaded,
          isRestart: isRestart,
        ),
        shownTips: state.shownTips,
        resolvedTips: state.resolvedTips,
      ),
    );
  }

  /// נקרא פעם אחת בעליית החלון. סופר הפעלות ומתזמן את טיפ ה"הידעת" הזכאי
  /// הראשון; סגירה לפני שהטיימר ירה משאירה אותו להפעלה הבאה (שימוש קצר).
  void registerSession() {
    if (_sessionRegistered) {
      return;
    }
    _sessionRegistered = true;

    final launchCount =
        (Settings.getValue<int>(LiveTipStorage.launchCountKey) ?? 0) + 1;
    Settings.setValue<int>(LiveTipStorage.launchCountKey, launchCount);

    for (final schedule in _delayedTipSchedules) {
      if (launchCount < schedule.minimumLaunchCount ||
          !_canShowTip(schedule.id)) {
        continue;
      }
      _delayedTipTimer = Timer(
        schedule.delay,
        () => _maybeShowDelayedTip(schedule.id),
      );
      break;
    }
  }

  void _maybeShowDelayedTip(LiveTipId tipId) {
    if (state.isActive ||
        state.hasActiveLiveTip ||
        _sessionTipShown ||
        !_canShowTip(tipId)) {
      return;
    }
    _sessionTipShown = true;
    emit(
      state.copyWith(
        activeLiveTipId: tipId,
        shownTips: <LiveTipId>{
          ...state.shownTips,
          tipId,
        },
      ),
    );
  }

  Future<void> recordInteraction(TourInteraction interaction) async {
    _rememberInteraction(interaction);
    _updateDerivedSignals(interaction);
    _maybeShowLiveTip(interaction);
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
    emit(
      state.copyWith(
        resolvedTips: updatedResolved,
        clearLiveTip: true,
      ),
    );
    _persistResolvedTips(updatedResolved);
  }

  /// מסמן את כל הטיפים כסגורים — אף "הידעת?" לא יוצג עוד.
  void dismissAllLiveTips() {
    final allTips = LiveTipId.values.toSet();
    emit(state.copyWith(resolvedTips: allTips, clearLiveTip: true));
    _persistResolvedTips(allTips);
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
    _delayedTipTimer?.cancel();
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
      case TourInteractionType.openedTextBook:
        _hasOpenedTextBookThisSession = true;
        if (_isInteractionRelevantToOpportunity(interaction)) {
          _commentaryOpportunityScore++;
        }
        if (!state.resolvedTips.contains(LiveTipId.bookSourceHint) &&
            interaction.primaryValue != null) {
          _openedTextBooks.add(interaction.primaryValue!);
        }
        break;
      case TourInteractionType.bookSourceViewed:
        _markTipResolved(LiveTipId.bookSourceHint);
        break;
      case TourInteractionType.printUsed:
        _markTipResolved(LiveTipId.printHint);
        break;
      case TourInteractionType.shortcutsSettingsOpened:
        _markTipResolved(LiveTipId.shortcutsHint);
        break;
      case TourInteractionType.systemSettingsOpened:
        _markTipResolved(LiveTipId.backupHint);
        break;
      case TourInteractionType.linkHighlightShown:
        break;
      case TourInteractionType.linkHighlightCleared:
        _markTipResolved(LiveTipId.linkHighlightHint);
        break;
      case TourInteractionType.currentTabChanged:
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

  void _maybeShowLiveTip(TourInteraction interaction) {
    if (state.isActive || state.hasActiveLiveTip || _sessionTipShown) {
      return;
    }

    final nextTipId = _resolveNextLiveTip(interaction);
    if (nextTipId == null) {
      return;
    }

    _sessionTipShown = true;
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

  LiveTipId? _resolveNextLiveTip(TourInteraction interaction) {
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

    // רק ברגע שההדגשה מופיעה: אחר כך היא עלולה להיעלם בלי Esc (חיפוש, מעבר טאב).
    if (_canShowTip(LiveTipId.linkHighlightHint) &&
        interaction.type == TourInteractionType.linkHighlightShown) {
      return LiveTipId.linkHighlightHint;
    }

    if (_canShowTip(LiveTipId.bookSourceHint) &&
        _hasLaunchesAtLeast(_bookSourceHintMinimumLaunchCount) &&
        _openedTextBooks.length >= _bookSourceHintMinimumBooks) {
      return LiveTipId.bookSourceHint;
    }

    if (_canShowTip(LiveTipId.printHint) &&
        _hasOpenedTextBookThisSession &&
        _hasLaunchesAtLeast(_printHintMinimumLaunchCount) &&
        DateTime.now().difference(_sessionStartedAt) >=
            _printHintMinimumSessionDuration) {
      return LiveTipId.printHint;
    }

    return null;
  }

  bool _canShowTip(LiveTipId tipId) {
    if (liveTipSpecById(tipId).audience == LiveTipAudience.desktopOnly &&
        _isMobilePlatform) {
      return false;
    }
    return !state.shownTips.contains(tipId) &&
        !state.resolvedTips.contains(tipId);
  }

  /// נגזר מ-defaultTargetPlatform (ולא מ-Platform) כדי שיהיה ניתן לזיוף בטסט.
  static bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// טיפ "הידעת?" אינו מוצג בהפעלות הראשונות, אלא רק מהסף ואילך.
  bool _hasLaunchesAtLeast(int minimumLaunchCount) {
    final launchCount =
        Settings.getValue<int>(LiveTipStorage.launchCountKey) ?? 0;
    return launchCount >= minimumLaunchCount;
  }

  bool _shouldShowSideBySideSuggestion() {
    final recentTitles = _recentInteractions
        .where(
          (interaction) =>
              interaction.type == TourInteractionType.currentTabChanged,
        )
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
