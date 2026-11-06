import 'dart:async';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// חיווי קצר להגדרות החיפוש הכלליות שאינן ברירת מחדל, לתצוגה בפריט
/// ההיסטוריה (מצב, מרחק, טווח, סדר, התאמת מילים, איחוד תוצאות, רגקס). ערכי
/// ברירת מחדל מושמטים כדי לא להעמיס על חיפושים פשוטים.
String formatGeneralSearchSettings(SearchConfiguration config) {
  final parts = <String>[];

  if (config.searchMode != SearchMode.advanced) {
    parts.add(config.searchMode.shortLabel);
  }
  // הטווח ומצב ההתאמה חלים רק במתקדם; טווח שאינו "מרווח מילים" מחליף
  // את המרחק, אחרת מציגים מרחק כשהוגדר.
  final policy = config.matchPolicy;
  if (policy.proximityScope != SearchScope.wordDistance) {
    parts.add(policy.proximityScope.label);
  } else if (config.distance > 0) {
    parts.add('מרחק ${config.distance}');
  }
  if (policy.anyOrder) {
    parts.add('בכל סדר');
  }
  if (policy.wordMatchMode != WordMatchMode.all) {
    parts.add(
      policy.wordMatchMode == WordMatchMode.atLeast
          ? 'לפחות ${policy.wordMatchCount} מילים'
          : policy.wordMatchMode.label,
    );
  }
  if (config.resultGrouping != ResultGroupingMode.none) {
    parts.add(config.resultGrouping.label);
  }
  if (config.regexEnabled) {
    parts.add('ביטוי רגולרי');
  }

  return parts.join(' · ');
}

/// קיצורי אפשרויות המילה הרגילות לכותרת קומפקטית; אפשרויות מתקדמות
/// (ללא קיצור כאן) מוצגות בשמן המלא.
const Map<String, String> _wordOptionAbbreviations = {
  'קידומות': 'ק',
  'סיומות': 'ס',
  'קידומות דקדוקיות': 'קד',
  'סיומות דקדוקיות': 'סד',
  'כתיב מלא/חסר': 'מח',
  'חלק ממילה': 'חמ',
};

const Set<String> _wordSuffixOptions = {'סיומות', 'סיומות דקדוקיות'};

/// מקטע יחיד בכותרת פריט חיפוש: טקסט מבנה השאילתה (מילה/חלופה/מפריד) או
/// חיווי אפשרות ([isOption]) שה-UI מציג מובחן (גופן קטן, גוון הנושא).
class SearchTitleSegment {
  final String text;
  final bool isOption;
  const SearchTitleSegment(this.text, {this.isOption = false});
}

/// בונה את מקטעי כותרת החיפוש מרכיבי השאילתה הגולמיים. חיבור טקסטי
/// המקטעים מייצר את מחרוזת ה-ref, כך שהתצוגה המפורמטת והשמורה זהות.
List<SearchTitleSegment> buildSearchTitleSegments({
  required String query,
  Map<String, Map<String, bool>> effectiveOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  String negativeText = '',
}) {
  final segments = <SearchTitleSegment>[];
  final words = SearchQueryBuilder.splitQueryWords(query);
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final selected =
        effectiveOptions['${word}_$i']?.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toList() ??
        const <String>[];
    final prefixes = selected
        .where((opt) => !_wordSuffixOptions.contains(opt))
        .map((opt) => _wordOptionAbbreviations[opt] ?? opt)
        .toList();
    final suffixes = selected
        .where((opt) => _wordSuffixOptions.contains(opt))
        .map((opt) => _wordOptionAbbreviations[opt] ?? opt)
        .toList();

    if (prefixes.isNotEmpty) {
      segments.add(
        SearchTitleSegment('(${prefixes.join(',')})', isOption: true),
      );
    }
    segments.add(SearchTitleSegment(word));
    final alternatives = alternativeWords[i] ?? const <String>[];
    if (alternatives.isNotEmpty) {
      segments.add(SearchTitleSegment(' או ${alternatives.join(' או ')}'));
    }
    if (suffixes.isNotEmpty) {
      segments.add(
        SearchTitleSegment('(${suffixes.join(',')})', isOption: true),
      );
    }
    if (i < words.length - 1) {
      final spacing = spacingValues['$i-${i + 1}'];
      segments.add(
        SearchTitleSegment(
          spacing != null && spacing.isNotEmpty ? ' +$spacing ' : ' + ',
        ),
      );
    }
  }
  final negative = negativeText.trim();
  if (negative.isNotEmpty) {
    segments.add(SearchTitleSegment(' ללא $negative'));
  }
  return segments;
}

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final HistoryRepository _repository;
  String? _currentWorkspaceName;
  Timer? _debounce;
  final Map<String, Bookmark> _pendingSnapshots = {};
  late final Future<void> Function() _preCloseCallback;

  /// הכרטיסיה הפעילה, ללכידה אחרונה לפני סגירה.
  final OpenedTab? Function()? currentTab;

  HistoryBloc(this._repository, {this.currentTab}) : super(HistoryInitial()) {
    on<LoadHistory>(_onLoadHistory, transformer: restartable());
    on<SetCurrentWorkspaceName>(_onSetCurrentWorkspaceName);
    on<AddHistory>(_onAddHistory);
    on<AddHistoryForTabs>(_onAddHistoryForTabs);
    on<BulkAddHistory>(_onBulkAddHistory, transformer: sequential());
    on<RemoveHistory>(_onRemoveHistory);
    on<ClearHistory>(_onClearHistory);
    on<CaptureStateForHistory>(_onCaptureStateForHistory);
    on<FlushHistory>(_onFlushHistory);

    _preCloseCallback = _flushPendingSnapshots;
    PreCloseRegistry.register(_preCloseCallback);
    // חלון אחר פתח ספר — ההיסטוריה שבזיכרון התיישנה.
    _remoteChanges = _repository.remoteChanges.listen(
      (_) => add(LoadHistory()),
    );
    add(LoadHistory());
  }

  StreamSubscription<void>? _remoteChanges;

  /// גדל בכל הצגה של תוצאת כתיבה. טעינה שהתחילה לפני כן (הפענוח שלה
  /// נמשך שניות ב-isolate) מציגה רשימה ישנה, ולכן נזנחת.
  int _writeGeneration = 0;

  void _emitWritten(Emitter<HistoryState> emit, List<Bookmark> history) {
    _writeGeneration++;
    emit(HistoryLoaded(history));
  }

  /// מוסיף את רשומות [tab] לממתינים לשמירה.
  Future<void> _capture(OpenedTab? tab) async {
    if (tab == null) return;
    for (final bookmark in await _bookmarksFromTab(tab)) {
      _pendingSnapshots[bookmark.historyKey] = bookmark;
    }
  }

  /// שומר את כל ה-snapshots הממתינים, כולל הכרטיסיה הפעילה במיקומה
  /// הנוכחי, ומחזיר את ההיסטוריה שנשמרה — או null כשלא היה מה לשמור.
  ///
  /// ⚠️ בלי לכידה בסגירה הספר שנקרא עכשיו אינו נרשם כלל: הלכידה שבפתיחתו
  /// רצה לפני שה-bloc שלו נטען, ומחזירה null, ואין אחריה לכידה נוספת.
  Future<List<Bookmark>?> _flushPendingSnapshots() async {
    _debounce?.cancel();
    await _capture(currentTab?.call());
    if (_pendingSnapshots.isEmpty) return null;
    final snapshots = _pendingSnapshots.values.toList();
    _pendingSnapshots.clear();
    return _updateAndSaveHistory(snapshots);
  }

  @override
  Future<void> close() async {
    PreCloseRegistry.unregister(_preCloseCallback);
    await _remoteChanges?.cancel();
    _debounce?.cancel();
    try {
      await _flushPendingSnapshots();
    } catch (e) {
      debugPrint('HistoryBloc.close: failed to flush pending snapshots: $e');
    }
    return super.close();
  }

  static const int _maxHistorySize = 200;

  static bool Function(Bookmark) _historyMatcher(Bookmark bookmark) {
    if (!bookmark.isSearch) {
      final key = bookmark.historyKey;
      return (other) => !other.isSearch && other.historyKey == key;
    }
    Set<String> scopeOf(Bookmark entry) =>
        entry.searchScopeFacets?.isNotEmpty == true
        ? entry.searchScopeFacets!.toSet()
        : {'/'};
    final scope = scopeOf(bookmark);
    final filter = bookmark.searchFilterFacets?.toSet() ?? scope;
    return (other) {
      if (!other.isSearch || other.ref != bookmark.ref) return false;
      // מסנן קטן יכול לפסול רשומה בלי לקרוא שוב תחום של אלפי ספרים.
      final otherFilter = other.searchFilterFacets;
      if (otherFilter != null && !setEquals(otherFilter.toSet(), filter)) {
        return false;
      }
      final otherScope = scopeOf(other);
      return setEquals(otherScope, scope) &&
          (otherFilter != null || setEquals(otherScope, filter));
    };
  }

  /// מוחל רק על ההיסטוריה הטרייה שבטרנזקציית הכתיבה, ולא על state מקומי.
  static List<Bookmark> _withSnapshots(
    List<Bookmark> current,
    List<Bookmark> snapshots,
  ) {
    final updated = List<Bookmark>.from(current);
    for (final bookmark in snapshots) {
      updated.removeWhere(_historyMatcher(bookmark));
      updated.insert(0, bookmark);
    }
    if (updated.length > _maxHistorySize) {
      updated.removeRange(_maxHistorySize, updated.length);
    }
    return updated;
  }

  Future<List<Bookmark>> _updateAndSaveHistory(List<Bookmark> snapshots) =>
      _repository.mutateHistory(
        (current) => _withSnapshots(current, snapshots),
      );

  /// רשומות ההיסטוריה של טאב: אחת לכל חלונית בטאב מפוצל, בסדר התצוגה.
  ///
  /// טאב מפוצל אינו ספר ולכן `_bookmarkFromTab` מחזיר עליו `null` — בלי הפירוק
  /// הזה כל מפגש קריאה בפיצול לא נרשם כלל.
  Future<List<Bookmark>> _bookmarksFromTab(
    OpenedTab tab, {
    List<String>? scopeFacetsOverride,
    SearchScope? proximityScopeOverride,
  }) async {
    final panes = leafPanes(tab);
    // ה-override מתאר את הטאב הנכנס, ובטאב מפוצל אין חלונית אחת שהוא שייך לה.
    final isSplit = panes.length > 1;
    final bookmarks = <Bookmark>[];
    // בסדר הפוך: `_updateAndSaveHistory` דוחף כל רשומה לראש ההיסטוריה, ולכן
    // כך החלונית הראשונה בסדר התצוגה היא זו שנשארת בראש.
    for (final pane in panes.reversed) {
      final bookmark = await _bookmarkFromTab(
        pane,
        scopeFacetsOverride: isSplit ? null : scopeFacetsOverride,
        proximityScopeOverride: isSplit ? null : proximityScopeOverride,
      );
      if (bookmark != null) bookmarks.add(bookmark);
    }
    return bookmarks;
  }

  Future<Bookmark?> _bookmarkFromTab(
    OpenedTab tab, {
    List<String>? scopeFacetsOverride,
    SearchScope? proximityScopeOverride,
  }) async {
    final workspaceName = _currentWorkspaceName;

    // ההיסטוריה משחזרת חיפוש מילולי; חיפוש סמנטי היה חוזר בה כמילולי.
    if (tab is SemanticSearchTab) return null;
    if (tab is SearchingTab) {
      final searchingTab = tab;
      final text = searchingTab.queryController.text;
      if (text.trim().isEmpty) return null;

      final searchState = searchingTab.searchBloc.state;

      final formattedQuery = _buildFormattedQuery(searchingTab);
      final scopeFacets = scopeFacetsOverride ?? searchState.searchScopeFacets;
      final nonRootScopeFacets = scopeFacets
          .where((facet) => facet != '/')
          .toList();

      return Bookmark(
        ref: formattedQuery,
        book: TextBook(title: text), // Use the original text for the book title
        index: 0, // No specific index for a search
        isSearch: true,
        // שמירת האפשרויות האפקטיביות (מורחבות מגלובלי לפר-מילה אם רלוונטי)
        // כדי שטעינה חוזרת תייצר את אותו חיפוש בדיוק
        searchOptions: searchingTab.effectiveSearchOptions(query: text),
        alternativeWords: searchingTab.alternativeWords,
        spacingValues: searchingTab.spacingValues,
        negativeSearchText: searchingTab.negativeQueryController.text,
        negativeSearchOptions: searchingTab.effectiveNegativeSearchOptions(
          query: searchingTab.negativeQueryController.text,
        ),
        negativeAlternativeWords: searchingTab.negativeAlternativeWords,
        negativeSpacingValues: searchingTab.negativeSpacingValues,
        workspaceName: workspaceName,
        searchScopeFacets: nonRootScopeFacets.isNotEmpty
            ? nonRootScopeFacets
            : null,
        searchFilterFacets:
            scopeFacetsOverride == null &&
                !setEquals(
                  searchState.currentFacets.toSet(),
                  scopeFacets.toSet(),
                )
            ? List<String>.of(searchState.currentFacets)
            : null,
        searchMode: searchState.configuration.searchMode,
        distance: searchState.configuration.distance,
        // ה-configuration המלא נשמר כמפה כדי ששחזור יחזיר גם הגדרות שאין
        // להן שדה ייעודי (מיון, איחוד תוצאות, התאמת מילים, רגקס).
        searchConfiguration: searchState.configuration.toMap(),
        proximityScope:
            proximityScopeOverride ?? searchState.configuration.proximityScope,
      );
    }

    final bookmark = await bookmarkFromReadingTab(
      tab,
      workspaceName: workspaceName,
    );
    return bookmark?.copyWith(historySlot: tab.historySlot);
  }

  String _buildFormattedQuery(SearchingTab tab) {
    final text = tab.queryController.text;
    if (text.trim().isEmpty) return '';
    final segments = buildSearchTitleSegments(
      query: text,
      effectiveOptions: tab.effectiveSearchOptions(query: text),
      alternativeWords: tab.alternativeWords,
      spacingValues: tab.spacingValues,
      negativeText: tab.negativeQueryController.text,
    );
    return segments.map((segment) => segment.text).join();
  }

  Future<void> _onCaptureStateForHistory(
    CaptureStateForHistory event,
    Emitter<HistoryState> emit,
  ) async {
    _debounce?.cancel();
    await _capture(event.tab);
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (_pendingSnapshots.isNotEmpty) {
        add(BulkAddHistory(List.from(_pendingSnapshots.values)));
        _pendingSnapshots.clear();
      }
    });
  }

  Future<void> _onFlushHistory(
    FlushHistory event,
    Emitter<HistoryState> emit,
  ) async {
    final updatedHistory = await _flushPendingSnapshots();
    if (updatedHistory != null) _emitWritten(emit, updatedHistory);
  }

  Future<void> _onLoadHistory(
    LoadHistory event,
    Emitter<HistoryState> emit,
  ) async {
    final generation = _writeGeneration;
    try {
      emit(HistoryLoading(state.history));
      final history = await _repository.loadHistory();
      if (generation != _writeGeneration) return;
      emit(HistoryLoaded(history));
    } catch (e) {
      if (generation != _writeGeneration) return;
      emit(HistoryError(state.history, e.toString()));
    }
  }

  void _onSetCurrentWorkspaceName(
    SetCurrentWorkspaceName event,
    Emitter<HistoryState> emit,
  ) {
    _currentWorkspaceName = event.workspaceName;
  }

  Future<void> _onAddHistory(
    AddHistory event,
    Emitter<HistoryState> emit,
  ) async {
    try {
      final bookmarks = await _bookmarksFromTab(
        event.tab,
        scopeFacetsOverride: event.scopeFacets,
        proximityScopeOverride: event.proximityScope,
      );
      if (bookmarks.isEmpty) return;
      add(BulkAddHistory(bookmarks));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onAddHistoryForTabs(
    AddHistoryForTabs event,
    Emitter<HistoryState> emit,
  ) async {
    try {
      final snapshots = <Bookmark>[];
      for (final tab in event.tabs) {
        snapshots.addAll(await _bookmarksFromTab(tab));
      }
      if (snapshots.isEmpty) return;
      add(BulkAddHistory(snapshots));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onBulkAddHistory(
    BulkAddHistory event,
    Emitter<HistoryState> emit,
  ) async {
    if (event.snapshots.isEmpty) return;
    try {
      final updatedHistory = await _updateAndSaveHistory(event.snapshots);
      _emitWritten(emit, updatedHistory);
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onRemoveHistory(
    RemoveHistory event,
    Emitter<HistoryState> emit,
  ) async {
    try {
      if (event.index < 0 || event.index >= state.history.length) return;
      // מתרגמים אינדקס לזהות מול רשימת ה-UI: חלון אחר עשוי להזיז את
      // הרשומות בבסיס בינתיים, ומחיקה לפי האינדקס החדש תמחק רשומה אחרת.
      final bookmark = state.history[event.index];
      final matches = _historyMatcher(bookmark);
      final updatedHistory = await _repository.mutateHistory(
        (current) => current.where((b) => !matches(b)).toList(),
      );
      _emitWritten(emit, updatedHistory);
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onClearHistory(
    ClearHistory event,
    Emitter<HistoryState> emit,
  ) async {
    try {
      await _repository.clearHistory();
      _emitWritten(emit, []);
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }
}
