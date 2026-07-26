import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';

/// חיווי קצר להגדרות החיפוש הכלליות שאינן ברירת מחדל, לתצוגה בפריט
/// ההיסטוריה (מצב, מרחק, טווח, התאמת מילים, איחוד תוצאות, רגקס). ערכי
/// ברירת מחדל מושמטים כדי לא להעמיס על חיפושים פשוטים.
String formatGeneralSearchSettings(SearchConfiguration config) {
  final parts = <String>[];

  if (config.searchMode != SearchMode.advanced) {
    parts.add(config.searchMode.shortLabel);
  }
  // טווח שאינו "מרווח מילים" מחליף את המרחק; אחרת מציגים מרחק כשהוגדר.
  if (config.proximityScope != SearchScope.wordDistance) {
    parts.add(config.proximityScope.label);
  } else if (config.distance > 0) {
    parts.add('מרחק ${config.distance}');
  }
  if (config.wordMatchMode != WordMatchMode.all) {
    parts.add(
      config.wordMatchMode == WordMatchMode.atLeast
          ? 'לפחות ${config.wordMatchCount} מילים'
          : config.wordMatchMode.label,
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

  HistoryBloc(this._repository) : super(HistoryInitial()) {
    on<LoadHistory>(_onLoadHistory);
    on<SetCurrentWorkspaceName>(_onSetCurrentWorkspaceName);
    on<AddHistory>(_onAddHistory);
    on<AddHistoryForTabs>(_onAddHistoryForTabs);
    on<BulkAddHistory>(_onBulkAddHistory);
    on<RemoveHistory>(_onRemoveHistory);
    on<ClearHistory>(_onClearHistory);
    on<CaptureStateForHistory>(_onCaptureStateForHistory);
    on<FlushHistory>(_onFlushHistory);

    _preCloseCallback = _flushPendingSnapshots;
    PreCloseRegistry.register(_preCloseCallback);
    add(LoadHistory());
  }

  /// שומר את כל ה-snapshots הממתינים לפני סגירת האפליקציה.
  Future<void> _flushPendingSnapshots() async {
    _debounce?.cancel();
    if (_pendingSnapshots.isNotEmpty) {
      final snapshots = _pendingSnapshots.values.toList();
      _pendingSnapshots.clear();
      await _updateAndSaveHistory(snapshots);
    }
  }

  @override
  Future<void> close() async {
    PreCloseRegistry.unregister(_preCloseCallback);
    _debounce?.cancel();
    try {
      await _flushPendingSnapshots();
    } catch (e) {
      debugPrint('HistoryBloc.close: failed to flush pending snapshots: $e');
    }
    return super.close();
  }

  Future<List<Bookmark>> _updateAndSaveHistory(List<Bookmark> snapshots) async {
    final updatedHistory = List<Bookmark>.from(state.history);

    for (final bookmark in snapshots) {
      final existingIndex = updatedHistory.indexWhere(
        (b) => b.historyKey == bookmark.historyKey,
      );
      if (existingIndex >= 0) {
        updatedHistory.removeAt(existingIndex);
      }
      updatedHistory.insert(0, bookmark);
    }

    const maxHistorySize = 200;
    if (updatedHistory.length > maxHistorySize) {
      updatedHistory.removeRange(maxHistorySize, updatedHistory.length);
    }

    await _repository.saveHistory(updatedHistory);
    return updatedHistory;
  }

  Future<Bookmark?> _bookmarkFromTab(
    OpenedTab tab, {
    List<String>? scopeFacetsOverride,
    SearchScope? proximityScopeOverride,
  }) async {
    final workspaceName = _currentWorkspaceName;

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
        searchMode: searchState.configuration.searchMode,
        distance: searchState.configuration.distance,
        // ה-configuration המלא נשמר כמפה כדי ששחזור יחזיר גם הגדרות שאין
        // להן שדה ייעודי (מיון, איחוד תוצאות, התאמת מילים, רגקס).
        searchConfiguration: searchState.configuration.toMap(),
        proximityScope:
            proximityScopeOverride ?? searchState.configuration.proximityScope,
      );
    }

    if (tab is TextBookTab) {
      final blocState = tab.bloc.state;
      if (blocState is TextBookLoaded && blocState.visibleIndices.isNotEmpty) {
        final index = blocState.visibleIndices.first;
        String ref = await refFromIndex(
          index,
          Future.value(blocState.tableOfContents),
        );
        // הוספת שם הספר לכותרת
        ref = addBookTitleToRef(ref, blocState.book.title);
        return Bookmark(
          ref: ref,
          book: blocState.book,
          index: index,
          commentatorsToShow: blocState.activeCommentators,
          workspaceName: workspaceName,
        );
      }
    } else if (tab is CommentatorsTab) {
      final blocState = tab.bloc.state;
      if (blocState is TextBookLoaded && blocState.visibleIndices.isNotEmpty) {
        final index = blocState.visibleIndices.first;
        String ref = await refFromIndex(
          index,
          Future.value(blocState.tableOfContents),
        );
        ref = addBookTitleToRef(ref, blocState.book.title);
        return Bookmark(
          ref: 'מפרשים | $ref',
          book: blocState.book,
          index: index,
          commentatorsToShow: blocState.activeCommentators,
          workspaceName: workspaceName,
          targetKind: BookmarkTargetKind.commentators,
        );
      }
    } else if (tab is PdfBookTab) {
      if (!tab.pdfViewerController.isReady) return null;
      final page = tab.pdfViewerController.pageNumber ?? 1;

      // נסה למצוא כותרת מה-outline
      String ref;
      final outline = tab.outline.value;
      if (outline != null && outline.isNotEmpty) {
        final heading = _findHeadingForPage(outline, page);
        if (heading != null) {
          ref = '${tab.title} $heading — עמוד $page';
        } else {
          ref = '${tab.title} עמוד $page'; // אם אין כותרת, הצג עם מספר עמוד
        }
      } else {
        ref = '${tab.title} עמוד $page'; // אם אין outline, הצג עם מספר עמוד
      }

      return Bookmark(
        ref: ref,
        book: tab.book,
        index: page,
        workspaceName: workspaceName,
      );
    } else if (tab is PdfCommentatorsTab) {
      final sourceTab = tab.sourceTab;
      final page = sourceTab.pdfViewerController.isReady
          ? (sourceTab.pdfViewerController.pageNumber ?? sourceTab.pageNumber)
          : sourceTab.pageNumber;
      final heading = sourceTab.currentTitle.value.trim();
      final ref = heading.isNotEmpty
          ? 'מפרשים | ${sourceTab.book.title} $heading'
          : 'מפרשים | ${sourceTab.book.title} עמוד $page';

      return Bookmark(
        ref: ref,
        book: sourceTab.book,
        index: page,
        commentatorsToShow: sourceTab.activeCommentators.toList(),
        workspaceName: workspaceName,
        targetKind: BookmarkTargetKind.commentators,
      );
    }
    return null;
  }

  /// מוצא את הכותרת המתאימה לעמוד מסוים ב-outline
  String? _findHeadingForPage(List<PdfOutlineNode> outline, int page) {
    PdfOutlineNode? bestMatch;

    void searchNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        final nodePage = node.dest?.pageNumber;
        if (nodePage != null && nodePage <= page) {
          // אם זה העמוד המדויק או קרוב יותר מהמצא הקודם
          if (bestMatch == null ||
              nodePage > (bestMatch!.dest?.pageNumber ?? 0)) {
            bestMatch = node;
          }
          // חפש גם בילדים
          if (node.children.isNotEmpty) {
            searchNodes(node.children);
          }
        }
      }
    }

    searchNodes(outline);
    return bestMatch?.title;
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
    final bookmark = await _bookmarkFromTab(event.tab);
    if (bookmark != null) {
      _pendingSnapshots[bookmark.historyKey] = bookmark;
    }
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
    _debounce?.cancel();
    if (_pendingSnapshots.isNotEmpty) {
      final snapshots = _pendingSnapshots.values.toList();
      _pendingSnapshots.clear();
      final updatedHistory = await _updateAndSaveHistory(snapshots);
      emit(HistoryLoaded(updatedHistory));
    }
  }

  Future<void> _onLoadHistory(
    LoadHistory event,
    Emitter<HistoryState> emit,
  ) async {
    try {
      emit(HistoryLoading(state.history));
      final history = await _repository.loadHistory();
      emit(HistoryLoaded(history));
    } catch (e) {
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
      final bookmark = await _bookmarkFromTab(
        event.tab,
        scopeFacetsOverride: event.scopeFacets,
        proximityScopeOverride: event.proximityScope,
      );
      if (bookmark == null) return;
      add(BulkAddHistory([bookmark]));
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
        final bookmark = await _bookmarkFromTab(tab);
        if (bookmark != null) snapshots.add(bookmark);
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
      emit(HistoryLoaded(updatedHistory));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }

  Future<void> _onRemoveHistory(
    RemoveHistory event,
    Emitter<HistoryState> emit,
  ) async {
    try {
      final updatedHistory = List<Bookmark>.from(state.history)
        ..removeAt(event.index);
      await _repository.saveHistory(updatedHistory);
      emit(HistoryLoaded(updatedHistory));
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
      emit(HistoryLoaded([]));
    } catch (e) {
      emit(HistoryError(state.history, e.toString()));
    }
  }
}
