import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/companion/companion_books.dart';
import 'package:otzaria/search/models/search_configuration.dart'
    show SearchMode;
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart'
    show kSearchResultAnchorAlignment;
import 'package:otzaria/text_book/utils/section_search_utils.dart'
    show matchFractionInLine;
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
  final Duration _disposeDelay;
  Future<void>? _closeFuture;
  int _pendingEvents = 0;

  /// Wraps a newly opened tab with its companion pane, when it has one.
  final Future<OpenedTab> Function(OpenedTab tab) _withCompanion;
  final List<_ClosedTabEntry> _recentlyClosedTabs = <_ClosedTabEntry>[];

  /// הכרטיסיות שנסגרו לאחרונה, מהאחרונה שנסגרה ואילך. הרשימה אינה חלק
  /// מה-state, ולכן קוראים אותה בתוך `BlocBuilder` על שינוי הכרטיסיות.
  List<OpenedTab> get recentlyClosedTabs => List<OpenedTab>.unmodifiable(
    _recentlyClosedTabs.reversed.map((entry) => entry.tab),
  );

  /// האם יש כרטיסיה לשחזור.
  ///
  /// ⚠️ נדרש כדי ש-Ctrl+Shift+T יידע מתי ליפול לשחזור **חלון** שנסגר,
  /// כמו בדפדפן. בלי הבדיקה הקיצור היה בולע את המקרה ולא עושה כלום.
  bool get hasRecentlyClosedTabs => _recentlyClosedTabs.isNotEmpty;

  List<OpenedTab>? _pendingSaveTabs;
  int _pendingSaveIndex = 0;
  Future<void>? _saveDrain;
  final _pendingOpenTabs = Queue<Completer<void>>();
  final _pendingAddTabs = Queue<Completer<void>>();
  final _pendingRemovals = Queue<Future<void>?>();

  /// סשן החלון ודור העץ; עץ חדש או ייבוא מונעים מהישן לשמור.
  final WindowTabsSession _session;
  final int _sessionGeneration;

  bool get _sessionReplaced => _session.generation != _sessionGeneration;

  /// משדר את [newTabs] עם בחירה מנורמלת ושומר אותם; [currentTabIndex] null
  /// משאיר את הטאב הנוכחי.
  void _emitAndSaveTabs(
    Emitter<TabsState> emit,
    List<OpenedTab> newTabs, {
    int? currentTabIndex,
    ActivePaneUpdate activePane = const ActivePaneUpdate.unchanged(),
  }) {
    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: currentTabIndex,
        selectedTabs: _normalizedSelection(newTabs),
        activePane: activePane,
      ),
    );
    _scheduleSave(newTabs, currentTabIndex ?? state.currentTabIndex);
  }

  /// מבקש שמירה של הטאבים, בלי להמתין לה. כל שמירה מקודדת את *כל* הטאבים,
  /// ולכן בקשות שמגיעות בזמן שכתיבה רצה מתמזגות לכתיבה אחת שאחריה.
  void _scheduleSave(List<OpenedTab> tabs, int currentTabIndex) {
    if (_sessionReplaced) return;
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
      while (_pendingSaveTabs != null && !_sessionReplaced) {
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
        if (!_sessionReplaced &&
            _pendingSaveTabs == null &&
            _pendingSaveIndex != index) {
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
    if (_sessionReplaced) return Future<void>.value();
    _pendingSaveIndex = index;
    return _repository.saveCurrentTabIndex(tabs, index);
  }

  /// שומר את מצב הטאבים הנוכחי וממתין לכתיבה, לפני סגירת התוכנה. בלי
  /// [_scheduleSave] אין מה לנקז: קריאה בתוך טאב אינה מפעילה SaveTabs.
  Future<void> _flushPendingSaves() async {
    if (_sessionReplaced) return;
    _scheduleSave(state.tabs, state.currentTabIndex);
    await _saveDrain?.timeout(const Duration(seconds: 5), onTimeout: () {});
    // האינדקס הפעיל נשמר בהשהיה, וטיימר ממתין לא היה מספיק לסגירה.
    await _repository.flushPendingWrites();
  }

  /// מעביר בעלות משותפת על [pane] לכרטיסיות המפרשים ששורדות.
  bool _transferSourceTabOwnership(OpenedTab pane) {
    final ownership = SourceTabOwnership(pane);
    var transferred = false;
    for (final survivor in state.tabs) {
      for (final surviving in leafPanes(survivor)) {
        if (surviving is CommentatorsTab &&
            identical(surviving.sourceTab, pane)) {
          surviving.assumeSourceTabOwnership(ownership);
          transferred = true;
        }
        if (surviving is PdfCommentatorsTab &&
            identical(surviving.sourceTab, pane)) {
          surviving.assumeSourceTabOwnership(ownership);
          transferred = true;
        }
      }
    }
    return transferred;
  }

  void _disposeTabLater(OpenedTab tab) {
    // חלונית שמפרשים ששרדו מחזיקים בה אינה משוחררת; אחיותיה כן.
    final inherited = leafPanes(tab).where(_transferSourceTabOwnership).toSet();
    if (inherited.isEmpty) {
      unawaited(
        Future<void>.delayed(_disposeDelay, () {
          tab.dispose();
        }),
      );
      return;
    }
    for (final pane in leafPanes(tab)) {
      if (inherited.contains(pane)) continue;
      unawaited(
        Future<void>.delayed(_disposeDelay, () {
          pane.dispose();
        }),
      );
    }
  }

  /// העץ פורק והסשן נשטף: אין עוד UI שצריך להמתין לניתוקו.
  void _releaseTabs() {
    for (final tab in state.tabs) {
      tab.dispose();
    }
    for (final entry in _recentlyClosedTabs) {
      entry.tab.dispose();
    }
    _recentlyClosedTabs.clear();
  }

  /// [disposeDelay] - השהיית השחרור של טאב שיצא מהרשימה; טסטים מעבירים אפס.
  /// [session] - סשן החלון שהדור שלו נבדק; חייב להיות זה של המאגר.
  TabsBloc({
    required this._repository,
    this._disposeDelay = const Duration(milliseconds: 350),
    this._withCompanion = withCompanionPane,
    WindowTabsSession? session,
  }) : _session = session ?? WindowTabsSession.current,
       _sessionGeneration = (session ?? WindowTabsSession.current)
           .beginRuntime(),
       super(TabsState.initial()) {
    on<LoadTabs>(_onLoadTabs, transformer: sequential());
    on<RemapBookPaths>(_onRemapBookPaths, transformer: sequential());
    on<ReplaceAllTabs>(_onReplaceAllTabs, transformer: sequential());
    on<AddTab>((event, emit) async {
      try {
        await _onAddTab(event, emit);
      } finally {
        _pendingAddTabs.removeFirst().complete();
      }
    }, transformer: sequential());
    on<OpenOrFocusTab>(
      (event, emit) async {
        try {
          await _onOpenOrFocusTab(event, emit);
        } finally {
          _pendingOpenTabs.removeFirst().complete();
        }
      },
      transformer: sequential(),
    );
    on<ReplaceTab>(_onReplaceTab, transformer: sequential());
    on<RemoveTab>(_onRemoveTab, transformer: sequential());
    on<RemoveTabs>(_onRemoveTabs, transformer: sequential());
    on<ToggleTabSelection>(_onToggleTabSelection, transformer: sequential());
    on<SelectTabRange>(_onSelectTabRange, transformer: sequential());
    on<ClearTabSelection>(_onClearTabSelection, transformer: sequential());
    on<SetCurrentTab>(_onSetCurrentTab, transformer: sequential());
    on<CloseAllTabs>(_onCloseAllTabs, transformer: sequential());
    on<AdoptTab>(_onAdoptTab, transformer: sequential());
    on<CloseOtherTabs>(_onCloseOtherTabs, transformer: sequential());
    on<CloneTab>(_onCloneTab, transformer: sequential());
    on<MoveTab>(_onMoveTab, transformer: sequential());
    on<NavigateToNextTab>(_onNavigateToNextTab, transformer: sequential());
    on<NavigateToPreviousTab>(
      _onNavigateToPreviousTab,
      transformer: sequential(),
    );
    on<CloseCurrentTab>(_onCloseCurrentTab, transformer: sequential());
    on<RestoreLastClosedTab>(
      _onRestoreLastClosedTab,
      transformer: sequential(),
    );
    on<RestoreClosedTab>(_onRestoreClosedTab, transformer: sequential());
    on<ClearRecentlyClosedTabs>(
      _onClearRecentlyClosedTabs,
      transformer: sequential(),
    );
    on<SaveTabs>(_onSaveTabs, transformer: sequential());
    on<TogglePinTab>(_onTogglePinTab, transformer: sequential());
    on<RenameTab>(_onRenameTab, transformer: sequential());
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
    on<DetachPane>(_onDetachPane, transformer: sequential());
    on<SetActivePane>(_onSetActivePane, transformer: sequential());

    _preCloseCallback = _flushPendingSaves;
    PreCloseRegistry.register(_preCloseCallback);
  }

  @override
  void onEvent(TabsEvent event) {
    super.onEvent(event);
    _pendingEvents++;
    // הרישום נעשה בשליחה: גם פתיחה שממתינה בתור חייבת להקדים את הסגירה.
    if (event is OpenOrFocusTab) _pendingOpenTabs.add(Completer<void>());
    if (event is AddTab) _pendingAddTabs.add(Completer<void>());

    if (event is RemoveTab) {
      _pendingRemovals.add(
        _pendingOpenTabs.isEmpty ? null : _pendingOpenTabs.last.future,
      );
    }
  }

  @override
  void onDone(TabsEvent event, [Object? error, StackTrace? stackTrace]) {
    _pendingEvents--;
    super.onDone(event, error, stackTrace);
  }

  late final Future<void> Function() _preCloseCallback;

  @override
  Future<void> close() => _closeFuture ??= Future<void>.sync(() async {
    PreCloseRegistry.unregister(_preCloseCallback);
    try {
      do {
        await Future.wait([
          for (final pending in _pendingOpenTabs) pending.future,
          for (final pending in _pendingAddTabs) pending.future,
        ]);
      } while (_pendingOpenTabs.isNotEmpty || _pendingAddTabs.isNotEmpty);
      await _flushPendingSaves();
    } finally {
      final closing = super.close();
      _releaseTabs();
      await closing;
    }
  });

  void _onLoadTabs(LoadTabs event, Emitter<TabsState> emit) {
    // הטאבים והאינדקס מנורמלים יחד כדי לשמור על הטאב הפעיל.
    final restored = flattenRestoredSplits(
      _repository.loadTabs(newRuntime: true),
      currentIndex: _repository.loadCurrentTabIndex(),
    );
    final tabs = restored.tabs;
    _separateHistorySlots(tabs, existingTabs: const []);

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

    // החלונית הפעילה מגיעה כצד ולא כאובייקט: הטאבים שוכפלו בדרך לכאן,
    // וזהות האובייקט של החלונית הישנה חסרת משמעות ברשימה החדשה.
    final restoredPane =
        event.currentTabIndex >= 0 && event.currentTabIndex < event.tabs.length
        ? paneForSide(event.tabs[event.currentTabIndex], event.activePane)
        : null;

    emit(
      state.copyWith(
        tabs: event.tabs,
        currentTabIndex: event.currentTabIndex,
        // ריק→ריק הוא state שווה ש-Bloc אינו פולט; בלי זה הממתין ב-main.dart נתקע.
        forceUpdate: true,
        selectedTabs: const <OpenedTab>[],
        // clear ולא unchanged: הרשימה הישנה מפונה, וחלונית פעילה ששייכת
        // לטאב שנסגר אינה יכולה להישאר.
        activePane: restoredPane == null
            ? const ActivePaneUpdate.clear()
            : ActivePaneUpdate.set(restoredPane),
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
    final tab = await _withCompanion(event.tab);
    if (!_insertTab(event, tab, emit.call)) _disposeTabLater(tab);
  }

  /// קליטה אטומית של כרטיסיה שכבר נפתחה; לא פותחים מחדש חלונית מלווה שנסגרה.
  bool receiveTransferredTab(OpenedTab tab, {int? index}) {
    if (isClosed || _closeFuture != null || _pendingEvents > 0) return false;
    // האישור למקור חייב לבוא אחרי ההכנסה, ללא תור שיכול לשרוד את החלון.
    // ignore: invalid_use_of_visible_for_testing_member
    return _insertTab(AddTab(tab, index: index), tab, super.emit);
  }

  /// מגביל תוספת מופעים; טעינת snapshot שלם משמרת את כל מצב המשתמש.
  bool _hasRoomForPluginTabs(
    List<OpenedTab> incoming,
    Iterable<OpenedTab> existing,
  ) {
    final plugins = incoming
        .expand(leafPanes)
        .whereType<ToolTab>()
        .where((tab) => tab.isPlugin);
    for (final plugin in plugins) {
      if (openToolInstanceCount([...existing, ...incoming], plugin.toolId) >
          kMaxPluginToolInstances) {
        UiSnack.showError(
          ToolsMessages.pluginInstanceLimitReached(
            plugin.title,
            kMaxPluginToolInstances,
          ),
        );
        return false;
      }
    }
    return true;
  }

  bool _insertTab(
    AddTab event,
    OpenedTab tab,
    void Function(TabsState) publish,
  ) {
    if (!_hasRoomForPluginTabs([tab], state.tabs)) return false;
    _separateHistorySlots([tab]);
    final newTabs = List<OpenedTab>.from(state.tabs);
    final newIndex =
        event.index?.clamp(0, newTabs.length) ??
        (event.insertAdjacent
            ? min(state.currentTabIndex + 1, newTabs.length)
            : newTabs.length);
    newTabs.insert(newIndex, tab);

    final keepCurrent = event.inBackground && state.hasOpenTabs;
    final currentIndex = keepCurrent
        ? state.currentTabIndex + (newIndex <= state.currentTabIndex ? 1 : 0)
        : newIndex;
    publish(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: currentIndex,
        // The book the user opened stays the active pane beside its companion.
        activePane: identical(tab, event.tab) || keepCurrent
            ? const ActivePaneUpdate.unchanged()
            : ActivePaneUpdate.set(event.tab),
      ),
    );
    _scheduleSave(newTabs, currentIndex);
    return true;
  }

  /// משמר מקום קיים, ומפריד רק התנגשות בין חלוניות של אותו ספר.
  void _separateHistorySlots(
    Iterable<OpenedTab> incomingTabs, {
    Iterable<OpenedTab>? existingTabs,
  }) {
    final used = <(String, String?)>{};
    for (final pane in (existingTabs ?? state.tabs).expand(leafPanes)) {
      final identity = _readingBookIdentity(pane);
      if (identity != null) used.add((identity, pane.historySlot));
    }
    for (final pane in incomingTabs.expand(leafPanes)) {
      final identity = _readingBookIdentity(pane);
      if (identity == null) continue;
      if (!used.add((identity, pane.historySlot))) {
        pane.historySlot = OpenedTab.newHistorySlot();
        used.add((identity, pane.historySlot));
      }
    }
  }

  Future<void> _onOpenOrFocusTab(
    OpenOrFocusTab event,
    Emitter<TabsState> emit,
  ) async {
    if (event.inBackground) {
      await _onAddTab(
        AddTab(
          event.tab,
          insertAdjacent: event.insertAdjacent,
          inBackground: true,
        ),
        emit,
      );
      return;
    }
    // הכותרת משמשת רק להשוואה מול חלונית של אותו ספר; בלעדיה נחסכת טעינת
    // תוכן העניינים לפני הוספת הטאב, והקורא טוען אותו ממילא.
    final hasSameBook = state.tabs
        .expand(leafPanes)
        .any((open) => _isSameBook(open, event.tab));
    final targetTitle =
        hasSameBook &&
            (!event.matchHistorySlot || event.tab.historySlot == null)
        ? await _resolveTabLocationTitle(
            event.tab,
            explicitTitle: event.targetTitle,
          )
        : null;
    final matchingIndex = await _findMatchingTopLevelTabIndex(
      event.tab,
      targetTitle,
      // סימניה או deep link מנווטים בספר הפתוח גם כשהכותרת המבוקשת שונה.
      ignoreLocation: event.navigateToPositionIfReused,
      matchHistorySlot: event.matchHistorySlot,
    );

    if (matchingIndex != null) {
      final matchingPane = await _matchingPaneIn(
        state.tabs[matchingIndex],
        event.tab,
        targetTitle,
        ignoreLocation: event.navigateToPositionIfReused,
        matchHistorySlot: event.matchHistorySlot,
      );
      final matchingTab = matchingPane ?? state.tabs[matchingIndex];
      _propagateSearchToExistingTab(
        existingTab: matchingTab,
        incomingTab: event.tab,
      );
      // סימניות/היסטוריה: המשתמש בחר מיקום ספציפי בספר, ולא מספיק להעביר
      // focus לטאב הקיים — צריך לגלול אותו למיקום המבוקש.
      if (event.navigateToPositionIfReused) {
        await _propagateNavigationToExistingTab(
          existingTab: matchingTab,
          incomingTab: event.tab,
        );
      }
      // ההדגשה מדייקת את היעד בתוך השורה, אחרי הניווט למיקום המפורש.
      _propagatePinpointHighlightToExistingTab(
        existingTab: matchingTab,
        incomingTab: event.tab,
      );
      _forwardToolQueryToExistingTab(
        existingTab: matchingTab,
        incomingTab: event.tab,
      );
      if (!identical(event.tab, matchingTab)) event.tab.dispose();
      final tabsToSave = state.tabs;
      final readerTarget = event.tab is TextBookTab
          ? _resolveTextBookTab(
              matchingTab,
              event.tab as TextBookTab,
            )
          : null;
      // התאמה בחלונית מפוצלת דורשת גם עדכון של החלונית הפעילה.
      emit(
        state.copyWith(
          currentTabIndex: matchingIndex,
          // ניווט בספר שכבר פעיל חייב להגיע גם ל-WebView: ערך index
          // משתנה בתוך הכרטיסייה ואינו נכלל בהשוואת TabsState.
          forceUpdate:
              event.navigateToPositionIfReused &&
              readerTarget != null &&
              PluginTextReaderRegistry.instance.usesPlugin(readerTarget),
          // null מציין התאמה לטאב עצמו; clear מסיר חלונית פעילה מטאב אחר.
          activePane: matchingPane == null
              ? const ActivePaneUpdate.clear()
              : ActivePaneUpdate.set(matchingPane),
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

    final kept = state.tabs.where((tab) => !identical(tab, event.oldTab));
    if (!_hasRoomForPluginTabs([event.newTab], kept)) {
      _disposeTabLater(event.newTab);
      return;
    }
    _separateHistorySlots([event.newTab], existingTabs: kept);
    event.newTab.isPinned = event.oldTab.isPinned;
    final newTabs = List<OpenedTab>.from(state.tabs);
    newTabs[index] = event.newTab;

    _emitAndSaveTabs(emit, newTabs);
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

    // pinpoint מקבל קדימות על highlightText/permanentHighlightLine.
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
        ),
      );
      if (effectiveLine != null) {
        final loaded = targetText.bloc.state;
        unawaited(
          targetText.lines.scrollToLine(
            effectiveLine,
            alignment: kSearchResultAnchorAlignment,
            intraLineFraction:
                loaded is TextBookLoaded &&
                    effectiveLine < loaded.content.length
                ? matchFractionInLine(
                    loaded.content[effectiveLine],
                    effectiveHighlight,
                    wholeWord: loaded.searchWholeWord,
                    searchOptions: loaded.searchOptions,
                    alternativeWords: loaded.alternativeWords,
                    spacingValues: loaded.spacingValues,
                    isFuzzy: loaded.searchMode == SearchMode.fuzzy,
                    searchDistance: loaded.searchDistance,
                    matchPolicy: loaded.matchPolicy,
                  )
                : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
        );
      }
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

  /// כלי פתוח מקבל את בקשת החיפוש של הטאב הנכנס, שאחרת נזרקת איתו.
  void _forwardToolQueryToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) {
    if (existingTab is! ToolTab || incomingTab is! ToolTab) return;
    final query = incomingTab.queryInbox.take();
    if (query != null) existingTab.queryInbox.post(query);
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
  Future<void> _propagateNavigationToExistingTab({
    required OpenedTab existingTab,
    required OpenedTab incomingTab,
  }) async {
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
      // יעד שנקבע לפני שהקורא מחובר נשמר ומבוצע בחיבור; tab.index מתעדכן מיד.
      final navigation = targetText.lines.scrollToLine(
        targetIndex,
        alignment: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      if (!PluginTextReaderRegistry.instance.usesPlugin(targetText)) {
        unawaited(navigation);
        return;
      }
      await navigation;
    }
  }

  Future<int?> _findMatchingTopLevelTabIndex(
    OpenedTab targetTab,
    String? normalizedTargetTitle, {
    bool ignoreLocation = false,
    bool matchHistorySlot = false,
  }) async {
    for (var index = 0; index < state.tabs.length; index++) {
      final openTab = state.tabs[index];
      if (await _topLevelTabMatches(
        openTab,
        targetTab,
        normalizedTargetTitle,
        ignoreLocation,
        matchHistorySlot,
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
    bool matchHistorySlot,
  ) async {
    if (await _singleTabMatches(
      openTab,
      targetTab,
      normalizedTargetTitle,
      ignoreLocation,
      matchHistorySlot,
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
          matchHistorySlot,
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
    bool matchHistorySlot,
  ) async {
    if (_hasMatchingDedupeKey(openTab, targetTab)) {
      return true;
    }

    if (!_isSameBook(openTab, targetTab)) {
      return false;
    }

    if (matchHistorySlot) {
      if (openTab.historySlot != targetTab.historySlot) return false;
      // null משותף לרשומות ישנות ללא שיוך מוכח, ולכן גם הכותרת חייבת להתאים.
      if (targetTab.historySlot != null) return true;
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
    required bool matchHistorySlot,
  }) async {
    if (openTab is! CombinedTab) return null;
    for (final pane in leafPanes(openTab)) {
      if (await _singleTabMatches(
        pane,
        targetTab,
        normalizedTargetTitle,
        ignoreLocation,
        matchHistorySlot,
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
    final identity = _readingBookIdentity(openTab);
    return identity != null && identity == _readingBookIdentity(targetTab);
  }

  String? _readingBookIdentity(OpenedTab tab) {
    if (tab is TextBookTab) {
      final identity = _textBookIdentity(tab);
      return identity == null ? null : 'text:$identity';
    }
    if (tab is PdfBookTab) return 'pdf:${tab.book.path}';
    return null;
  }

  String? _textBookIdentity(TextBookTab tab) {
    final identity = _textBookBaseIdentity(tab);
    if (identity == null) return null;
    final base = '$identity${tab.book.sourceIdentitySuffix}';
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
        explicitTitle ?? _resolvePdfTabLocationTitle(tab),
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
      // מסלול ה-DB קורא שורה אחת; טעינת עץ הכותרות נשארת רק כשאין מיפוי.
      final fromDb = await refFromDbLine(
        tab.book,
        tab.index,
      ).timeout(locationTitleResolveTimeout);
      if (fromDb != null && fromDb.trim().isNotEmpty) return fromDb;

      final ref = await refFromIndex(
        tab.index,
        tab.book.tableOfContents,
      ).timeout(locationTitleResolveTimeout);
      return ref.trim().isEmpty ? null : ref;
    } catch (_) {
      return null;
    }
  }

  String? _resolvePdfTabLocationTitle(PdfBookTab tab) {
    final currentTitle = tab.currentTitle.value.trim();
    if (currentTitle.isNotEmpty) {
      return currentTitle;
    }

    final ref = referenceFromPageNumber(
      tab.pageNumber,
      tab.outline.value,
      tab.book.title,
    );
    return ref.trim().isNotEmpty ? ref : null;
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

  /// בסגירה קבוצתית קוראים בסדר אינדקס יורד: השחזור הוא LIFO, וכך שחזור
  /// סדרתי מחזיר כל כרטיסיה למקומה המקורי.
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
    final precedingOpening = _pendingRemovals.removeFirst();
    // רק סגירת הטאב האחרון עלולה להעביר לספרייה בזמן שספר עדיין נפתח.
    if (state.tabs.length == 1 && state.tabs.contains(event.tab)) {
      await precedingOpening;
    }
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

    _emitAndSaveTabs(emit, newTabs, currentTabIndex: newIndex);

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
    await _restoreClosedEntry(_recentlyClosedTabs.last, emit);
  }

  Future<void> _onRestoreClosedTab(
    RestoreClosedTab event,
    Emitter<TabsState> emit,
  ) async {
    final index = _recentlyClosedTabs.indexWhere(
      (entry) => identical(entry.tab, event.tab),
    );
    if (index == -1) return;
    await _restoreClosedEntry(_recentlyClosedTabs[index], emit);
  }

  void _onClearRecentlyClosedTabs(
    ClearRecentlyClosedTabs event,
    Emitter<TabsState> emit,
  ) {
    if (_recentlyClosedTabs.isEmpty) return;
    for (final entry in _recentlyClosedTabs) {
      entry.tab.dispose();
    }
    _recentlyClosedTabs.clear();
    // הרשימה אינה חלק מה-state, ולכן רק forceUpdate מרענן את מי שמציג אותה.
    emit(state.copyWith(forceUpdate: true));
  }

  Future<void> _restoreClosedEntry(
    _ClosedTabEntry closedEntry,
    Emitter<TabsState> emit,
  ) async {
    // כלי פתוח ממוקד במקום ליצור מופע נוסף.
    final existingIndex = _indexOfMatchingDedupeKey(closedEntry.tab);
    if (existingIndex != null) {
      _recentlyClosedTabs.remove(closedEntry);
      closedEntry.tab.dispose();
      final tabsToSave = state.tabs;
      emit(state.copyWith(currentTabIndex: existingIndex));
      await _saveCurrentTabIndex(tabsToSave, existingIndex);
      return;
    }
    if (!_hasRoomForPluginTabs([closedEntry.tab], state.tabs)) return;
    _recentlyClosedTabs.remove(closedEntry);
    _separateHistorySlots([closedEntry.tab]);
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
    for (var i = state.tabs.length - 1; i >= 0; i--) {
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

  /// מחליף את תוכן החלון בכרטיסיה שאומצה, **בעדכון מצב יחיד**.
  ///
  /// התוצאה זהה ל-[CloseAllTabs] ואחריו [AddTab] — המוצמדות נשארות,
  /// השאר נזכרות לשחזור ומשוחררות — אבל בלי מצב הביניים של אפס
  /// כרטיסיות, שהוא באג ולא מצב אמיתי. ראו [AdoptTab].
  Future<void> _onAdoptTab(AdoptTab event, Emitter<TabsState> emit) async {
    final pinned = state.tabs.where((tab) => tab.isPinned).toList();
    if (!_hasRoomForPluginTabs([event.tab], pinned)) {
      _disposeTabLater(event.tab);
      return;
    }
    final toDispose = state.tabs.where((tab) => !tab.isPinned).toList();
    for (var i = state.tabs.length - 1; i >= 0; i--) {
      if (!state.tabs[i].isPinned) {
        _rememberClosedTab(state.tabs[i], i);
      }
    }

    _separateHistorySlots([event.tab], existingTabs: pinned);
    final newTabs = [...pinned, event.tab];
    final newIndex = newTabs.length - 1;
    emit(
      state.copyWith(
        tabs: newTabs,
        currentTabIndex: newIndex,
        selectedTabs: const <OpenedTab>[],
      ),
    );
    _scheduleSave(newTabs, newIndex);

    for (final tab in toDispose) {
      _disposeTabLater(tab);
    }
  }

  Future<void> _onCloseOtherTabs(
    CloseOtherTabs event,
    Emitter<TabsState> emit,
  ) async {
    for (var i = state.tabs.length - 1; i >= 0; i--) {
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
    // ⚠️ בלי בדיקת השייכות, `MoveTab` על כרטיסיה שנסגרה **מחדיר** אותה —
    // ואת ה-`dispose` שלה כבר תזמנו. האינדקס מגיע מרצועת היעד ויכול
    // להתיישן בין הריחוף לשחרור.
    if (!state.tabs.contains(event.tab)) return;
    final newTabs = List<OpenedTab>.from(state.tabs)..remove(event.tab);
    final targetIndex = event.newIndex.clamp(0, newTabs.length);
    newTabs.insert(targetIndex, event.tab);

    emit(
      state.copyWith(
        tabs: newTabs,
        // כמו בדפדפן: הכרטיסייה שנגררה היא שמוצגת בתום הסידור (issue #1104).
        currentTabIndex: targetIndex,
      ),
    );
    _scheduleSave(newTabs, targetIndex);
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

  void _onRenameTab(RenameTab event, Emitter<TabsState> emit) {
    if (event.tab.title == event.title) return;
    if (!state.tabs.any((tab) => leafPanes(tab).contains(event.tab))) return;
    event.tab.title = event.title;
    emit(
      state.copyWith(tabs: List<OpenedTab>.from(state.tabs), forceUpdate: true),
    );
    _scheduleSave(state.tabs, state.currentTabIndex);
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

    _emitAndSaveTabs(emit, newTabs, currentTabIndex: newCurrentIndex);
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

    if (!_hasRoomForPluginTabs([event.tab], state.tabs)) {
      _disposeTabLater(event.tab);
      return;
    }
    _separateHistorySlots([event.tab]);
    final combinedTab = CombinedTab(
      rightTab: current,
      leftTab: event.tab,
      splitRatio: event.splitRatio,
      isPinned: current.isPinned,
    );
    final newTabs = List<OpenedTab>.from(state.tabs)..[index] = combinedTab;

    // החלונית החדשה היא זו שהמשתמש ביקש לקרוא בה.
    _emitAndSaveTabs(
      emit,
      newTabs,
      currentTabIndex: index,
      activePane: ActivePaneUpdate.set(event.tab),
    );
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

      _emitAndSaveTabs(emit, newTabs, currentTabIndex: newCurrentIndex);
      // אין לשחרר את העוטף, כי החלוניות ממשיכות להיות מוצגות.
    }
  }

  Future<void> _onUpdateSplitRatio(
    UpdateSplitRatio event,
    Emitter<TabsState> emit,
  ) async {
    final current = state.currentTab;
    if (current is! CombinedTab) return;
    // SplitPaneView כבר כתב את היחס ל-node הנכון; forceUpdate כאן בונה מחדש את
    // תוכן כל הכרטיסיות, וכתיבה ל-currentTab דורסת טאב מפוצל אחר.
    _scheduleSave(state.tabs, state.currentTabIndex);
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

    _emitAndSaveTabs(emit, newTabs);
  }

  void _onSetActivePane(SetActivePane event, Emitter<TabsState> emit) {
    final current = state.currentTab;
    if (current == null) return;
    // החלונית הפעילה חייבת להיות בטאב המוצג.
    if (!leafPanes(current).any((pane) => identical(pane, event.pane))) return;
    if (identical(state.activePane, event.pane)) return;
    emit(state.copyWith(activePane: ActivePaneUpdate.set(event.pane)));
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

    _emitAndSaveTabs(emit, newTabs);

    // אין לשחרר את הטאב המפוצל כי האחות ממשיכה להיות מוצגת.
    _disposeTabLater(event.pane);
  }

  Future<void> _onDetachPane(DetachPane event, Emitter<TabsState> emit) async {
    final index = state.tabs.indexWhere(
      (tab) => tab is CombinedTab && tab.sibling(event.pane) != null,
    );
    if (index == -1) return;

    final combined = state.tabs[index] as CombinedTab;
    final survivor = combined.sibling(event.pane)!;
    // ההצמדה עוברת לשתי החלוניות, כמו בפירוק מלא של הטאב המפוצל.
    if (combined.isPinned) {
      survivor.isPinned = true;
      event.pane.isPinned = true;
    }

    final newTabs = List<OpenedTab>.from(state.tabs);
    newTabs[index] = survivor;
    final insertIndex = event.insertIndex.clamp(0, newTabs.length);
    newTabs.insert(insertIndex, event.pane);

    // החלונית שנגררה החוצה נשארת מול העיניים, כמו גרירת כרטיסיה בדפדפן.
    _emitAndSaveTabs(emit, newTabs, currentTabIndex: insertIndex);
    // אין לשחרר דבר: שתי החלוניות ממשיכות להיות מוצגות ככרטיסיות.
  }
}
