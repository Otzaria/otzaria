import 'dart:async';
import 'dart:math';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// כמה כרטיסיות שנסגרו נשמרות לשחזור. מוגבל כי כל רשומה מחזיקה מופע טאב חי.
const int _kMaxRecentlyClosedTabs = 10;

class _ClosedTabEntry {
  final OpenedTab tab;
  final int originalIndex;

  const _ClosedTabEntry({
    required this.tab,
    required this.originalIndex,
  });
}

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository _repository;
  final List<_ClosedTabEntry> _recentlyClosedTabs = <_ClosedTabEntry>[];

  /// הכרטיסיות שנסגרו לאחרונה, מהאחרונה שנסגרה ואילך. הרשימה אינה חלק
  /// מה-state, ולכן קוראים אותה בתוך `BlocBuilder` על שינוי הכרטיסיות.
  List<OpenedTab> get recentlyClosedTabs => List<OpenedTab>.unmodifiable(
    _recentlyClosedTabs.reversed.map((entry) => entry.tab),
  );

  List<OpenedTab>? _pendingSaveTabs;
  int _pendingSaveIndex = 0;
  Future<void>? _saveDrain;

  /// מבקש שמירה של הטאבים, בלי להמתין לה.
  ///
  /// כל שמירה מקודדת את *כל* הטאבים, ולכן בקשות שמגיעות בזמן שכתיבה רצה
  /// מתמזגות לכתיבה אחת שאחריה.
  void _scheduleSave(List<OpenedTab> tabs, int currentTabIndex) {
    _pendingSaveTabs = tabs;
    _pendingSaveIndex = currentTabIndex;
    _saveDrain ??= _drainSaves();
  }

  void _logSaveFailure(Object error, StackTrace stackTrace) {
    try {
      ErrorLogFile.append(
        title: 'שמירת הכרטיסיות הפתוחות נכשלה',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (logError, logStackTrace) {
      debugPrint('רישום כשל שמירת כרטיסיות נכשל: $logError\n$logStackTrace');
    }
  }

  Future<void> _drainSaves() async {
    try {
      while (_pendingSaveTabs != null) {
        final tabs = _pendingSaveTabs!;
        final index = _pendingSaveIndex;
        _pendingSaveTabs = null;
        try {
          await _repository.saveTabs(tabs, index);
        } catch (error, stackTrace) {
          _logSaveFailure(error, stackTrace);
        }
        // הכתיבה נשאה את האינדקס שהיה בתחילתה; אם המשתמש החליף טאב בזמנה,
        // היא דרסה את מה שכתב [_saveCurrentTabIndex].
        if (_pendingSaveTabs == null && _pendingSaveIndex != index) {
          try {
            await _repository.saveCurrentTabIndex(tabs, _pendingSaveIndex);
          } catch (error, stackTrace) {
            _logSaveFailure(error, stackTrace);
          }
        }
      }
    } finally {
      _saveDrain = null;
    }
  }

  /// שומר את האינדקס הפעיל בלבד, ומעדכן גם את האינדקס של השמירה המלאה —
  /// זו שממתינה וזו שרצה — כדי שלא תחזיר לאחור את הטאב שנבחר.
  Future<void> _saveCurrentTabIndex(List<OpenedTab> tabs, int index) {
    _pendingSaveIndex = index;
    return _repository.saveCurrentTabIndex(tabs, index);
  }

  /// ממתין לכתיבת הטאבים שטרם הסתיימה, לפני סגירת התוכנה. ה-timeout מונע
  /// היתקעות ביציאה כשכתיבת Hive נחסמת (כמו ב-[remapBookPathsAwaitable]).
  Future<void> _flushPendingSaves() =>
      _saveDrain?.timeout(const Duration(seconds: 5), onTimeout: () {}) ??
      Future<void>.value();

  void _disposeTabLater(OpenedTab tab) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        tab.dispose();
      }),
    );
  }

  TabsBloc({
    required this._repository,
  }) : super(TabsState.initial()) {
    on<LoadTabs>(_onLoadTabs);
    on<RemapBookPaths>(_onRemapBookPaths, transformer: sequential());
    on<ReplaceAllTabs>(_onReplaceAllTabs, transformer: sequential());
    on<AddTab>(_onAddTab, transformer: sequential());
    on<OpenOrFocusTab>(_onOpenOrFocusTab, transformer: sequential());
    on<ReplaceTab>(_onReplaceTab, transformer: sequential());
    on<RemoveTab>(_onRemoveTab, transformer: sequential());
    on<RemoveTabs>(_onRemoveTabs, transformer: sequential());
    on<ToggleTabSelection>(_onToggleTabSelection, transformer: sequential());
    on<SelectTabRange>(_onSelectTabRange, transformer: sequential());
    on<ClearTabSelection>(_onClearTabSelection, transformer: sequential());
    on<SetCurrentTab>(_onSetCurrentTab, transformer: sequential());
    on<CloseAllTabs>(_onCloseAllTabs, transformer: sequential());
    on<CloseOtherTabs>(_onCloseOtherTabs, transformer: sequential());
    on<CloneTab>(_onCloneTab);
    on<MoveTab>(_onMoveTab, transformer: sequential());
    on<NavigateToNextTab>(_onNavigateToNextTab, transformer: sequential());
    on<NavigateToPreviousTab>(
      _onNavigateToPreviousTab,
      transformer: sequential(),
    );
    on<CloseCurrentTab>(_onCloseCurrentTab);
    on<RestoreLastClosedTab>(
      _onRestoreLastClosedTab,
      transformer: sequential(),
    );
    on<RestoreClosedTab>(_onRestoreClosedTab, transformer: sequential());
    on<SaveTabs>(_onSaveTabs, transformer: sequential());
    on<TogglePinTab>(_onTogglePinTab, transformer: sequential());
    on<CreateCombinedTab>(
      _onCreateCombinedTab,
      transformer: sequential(),
    );
    on<OpenTabInSidePane>(
      _onOpenTabInSidePane,
      transformer: sequential(),
    );
    on<ExpandCombinedTab>(
      _onExpandCombinedTab,
      transformer: sequential(),
    );
    on<UpdateSplitRatio>(_onUpdateSplitRatio, transformer: sequential());
    on<SwapSideBySideTabs>(_onSwapSideBySideTabs, transformer: sequential());
    on<ClosePane>(_onClosePane, transformer: sequential());
    on<SetActivePane>(_onSetActivePane);

    _preCloseCallback = _flushPendingSaves;
    PreCloseRegistry.register(_preCloseCallback);
  }

  late final Future<void> Function() _preCloseCallback;

  @override
  Future<void> close() async {
    PreCloseRegistry.unregister(_preCloseCallback);
    await _flushPendingSaves();
    await super.close();
  }

  void _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) {
    // הטאבים והאינדקס מנורמלים יחד כדי לשמור על הטאב הפעיל.
    final restored = flattenRestoredSplits(
      _repository.loadTabs(),
      currentIndex: _repository.loadCurrentTabIndex(),
    );
    final tabs = restored.tabs;

    emit(
      state.copyWith(
        tabs: tabs,
        currentTabIndex: tabs.isEmpty
            ? 0
            : restored.currentIndex.clamp(0, tabs.length - 1),
      ),
    );
  }

  /// ממפה נתיבי ספרים פתוחים מ-[from] ל-[to] (זיכרון + Hive) וממתין לסיום.
  /// משמש את העברת הספרייה: חובה להמתין לפני הרענון כדי ששמירת הטאבים בעת
  /// ה-dispose לא תדרוס את המיפוי עם הנתיב הישן.
  Future<void> remapBookPathsAwaitable(String from, String to) {
    final completer = Completer<void>();
    add(RemapBookPaths(from, to, completer: completer));
    // רשת ביטחון: לא להקפיא את זרימת ההעברה אם ה-handler לא ירוץ (למשל
    // אם ה-bloc נסגר). בזרימה הרגילה ה-handler משלים הרבה לפני הזמן הזה.
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  Future<void> _onRemapBookPaths(
    RemapBookPaths event,
    Emitter<TabsState> emit,
  ) async {
    try {
      final remapped = _repository.remapTabsInMemory(
        state.tabs,
        event.fromDir,
        event.toDir,
      );
      final unchanged =
          remapped.length == state.tabs.length &&
          List.generate(
            remapped.length,
            (i) => i,
          ).every((i) => identical(remapped[i], state.tabs[i]));
      if (!unchanged) {
        emit(state.copyWith(tabs: remapped));
        // המיפוי חייב להיכתב אחרי הכתיבה שרצה, כי היא נושאת את הנתיבים הישנים.
        await _saveDrain;
        await _repository.saveTabs(remapped, state.currentTabIndex);
      }
      event.completer?.complete();
    } catch (e, st) {
      // בהעברת ספרייה זו פעולה קריטית — הכישלון חייב להגיע למי שממתין
      // ל-Future (ולא להיראות כהצלחה). ללא completer (fire-and-forget) נזרק.
      if (event.completer != null) {
        event.completer!.completeError(e, st);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _onReplaceAllTabs(
    ReplaceAllTabs event,
    Emitter<TabsState> emit,
  ) async {
    debugPrint('DEBUG: החלפת כל הטאבים - ${event.tabs.length} טאבים חדשים');

    final tabsToDispose = List<OpenedTab>.from(state.tabs);

    emit(
      state.copyWith(
        tabs: event.tabs,
        currentTabIndex: event.currentTabIndex,
        selectedTabs: const <OpenedTab>[],
      ),
    );
    _scheduleSave(event.tabs, event.currentTabIndex);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  /// נשלח ביציאה מהתוכנה ובמעבר לרקע — כאן ממתינים לסיום הכתיבה בפועל, אחרת
  /// שמירה שממתינה תלך לאיבוד עם התהליך.
  Future<void> _onSaveTabs(SaveTabs event, Emitter<TabsState> emit) async {
    _scheduleSave(state.tabs, state.currentTabIndex);
    await _saveDrain;
  }

  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
    debugPrint('DEBUG: הוספת טאב חדש - ${event.tab.title}');
    final newTabs = List<OpenedTab>.from(state.tabs);
    final newIndex = event.insertAdjacent
        ? min(state.currentTabIndex + 1, newTabs.length)
        : newTabs.length;
    newTabs.insert(newIndex, event.tab);

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: newIndex,
      ),
    );
    _scheduleSave(newTabs, newIndex);
  }

  Future<void> _onOpenOrFocusTab(
    OpenOrFocusTab event,
    Emitter<TabsState> emit,
  ) async {
    final targetTitle = await _resolveTabLocationTitle(
      event.tab,
      explicitTitle: event.targetTitle,
    );
    final matchingIndex = await _findMatchingTopLevelTabIndex(
      event.tab,
      targetTitle,
      // כשמבקשים לנווט למיקום (סימניה/deep link עם מיקום מפורש), ההתאמה
      // לפי זהות הספר בלבד - הכותרת מקודדת מיקום ולכן תיכשל בכוונה כשהמיקום
      // שונה, ואז היה נפתח טאב חדש במקום לנווט בטאב הקיים.
      ignoreLocation: event.navigateToPositionIfReused,
    );

    if (matchingIndex != null) {
      // אם הטאב החדש מבקש הדגשה ממוקדת (deep link), נעביר אותה ל‑bloc של
      // הטאב הקיים — אחרת ה‑highlight החדש היה נזרק עם ה‑dispose.
      _propagatePinpointHighlightToExistingTab(
        existingTab: state.tabs[matchingIndex],
        incomingTab: event.tab,
      );
      _propagateSearchToExistingTab(
        existingTab: state.tabs[matchingIndex],
        incomingTab: event.tab,
      );
      // סימניות/היסטוריה: המשתמש בחר מיקום ספציפי בספר, ולא מספיק להעביר
      // focus לטאב הקיים — צריך לגלול אותו למיקום המבוקש.
      if (event.navigateToPositionIfReused) {
        _propagateNavigationToExistingTab(
          existingTab: state.tabs[matchingIndex],
          incomingTab: event.tab,
        );
      }
      final matchingPane = await _matchingPaneIn(
        state.tabs[matchingIndex],
        event.tab,
        targetTitle,
        ignoreLocation: event.navigateToPositionIfReused,
      );
      event.tab.dispose();
      final tabsToSave = state.tabs;
      // התאמה בחלונית מפוצלת דורשת גם עדכון של החלונית הפעילה.
      emit(
        state.copyWith(
          currentTabIndex: matchingIndex,
          rawActivePane: matchingPane,
        ),
      );
      _scheduleSave(tabsToSave, matchingIndex);
      return;
    }

    await _onAddTab(
      AddTab(event.tab, insertAdjacent: event.insertAdjacent),
      emit,
    );
  }

  Future<void> _onReplaceTab(ReplaceTab event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexOf(event.oldTab);
    if (index == -1) {
      // הטאב נסגר בזמן הרזולוציה — אין את מי להחליף.
      _disposeTabLater(event.newTab);
      return;
    }

    event.newTab.isPinned = event.oldTab.isPinned;
    final newTabs = List<OpenedTab>.from(state.tabs);
    newTabs[index] = event.newTab;

    emit(
      state.copyWith(
        tabs: newTabs,
        forceUpdate: true,
        selectedTabs: _normalizedSelection(newTabs),
      ),
    );
    _scheduleSave(newTabs, state.currentTabIndex);
    _disposeTabLater(event.oldTab);
  }

  void _propagatePinpointHighlightToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (incomingTab is! TextBookTab) return;

    final TextBookTab? targetText = _resolveTextBookTab(
      existingTab,
      incomingTab,
    );
    if (targetText == null) return;

    // בוחרים את ערכי ההדגשה לפי סדר עדיפות: pinpoint (deep link עם highlight
    // ממוקד לסעיף) מקבל קדימות. אחרת, highlightText/permanentHighlightLine
    // (deep link ?mark). אם אין כלום — אין מה להחיל.
    final pinpoint = incomingTab.pinpointHighlight;
    final String effectiveHighlight;
    final int? effectiveLine;
    if (pinpoint != null && pinpoint.isNotEmpty) {
      effectiveHighlight = pinpoint;
      effectiveLine =
          incomingTab.pinpointHighlightSectionIndex ?? incomingTab.index;
    } else if (incomingTab.highlightText.isNotEmpty ||
        incomingTab.permanentHighlightLine != null) {
      effectiveHighlight = incomingTab.highlightText;
      effectiveLine = incomingTab.permanentHighlightLine;
    } else {
      return;
    }

    void dispatch() {
      targetText.bloc.add(
        ApplyMarkHighlight(
          highlightText: effectiveHighlight,
          permanentHighlightLine: effectiveLine,
          scrollToIndex: effectiveLine,
        ),
      );
    }

    if (targetText.bloc.state is TextBookLoaded) {
      dispatch();
      return;
    }

    // הטאב הקיים עוד לא נטען — נחכה לטעינה ואז נחיל. .catchError() מטפל
    // בסגירת ה-bloc מוקדמת (למשל כשהמשתמש סגר את הטאב).
    targetText.bloc.stream
        .firstWhere((state) => state is TextBookLoaded)
        .then((_) => dispatch())
        .catchError((_) {});
  }

  /// מעביר את החיפוש של הטאב הנכנס אל הטאב הקיים שקיבל את המיקוד. בלעדיו
  /// פתיחת תוצאה בספר שכבר פתוח מאבדת את השאילתה ואת כל התוספות שלה, והחיפוש
  /// בספר חוזר למסלול המחרוזת הרצופה — "אין תוצאות" על תוצאה שנמצאה.
  void _propagateSearchToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (incomingTab is TextBookTab) {
      if (incomingTab.searchText.isEmpty) return;
      final targetText = _resolveTextBookTab(existingTab, incomingTab);
      if (targetText == null) return;
      void dispatch() {
        targetText.bloc.add(
          UpdateSearchText(
            incomingTab.searchText,
            searchOptions: incomingTab.searchOptions,
            alternativeWords: incomingTab.alternativeWords,
            spacingValues: incomingTab.spacingValues,
            searchMode: incomingTab.searchMode,
            searchDistance: incomingTab.searchDistance,
            matchPolicy: incomingTab.matchPolicy,
          ),
        );
      }

      // טאב שוחזר ולא נצפה עדיין — ה-bloc שלו ב-TextBookInitial, ושם
      // UpdateSearchText נזרק. ממתינים לטעינה, כמו במסלול ההדגשה המדויקת.
      if (targetText.bloc.state is TextBookLoaded) {
        dispatch();
      } else {
        targetText.bloc.stream
            .firstWhere((state) => state is TextBookLoaded)
            .then((_) => dispatch())
            .catchError((_) {});
      }
      return;
    }

    if (incomingTab is PdfBookTab) {
      if (incomingTab.searchText.isEmpty) return;
      final targetPdf = _resolvePdfBookTab(existingTab, incomingTab);
      if (targetPdf == null) return;
      // החלה אטומית: השאילתה והתצורה יחד. עדכון שדה החיפוש לפני התצורה היה
      // מריץ את השאילתה החדשה עם התצורה הישנה.
      targetPdf.applyIncomingSearchConfiguration(
        ReadingTabSearchState(
          searchText: incomingTab.searchText,
          searchOptions: incomingTab.searchOptions,
          alternativeWords: incomingTab.alternativeWords,
          spacingValues: incomingTab.spacingValues,
          searchMode: incomingTab.searchMode,
          searchDistance: incomingTab.searchDistance,
          matchPolicy: incomingTab.matchPolicy,
        ),
      );
    }
  }

  TextBookTab? _resolveTextBookTab(
    OpenedTab existingTab,
    TextBookTab incomingTab,
  ) {
    if (existingTab is TextBookTab) {
      return existingTab;
    }
    // בפיצול מזהים ספר לפי מזהה, כדי לא לעדכן ספר בעל כותרת זהה.
    if (existingTab is CombinedTab) {
      for (final pane in leafPanes(existingTab)) {
        if (pane is TextBookTab && _isSameBook(pane, incomingTab)) {
          return pane;
        }
      }
    }
    return null;
  }

  PdfBookTab? _resolvePdfBookTab(
    OpenedTab existingTab,
    PdfBookTab incomingTab,
  ) {
    if (existingTab is PdfBookTab) {
      return existingTab;
    }
    if (existingTab is CombinedTab) {
      for (final pane in leafPanes(existingTab)) {
        if (pane is PdfBookTab && _isSameBook(pane, incomingTab)) {
          return pane;
        }
      }
    }
    return null;
  }

  /// מנווט טאב קיים למיקום של הטאב הנכנס (index ב‑TextBook, pageNumber ב‑PDF).
  /// משמש כשפתיחת סימניה/היסטוריה ממחזרת טאב קיים — המשתמש בחר מיקום ספציפי
  /// ולא רק את הספר.
  void _propagateNavigationToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (incomingTab is PdfBookTab) {
      final targetPdf = _resolvePdfBookTab(existingTab, incomingTab);
      if (targetPdf == null) return;
      final targetPage = incomingTab.pageNumber;
      // עדכון pageNumber בטאב כך שיישמר ל-restore עתידי וכך שאם המסך עוד
      // לא הצטרף ל-controller, הטעינה הבאה תיפתח בעמוד הנכון.
      targetPdf.pageNumber = targetPage;
      if (targetPdf.pdfViewerController.isReady) {
        targetPdf.pdfViewerController.goToPage(pageNumber: targetPage);
      }
      return;
    }

    if (incomingTab is TextBookTab) {
      final targetText = _resolveTextBookTab(existingTab, incomingTab);
      if (targetText == null) return;
      final targetIndex = incomingTab.index;
      // עדכון אינדקס הטאב מיידית - חשוב משתי סיבות:
      // 1. saveTabs רץ ב‑finally של ה‑handler ועלול להישמר על המיקום הישן.
      // 2. אם המסך עוד לא בנה את הרשימה (scrollController לא מחובר), הקריאה
      //    הבאה ל‑initState/load תפתח באינדקס הזה.
      targetText.index = targetIndex;

      Future<void> dispatch() async {
        // ApplyPinpointHighlight (אם קודם) כבר גלל. כאן מטפלים במקרה שאין
        // pinpoint אבל יש בקשת ניווט. הקונטרולר עשוי להיות לא מחובר גם
        // כש‑state הוא Loaded (הרשימה עדיין לא קיבלה את הפריימים הראשונים),
        // לכן מנסים שוב ושוב עד שמחובר או עד timeout סביר.
        for (var attempt = 0; attempt < 30; attempt++) {
          if (targetText.bloc.isClosed) return;
          if (targetText.bloc.scrollController.isAttached) {
            targetText.bloc.scrollController.scrollTo(
              index: targetIndex,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      if (targetText.bloc.state is TextBookLoaded) {
        unawaited(dispatch());
        return;
      }

      late StreamSubscription<TextBookState> sub;
      sub = targetText.bloc.stream.listen((state) {
        if (state is TextBookLoaded) {
          unawaited(dispatch());
          sub.cancel();
        }
      });
    }
  }

  Future<int?> _findMatchingTopLevelTabIndex(
    OpenedTab targetTab,
    String? normalizedTargetTitle, {
    bool ignoreLocation = false,
  }) async {
    for (var index = 0; index < state.tabs.length; index++) {
      final openTab = state.tabs[index];
      if (await _topLevelTabMatches(
        openTab,
        targetTab,
        normalizedTargetTitle,
        ignoreLocation,
      )) {
        return index;
      }
    }
    return null;
  }

  Future<bool> _topLevelTabMatches(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle,
    bool ignoreLocation,
  ) async {
    if (await _singleTabMatches(
      openTab,
      targetTab,
      normalizedTargetTitle,
      ignoreLocation,
    )) {
      return true;
    }

    if (openTab is CombinedTab) {
      for (final pane in leafPanes(openTab)) {
        if (await _singleTabMatches(
          pane,
          targetTab,
          normalizedTargetTitle,
          ignoreLocation,
        )) {
          return true;
        }
      }
    }

    return false;
  }

  Future<bool> _singleTabMatches(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle,
    bool ignoreLocation,
  ) async {
    if (_hasMatchingDedupeKey(openTab, targetTab)) {
      return true;
    }

    if (!_isSameBook(openTab, targetTab)) {
      return false;
    }

    // ניווט למיקום בספר פתוח: זהות הספר מספיקה, אין צורך בהתאמת כותרת/מיקום.
    if (ignoreLocation) {
      return true;
    }

    final normalizedOpenTitle = await _resolveTabLocationTitle(openTab);
    return _titlesMatch(
      normalizedOpenTitle: normalizedOpenTitle,
      normalizedTargetTitle: normalizedTargetTitle,
      openTab: openTab,
      targetTab: targetTab,
    );
  }

  /// החלונית המתאימה בתוך [openTab], או `null` כשהטאב עצמו הוא ההתאמה.
  Future<OpenedTab?> _matchingPaneIn(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle, {
    required bool ignoreLocation,
  }) async {
    if (openTab is! CombinedTab) return null;
    for (final pane in leafPanes(openTab)) {
      if (await _singleTabMatches(
        pane,
        targetTab,
        normalizedTargetTitle,
        ignoreLocation,
      )) {
        return pane;
      }
    }
    return null;
  }

  /// אינדקס הכרטיסיה העליונה שחולקת `dedupeKey` עם [tab], או `null`.
  int? _indexOfMatchingDedupeKey(OpenedTab tab) {
    if (tab.dedupeKey == null) return null;
    for (var i = 0; i < state.tabs.length; i++) {
      if (_hasMatchingDedupeKey(state.tabs[i], tab)) return i;
      final openTab = state.tabs[i];
      if (openTab is CombinedTab) {
        for (final pane in leafPanes(openTab)) {
          if (_hasMatchingDedupeKey(pane, tab)) return i;
        }
      }
    }
    return null;
  }

  bool _hasMatchingDedupeKey(OpenedTab openTab, OpenedTab targetTab) {
    final openKey = openTab.dedupeKey;
    final targetKey = targetTab.dedupeKey;
    return openKey != null && targetKey != null && openKey == targetKey;
  }

  bool _isSameBook(OpenedTab openTab, OpenedTab targetTab) {
    if (openTab is TextBookTab && targetTab is TextBookTab) {
      final openIdentity = _textBookIdentity(openTab);
      final targetIdentity = _textBookIdentity(targetTab);
      if (openIdentity == null || targetIdentity == null) {
        return false;
      }
      return openIdentity == targetIdentity;
    }

    if (openTab is PdfBookTab && targetTab is PdfBookTab) {
      return openTab.book.path == targetTab.book.path;
    }

    return false;
  }

  String? _textBookIdentity(TextBookTab tab) {
    final base = _textBookBaseIdentity(tab);
    if (base == null) return null;
    // מהדורה חלופית היא טאב נפרד מהנוסח הממוזג של אותו ספר.
    final versionTitle = tab.book.versionTitle;
    return versionTitle == null ? base : '$base|version:$versionTitle';
  }

  String? _textBookBaseIdentity(TextBookTab tab) {
    final bookId = tab.book.id;
    if (bookId != null) {
      return 'book:$bookId';
    }

    final categoryId = tab.book.categoryId;
    if (categoryId != null) {
      return 'category:$categoryId|title:${tab.book.title}|type:${tab.book.fileType ?? 'txt'}';
    }

    final externalLibraryId = tab.book.externalLibraryId;
    if (externalLibraryId != null && externalLibraryId.isNotEmpty) {
      return 'external:$externalLibraryId';
    }

    final filePath = tab.book.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      return 'file:$filePath';
    }

    return null;
  }

  Future<String?> _resolveTabLocationTitle(
    OpenedTab tab, {
    String? explicitTitle,
  }) async {
    if (tab is TextBookTab) {
      return _normalizeLocationTitle(
        tab.book.title,
        explicitTitle ??
            await _resolveTextTabLocationTitle(
              tab,
            ),
      );
    }

    if (tab is PdfBookTab) {
      return _normalizeLocationTitle(
        tab.book.title,
        explicitTitle ??
            await _resolvePdfTabLocationTitle(
              tab,
            ),
      );
    }

    return explicitTitle?.trim().isEmpty ?? true ? null : explicitTitle!.trim();
  }

  /// תקרת-זמן לשליפת ה-TOC של רזולוציית הכותרת: הרזולוציה היא best-effort
  /// (null ⇒ טאב חדש), ושליפה תקועה חוסמת לצמיתות כל פתיחת ספר (issue #853).
  @visibleForTesting
  static Duration locationTitleResolveTimeout = const Duration(seconds: 5);

  Future<String?> _resolveTextTabLocationTitle(TextBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromIndex(
        tab.index,
        tab.book.tableOfContents,
      ).timeout(locationTitleResolveTimeout);
      return ref.trim().isEmpty ? null : ref;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolvePdfTabLocationTitle(PdfBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromPageNumber(
        tab.pageNumber,
        tab.outline.value,
        tab.book.title,
      );
      if (ref.trim().isNotEmpty) {
        return ref;
      }
    } catch (_) {
      // Fall back to page-based comparison when outline is unavailable.
    }

    return null;
  }

  String? _normalizeLocationTitle(String bookTitle, String? title) {
    if (title == null) {
      return null;
    }

    var normalized = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith(bookTitle)) {
      normalized = normalized.substring(bookTitle.length).trimLeft();
      if (normalized.startsWith(',')) {
        normalized = normalized.substring(1).trimLeft();
      }
    }

    return normalized.isEmpty ? null : normalized;
  }

  bool _titlesMatch({
    required String? normalizedOpenTitle,
    required String? normalizedTargetTitle,
    required OpenedTab openTab,
    required OpenedTab targetTab,
  }) {
    if (normalizedOpenTitle != null && normalizedTargetTitle != null) {
      return normalizedOpenTitle == normalizedTargetTitle;
    }

    return _fallbackLocationKey(openTab) == _fallbackLocationKey(targetTab);
  }

  String _fallbackLocationKey(OpenedTab tab) {
    if (tab is TextBookTab) {
      return 'index:${tab.index}';
    }

    if (tab is PdfBookTab) {
      return 'page:${tab.pageNumber}';
    }

    return tab.title;
  }

  void _rememberClosedTab(OpenedTab tab, int originalIndex) {
    _recentlyClosedTabs.add(
      _ClosedTabEntry(
        tab: OpenedTab.from(tab),
        originalIndex: originalIndex,
      ),
    );
    while (_recentlyClosedTabs.length > _kMaxRecentlyClosedTabs) {
      _recentlyClosedTabs.removeAt(0).tab.dispose();
    }
  }

  /// מנרמל את הבחירה המרובה מול רשימת טאבים חדשה: כרטיסיות שנסגרו/הוחלפו
  /// יוצאות, וקבוצה שהצטמקה לאחת מתפרקת.
  List<OpenedTab> _normalizedSelection(List<OpenedTab> newTabs) {
    final selected = state.selectedTabs.where(newTabs.contains).toList();
    return selected.length > 1 ? selected : const <OpenedTab>[];
  }

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final removedTabIndex = state.tabs.indexOf(event.tab);
    if (removedTabIndex == -1) return;

    _rememberClosedTab(event.tab, removedTabIndex);

    final newTabs = List<OpenedTab>.from(state.tabs)..remove(event.tab);

    final prunedSelection = _normalizedSelection(newTabs);

    // אם אין טאבים נותרים, נשאיר את האינדקס ב-0
    if (newTabs.isEmpty) {
      emit(
        state.copyWith(
          tabs: newTabs,
          currentTabIndex: 0,
          selectedTabs: prunedSelection,
        ),
      );
      _scheduleSave(newTabs, 0);
      _disposeTabLater(event.tab);
      return;
    }

    // סגירת הטאב הפעיל מעבירה לטאב הבא (שנכנס תחת אותו אינדקס לאחר המחיקה).
    // סגירת טאב שלפני הפעיל מזיזה את הפעיל אינדקס אחד אחורה.
    var newIndex = removedTabIndex < state.currentTabIndex
        ? state.currentTabIndex - 1
        : state.currentTabIndex;

    // וידוא שהאינדקס תקין (לא חורג מגבולות הרשימה)
    newIndex = min(newIndex, newTabs.length - 1);

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: newIndex,
        selectedTabs: prunedSelection,
      ),
    );
    _scheduleSave(newTabs, newIndex);
    _disposeTabLater(event.tab);
  }

  Future<void> _onRemoveTabs(RemoveTabs event, Emitter<TabsState> emit) async {
    final toRemove = event.tabs.where(state.tabs.contains).toSet();
    if (toRemove.isEmpty) return;

    // נזכרים בסדר אינדקס יורד: השחזור הוא LIFO, וכך שחזור סדרתי מחזיר כל
    // כרטיסיה למקומה המקורי.
    for (var i = state.tabs.length - 1; i >= 0; i--) {
      if (toRemove.contains(state.tabs[i])) {
        _rememberClosedTab(state.tabs[i], i);
      }
    }

    final newTabs = state.tabs.where((t) => !toRemove.contains(t)).toList();

    // הטאב הפעיל נשאר אם שרד; אחרת עוברים לטאב שנכנס תחת אותו אינדקס
    // (כמו בסגירה בודדת), בניכוי הטאבים שנסגרו לפניו.
    final currentTab = state.currentTab;
    int newIndex;
    if (currentTab != null && !toRemove.contains(currentTab)) {
      newIndex = newTabs.indexOf(currentTab);
    } else {
      var removedBefore = 0;
      for (var i = 0; i < state.currentTabIndex; i++) {
        if (toRemove.contains(state.tabs[i])) removedBefore++;
      }
      newIndex = newTabs.isEmpty
          ? 0
          : (state.currentTabIndex - removedBefore).clamp(
              0,
              newTabs.length - 1,
            );
    }

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: newIndex,
        selectedTabs: _normalizedSelection(newTabs),
      ),
    );
    _scheduleSave(newTabs, newIndex);

    for (final tab in toRemove) {
      _disposeTabLater(tab);
    }
  }

  void _onToggleTabSelection(
    ToggleTabSelection event,
    Emitter<TabsState> emit,
  ) {
    if (!state.tabs.contains(event.tab)) return;
    final selected = state.selectedTabs.where(state.tabs.contains).toList();
    // הכרטיסיה הפעילה היא חלק מהקבוצה: הלחיצה הראשונה מצרפת גם אותה
    // (כמו בדפדפן).
    final current = state.currentTab;
    if (selected.isEmpty && current != null && event.tab != current) {
      selected.add(current);
    }
    if (!selected.remove(event.tab)) selected.add(event.tab);
    // קבוצה של כרטיסיה אחת חסרת משמעות — הבחירה מתפרקת.
    emit(
      state.copyWith(
        selectedTabs: selected.length > 1 ? selected : const <OpenedTab>[],
      ),
    );
  }

  void _onSelectTabRange(SelectTabRange event, Emitter<TabsState> emit) {
    final index = state.tabs.indexOf(event.tab);
    if (index == -1) return;
    final start = min(state.currentTabIndex, index);
    final end = max(state.currentTabIndex, index);
    final selected = state.tabs.sublist(start, end + 1);
    emit(
      state.copyWith(
        selectedTabs: selected.length > 1 ? selected : const <OpenedTab>[],
      ),
    );
  }

  void _onClearTabSelection(ClearTabSelection event, Emitter<TabsState> emit) {
    if (state.selectedTabs.isEmpty) return;
    emit(state.copyWith(selectedTabs: const <OpenedTab>[]));
  }

  Future<void> _onSetCurrentTab(
    SetCurrentTab event,
    Emitter<TabsState> emit,
  ) async {
    if (event.index >= 0 && event.index < state.tabs.length) {
      final tabsToSave = state.tabs;
      emit(state.copyWith(currentTabIndex: event.index));
      // מעבר טאב לא משנה את רשימת הטאבים — שומרים רק את האינדקס הנוכחי
      // במקום לקודד מחדש את כל הטאבים.
      await _saveCurrentTabIndex(tabsToSave, event.index);
    }
  }

  void _onCloseCurrentTab(CloseCurrentTab event, Emitter<TabsState> emit) {
    if (state.tabs.isEmpty || state.currentTabIndex >= state.tabs.length) {
      return;
    }
    // כשהכרטיסיה הפעילה חלק מבחירה מרובה, הקיצור סוגר את כל הקבוצה.
    final group = state.currentCloseGroup;
    if (group.length > 1) {
      add(RemoveTabs(group));
    } else {
      add(RemoveTab(state.tabs[state.currentTabIndex]));
    }
  }

  Future<void> _onRestoreLastClosedTab(
    RestoreLastClosedTab event,
    Emitter<TabsState> emit,
  ) async {
    if (_recentlyClosedTabs.isEmpty) return;
    await _restoreClosedEntry(_recentlyClosedTabs.removeLast(), emit);
  }

  Future<void> _onRestoreClosedTab(
    RestoreClosedTab event,
    Emitter<TabsState> emit,
  ) async {
    final index = _recentlyClosedTabs.indexWhere(
      (entry) => identical(entry.tab, event.tab),
    );
    if (index == -1) return;
    await _restoreClosedEntry(_recentlyClosedTabs.removeAt(index), emit);
  }

  Future<void> _restoreClosedEntry(
    _ClosedTabEntry closedEntry,
    Emitter<TabsState> emit,
  ) async {
    // כלי פתוח ממוקד במקום ליצור מופע נוסף.
    final existingIndex = _indexOfMatchingDedupeKey(closedEntry.tab);
    if (existingIndex != null) {
      closedEntry.tab.dispose();
      final tabsToSave = state.tabs;
      emit(state.copyWith(currentTabIndex: existingIndex));
      await _saveCurrentTabIndex(tabsToSave, existingIndex);
      return;
    }
    final restoredTabs = List<OpenedTab>.from(state.tabs);
    final restoreIndex = closedEntry.originalIndex.clamp(
      0,
      restoredTabs.length,
    );
    restoredTabs.insert(restoreIndex, closedEntry.tab);

    emit(
      state.copyWith(
        tabs: restoredTabs,
        currentTabIndex: restoreIndex,
      ),
    );
    _scheduleSave(restoredTabs, restoreIndex);
  }

  Future<void> _onCloseAllTabs(
    CloseAllTabs event,
    Emitter<TabsState> emit,
  ) async {
    // שמירת טאבים מוצמדים בלבד
    final pinnedTabs = state.tabs.where((tab) => tab.isPinned).toList();
    final tabsToDispose = state.tabs.where((tab) => !tab.isPinned).toList();
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (!tab.isPinned) {
        _rememberClosedTab(tab, i);
      }
    }

    // אם יש טאבים מוצמדים, נשאיר אותם
    final newIndex = pinnedTabs.isNotEmpty ? 0 : 0;

    emit(
      state.copyWith(
        tabs: pinnedTabs,
        currentTabIndex: newIndex,
        selectedTabs: const <OpenedTab>[],
      ),
    );
    _scheduleSave(pinnedTabs, newIndex);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  Future<void> _onCloseOtherTabs(
    CloseOtherTabs event,
    Emitter<TabsState> emit,
  ) async {
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (tab != event.keepTab) {
        _rememberClosedTab(tab, i);
      }
    }
    final tabsToDispose = state.tabs
        .where((tab) => tab != event.keepTab)
        .toList();

    final newTabs = [event.keepTab];

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: 0,
        selectedTabs: const <OpenedTab>[],
      ),
    );
    _scheduleSave(newTabs, 0);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  void _onCloneTab(CloneTab event, Emitter<TabsState> emit) {
    if (event.tab is ToolTab && (event.tab as ToolTab).isPlugin) return;
    add(AddTab(OpenedTab.from(event.tab), insertAdjacent: true));
  }

  Future<void> _onMoveTab(MoveTab event, Emitter<TabsState> emit) async {
    final newTabs = List<OpenedTab>.from(state.tabs);
    final currentTab = newTabs[state.currentTabIndex];
    newTabs.remove(event.tab);
    newTabs.insert(event.newIndex, event.tab);
    final newIndex = newTabs.indexOf(currentTab);

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: newIndex,
      ),
    );
    _scheduleSave(newTabs, newIndex);
  }

  Future<void> _onNavigateToNextTab(
    NavigateToNextTab event,
    Emitter<TabsState> emit,
  ) async {
    if (state.tabs.isEmpty) return;
    final newIndex = (state.currentTabIndex + 1) % state.tabs.length;
    final tabsToSave = state.tabs;
    emit(state.copyWith(currentTabIndex: newIndex));
    await _saveCurrentTabIndex(tabsToSave, newIndex);
  }

  Future<void> _onNavigateToPreviousTab(
    NavigateToPreviousTab event,
    Emitter<TabsState> emit,
  ) async {
    if (state.tabs.isEmpty) return;
    final newIndex = state.currentTabIndex == 0
        ? state.tabs.length - 1
        : state.currentTabIndex - 1;
    final tabsToSave = state.tabs;
    emit(state.copyWith(currentTabIndex: newIndex));
    await _saveCurrentTabIndex(tabsToSave, newIndex);
  }

  Future<void> _onTogglePinTab(
    TogglePinTab event,
    Emitter<TabsState> emit,
  ) async {
    final tabIndex = state.tabs.indexOf(event.tab);
    if (tabIndex == -1) return;

    // החלפת מצב ההצמדה
    event.tab.isPinned = !event.tab.isPinned;

    debugPrint(
      'DEBUG: הצמדת טאב ${event.tab.title} - isPinned: ${event.tab.isPinned}',
    );

    // יצירת רשימה חדשה לחלוטין כדי לגרום ל-Equatable לזהות שינוי
    final newTabs = List<OpenedTab>.from(state.tabs);

    // עדכון ה-state כדי לגרום ל-rebuild - עם forceUpdate
    final indexToSave = state.currentTabIndex;
    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: state.currentTabIndex,
        forceUpdate: true,
      ),
    );
    // שמירת השינויים
    _scheduleSave(newTabs, indexToSave);
  }

  Future<void> _onCreateCombinedTab(
    CreateCombinedTab event,
    Emitter<TabsState> emit,
  ) async {
    final rightIndex = state.tabs.indexOf(event.rightTab);
    final leftIndex = state.tabs.indexOf(event.leftTab);

    if (rightIndex == -1 || leftIndex == -1) {
      debugPrint('ERROR: לא נמצאו הטאבים למצב side-by-side');
      return;
    }

    // פיצול הוא לשתי חלוניות בלבד: מיזוג טאב שכבר מפוצל היה מקנן אותו.
    if (event.rightTab is CombinedTab || event.leftTab is CombinedTab) return;
    // אותו טאב בשני הצדדים יוצר מפתח חלונית כפול.
    if (identical(event.rightTab, event.leftTab)) return;

    // שומרים על זהות החלוניות כדי לשמר את מצב הקריאה.
    final combinedTab = CombinedTab(
      rightTab: event.rightTab,
      leftTab: event.leftTab,
      isPinned: event.rightTab.isPinned || event.leftTab.isPinned,
    );

    final newTabs = List<OpenedTab>.from(state.tabs);

    final insertIndex = rightIndex < leftIndex ? rightIndex : leftIndex;

    // הסרה מהאינדקס הגבוה שומרת על האינדקס הנמוך.
    if (rightIndex > leftIndex) {
      newTabs.removeAt(rightIndex);
      newTabs.removeAt(leftIndex);
    } else {
      newTabs.removeAt(leftIndex);
      newTabs.removeAt(rightIndex);
    }

    newTabs.insert(insertIndex, combinedTab);

    final newCurrentIndex = insertIndex;

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
        forceUpdate: true,
        selectedTabs: _normalizedSelection(newTabs),
      ),
    );
    _scheduleSave(newTabs, newCurrentIndex);
  }

  Future<void> _onOpenTabInSidePane(
    OpenTabInSidePane event,
    Emitter<TabsState> emit,
  ) async {
    final index = state.currentTabIndex;
    if (index < 0 || index >= state.tabs.length) {
      _disposeTabLater(event.tab);
      return;
    }
    final current = state.tabs[index];
    // פיצול הוא לשתי חלוניות בלבד, ואותו ספר בשני הצדדים יוצר כפילות.
    if (current is CombinedTab ||
        event.tab is CombinedTab ||
        identical(current, event.tab) ||
        _isSameBook(current, event.tab)) {
      if (!identical(current, event.tab)) _disposeTabLater(event.tab);
      return;
    }

    final combinedTab = CombinedTab(
      rightTab: current,
      leftTab: event.tab,
      isPinned: current.isPinned,
    );
    final newTabs = List<OpenedTab>.from(state.tabs)..[index] = combinedTab;

    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: index,
        forceUpdate: true,
        selectedTabs: _normalizedSelection(newTabs),
        // החלונית החדשה היא זו שהמשתמש ביקש לקרוא בה.
        rawActivePane: event.tab,
      ),
    );
    _scheduleSave(newTabs, index);
  }

  Future<void> _onExpandCombinedTab(
    ExpandCombinedTab event,
    Emitter<TabsState> emit,
  ) async {
    if (event.tabIndex >= 0 &&
        event.tabIndex < state.tabs.length &&
        state.tabs[event.tabIndex] is CombinedTab) {
      final combinedTab = state.tabs[event.tabIndex] as CombinedTab;
      final newTabs = List<OpenedTab>.from(state.tabs);
      final combinedIndex = event.tabIndex;

      // החלוניות חוזרות לרשימה בזהותן כדי לשמר את מצב הקריאה.
      final panes = leafPanes(combinedTab);
      // ההצמדה עוברת לשתי החלוניות.
      if (combinedTab.isPinned) {
        for (final pane in panes) {
          pane.isPinned = true;
        }
      }
      newTabs.removeAt(combinedIndex);
      newTabs.insertAll(combinedIndex, panes);

      final activePaneIndex = panes.indexWhere(
        (pane) => identical(pane, state.activePane),
      );
      final newCurrentIndex =
          combinedIndex + (activePaneIndex < 0 ? 0 : activePaneIndex);

      emit(
        state.copyWith(
          tabs: newTabs,
          currentTabIndex: newCurrentIndex,
          forceUpdate: true,
          selectedTabs: _normalizedSelection(newTabs),
        ),
      );
      _scheduleSave(newTabs, newCurrentIndex);
      // אין לשחרר את העוטף, כי החלוניות ממשיכות להיות מוצגות.
    }
  }

  Future<void> _onUpdateSplitRatio(
    UpdateSplitRatio event,
    Emitter<TabsState> emit,
  ) async {
    final current = state.currentTab;
    if (current is! CombinedTab) return;

    current.splitRatio = event.ratio;

    final tabsToSave = state.tabs;
    final indexToSave = state.currentTabIndex;
    emit(state.copyWith(forceUpdate: true));
    _scheduleSave(tabsToSave, indexToSave);
  }

  /// אינדקס הטאב שאירוע חלונית פועל עליו, או `null` אם אינו קיים.
  int? _paneEventTabIndex(int? requested) {
    final index = requested ?? state.currentTabIndex;
    if (index < 0 || index >= state.tabs.length) return null;
    return index;
  }

  Future<void> _onSwapSideBySideTabs(
    SwapSideBySideTabs event,
    Emitter<TabsState> emit,
  ) async {
    final tabIndex = _paneEventTabIndex(event.tabIndex);
    if (tabIndex == null) return;
    final current = state.tabs[tabIndex];
    if (current is! CombinedTab) return;

    // החלפה בזהות שומרת על מצב הקריאה של החלוניות.
    final newTabs = List<OpenedTab>.from(state.tabs);
    newTabs[tabIndex] = current.copyWith(
      rightTab: current.leftTab,
      leftTab: current.rightTab,
      splitRatio: 1.0 - current.splitRatio,
    );

    emit(
      state.copyWith(
        tabs: newTabs,
        forceUpdate: true,
        selectedTabs: _normalizedSelection(newTabs),
      ),
    );
    _scheduleSave(newTabs, state.currentTabIndex);
  }

  void _onSetActivePane(SetActivePane event, Emitter<TabsState> emit) {
    final current = state.currentTab;
    if (current == null) return;
    // החלונית הפעילה חייבת להיות בטאב המוצג.
    if (!leafPanes(current).any((pane) => identical(pane, event.pane))) return;
    if (identical(state.activePane, event.pane)) return;
    emit(state.copyWith(rawActivePane: event.pane));
  }

  Future<void> _onClosePane(ClosePane event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexWhere(
      (tab) => tab is CombinedTab && tab.sibling(event.pane) != null,
    );
    if (index == -1) return;

    final combined = state.tabs[index] as CombinedTab;
    final survivor = combined.sibling(event.pane)!;
    // החלונית השורדת יורשת את ההצמדה.
    if (combined.isPinned) survivor.isPinned = true;

    final newTabs = List<OpenedTab>.from(state.tabs);
    newTabs[index] = survivor;

    emit(
      state.copyWith(
        tabs: newTabs,
        forceUpdate: true,
        selectedTabs: _normalizedSelection(newTabs),
      ),
    );
    _scheduleSave(newTabs, state.currentTabIndex);

    // אין לשחרר את הטאב המפוצל כי האחות ממשיכה להיות מוצגת.
    _disposeTabLater(event.pane);
  }
}
