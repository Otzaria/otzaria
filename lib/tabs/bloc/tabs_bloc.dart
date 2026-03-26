import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/ref_helper.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository _repository;
  int _pdfWorkerStopRequestId = 0;
  bool _isStoppingPdfWorker = false;

  void _disposeTabLater(OpenedTab tab) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        tab.dispose();
      }),
    );
  }

  bool _containsPdfTab(OpenedTab tab) {
    if (tab is PdfBookTab) {
      return true;
    }
    if (tab is CombinedTab) {
      return _containsPdfTab(tab.rightTab) || _containsPdfTab(tab.leftTab);
    }
    return false;
  }

  bool _hasAnyPdfTabs(List<OpenedTab> tabs) {
    return tabs.any(_containsPdfTab);
  }

  void _maybeStopPdfWorker({
    required List<OpenedTab> previousTabs,
    required List<OpenedTab> nextTabs,
  }) {
    final hadPdfTabs = _hasAnyPdfTabs(previousTabs);
    final hasPdfTabsNow = _hasAnyPdfTabs(nextTabs);

    if (hadPdfTabs && !hasPdfTabsNow) {
      _requestStopPdfWorker();
    }
  }

  void _requestStopPdfWorker() {
    _pdfWorkerStopRequestId++;
    final requestId = _pdfWorkerStopRequestId;
    unawaited(_stopPdfWorkerIfStillUnused(requestId));
  }

  Future<void> _stopPdfWorkerIfStillUnused(int requestId) async {
    // Give widgets time to dispose their PdfViewer resources after tab removal.
    await Future<void>.delayed(const Duration(milliseconds: 350));

    if (requestId != _pdfWorkerStopRequestId) {
      return;
    }
    if (_hasAnyPdfTabs(state.tabs)) {
      return;
    }
    if (_isStoppingPdfWorker) {
      return;
    }

    _isStoppingPdfWorker = true;
    try {
      await PdfrxEntryFunctions.instance.stopBackgroundWorker();
      debugPrint('DEBUG: Pdfrx background worker stopped (no PDF tabs left)');
    } catch (e) {
      debugPrint('DEBUG: Failed to stop Pdfrx background worker: $e');
    } finally {
      _isStoppingPdfWorker = false;
    }
  }

  TabsBloc({
    required TabsRepository repository,
  })  : _repository = repository,
        super(TabsState.initial()) {
    on<LoadTabs>(_onLoadTabs);
    on<ReplaceAllTabs>(_onReplaceAllTabs);
    on<AddTab>(_onAddTab);
    on<OpenOrFocusTab>(_onOpenOrFocusTab);
    on<RemoveTab>(_onRemoveTab);
    on<SetCurrentTab>(_onSetCurrentTab);
    on<CloseAllTabs>(_onCloseAllTabs);
    on<CloseOtherTabs>(_onCloseOtherTabs);
    on<CloneTab>(_onCloneTab);
    on<MoveTab>(_onMoveTab);
    on<NavigateToNextTab>(_onNavigateToNextTab);
    on<NavigateToPreviousTab>(_onNavigateToPreviousTab);
    on<CloseCurrentTab>(_onCloseCurrentTab);
    on<SaveTabs>(_onSaveTabs);
    on<TogglePinTab>(_onTogglePinTab);
    on<EnableSideBySideMode>(_onEnableSideBySideMode);
    on<DisableSideBySideMode>(_onDisableSideBySideMode);
    on<UpdateSplitRatio>(_onUpdateSplitRatio);
    on<SwapSideBySideTabs>(_onSwapSideBySideTabs);
  }

  void _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) {
    final tabs = _repository.loadTabs();
    final currentTabIndex = _repository.loadCurrentTabIndex();
    final sideBySideMode = _repository.loadSideBySideMode();

    // וידוא שהאינדקסים של side-by-side תקינים
    SideBySideMode? validatedMode;
    if (sideBySideMode != null && tabs.isNotEmpty) {
      if (sideBySideMode.leftTabIndex < tabs.length &&
          sideBySideMode.rightTabIndex < tabs.length &&
          sideBySideMode.leftTabIndex != sideBySideMode.rightTabIndex) {
        validatedMode = sideBySideMode;
      } else {
        debugPrint('DEBUG: מצב side-by-side לא תקין, מתעלם');
      }
    }

    emit(state.copyWith(
      tabs: tabs,
      currentTabIndex: currentTabIndex,
      sideBySideMode: validatedMode,
    ));
  }

  void _onReplaceAllTabs(ReplaceAllTabs event, Emitter<TabsState> emit) {
    debugPrint('DEBUG: החלפת כל הטאבים - ${event.tabs.length} טאבים חדשים');

    final previousTabs = List<OpenedTab>.from(state.tabs);

    // ניקוי משאבים של כל הטאבים הקיימים
    for (final tab in state.tabs) {
      tab.dispose();
    }

    _maybeStopPdfWorker(previousTabs: previousTabs, nextTabs: event.tabs);

    _repository.saveTabs(event.tabs, event.currentTabIndex, null);

    emit(state.copyWith(
      tabs: event.tabs,
      currentTabIndex: event.currentTabIndex,
      clearSideBySide: true,
    ));
  }

  void _onSaveTabs(SaveTabs event, Emitter<TabsState> emit) {
    _repository.saveTabs(
        state.tabs, state.currentTabIndex, state.sideBySideMode);
  }

  void _onAddTab(AddTab event, Emitter<TabsState> emit) {
    debugPrint('DEBUG: הוספת טאב חדש - ${event.tab.title}');
    final newTabs = List<OpenedTab>.from(state.tabs);
    final newIndex = min(state.currentTabIndex + 1, newTabs.length);
    newTabs.insert(newIndex, event.tab);

    // עדכון אינדקסים במצב side-by-side אם קיים
    SideBySideMode? newSideBySideMode = state.sideBySideMode;
    if (state.sideBySideMode != null) {
      var newLeftIndex = state.sideBySideMode!.leftTabIndex;
      var newRightIndex = state.sideBySideMode!.rightTabIndex;

      // אם הטאב החדש נוסף לפני אחד מהטאבים במצב side-by-side, מעדכנים את האינדקס
      if (newIndex <= newLeftIndex) newLeftIndex++;
      if (newIndex <= newRightIndex) newRightIndex++;

      newSideBySideMode = state.sideBySideMode!.copyWith(
        leftTabIndex: newLeftIndex,
        rightTabIndex: newRightIndex,
      );

      debugPrint(
          'DEBUG: עדכון אינדקסים במצב side-by-side: left=$newLeftIndex, right=$newRightIndex');
    }

    _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
    ));
  }

  Future<void> _onOpenOrFocusTab(
      OpenOrFocusTab event, Emitter<TabsState> emit) async {
    final targetTitle = await _resolveTabLocationTitle(event.tab,
        explicitTitle: event.targetTitle);
    final matchingIndex = await _findMatchingTopLevelTabIndex(
      event.tab,
      targetTitle,
    );

    if (matchingIndex != null) {
      event.tab.dispose();
      _repository.saveTabs(state.tabs, matchingIndex, state.sideBySideMode);
      emit(state.copyWith(currentTabIndex: matchingIndex));
      return;
    }

    _onAddTab(AddTab(event.tab), emit);
  }

  Future<int?> _findMatchingTopLevelTabIndex(
    OpenedTab targetTab,
    String? normalizedTargetTitle,
  ) async {
    for (var index = 0; index < state.tabs.length; index++) {
      final openTab = state.tabs[index];
      if (await _topLevelTabMatches(
          openTab, targetTab, normalizedTargetTitle)) {
        return index;
      }
    }
    return null;
  }

  Future<bool> _topLevelTabMatches(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle,
  ) async {
    if (await _singleTabMatches(openTab, targetTab, normalizedTargetTitle)) {
      return true;
    }

    if (openTab is CombinedTab) {
      return await _singleTabMatches(
            openTab.rightTab,
            targetTab,
            normalizedTargetTitle,
          ) ||
          await _singleTabMatches(
            openTab.leftTab,
            targetTab,
            normalizedTargetTitle,
          );
    }

    return false;
  }

  Future<bool> _singleTabMatches(
    OpenedTab openTab,
    OpenedTab targetTab,
    String? normalizedTargetTitle,
  ) async {
    if (!_isSameBook(openTab, targetTab)) {
      return false;
    }

    final normalizedOpenTitle = await _resolveTabLocationTitle(openTab);
    return _titlesMatch(
      normalizedOpenTitle: normalizedOpenTitle,
      normalizedTargetTitle: normalizedTargetTitle,
      openTab: openTab,
      targetTab: targetTab,
    );
  }

  bool _isSameBook(OpenedTab openTab, OpenedTab targetTab) {
    if (openTab is TextBookTab && targetTab is TextBookTab) {
      return _textBookIdentity(openTab) == _textBookIdentity(targetTab);
    }

    if (openTab is PdfBookTab && targetTab is PdfBookTab) {
      return openTab.book.path == targetTab.book.path;
    }

    return false;
  }

  String _textBookIdentity(TextBookTab tab) {
    final categoryId = tab.book.categoryId;
    if (categoryId != null) {
      return 'category:$categoryId';
    }

    final filePath = tab.book.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      return 'file:$filePath';
    }

    return 'title:${tab.book.title}';
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

  Future<String?> _resolveTextTabLocationTitle(TextBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromIndex(tab.index, tab.book.tableOfContents);
      return ref.trim().isEmpty ? null : ref;
    } catch (_) {
      return 'index:${tab.index}';
    }
  }

  Future<String?> _resolvePdfTabLocationTitle(PdfBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromPageNumber(
          tab.pageNumber, tab.outline.value, tab.book.title);
      if (ref.trim().isNotEmpty) {
        return ref;
      }
    } catch (_) {
      // Fall back to page-based comparison when outline is unavailable.
    }

    return 'page:${tab.pageNumber}';
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

  void _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final previousTabs = List<OpenedTab>.from(state.tabs);
    final removedTabIndex = state.tabs.indexOf(event.tab);

    // ניקוי משאבים של הטאב שנסגר
    event.tab.dispose();

    final newTabs = List<OpenedTab>.from(state.tabs)..remove(event.tab);

    _maybeStopPdfWorker(previousTabs: previousTabs, nextTabs: newTabs);

    // בדיקה אם הטאב שנסגר היה חלק ממצב side-by-side
    SideBySideMode? newSideBySideMode = state.sideBySideMode;
    if (state.sideBySideMode != null) {
      if (removedTabIndex == state.sideBySideMode!.leftTabIndex ||
          removedTabIndex == state.sideBySideMode!.rightTabIndex) {
        // אם סגרנו אחד מהטאבים במצב side-by-side, מבטלים את המצב
        debugPrint('DEBUG: ביטול מצב side-by-side כי נסגר טאב שהיה חלק ממנו');
        newSideBySideMode = null;
      } else {
        // עדכון האינדקסים אם הם השתנו
        var newLeftIndex = state.sideBySideMode!.leftTabIndex;
        var newRightIndex = state.sideBySideMode!.rightTabIndex;

        if (removedTabIndex < newLeftIndex) newLeftIndex--;
        if (removedTabIndex < newRightIndex) newRightIndex--;

        newSideBySideMode = state.sideBySideMode!.copyWith(
          leftTabIndex: newLeftIndex,
          rightTabIndex: newRightIndex,
        );
      }
    }

    // אם אין טאבים נותרים, נשאיר את האינדקס ב-0
    if (newTabs.isEmpty) {
      _repository.saveTabs(newTabs, 0, null);
      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: 0,
        clearSideBySide: true,
      ));
      return;
    }

    // חישוב האינדקס החדש - אם סגרנו טאב לפני או בדיוק על הטאב הפעיל, זזים אינדקס אחד אחורה
    var newIndex = removedTabIndex <= state.currentTabIndex
        ? max(state.currentTabIndex - 1, 0)
        : state.currentTabIndex;

    // וידוא שהאינדקס תקין (לא חורג מגבולות הרשימה)
    newIndex = min(newIndex, newTabs.length - 1);

    _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
      clearSideBySide: newSideBySideMode == null,
    ));
  }

  void _onSetCurrentTab(SetCurrentTab event, Emitter<TabsState> emit) {
    if (event.index >= 0 && event.index < state.tabs.length) {
      // לא מבטלים את מצב side-by-side - פשוט עוברים לטאב
      // הפונקציה _shouldShowSideBySideView תחליט אם להציג side-by-side או TabBarView
      _repository.saveTabs(state.tabs, event.index, state.sideBySideMode);
      emit(state.copyWith(currentTabIndex: event.index));
    }
  }

  void _onCloseCurrentTab(CloseCurrentTab event, Emitter<TabsState> emit) {
    add(RemoveTab(state.tabs[state.currentTabIndex]));
  }

  void _onCloseAllTabs(CloseAllTabs event, Emitter<TabsState> emit) {
    final previousTabs = List<OpenedTab>.from(state.tabs);

    // שמירת טאבים מוצמדים בלבד
    final pinnedTabs = state.tabs.where((tab) => tab.isPinned).toList();

    // ניקוי משאבים של כל הטאבים שאינם מוצמדים
    for (final tab in state.tabs) {
      if (!tab.isPinned) {
        tab.dispose();
      }
    }

    // אם יש טאבים מוצמדים, נשאיר אותם
    final newIndex = pinnedTabs.isNotEmpty ? 0 : 0;

    _maybeStopPdfWorker(previousTabs: previousTabs, nextTabs: pinnedTabs);

    // ביטול מצב side-by-side כי סגרנו טאבים
    _repository.saveTabs(pinnedTabs, newIndex, null);
    emit(state.copyWith(
      tabs: pinnedTabs,
      currentTabIndex: newIndex,
      clearSideBySide: true,
    ));
  }

  void _onCloseOtherTabs(CloseOtherTabs event, Emitter<TabsState> emit) {
    final previousTabs = List<OpenedTab>.from(state.tabs);

    // ניקוי משאבים של כל הטאבים מלבד זה שנשאר
    for (final tab in state.tabs) {
      if (tab != event.keepTab) {
        tab.dispose();
      }
    }

    final newTabs = [event.keepTab];

    _maybeStopPdfWorker(previousTabs: previousTabs, nextTabs: newTabs);

    // ביטול מצב side-by-side כי נשאר רק טאב אחד
    _repository.saveTabs(newTabs, 0, null);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: 0,
      clearSideBySide: true,
    ));
  }

  void _onCloneTab(CloneTab event, Emitter<TabsState> emit) {
    add(AddTab(OpenedTab.from(event.tab)));
  }

  void _onMoveTab(MoveTab event, Emitter<TabsState> emit) {
    final newTabs = List<OpenedTab>.from(state.tabs);
    final currentTab = newTabs[state.currentTabIndex];
    final oldIndex = newTabs.indexOf(event.tab);
    newTabs.remove(event.tab);
    newTabs.insert(event.newIndex, event.tab);
    final newIndex = newTabs.indexOf(currentTab);

    // עדכון אינדקסים במצב side-by-side אם קיים
    SideBySideMode? newSideBySideMode = state.sideBySideMode;
    if (state.sideBySideMode != null) {
      var newLeftIndex = state.sideBySideMode!.leftTabIndex;
      var newRightIndex = state.sideBySideMode!.rightTabIndex;

      // עדכון האינדקסים לפי התזוזה
      if (oldIndex == newLeftIndex) {
        newLeftIndex = event.newIndex;
      } else if (oldIndex < newLeftIndex && event.newIndex >= newLeftIndex) {
        newLeftIndex--;
      } else if (oldIndex > newLeftIndex && event.newIndex <= newLeftIndex) {
        newLeftIndex++;
      }

      if (oldIndex == newRightIndex) {
        newRightIndex = event.newIndex;
      } else if (oldIndex < newRightIndex && event.newIndex >= newRightIndex) {
        newRightIndex--;
      } else if (oldIndex > newRightIndex && event.newIndex <= newRightIndex) {
        newRightIndex++;
      }

      newSideBySideMode = state.sideBySideMode!.copyWith(
        leftTabIndex: newLeftIndex,
        rightTabIndex: newRightIndex,
      );
    }

    _repository.saveTabs(newTabs, state.currentTabIndex, newSideBySideMode);
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
    ));
  }

  void _onNavigateToNextTab(NavigateToNextTab event, Emitter<TabsState> emit) {
    if (state.tabs.isEmpty) return;
    final newIndex = (state.currentTabIndex + 1) % state.tabs.length;
    _repository.saveTabs(state.tabs, newIndex);
    emit(state.copyWith(currentTabIndex: newIndex));
  }

  void _onNavigateToPreviousTab(
      NavigateToPreviousTab event, Emitter<TabsState> emit) {
    if (state.tabs.isEmpty) return;
    final newIndex = state.currentTabIndex == 0
        ? state.tabs.length - 1
        : state.currentTabIndex - 1;
    _repository.saveTabs(state.tabs, newIndex);
    emit(state.copyWith(currentTabIndex: newIndex));
  }

  void _onTogglePinTab(TogglePinTab event, Emitter<TabsState> emit) {
    final tabIndex = state.tabs.indexOf(event.tab);
    if (tabIndex == -1) return;

    // החלפת מצב ההצמדה
    event.tab.isPinned = !event.tab.isPinned;

    debugPrint(
        'DEBUG: הצמדת טאב ${event.tab.title} - isPinned: ${event.tab.isPinned}');

    // יצירת רשימה חדשה לחלוטין כדי לגרום ל-Equatable לזהות שינוי
    final newTabs = List<OpenedTab>.from(state.tabs);

    // שמירת השינויים
    _repository.saveTabs(newTabs, state.currentTabIndex);

    // עדכון ה-state כדי לגרום ל-rebuild - עם forceUpdate
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: state.currentTabIndex,
      forceUpdate: true,
    ));
  }

  void _onEnableSideBySideMode(
      EnableSideBySideMode event, Emitter<TabsState> emit) {
    final rightIndex = state.tabs.indexOf(event.rightTab);
    final leftIndex = state.tabs.indexOf(event.leftTab);

    if (rightIndex == -1 || leftIndex == -1) {
      debugPrint('ERROR: לא נמצאו הטאבים למצב side-by-side');
      return;
    }

    debugPrint(
        'DEBUG: הפעלת מצב side-by-side: right=${event.rightTab.title}, left=${event.leftTab.title}');

    // יצירת עותקים נפרדים כדי לא לשתף controllers עם הטאבים שעדיין מפורקים מהעץ.
    final combinedTab = CombinedTab(
      rightTab: OpenedTab.from(event.rightTab),
      leftTab: OpenedTab.from(event.leftTab),
      isPinned: event.rightTab.isPinned || event.leftTab.isPinned,
    );

    // הסרת שני הטאבים המקוריים והוספת הטאב המשולב במקומם
    final newTabs = List<OpenedTab>.from(state.tabs);

    // מוצאים את האינדקס הנמוך יותר כדי להכניס שם את הטאב המשולב
    final insertIndex = rightIndex < leftIndex ? rightIndex : leftIndex;

    // מסירים את שני הטאבים (מהגבוה לנמוך כדי לא לשבש אינדקסים)
    if (rightIndex > leftIndex) {
      newTabs.removeAt(rightIndex);
      newTabs.removeAt(leftIndex);
    } else {
      newTabs.removeAt(leftIndex);
      newTabs.removeAt(rightIndex);
    }

    // מוסיפים את הטאב המשולב
    newTabs.insert(insertIndex, combinedTab);

    // האינדקס הנוכחי יהיה האינדקס של הטאב המשולב
    final newCurrentIndex = insertIndex;

    _repository.saveTabs(newTabs, newCurrentIndex, null);

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newCurrentIndex,
      clearSideBySide: true,
      forceUpdate: true,
    ));

    _disposeTabLater(event.rightTab);
    _disposeTabLater(event.leftTab);
  }

  void _onDisableSideBySideMode(
      DisableSideBySideMode event, Emitter<TabsState> emit) {
    // אם הטאב הנוכחי הוא CombinedTab, נפרק אותו לשני טאבים נפרדים
    if (state.currentTab is CombinedTab) {
      final combinedTab = state.currentTab as CombinedTab;
      final newTabs = List<OpenedTab>.from(state.tabs);
      final combinedIndex = state.currentTabIndex;

      // מסירים את הטאב המשולב
      newTabs.removeAt(combinedIndex);

      // מוסיפים עותקים נפרדים כדי לא לשתף controllers עם ה-combined view
      newTabs.insert(combinedIndex, OpenedTab.from(combinedTab.rightTab));
      newTabs.insert(combinedIndex + 1, OpenedTab.from(combinedTab.leftTab));

      // האינדקס הנוכחי יהיה הטאב הימני
      final newCurrentIndex = combinedIndex;

      _repository.saveTabs(newTabs, newCurrentIndex, null);

      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
        clearSideBySide: true,
        forceUpdate: true,
      ));

      _disposeTabLater(combinedTab);
    } else {
      // אם זה לא טאב משולב, פשוט מנקים את המצב
      _repository.saveTabs(state.tabs, state.currentTabIndex, null);

      emit(state.copyWith(
        clearSideBySide: true,
        forceUpdate: true,
      ));
    }
  }

  void _onUpdateSplitRatio(UpdateSplitRatio event, Emitter<TabsState> emit) {
    // עדכון היחס של הטאב המשולב
    if (state.currentTab is CombinedTab) {
      final combinedTab = state.currentTab as CombinedTab;
      combinedTab.splitRatio = event.ratio;

      // שמירת השינוי
      _repository.saveTabs(state.tabs, state.currentTabIndex, null);

      emit(state.copyWith(
        forceUpdate: true,
      ));
    }
  }

  void _onSwapSideBySideTabs(
      SwapSideBySideTabs event, Emitter<TabsState> emit) {
    // החלפת צדדים בטאב המשולב
    if (state.currentTab is CombinedTab) {
      final combinedTab = state.currentTab as CombinedTab;

      debugPrint('DEBUG: החלפת צדדים במצב side-by-side');

      // יצירת טאב משולב חדש עם עותקים נפרדים של הטאבים המוחלפים.
      final newCombinedTab = CombinedTab(
        rightTab: OpenedTab.from(combinedTab.leftTab),
        leftTab: OpenedTab.from(combinedTab.rightTab),
        splitRatio: 1.0 - combinedTab.splitRatio,
        isPinned: combinedTab.isPinned,
      );

      // עדכון הרשימה
      final newTabs = List<OpenedTab>.from(state.tabs);
      newTabs[state.currentTabIndex] = newCombinedTab;

      // ניקוי הטאב הישן
      combinedTab.dispose();

      _repository.saveTabs(newTabs, state.currentTabIndex, null);

      emit(state.copyWith(
        tabs: newTabs,
        forceUpdate: true,
      ));

      _disposeTabLater(combinedTab);
    }
  }
}
