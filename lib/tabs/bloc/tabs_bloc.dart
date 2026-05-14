import 'dart:async';
import 'dart:math';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  final TabsRepository _repository;

  void _disposeTabLater(OpenedTab tab) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        tab.dispose();
      }),
    );
  }

  TabsBloc({
    required TabsRepository repository,
  })  : _repository = repository,
        super(TabsState.initial()) {
    on<LoadTabs>(_onLoadTabs);
    on<ReplaceAllTabs>(_onReplaceAllTabs, transformer: sequential());
    on<AddTab>(_onAddTab, transformer: sequential());
    on<OpenOrFocusTab>(_onOpenOrFocusTab, transformer: sequential());
    on<RemoveTab>(_onRemoveTab, transformer: sequential());
    on<SetCurrentTab>(_onSetCurrentTab, transformer: sequential());
    on<CloseAllTabs>(_onCloseAllTabs, transformer: sequential());
    on<CloseOtherTabs>(_onCloseOtherTabs, transformer: sequential());
    on<CloneTab>(_onCloneTab);
    on<MoveTab>(_onMoveTab, transformer: sequential());
    on<NavigateToNextTab>(_onNavigateToNextTab, transformer: sequential());
    on<NavigateToPreviousTab>(_onNavigateToPreviousTab,
        transformer: sequential());
    on<CloseCurrentTab>(_onCloseCurrentTab);
    on<SaveTabs>(_onSaveTabs, transformer: sequential());
    on<TogglePinTab>(_onTogglePinTab, transformer: sequential());
    on<EnableSideBySideMode>(_onEnableSideBySideMode,
        transformer: sequential());
    on<DisableSideBySideMode>(_onDisableSideBySideMode,
        transformer: sequential());
    on<UpdateSplitRatio>(_onUpdateSplitRatio, transformer: sequential());
    on<SwapSideBySideTabs>(_onSwapSideBySideTabs, transformer: sequential());
  }

  void _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) {
    final tabs = _repository.loadTabs();
    final savedIndex = _repository.loadCurrentTabIndex();
    final currentTabIndex =
        tabs.isEmpty ? 0 : savedIndex.clamp(0, tabs.length - 1);
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

  Future<void> _onReplaceAllTabs(
      ReplaceAllTabs event, Emitter<TabsState> emit) async {
    debugPrint('DEBUG: החלפת כל הטאבים - ${event.tabs.length} טאבים חדשים');

    final tabsToDispose = List<OpenedTab>.from(state.tabs);

    emit(state.copyWith(
      tabs: event.tabs,
      currentTabIndex: event.currentTabIndex,
      clearSideBySide: true,
    ));
    await _repository.saveTabs(event.tabs, event.currentTabIndex, null);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  Future<void> _onSaveTabs(SaveTabs event, Emitter<TabsState> emit) async {
    await _repository.saveTabs(
        state.tabs, state.currentTabIndex, state.sideBySideMode);
  }

  Future<void> _onAddTab(AddTab event, Emitter<TabsState> emit) async {
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

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
    ));
    await _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
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
      // אם הטאב החדש מבקש הדגשה ממוקדת (deep link), נעביר אותה ל‑bloc של
      // הטאב הקיים — אחרת ה‑highlight החדש היה נזרק עם ה‑dispose.
      _propagatePinpointHighlightToExistingTab(
        existingTab: state.tabs[matchingIndex],
        incomingTab: event.tab,
      );
      event.tab.dispose();
      final tabsToSave = state.tabs;
      final modeToSave = state.sideBySideMode;
      emit(state.copyWith(currentTabIndex: matchingIndex));
      await _repository.saveTabs(tabsToSave, matchingIndex, modeToSave);
      return;
    }

    await _onAddTab(AddTab(event.tab), emit);
  }

  void _propagatePinpointHighlightToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (incomingTab is! TextBookTab) return;
    final pinpoint = incomingTab.pinpointHighlight;
    if (pinpoint == null || pinpoint.isEmpty) return;
    // pinpointHighlightSectionIndex נשמר על הטאב מהקואורדינטור עם הסעיף
    // המקורי שהמשתמש ביקש בקישור; ה‑index של הטאב כבר עלול להשתנות אם
    // הקואורדינטור החיל fallback להיסטוריה (במסלול שאינו pinpoint).
    final sectionIndex =
        incomingTab.pinpointHighlightSectionIndex ?? incomingTab.index;

    final TextBookTab? targetText = _resolveTextBookTab(
      existingTab,
      incomingTab,
    );
    if (targetText == null) return;

    void dispatch() {
      targetText.bloc.add(ApplyPinpointHighlight(
        sectionIndex: sectionIndex,
        text: pinpoint,
      ));
    }

    if (targetText.bloc.state is TextBookLoaded) {
      dispatch();
      return;
    }

    // הטאב הקיים אולי עדיין בטעינה ראשונית — נמתין להגעה ל‑Loaded פעם אחת.
    late StreamSubscription<TextBookState> sub;
    sub = targetText.bloc.stream.listen((state) {
      if (state is TextBookLoaded) {
        dispatch();
        sub.cancel();
      }
    });
  }

  TextBookTab? _resolveTextBookTab(
    OpenedTab existingTab,
    TextBookTab incomingTab,
  ) {
    if (existingTab is TextBookTab) {
      return existingTab;
    }
    // ב‑side‑by‑side צריך להחיל את ה‑pinpoint על הצד שמתאים בזהות חזקה (book id
    // / category id), לא רק כותרת — כדי שלא לעדכן בטעות צד עם ספר שונה
    // ששם הקובץ שלו זהה.
    if (existingTab is CombinedTab) {
      final right = existingTab.rightTab;
      if (right is TextBookTab && _isSameBook(right, incomingTab)) {
        return right;
      }
      final left = existingTab.leftTab;
      if (left is TextBookTab && _isSameBook(left, incomingTab)) {
        return left;
      }
    }
    return null;
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
    if (_hasMatchingDedupeKey(openTab, targetTab)) {
      return true;
    }

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

  Future<String?> _resolveTextTabLocationTitle(TextBookTab tab) async {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    try {
      final ref = await refFromIndex(tab.index, tab.book.tableOfContents);
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
          tab.pageNumber, tab.outline.value, tab.book.title);
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

  Future<void> _onRemoveTab(RemoveTab event, Emitter<TabsState> emit) async {
    final removedTabIndex = state.tabs.indexOf(event.tab);

    final newTabs = List<OpenedTab>.from(state.tabs)..remove(event.tab);

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
      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: 0,
        clearSideBySide: true,
      ));
      await _repository.saveTabs(newTabs, 0, null);
      _disposeTabLater(event.tab);
      return;
    }

    // חישוב האינדקס החדש - אם סגרנו טאב לפני או בדיוק על הטאב הפעיל, זזים אינדקס אחד אחורה
    var newIndex = removedTabIndex <= state.currentTabIndex
        ? max(state.currentTabIndex - 1, 0)
        : state.currentTabIndex;

    // וידוא שהאינדקס תקין (לא חורג מגבולות הרשימה)
    newIndex = min(newIndex, newTabs.length - 1);

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
      clearSideBySide: newSideBySideMode == null,
    ));
    await _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
    _disposeTabLater(event.tab);
  }

  Future<void> _onSetCurrentTab(
      SetCurrentTab event, Emitter<TabsState> emit) async {
    if (event.index >= 0 && event.index < state.tabs.length) {
      // לא מבטלים את מצב side-by-side - פשוט עוברים לטאב
      // הפונקציה _shouldShowSideBySideView תחליט אם להציג side-by-side או TabBarView
      final tabsToSave = state.tabs;
      final modeToSave = state.sideBySideMode;
      emit(state.copyWith(currentTabIndex: event.index));
      await _repository.saveTabs(tabsToSave, event.index, modeToSave);
    }
  }

  void _onCloseCurrentTab(CloseCurrentTab event, Emitter<TabsState> emit) {
    if (state.tabs.isEmpty || state.currentTabIndex >= state.tabs.length) return;
    add(RemoveTab(state.tabs[state.currentTabIndex]));
  }

  Future<void> _onCloseAllTabs(
      CloseAllTabs event, Emitter<TabsState> emit) async {
    // שמירת טאבים מוצמדים בלבד
    final pinnedTabs = state.tabs.where((tab) => tab.isPinned).toList();
    final tabsToDispose = state.tabs.where((tab) => !tab.isPinned).toList();

    // אם יש טאבים מוצמדים, נשאיר אותם
    final newIndex = pinnedTabs.isNotEmpty ? 0 : 0;

    // ביטול מצב side-by-side כי סגרנו טאבים
    emit(state.copyWith(
      tabs: pinnedTabs,
      currentTabIndex: newIndex,
      clearSideBySide: true,
    ));
    await _repository.saveTabs(pinnedTabs, newIndex, null);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  Future<void> _onCloseOtherTabs(
      CloseOtherTabs event, Emitter<TabsState> emit) async {
    final tabsToDispose =
        state.tabs.where((tab) => tab != event.keepTab).toList();

    final newTabs = [event.keepTab];

    // ביטול מצב side-by-side כי נשאר רק טאב אחד
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: 0,
      clearSideBySide: true,
    ));
    await _repository.saveTabs(newTabs, 0, null);

    for (final tab in tabsToDispose) {
      _disposeTabLater(tab);
    }
  }

  void _onCloneTab(CloneTab event, Emitter<TabsState> emit) {
    add(AddTab(OpenedTab.from(event.tab)));
  }

  Future<void> _onMoveTab(MoveTab event, Emitter<TabsState> emit) async {
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

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newIndex,
      sideBySideMode: newSideBySideMode,
    ));
    await _repository.saveTabs(newTabs, newIndex, newSideBySideMode);
  }

  Future<void> _onNavigateToNextTab(
      NavigateToNextTab event, Emitter<TabsState> emit) async {
    if (state.tabs.isEmpty) return;
    final newIndex = (state.currentTabIndex + 1) % state.tabs.length;
    final tabsToSave = state.tabs;
    emit(state.copyWith(currentTabIndex: newIndex));
    await _repository.saveTabs(tabsToSave, newIndex);
  }

  Future<void> _onNavigateToPreviousTab(
      NavigateToPreviousTab event, Emitter<TabsState> emit) async {
    if (state.tabs.isEmpty) return;
    final newIndex = state.currentTabIndex == 0
        ? state.tabs.length - 1
        : state.currentTabIndex - 1;
    final tabsToSave = state.tabs;
    emit(state.copyWith(currentTabIndex: newIndex));
    await _repository.saveTabs(tabsToSave, newIndex);
  }

  Future<void> _onTogglePinTab(
      TogglePinTab event, Emitter<TabsState> emit) async {
    final tabIndex = state.tabs.indexOf(event.tab);
    if (tabIndex == -1) return;

    // החלפת מצב ההצמדה
    event.tab.isPinned = !event.tab.isPinned;

    debugPrint(
        'DEBUG: הצמדת טאב ${event.tab.title} - isPinned: ${event.tab.isPinned}');

    // יצירת רשימה חדשה לחלוטין כדי לגרום ל-Equatable לזהות שינוי
    final newTabs = List<OpenedTab>.from(state.tabs);

    // עדכון ה-state כדי לגרום ל-rebuild - עם forceUpdate
    final indexToSave = state.currentTabIndex;
    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: state.currentTabIndex,
      forceUpdate: true,
    ));
    // שמירת השינויים
    await _repository.saveTabs(newTabs, indexToSave);
  }

  Future<void> _onEnableSideBySideMode(
      EnableSideBySideMode event, Emitter<TabsState> emit) async {
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

    emit(state.copyWith(
      tabs: newTabs,
      currentTabIndex: newCurrentIndex,
      clearSideBySide: true,
      forceUpdate: true,
    ));
    await _repository.saveTabs(newTabs, newCurrentIndex, null);

    _disposeTabLater(event.rightTab);
    _disposeTabLater(event.leftTab);
  }

  Future<void> _onDisableSideBySideMode(
      DisableSideBySideMode event, Emitter<TabsState> emit) async {
    // אם הטאב המבוקש הוא CombinedTab, נפרק אותו לשני טאבים נפרדים
    if (event.tabIndex >= 0 &&
        event.tabIndex < state.tabs.length &&
        state.tabs[event.tabIndex] is CombinedTab) {
      final combinedTab = state.tabs[event.tabIndex] as CombinedTab;
      final newTabs = List<OpenedTab>.from(state.tabs);
      final combinedIndex = event.tabIndex;

      // מסירים את הטאב המשולב
      newTabs.removeAt(combinedIndex);

      // מוסיפים עותקים נפרדים כדי לא לשתף controllers עם ה-combined view
      newTabs.insert(combinedIndex, OpenedTab.from(combinedTab.rightTab));
      newTabs.insert(combinedIndex + 1, OpenedTab.from(combinedTab.leftTab));

      // האינדקס הנוכחי יהיה הטאב הימני
      final newCurrentIndex = combinedIndex;

      emit(state.copyWith(
        tabs: newTabs,
        currentTabIndex: newCurrentIndex,
        clearSideBySide: true,
        forceUpdate: true,
      ));
      await _repository.saveTabs(newTabs, newCurrentIndex, null);

      _disposeTabLater(combinedTab);
    } else {
      // אם זה לא טאב משולב, פשוט מנקים את המצב
      final tabsToSave = state.tabs;
      final indexToSave = state.currentTabIndex;
      emit(state.copyWith(
        clearSideBySide: true,
        forceUpdate: true,
      ));
      await _repository.saveTabs(tabsToSave, indexToSave, null);
    }
  }

  Future<void> _onUpdateSplitRatio(
      UpdateSplitRatio event, Emitter<TabsState> emit) async {
    // עדכון היחס של הטאב המשולב
    if (state.currentTab is CombinedTab) {
      final combinedTab = state.currentTab as CombinedTab;
      combinedTab.splitRatio = event.ratio;

      // שמירת השינוי
      final tabsToSave = state.tabs;
      final indexToSave = state.currentTabIndex;
      emit(state.copyWith(
        forceUpdate: true,
      ));
      await _repository.saveTabs(tabsToSave, indexToSave, null);
    }
  }

  Future<void> _onSwapSideBySideTabs(
      SwapSideBySideTabs event, Emitter<TabsState> emit) async {
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

      final indexToSave = state.currentTabIndex;
      emit(state.copyWith(
        tabs: newTabs,
        forceUpdate: true,
      ));
      await _repository.saveTabs(newTabs, indexToSave, null);

      _disposeTabLater(combinedTab);
    }
  }
}
