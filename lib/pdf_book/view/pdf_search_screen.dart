import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/text_book/utils/search_query_sync.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class PdfBookSearchView extends StatefulWidget {
  const PdfBookSearchView({
    required this.textSearcher,
    required this.searchController,
    required this.focusNode,
    this.outline,
    this.bookTitle,
    this.bookTopics,
    this.bookCategoryPath,
    this.bookId,
    this.isUserBook = false,
    this.externalLibraryId,
    this.pdfFilePath,
    this.initialSearchText = '',
    this.initialSearchOptions = const {},
    this.initialAlternativeWords = const {},
    this.initialSpacingValues = const {},
    this.initialSearchMode = SearchMode.exact,
    this.initialSearchDistance = 0,
    this.initialMatchPolicy = SearchMatchPolicy.standard,
    this.incomingSearchConfiguration,
    this.onSearchResultNavigated,
    this.searchRepository = const SearchRepository(),
    super.key,
  });

  final PdfTextSearcher textSearcher;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final List<PdfOutlineNode>? outline;
  final String? bookTitle;
  final String? bookTopics;
  final String? bookCategoryPath;

  /// מזהי הספר לבניית נתיב ה-facet — חייבים להיכלל בדיוק כמו באינדוקס
  /// (id:/uid:/ext:), אחרת מסלול המנוע מחפש תחת facet שאינו קיים.
  final int? bookId;
  final bool isUserBook;
  final String? externalLibraryId;

  /// Absolute path to the currently opened PDF file.
  ///
  /// Used to ensure in-book PDF search doesn't return results from a same-title
  /// text book (TXT) that shares the same facet path in the search index.
  final String? pdfFilePath;

  final String initialSearchText;
  final Map<String, Map<String, bool>> initialSearchOptions;
  final Map<int, List<String>> initialAlternativeWords;
  final Map<String, String> initialSpacingValues;
  final SearchMode initialSearchMode;
  final int initialSearchDistance;
  final SearchMatchPolicy initialMatchPolicy;

  /// תצורת חיפוש שממתינה להחלה אטומית בחלונית.
  final ValueNotifier<ReadingTabSearchState?>? incomingSearchConfiguration;

  final VoidCallback? onSearchResultNavigated;

  /// מנוע החיפוש המתקדם. נחלף בבדיקות במימוש שלא נוגע במנוע ה-Rust.
  final SearchRepository searchRepository;

  /// חישוב האינדקס הוויזואלי ב-ScrollablePositionedList של תוצאות החיפוש,
  /// שאליו יש לגלול בהתאם לעמוד הנוכחי בספר.
  ///
  /// [resultsPageNumbersSorted] — מספרי עמוד לכל תוצאה, ממוינים בסדר עולה.
  /// [currentPage] — העמוד בו המשתמש נמצא כרגע.
  ///
  /// היעד: כותרת העמוד הראשון שגדול או שווה ל-[currentPage]. אם כל
  /// העמודים בתוצאות לפני המיקום הנוכחי, היעד הוא כותרת העמוד האחרון
  /// (התוצאה הקרובה ממעל), לא הראשון.
  @visibleForTesting
  static int computeTargetVisualIndexForTesting({
    required List<int> resultsPageNumbersSorted,
    required int currentPage,
  }) {
    if (resultsPageNumbersSorted.isEmpty) return 0;
    final pages = resultsPageNumbersSorted.toSet().toList()..sort();
    final targetPage = pages.firstWhere(
      (p) => p >= currentPage,
      orElse: () => pages.last,
    );

    int visualIdx = 0;
    int resultIdx = 0;
    for (final page in pages) {
      if (page == targetPage) break;
      visualIdx++; // כותרת הדף
      while (resultIdx < resultsPageNumbersSorted.length &&
          resultsPageNumbersSorted[resultIdx] == page) {
        visualIdx++;
        resultIdx++;
      }
    }
    return visualIdx;
  }

  /// הודעה כשמסלול המנוע החזיר 0 תוצאות והספר כלל אינו באינדקס —
  /// בלעדיה "אין תוצאות" הגנרי מסתיר מהמשתמש את הסיבה האמיתית.
  @visibleForTesting
  static String? missingFromIndexNotice({
    required String? pdfFilePath,
    required bool indexInitialized,
    required Set<String> indexedFilePaths,
  }) {
    if (pdfFilePath == null || pdfFilePath.isEmpty) return null;
    if (!indexInitialized) return null;
    if (indexedFilePaths.contains(pdfFilePath)) return null;
    return PdfMessages.bookNotInSearchIndex;
  }

  /// תקרת מונחים ייחודיים לתבנית ההדגשה, כדי שהרגקס לא יתנפח.
  static const int _maxHighlightTerms = 50;

  /// בונה תבנית הדגשה אחת מהמונחים שהמנוע סימן כהתאמות ב-[resultHtmls]
  /// (עד [_maxHighlightTerms] מונחים). מחזיר null כשאין מונחים.
  @visibleForTesting
  static RegExp? buildAdvancedHighlightPattern(Iterable<String> resultHtmls) {
    final terms = <String>{};
    for (final html in resultHtmls) {
      terms.addAll(SnippetBuilder.extractHighlightedTerms(html));
      if (terms.length >= _maxHighlightTerms) break;
    }

    final sources = <String>[];
    for (final term in terms.take(_maxHighlightTerms)) {
      final literal = buildLiteralPattern(term);
      if (literal != null) sources.add('(?:${literal.source})');
    }
    if (sources.isEmpty) return null;
    return RegExp(sources.join('|'), caseSensitive: false, unicode: true);
  }

  @override
  State<PdfBookSearchView> createState() => PdfBookSearchViewState();
}

class PdfBookSearchViewState extends State<PdfBookSearchView> {
  final ItemScrollController _resultsScrollController = ItemScrollController();

  bool _isSearching = false;
  List<SearchResult> _searchResults = [];

  /// מוצגת במקום "אין תוצאות" הגנרי: כשל מנוע/FFI או ספר שאינו באינדקס.
  String? _searchErrorMessage;
  String? _bookPath;
  final Map<int, String> _pageTitles = <int, String>{};

  bool _forceSearchEngine = false;

  Map<String, Map<String, bool>> _searchOptions = {};
  Map<int, List<String>> _alternativeWords = {};
  Map<String, String> _spacingValues = {};
  SearchMode _searchMode = SearchMode.exact;
  int _searchDistance = 0;
  SearchMatchPolicy _matchPolicy = SearchMatchPolicy.standard;

  Timer? _pdfHighlightDebounce;
  String _lastPdfHighlightSource = '';
  int _searchGeneration = 0;

  /// התבנית שנבנתה מהמונחים שהמנוע מצא בפועל — לשימוש חוזר בלחיצה על תוצאה.
  RegExp? _lastAdvancedHighlightPattern;

  /// השאילתה שעבורה תוזמנה גלילה לעמוד הנוכחי בסיום חיפוש פשוט.
  /// בחיפוש פשוט התוצאות מגיעות אסינכרונית דרך ה-listener של pdfrx, ולכן
  /// אי אפשר לגלול ב-_searchTextUpdated. השדה נדלק שם וייושם בסיום החיפוש —
  /// רק אם השאילתה עדיין תואמת למה שהמשתמש מקליד, כדי למנוע גלילה על
  /// תוצאות מיושנות (race) של חיפוש קודם.
  String? _pendingSimpleSearchScrollFor;

  bool get _isSimpleSearch =>
      !_forceSearchEngine && _searchMode == SearchMode.exact;

  void _updateForceSearchEngine() {
    _forceSearchEngine = !InBookSearchRouting.canRunAsSimpleSearch(
      searchMode: _searchMode,
      distance: _searchDistance,
      searchOptions: _searchOptions,
      alternativeWords: _alternativeWords,
      spacingValues: _spacingValues,
      matchPolicy: _matchPolicy,
    );
  }

  SearchModeScopedParameters get _activeSearchParameters {
    return SearchQueryBuilder.normalizeParametersForMode(
      _searchMode,
      customSpacing: _spacingValues,
      alternativeWords: _alternativeWords,
      searchOptions: _searchOptions,
    );
  }

  int _getPdfPageNumber(SearchResult result) => result.segment.toInt() + 1;

  void _schedulePdfHighlight(RegExp? pattern) {
    final source = pattern?.pattern ?? '';
    if (source == _lastPdfHighlightSource) return;
    _lastPdfHighlightSource = source;

    _pdfHighlightDebounce?.cancel();
    _pdfHighlightDebounce = Timer(const Duration(milliseconds: 250), () {
      widget.textSearcher.startTextSearch(
        pattern ?? '',
        goToFirstMatch: false,
      );
    });
  }

  /// מדגיש על העמוד את מה שהמנוע מצא בפועל (כולל fuzzy/מילים חלופיות).
  void _updateAdvancedHighlight(List<SearchResult> results) {
    final pattern = PdfBookSearchView.buildAdvancedHighlightPattern(
      results.map((r) => r.text),
    );
    _lastAdvancedHighlightPattern = pattern;
    _schedulePdfHighlight(pattern);
  }

  @override
  void initState() {
    super.initState();
    _searchOptions = widget.initialSearchOptions;
    _alternativeWords = widget.initialAlternativeWords;
    _spacingValues = widget.initialSpacingValues;
    _searchMode = widget.initialSearchMode;
    _searchDistance = widget.initialSearchDistance;
    _matchPolicy = widget.initialMatchPolicy;
    _updateForceSearchEngine();
    // התצורה הממתינה כבר משוקפת בערכי האתחול; אין להחילה שוב.
    widget.incomingSearchConfiguration?.value = null;
    widget.incomingSearchConfiguration?.addListener(
      _onIncomingSearchConfiguration,
    );
    widget.textSearcher.addListener(_onTextSearcherMatchesChanged);
    widget.searchController.addListener(_searchTextUpdated);
    _initializeBookPath();
  }

  /// מחילה קונפיגורציית חיפוש שהגיעה מפתיחת תוצאה בספר שכבר פתוח.
  void _onIncomingSearchConfiguration() {
    final notifier = widget.incomingSearchConfiguration;
    final configuration = notifier?.value;
    if (configuration == null) return;
    // הריקון מונע מהטאב לכתוב את השאילתה במסלול נפרד עם תצורה ישנה.
    notifier!.value = null;
    if (!mounted) return;

    _applySearchConfiguration(
      query: configuration.searchText,
      searchOptions: configuration.searchOptions,
      alternativeWords: configuration.alternativeWords,
      spacingValues: configuration.spacingValues,
      searchMode: configuration.searchMode,
      searchDistance: configuration.searchDistance,
      matchPolicy: configuration.matchPolicy,
      pdfBookBloc: context.read<PdfBookBloc>(),
    );
  }

  Future<void> _initializeBookPath() async {
    final title = widget.bookTitle?.trim();
    if (title == null || title.isEmpty) return;

    final topics = await BookFacet.resolveTopics(
      title: title,
      initialTopics: widget.bookTopics ?? '',
      type: PdfBook,
      categoryPath: widget.bookCategoryPath,
      externalLibraryId: widget.externalLibraryId,
      bookId: widget.bookId,
      fileType: 'pdf',
      filePath: widget.pdfFilePath,
    );

    if (!mounted) return;

    _bookPath = BookFacet.buildFacetPath(
      title: title,
      topics: topics,
      bookId: widget.bookId,
      isUserBook: widget.isUserBook,
      externalLibraryId: widget.externalLibraryId,
      categoryPath: widget.bookCategoryPath,
      fileType: 'pdf',
      filePath: widget.pdfFilePath,
    );

    if (widget.searchController.text.isNotEmpty && mounted) {
      _searchTextUpdated();
    }
  }

  void _onTextSearcherMatchesChanged() {
    if (_isSimpleSearch) {
      if (mounted) {
        setState(() {
          final query = widget.searchController.text;
          _searchResults =
              widget.textSearcher.matches
                  .map(
                    (m) => SearchResult(
                      id: BigInt.zero,
                      title: widget.bookTitle ?? '',
                      reference: '', // Populated by _pageTitles in build
                      // Use query as text so it appears in the list and is highlighted.
                      // Ideally we would fetch the surrounding text but that requires async page loading.
                      text: query,
                      segment: BigInt.from(m.pageNumber - 1),
                      isPdf: true,
                      filePath: widget.pdfFilePath ?? '',
                      mergedCount: 1,
                      merged: const [],
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.segment.compareTo(b.segment));
          _isSearching = widget.textSearcher.isSearching;
        });
        // גלילה לעמוד הנוכחי בסיום החיפוש — רק אם השאילתה הממתינה עדיין
        // תואמת למה שמופיע בשדה החיפוש. זה מונע גלילה על תוצאות מיושנות
        // של חיפוש פשוט קודם שהסתיים אחרי שהמשתמש כבר שינה את השאילתה.
        final pendingQuery = _pendingSimpleSearchScrollFor;
        if (pendingQuery != null &&
            !_isSearching &&
            _searchResults.isNotEmpty) {
          var controllerQuery = widget.searchController.text.trim();
          if (utils.hasNikud(controllerQuery)) {
            controllerQuery = utils.removeVolwels(controllerQuery);
          }
          if (pendingQuery == controllerQuery) {
            _pendingSimpleSearchScrollFor = null;
            _scheduleScrollToCurrentPage();
          }
        }
      }
    }
  }

  void _scheduleScrollToCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final pdfState = context.read<PdfBookBloc>().state;
      if (pdfState is! PdfBookLoaded) return;

      final resultsPageNumbers = _searchResults.map(_getPdfPageNumber).toList();
      if (resultsPageNumbers.isEmpty) return;

      final visualIdx = PdfBookSearchView.computeTargetVisualIndexForTesting(
        resultsPageNumbersSorted: resultsPageNumbers,
        currentPage: pdfState.currentPageNumber,
      );

      if (!_resultsScrollController.isAttached) return;
      _resultsScrollController.jumpTo(index: visualIdx, alignment: 0.0);
    });
  }

  @override
  void dispose() {
    widget.incomingSearchConfiguration?.removeListener(
      _onIncomingSearchConfiguration,
    );
    widget.textSearcher.removeListener(_onTextSearcherMatchesChanged);
    widget.searchController.removeListener(_searchTextUpdated);
    _pdfHighlightDebounce?.cancel();
    super.dispose();
  }

  /// מחיל את הפרמטרים שחזרו מדיאלוג החיפוש המתקדם ומריץ חיפוש מחדש.
  ///
  /// חוזרים למסלול החיפוש הפשוט כשכל הפרמטרים ריקים והמצב מדויק.
  void applySearchDialogResult(
    SearchDialogResult result,
    PdfBookBloc pdfBookBloc,
  ) {
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      result.searchMode,
      customSpacing: result.spacingValues,
      alternativeWords: result.alternativeWords,
      searchOptions: result.searchOptions,
    );

    _applySearchConfiguration(
      query: result.query,
      searchOptions: normalizedParameters.searchOptions,
      alternativeWords: normalizedParameters.alternativeWords,
      spacingValues: normalizedParameters.customSpacing,
      searchMode: result.searchMode,
      searchDistance: result.distance,
      matchPolicy: result.matchPolicy,
      pdfBookBloc: pdfBookBloc,
    );
  }

  /// מחילה את התצורה לפני השאילתה ומריצה חיפוש אחד בלבד.
  void _applySearchConfiguration({
    required String query,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
    required Map<String, String> spacingValues,
    required SearchMode searchMode,
    required int searchDistance,
    required SearchMatchPolicy matchPolicy,
    required PdfBookBloc pdfBookBloc,
  }) {
    final queryChanged = widget.searchController.text != query;

    setState(() {
      _searchOptions = searchOptions;
      _alternativeWords = alternativeWords;
      _spacingValues = spacingValues;
      _searchMode = searchMode;
      _searchDistance = searchDistance;
      _matchPolicy = matchPolicy;
      _updateForceSearchEngine();
    });
    pdfBookBloc.add(
      UpdateSearchOptions(
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        searchDistance: searchDistance,
        matchPolicy: matchPolicy,
      ),
    );

    syncSearchControllerQuery(widget.searchController, query);
    if (!queryChanged) {
      _searchTextUpdated();
    }
  }

  Future<void> _searchTextUpdated() async {
    // כל שינוי בשאילתה/במצב החיפוש מבטל תוצאות אסינכרוניות ישנות. בלי מזהה
    // דור, חיפוש איטי קודם יכול להסתיים אחרי החדש ולדרוס תוצאות והדגשות.
    final generation = ++_searchGeneration;
    String query = widget.searchController.text.trim();

    if (query.isEmpty || (!_isSimpleSearch && _bookPath == null)) {
      // איפוס גלילה ממתינה כדי שתוצאות מיושנות לא יגרמו לקפיצה אחרי
      // ניקוי השדה.
      _pendingSimpleSearchScrollFor = null;
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _searchErrorMessage = null;
        });
      }
      _lastAdvancedHighlightPattern = null;
      if (_isSimpleSearch) {
        widget.textSearcher.startTextSearch('', goToFirstMatch: false);
      } else {
        _schedulePdfHighlight(null);
      }
      return;
    }

    if (utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }

    // איפוס השגיאה לפני פיצול המסלול — במסלול הפשוט התוצאות מגיעות
    // אסינכרונית, ובלי האיפוס כאן שגיאת מנוע קודמת נשארת מוצגת.
    if (mounted) {
      setState(() {
        _searchErrorMessage = null;
        if (!_isSimpleSearch) _isSearching = true;
      });
    }

    if (_isSimpleSearch) {
      _pdfHighlightDebounce?.cancel();
      _pendingSimpleSearchScrollFor = query;
      // תבנית סובלנית-ניקוד מהמנוע, כדי שגם PDF ששכבת הטקסט שלו מנוקדת יודגש.
      final literal = buildLiteralPattern(query);
      _lastPdfHighlightSource = literal?.source ?? query;
      widget.textSearcher.startTextSearch(
        literal?.regExp ?? query,
        goToFirstMatch: false,
      );
      return;
    }

    try {
      final activeParameters = _activeSearchParameters;
      final rawResults = await widget.searchRepository.searchTexts(
        query,
        [_bookPath!],
        1000,
        searchOptions: activeParameters.searchOptions,
        alternativeWords: activeParameters.alternativeWords,
        customSpacing: activeParameters.customSpacing,
        fuzzy: _searchMode == SearchMode.fuzzy,
        distance: _searchDistance,
        searchMode: _searchMode,
        scope: _matchPolicy.proximityScope,
        wordMatchMode: _matchPolicy.wordMatchMode,
        wordMatchCount: _matchPolicy.wordMatchCount,
        order: ResultsOrder.catalogue,
      );

      final pdfPath = widget.pdfFilePath;
      final results =
          rawResults
              .where((r) {
                if (!r.isPdf) return false;
                if (pdfPath == null || pdfPath.isEmpty) return true;
                return r.filePath == pdfPath;
              })
              .toList(growable: true)
            ..sort((a, b) {
              final sa = a.segment.toInt();
              final sb = b.segment.toInt();
              if (sa != sb) return sa.compareTo(sb);
              return a.reference.compareTo(b.reference);
            });

      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        if (results.isEmpty) {
          _searchErrorMessage = PdfBookSearchView.missingFromIndexNotice(
            pdfFilePath: widget.pdfFilePath,
            indexInitialized: TantivyDataProvider.instance.isInitialized.value,
            indexedFilePaths: TantivyDataProvider.instance.indexedFilePaths,
          );
        }
      });
      _updateAdvancedHighlight(results);
      _scheduleScrollToCurrentPage();
    } catch (e, st) {
      debugPrint('[PdfSearch] search failed for "$query": $e\n$st');
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchErrorMessage = PdfMessages.searchError;
      });
      _updateAdvancedHighlight(const []);
      UiSnack.showError(PdfMessages.searchError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, List<SearchResult>> resultsByPage = {};
    for (final result in _searchResults) {
      final pageNumber = _getPdfPageNumber(result);
      resultsByPage.putIfAbsent(pageNumber, () => []).add(result);
    }

    final List<dynamic> items = [];
    for (final entry
        in resultsByPage.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      items.add(entry.key);
      items.addAll(entry.value);

      if (!_pageTitles.containsKey(entry.key)) {
        () async {
          final title = await refFromPageNumber(
            entry.key,
            widget.outline,
            widget.bookTitle,
          );
          if (!mounted) return;
          setState(() {
            _pageTitles[entry.key] = title;
          });
        }();
      }
    }

    return SearchPaneBase(
      searchController: widget.searchController,
      focusNode: widget.focusNode,
      progressWidget: _isSearching
          ? const LinearProgressIndicator(minHeight: 4)
          : null,
      resultCountString: _searchResults.isNotEmpty
          ? 'נמצאו ${_searchResults.length} תוצאות'
          : null,
      resultsWidget: NavTreeFocusGroup(
        child: ScrollablePositionedList.builder(
          itemScrollController: _resultsScrollController,
          padding: kNavTreeListPadding,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            // הקבוצה נפתחת אחרי כותרת עמוד ונסגרת לפני הכותרת הבאה.
            final isGroupStart = index == 0 || items[index - 1] is int;
            final isGroupEnd =
                index == items.length - 1 || items[index + 1] is int;

            if (item is int) {
              return BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  var text = _pageTitles[item]?.isNotEmpty == true
                      ? _pageTitles[item]!
                      : 'עמוד $item';

                  if (settingsState.replaceHolyNames) {
                    text = utils.replaceHolyNames(text);
                  }

                  return NavTreeHeader(title: text);
                },
              );
            }

            final result = item as SearchResult;
            return NavTreeGroupCard(
              isGroupStart: isGroupStart,
              isGroupEnd: isGroupEnd,
              child: SearchResultTile(
                key: ValueKey('${result.segment}_${result.text.hashCode}'),
                result: result,
                onTap: () async {
                  final pageNumber = _getPdfPageNumber(result);
                  final controller = widget.textSearcher.controller;
                  if (controller != null &&
                      controller.isReady &&
                      controller.layout.pageLayouts.isNotEmpty) {
                    final layout = controller.layout;
                    final safePage = pageNumber.clamp(
                      1,
                      layout.pageLayouts.length,
                    );
                    final page = layout.pageLayouts[safePage - 1];
                    final halfViewHeight =
                        controller.viewSize.height / 2 / controller.value.zoom;
                    await controller.goTo(
                      controller.calcMatrixFor(
                        page.topCenter.translate(0, halfViewHeight),
                      ),
                    );
                  }

                  _schedulePdfHighlight(
                    _isSimpleSearch
                        ? buildLiteralPattern(
                            widget.searchController.text,
                          )?.regExp
                        : _lastAdvancedHighlightPattern,
                  );
                  widget.onSearchResultNavigated?.call();
                },
                height: 50,
                query: widget.searchController.text,
                isSimpleSearch: _isSimpleSearch,
              ),
            );
          },
        ),
      ),
      isNoResults:
          widget.searchController.text.isNotEmpty &&
          _searchResults.isEmpty &&
          !_isSearching,
      errorMessage: _searchErrorMessage,
      onSearchTextChanged: (_) => _searchTextUpdated(),
      resetSearchCallback: () {
        _pendingSimpleSearchScrollFor = null;
        _lastAdvancedHighlightPattern = null;
        setState(() {
          _searchResults = [];
          _searchErrorMessage = null;
          _forceSearchEngine = false;
          _searchOptions = {};
          _alternativeWords = {};
          _spacingValues = {};
          _searchMode = SearchMode.exact;
          _searchDistance = 0;
          _matchPolicy = SearchMatchPolicy.standard;
        });
        context.read<PdfBookBloc>().add(
          const UpdateSearchOptions(
            searchOptions: {},
            alternativeWords: {},
            spacingValues: {},
            searchMode: SearchMode.exact,
            searchDistance: 0,
            matchPolicy: SearchMatchPolicy.standard,
          ),
        );
        _schedulePdfHighlight(null);
      },
      additionalActions: const [],
      hintText: 'חפש כאן..',
      onAdvancedSearch: () async {
        final pdfBookBloc = context.read<PdfBookBloc>();
        // ראה הערה מקבילה ב-text_book_search_screen.dart: initialConfiguration
        // נמנעת מ-race condition של events ו-dispose נדחה ל-frame הבא כדי
        // למנוע FocusNode disposed בזמן rebuild של ה-dialog.
        final tempTab = SearchingTab(
          'חיפוש',
          widget.searchController.text,
          initialConfiguration: SearchConfiguration.forInBookSearch(
            searchMode: _searchMode,
            distance: _searchDistance,
            matchPolicy: _matchPolicy,
          ),
        );
        tempTab.searchOptions.addAll(_searchOptions);
        tempTab.alternativeWords.addAll(_alternativeWords);
        tempTab.spacingValues.addAll(_spacingValues);

        final result = await showDialog<SearchDialogResult>(
          context: context,
          builder: (context) => SearchDialog(
            existingTab: tempTab,
            bookTitle: widget.bookTitle,
            returnResultOnSubmit: true,
          ),
        );

        // ראה הערה ב-text_book_search_screen: דחיה של 500ms מאפשרת ל-dialog
        // fade-out animation להסתיים לפני שחרור ה-FocusNode.
        Future.delayed(const Duration(milliseconds: 500), () {
          tempTab.dispose();
        });

        if (!mounted || result == null) {
          return;
        }

        applySearchDialogResult(result, pdfBookBloc);
      },
    );
  }
}

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.result,
    required this.onTap,
    required this.height,
    required this.query,
    required this.isSimpleSearch,
    super.key,
  });

  final SearchResult result;
  final void Function() onTap;
  final double height;
  final String query;
  final bool isSimpleSearch;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final text = _createHighlightedText(
          result.text,
          query,
          isSimpleSearch,
          settingsState,
          context,
        );

        return NavTreeContentRow(onTap: onTap, child: text);
      },
    );
  }

  Widget _createHighlightedText(
    String text,
    String query,
    bool isSimpleSearch,
    SettingsState settingsState,
    BuildContext context,
  ) {
    final defaultStyle = TextStyle(
      fontSize: 16,
      fontFamily: settingsState.fontFamily,
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.5,
    );

    var html = text;
    if (settingsState.replaceHolyNames) {
      html = utils.replaceHolyNames(html);
    }

    if (query.isEmpty) {
      return Text(
        utils.stripHtmlIfNeeded(html),
        style: defaultStyle,
      );
    }

    final highlightStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 18,
      color: Theme.of(context).colorScheme.error,
    );

    if (isSimpleSearch) {
      final spans = SnippetBuilder.highlightLiteral(
        plainText: utils.stripHtmlIfNeeded(html),
        query: query,
        defaultStyle: defaultStyle,
        highlightStyle: highlightStyle,
      );

      return Text.rich(
        TextSpan(
          children: spans,
          style: defaultStyle,
        ),
      );
    }

    // המנוע מחזיר את ההתאמות מסומנות בתגי הדגשה בתוך ה-HTML.
    final spans = SnippetBuilder.fromHighlightedHtml(
      html: html,
      defaultStyle: defaultStyle,
      highlightStyle: highlightStyle,
    );

    return Text.rich(
      TextSpan(
        children: spans,
        style: defaultStyle,
      ),
    );
  }
}
