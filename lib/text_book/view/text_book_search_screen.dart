import 'dart:async';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/utils/search_query_sync.dart';

class _GroupedResultItem {
  final String? header;
  final TextSearchResult? result;
  final int? resultListIndex;
  const _GroupedResultItem.header(this.header)
    : result = null,
      resultListIndex = null;
  const _GroupedResultItem.result(this.result, this.resultListIndex)
    : header = null;
  bool get isHeader => header != null;
}

class TextBookSearchView extends StatefulWidget {
  /// טוען את תוכן הספר המלא (שורות) לפי דרישה — רק כשחיפוש פשוט רץ בפועל.
  /// כך החיפוש אינו תלוי ב-state.content, שיכול להיות חלקי או משוחרר.
  final Future<List<String>> Function() contentLoader;
  final ItemScrollController scrollControler;
  final FocusNode focusNode;
  final void Function() closeLeftPaneCallback;
  final String initialQuery;
  final Map<String, Map<String, bool>> initialSearchOptions;
  final Map<int, List<String>> initialAlternativeWords;
  final Map<String, String> initialSpacingValues;
  final SearchMode initialSearchMode;
  final int initialSearchDistance;
  final Future<List<TextSearchResult>> Function(
    List<String> content,
    String query,
  )?
  simpleSearchRunner;

  const TextBookSearchView({
    super.key,
    required this.contentLoader,
    required this.scrollControler,
    required this.focusNode,
    required this.closeLeftPaneCallback,
    required this.initialQuery,
    this.initialSearchOptions = const {},
    this.initialAlternativeWords = const {},
    this.initialSpacingValues = const {},
    this.initialSearchMode = SearchMode.exact,
    this.initialSearchDistance = 0,
    this.simpleSearchRunner,
  });

  @override
  TextBookSearchViewState createState() => TextBookSearchViewState();
}

class TextBookSearchViewState extends State<TextBookSearchView>
    with AutomaticKeepAliveClientMixin<TextBookSearchView> {
  TextEditingController searchTextController = TextEditingController();
  final SearchRepository _searchRepository = SearchRepository();
  List<TextSearchResult> searchResults = [];
  late ItemScrollController scrollControler;
  bool _isSearching = false;

  /// הודעת שגיאה אחרונה בחיפוש (כשל מנוע/FFI). ראו doc ב-[SearchPaneBase].
  String? _searchErrorMessage;
  List<String>? _content;
  Future<List<String>>? _contentFuture;
  String? _bookPath;
  String? _bookTitle;
  bool _forceSearchEngine = false;
  Map<String, Map<String, bool>> _searchOptions = {};
  Map<int, List<String>> _alternativeWords = {};
  Map<String, String> _spacingValues = {};
  SearchMode _searchMode = SearchMode.exact;
  int _searchDistance = 0;
  int? _selectedSearchResultIndex;
  // מספר השורה בספר של התוצאה הנבחרת — משמש לשמירת הבחירה לפי זהות בין
  // חיפושים. אינדקס סידורי לבדו אינו אמין כי תוכן הרשימה משתנה כשהשאילתה
  // משתנה. ההיסט מבחין בין כמה הופעות באותה שורה.
  int? _selectedResultLine;
  int? _selectedResultOffset;
  int _activeSearchRequestId = 0;
  final ItemScrollController _resultsScrollController = ItemScrollController();
  final ItemPositionsListener _resultsPositionsListener =
      ItemPositionsListener.create();

  bool get _isSimpleSearch =>
      !_forceSearchEngine && _searchMode == SearchMode.exact;

  static const int _maxResultSnippetChars = 220;

  SearchMode _normalizedSearchMode(SearchMode searchMode) {
    return searchMode;
  }

  bool _searchOptionsEqual(
    Map<String, Map<String, bool>> first,
    Map<String, Map<String, bool>> second,
  ) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;

    for (final key in first.keys) {
      final firstValue = first[key];
      final secondValue = second[key];
      if (firstValue == null || secondValue == null) return false;
      if (!mapEquals(firstValue, secondValue)) return false;
    }

    return true;
  }

  bool _alternativeWordsEqual(
    Map<int, List<String>> first,
    Map<int, List<String>> second,
  ) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;

    for (final key in first.keys) {
      final firstValue = first[key];
      final secondValue = second[key];
      if (firstValue == null || secondValue == null) return false;
      if (!listEquals(firstValue, secondValue)) return false;
    }

    return true;
  }

  SearchModeScopedParameters get _activeSearchParameters {
    return SearchQueryBuilder.normalizeParametersForMode(
      _searchMode,
      customSpacing: _spacingValues,
      alternativeWords: _alternativeWords,
      searchOptions: _searchOptions,
    );
  }

  void _updateForceSearchEngine() {
    final activeParameters = _activeSearchParameters;
    _forceSearchEngine =
        _searchMode != SearchMode.exact ||
        _searchDistance > 0 ||
        activeParameters.searchOptions.isNotEmpty ||
        activeParameters.alternativeWords.isNotEmpty ||
        activeParameters.customSpacing.isNotEmpty;
  }

  void _syncSearchConfigurationFromWidget() {
    _searchOptions = widget.initialSearchOptions;
    _alternativeWords = widget.initialAlternativeWords;
    _spacingValues = widget.initialSpacingValues;
    _searchMode = _normalizedSearchMode(widget.initialSearchMode);
    _searchDistance = widget.initialSearchDistance;
    _updateForceSearchEngine();
  }

  void _syncBlocSearchTextState() {
    final activeParameters = _activeSearchParameters;
    context.read<TextBookBloc>().add(
      UpdateSearchText(
        searchTextController.text,
        searchOptions: activeParameters.searchOptions,
        alternativeWords: activeParameters.alternativeWords,
        spacingValues: activeParameters.customSpacing,
        searchMode: _searchMode,
        searchDistance: _searchDistance,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    searchTextController.text = widget.initialQuery;
    _syncSearchConfigurationFromWidget();
    _syncBlocSearchTextState();

    scrollControler = widget.scrollControler;
    widget.focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBookPath();
    });
  }

  @override
  void didUpdateWidget(TextBookSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // עדכון שדה החיפוש אם initialQuery השתנה
    final queryChanged = widget.initialQuery != oldWidget.initialQuery;
    final needsControllerSync =
        widget.initialQuery != searchTextController.text;
    final normalizedSearchMode = _normalizedSearchMode(
      widget.initialSearchMode,
    );
    final searchConfigurationChanged =
        !_searchOptionsEqual(_searchOptions, widget.initialSearchOptions) ||
        !_alternativeWordsEqual(
          _alternativeWords,
          widget.initialAlternativeWords,
        ) ||
        !mapEquals(_spacingValues, widget.initialSpacingValues) ||
        _searchMode != normalizedSearchMode ||
        _searchDistance != widget.initialSearchDistance;

    if (queryChanged && needsControllerSync) {
      syncSearchControllerQuery(searchTextController, widget.initialQuery);
    }

    if (searchConfigurationChanged) {
      _syncSearchConfigurationFromWidget();
    }

    // הרצת חיפוש מ-didUpdateWidget רק כששינוי ה-query מקורו חיצוני (ה-controller
    // עדיין לא מסונכרן) או כשהקונפיגורציה השתנתה. שינוי query שכבר משוקף
    // ב-controller הוא ההד של הקלדה ש-onSearchTextChanged כבר טיפל בה — הרצה
    // נוספת כאן רק מכפילה את העבודה.
    final isExternalQueryChange = queryChanged && needsControllerSync;
    if (isExternalQueryChange || searchConfigurationChanged) {
      _syncBlocSearchTextState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchTextUpdated();
        }
      });
    }
  }

  Future<void> _initializeBookPath() async {
    if (!mounted) return;
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      final bookTitle = state.book.title;
      debugPrint('📚 TextBookSearch: book.title = $bookTitle');

      _bookTitle = bookTitle;

      final topics = await BookFacet.resolveTopics(
        title: bookTitle,
        initialTopics: state.book.topics,
        type: TextBook,
        categoryPath: state.book.categoryPath,
        externalLibraryId: state.book.externalLibraryId,
        bookId: state.book.id,
        fileType: state.book.fileType,
        filePath: state.book.filePath,
      );

      if (!mounted) return;

      debugPrint('📚 TextBookSearch: final topics = "$topics"');
      _bookPath = BookFacet.buildFacetPath(
        title: bookTitle,
        topics: topics,
        bookId: state.book.id,
        isUserBook: state.book.isUserBook,
        externalLibraryId: state.book.externalLibraryId,
        categoryPath: state.book.categoryPath,
        fileType: state.book.fileType,
        filePath: state.book.filePath,
      );
      debugPrint('📚 TextBookSearch: _bookPath = $_bookPath');
      if (searchTextController.text.isNotEmpty) {
        _runInitialSearch();
      }
    }
  }

  void _runInitialSearch() {
    _searchTextUpdated();
  }

  /// טוען את תוכן הספר פעם אחת ושומר אותו לחיי החלונית. כישלון מאפס את
  /// ה-Future כדי לאפשר ניסיון חוזר בחיפוש הבא.
  Future<List<String>> _ensureContent() async {
    final existing = _contentFuture;
    if (existing != null) {
      return existing;
    }
    final future = widget.contentLoader();
    _contentFuture = future;
    try {
      final lines = await future;
      _content = lines;
      return lines;
    } catch (_) {
      if (identical(_contentFuture, future)) {
        _contentFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _searchTextUpdated() async {
    final requestId = ++_activeSearchRequestId;
    String query = searchTextController.text.trim();
    if (query.isEmpty ||
        (!_isSimpleSearch && (_bookPath == null || _bookTitle == null))) {
      setState(() {
        searchResults = [];
        _isSearching = false;
        _searchErrorMessage = null;
      });
      return;
    }

    if (utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }

    setState(() {
      _isSearching = true;
      _searchErrorMessage = null;
    });

    if (_isSimpleSearch) {
      List<String> content;
      try {
        content = await _ensureContent();
      } catch (e) {
        debugPrint('טעינת תוכן הספר לחיפוש נכשלה: $e');
        if (mounted && requestId == _activeSearchRequestId) {
          UiSnack.showError(TextBookMessages.searchContentLoadFailed);
          setState(() {
            searchResults = [];
            _isSearching = false;
          });
        }
        return;
      }
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }

      final effectiveResults = widget.simpleSearchRunner != null
          ? await widget.simpleSearchRunner!(content, query)
          : await searchInContent(
              content: content,
              query: query,
            );

      if (mounted && requestId == _activeSearchRequestId) {
        _applySearchResults(effectiveResults);
      }
      return;
    }

    try {
      // The facet filter is a prefix filter in the underlying engine, so when a
      // book is a parent facet (e.g. /.../ספר הזהר) it may also match child
      // facets like commentaries. We therefore post-filter by exact title.
      //
      // Use a higher raw limit to avoid losing relevant results that would have
      // been returned after filtering.
      const rawLimit = 5000;
      const displayLimit = 1000;

      final List<SearchResult> rawResults;
      final activeParameters = _activeSearchParameters;
      rawResults = await _searchRepository.searchTexts(
        query,
        [_bookPath!],
        rawLimit,
        searchOptions: activeParameters.searchOptions,
        alternativeWords: activeParameters.alternativeWords,
        customSpacing: activeParameters.customSpacing,
        fuzzy: _searchMode == SearchMode.fuzzy,
        distance: _searchDistance,
        searchMode: _searchMode,
        order: ResultsOrder.catalogue,
      );

      final expectedTitle = _bookTitle!.trim();

      final filtered = rawResults
          .where((r) => !r.isPdf && r.title.trim() == expectedTitle)
          .toList(growable: false);

      // In-book search should be presented in reading order (by segment/line),
      // not by relevance.
      final sorted = filtered.toList(growable: true)
        ..sort((a, b) {
          final sa = a.segment.toInt();
          final sb = b.segment.toInt();
          if (sa != sb) return sa.compareTo(sb);

          final ra = a.reference;
          final rb = b.reference;
          final rc = ra.compareTo(rb);
          if (rc != 0) return rc;

          return a.text.compareTo(b.text);
        });

      final results = sorted.take(displayLimit).toList(growable: false);

      debugPrint(
        '📚 TextBookSearch: rawResults=${rawResults.length}, '
        'filteredResults=${results.length}, title="$expectedTitle"',
      );

      if (mounted && requestId == _activeSearchRequestId) {
        _applySearchResults(_convertSearchResults(results));
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted && requestId == _activeSearchRequestId) {
        UiSnack.showError(LibraryMessages.searchError);
        setState(() {
          searchResults = [];
          _isSearching = false;
          _selectedSearchResultIndex = null;
          _searchErrorMessage = LibraryMessages.searchError;
        });
      }
    }
  }

  void _applySearchResults(List<TextSearchResult> results) {
    // שמירת בחירה לפי זהות (שורה בספר), לא לפי אינדקס סידורי.
    // אינדקס סידורי לא יציב כי תוכן הרשימה משתנה בין חיפושים.
    int? selectedIndex;
    final lastSelectedLine = _selectedResultLine;
    if (lastSelectedLine != null) {
      // התאמה מלאה (שורה + היסט הופעה), ואם לא נמצאה — לפי שורה בלבד
      // (השאילתה השתנתה וההיסטים זזו, או תוצאות מנוע ללא היסט).
      var preservedIdx = results.indexWhere(
        (r) =>
            r.index == lastSelectedLine &&
            r.matchOffset == _selectedResultOffset,
      );
      if (preservedIdx == -1) {
        preservedIdx = results.indexWhere((r) => r.index == lastSelectedLine);
      }
      if (preservedIdx != -1) {
        selectedIndex = preservedIdx;
      }
    }

    // יעד הגלילה: אם זוהתה אותה תוצאה — גלול אליה.
    // אחרת — חפש את התוצאה הראשונה מהשורה הנוכחית בספר והלאה;
    // אם כל התוצאות לפני המיקום הנוכחי, גלול לאחרונה (הקרובה ממעל).
    int? scrollIndex;
    if (results.isNotEmpty) {
      if (selectedIndex != null) {
        scrollIndex = selectedIndex;
      } else {
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded && state.visibleIndices.isNotEmpty) {
          final currentLine = state.visibleIndices.first;
          final idx = results.indexWhere((r) => r.index >= currentLine);
          scrollIndex = idx != -1 ? idx : results.length - 1;
        } else {
          scrollIndex = 0;
        }
        // התאמת הבחירה הראשונית כך שניווט בחצים יתחיל מהתוצאה הקרובה למיקום.
        selectedIndex = scrollIndex;
      }
    }

    setState(() {
      searchResults = results;
      _isSearching = false;
      _selectedSearchResultIndex = selectedIndex;
      _selectedResultLine = selectedIndex != null
          ? results[selectedIndex].index
          : null;
      _selectedResultOffset = selectedIndex != null
          ? results[selectedIndex].matchOffset
          : null;
    });

    if (scrollIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollResultsToIndex(scrollIndex!);
      });
    }
  }

  /// מחזיר את האינדקס הוויזואלי (בתוך הרשימה המקובצת) של תוצאה.
  /// אם התוצאה פותחת קטע חדש, מחזיר את אינדקס הכותרת (כדי שתהיה גלויה).
  int _visualIndexForResultListIndex(int target) {
    int idx = 0;
    String? lastAddress;
    for (var i = 0; i < searchResults.length; i++) {
      final r = searchResults[i];
      final isNewSection = r.address != lastAddress;
      if (isNewSection) {
        lastAddress = r.address;
        if (i == target) return idx; // גלול לכותרת
        idx++;
      }
      if (i == target) return idx;
      idx++;
    }
    return 0;
  }

  /// מחזיר את האינדקס הוויזואלי של שורת התוצאה עצמה (בלי הכותרת שלפניה).
  /// משמש לבדיקת נראות בניווט בחצים — נראות הכותרת אינה מבטיחה שהשורה גלויה.
  int _visualIndexForResultRow(int target) {
    int idx = 0;
    String? lastAddress;
    for (var i = 0; i < searchResults.length; i++) {
      final r = searchResults[i];
      if (r.address != lastAddress) {
        lastAddress = r.address;
        idx++;
      }
      if (i == target) return idx;
      idx++;
    }
    return 0;
  }

  /// גולל את רשימת התוצאות לאינדקס הוויזואלי המדויק.
  ///
  /// כש‑[onlyIfNotVisible] true, מדלגים על הגלילה אם היעד כבר גלוי לחלוטין —
  /// כדי שניווט בחצים בין תוצאות סמוכות לא יזיז את הרשימה ללא צורך.
  void _scrollResultsToIndex(
    int resultListIndex, {
    bool onlyIfNotVisible = false,
  }) {
    if (!mounted) return;
    if (!_resultsScrollController.isAttached) return;

    if (onlyIfNotVisible) {
      final rowIdx = _visualIndexForResultRow(resultListIndex);
      final positions = _resultsPositionsListener.itemPositions.value;
      for (final p in positions) {
        if (p.index == rowIdx &&
            p.itemLeadingEdge >= 0.0 &&
            p.itemTrailingEdge <= 1.0) {
          return;
        }
      }
    }

    final visualIdx = _visualIndexForResultListIndex(resultListIndex);
    _resultsScrollController.jumpTo(index: visualIdx, alignment: 0.0);
  }

  void _navigateToSearchResult(
    int resultListIndex, {
    bool closePaneOnAndroid = false,
  }) {
    if (resultListIndex < 0 || resultListIndex >= searchResults.length) {
      return;
    }

    final result = searchResults[resultListIndex];
    setState(() {
      _selectedSearchResultIndex = resultListIndex;
      _selectedResultLine = result.index;
      _selectedResultOffset = result.matchOffset;
    });

    final bloc = context.read<TextBookBloc>();
    bloc.add(UpdateSelectedIndex(result.index));
    bloc.add(HighlightLine(result.index));

    final loadedState = bloc.state;
    if (loadedState is! TextBookLoaded) {
      return;
    }
    final lineText = _lineTextAt(result.index, loadedState);
    final intraLineFraction = lineText == null
        ? 0.0
        : matchFractionInLine(
            lineText,
            result.query,
            matchOffset: result.matchOffset,
          );
    final navigation = scrollToSourceLine(
      scrollController: widget.scrollControler,
      scrollOffsetController: loadedState.scrollOffsetController,
      positionsListener: loadedState.positionsListener,
      segments: loadedState.readingSegments,
      lineIndex: result.index,
      viewportExtent: context.size?.height ?? MediaQuery.sizeOf(context).height,
      duration: const Duration(milliseconds: 250),
      curve: Curves.ease,
      alignment: kSearchResultAnchorAlignment,
      intraLineFraction: intraLineFraction,
    );

    if (closePaneOnAndroid && Platform.isAndroid) {
      unawaited(
        closePaneAfterNavigation(
          navigation: navigation,
          closePane: () {
            if (mounted) widget.closeLeftPaneCallback();
          },
        ),
      );
    } else {
      unawaited(navigation);
    }
  }

  void _moveBetweenResults(int offset) {
    if (searchResults.isEmpty) {
      return;
    }

    final currentIndex =
        _selectedSearchResultIndex ?? (offset >= 0 ? -1 : searchResults.length);
    final nextIndex = (currentIndex + offset).clamp(
      0,
      searchResults.length - 1,
    );
    if (nextIndex == currentIndex) {
      return;
    }

    _navigateToSearchResult(nextIndex);
    _scrollResultsToIndex(nextIndex, onlyIfNotVisible: true);
  }

  /// טקסט השורה לצורך דיוק גלילה אל המילה: קודם התוכן שנטען לחיפוש, ואם
  /// אינו זמין — התוכן שב-state (מלא בטאב פעיל אחרי חימום). null אם השורה
  /// לא זמינה — ואז נופלים לגלילה לתחילת השורה.
  String? _lineTextAt(int index, TextBookLoaded loadedState) {
    if (index < 0) {
      return null;
    }
    final content = _content;
    if (content != null && index < content.length) {
      return content[index];
    }
    if (index < loadedState.content.length) {
      return loadedState.content[index];
    }
    return null;
  }

  List<TextSearchResult> _convertSearchResults(List<SearchResult> results) {
    final state = context.read<TextBookBloc>().state;
    final int? contentLength =
        _content?.length ??
        (state is TextBookLoaded ? state.content.length : null);
    final List<TextSearchResult> converted = [];
    for (final result in results) {
      try {
        final lineNumber = result.segment.toInt();
        if (lineNumber >= 0 &&
            (contentLength == null || lineNumber < contentLength)) {
          converted.add(
            TextSearchResult(
              index: lineNumber,
              snippet: result.text,
              address: result.reference,
              query: searchTextController.text,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error converting result: $e');
      }
    }
    return converted;
  }

  @override
  void dispose() {
    searchTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // יצירת רשימה מקובצת - כותרת מופיעה רק כשהיא משתנה
    final List<_GroupedResultItem> items = [];
    String? lastAddress;
    for (
      var resultListIndex = 0;
      resultListIndex < searchResults.length;
      resultListIndex++
    ) {
      final r = searchResults[resultListIndex];
      if (lastAddress != r.address) {
        items.add(_GroupedResultItem.header(r.address));
        lastAddress = r.address;
      }
      items.add(_GroupedResultItem.result(r, resultListIndex));
    }

    return SearchPaneBase(
      searchController: searchTextController,
      focusNode: widget.focusNode,
      progressWidget: _isSearching
          ? const LinearProgressIndicator(minHeight: 4)
          : null,
      resultToolbar: searchResults.isNotEmpty
          ? _buildSearchResultNavigationBar()
          : null,
      resultCountString: searchResults.isNotEmpty
          ? 'נמצאו ${searchResults.length} תוצאות'
          : null,
      // כשתבנית ההדגשה מבוססת-האינדקס מגיעה (אסינכרונית), ה-snippets מחושבים
      // מחדש כדי לכלול את הווריאנטים שה-fallback החמיץ.
      resultsWidget: ListenableBuilder(
        listenable: utils.highlightPatternRevision,
        builder: (context, _) => ScrollablePositionedList.builder(
          itemScrollController: _resultsScrollController,
          itemPositionsListener: _resultsPositionsListener,
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            // אם זו כותרת קבוצה
            if (item.isHeader) {
              return BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  String text = item.header!;
                  if (settingsState.replaceHolyNames) {
                    text = utils.replaceHolyNames(text);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(
                      top: 8.0,
                      bottom: 8.0,
                      right: 4.0,
                      left: 4.0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          FluentIcons.text_align_right_24_regular,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            // אם זו תוצאה רגילה
            final result = item.result!;
            final resultListIndex = item.resultListIndex!;
            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                String snippet = result.snippet;
                if (settingsState.replaceHolyNames) {
                  snippet = utils.replaceHolyNames(snippet);
                }

                final defaultStyle = TextStyle(
                  fontSize: 16,
                  fontFamily: settingsState.fontFamily,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.5,
                );
                final highlightStyle = TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.error,
                );

                // בחיפוש פשוט התוצאה היא טקסט מקומי — חותכים קטע ומדגישים את
                // השאילתה הליטרלית. בחיפוש מתקדם/מקורב התוצאה מגיעה מהמנוע עם
                // הדגשות מוטמעות ב-HTML.
                final List<InlineSpan> highlightedSnippet;
                if (_isSimpleSearch) {
                  final excerpt = SnippetBuilder.buildExcerptText(
                    fullText: snippet,
                    query: result.query,
                    maxChars: _maxResultSnippetChars,
                  );
                  highlightedSnippet = SnippetBuilder.highlightLiteral(
                    plainText: excerpt,
                    query: result.query,
                    defaultStyle: defaultStyle,
                    highlightStyle: highlightStyle,
                  );
                } else {
                  // המנוע מדגיש את הטוקן השלם; מדגישים מחדש בצד האפליקציה את
                  // החלק המותאם בלבד, בעקביות עם הדגשת פאנל הקריאה. אם לא נמצאה
                  // התאמה (וריאנט שהתבנית לא מכסה) — נשארים בהדגשת המנוע.
                  final plain = SnippetBuilder.htmlToPlainText(snippet);
                  final ranges = utils.computeHighlightRanges(
                    plain,
                    result.query,
                    searchOptions: _searchOptions,
                    alternativeWords: _alternativeWords,
                    spacingValues: _spacingValues,
                    isFuzzy: _searchMode == SearchMode.fuzzy,
                    searchDistance: _searchDistance,
                  );
                  highlightedSnippet = ranges.isEmpty
                      ? SnippetBuilder.fromHighlightedHtml(
                          html: snippet,
                          defaultStyle: defaultStyle,
                          highlightStyle: highlightStyle,
                        )
                      : SnippetBuilder.spansFromRanges(
                          plainText: plain,
                          ranges: ranges,
                          defaultStyle: defaultStyle,
                          highlightStyle: highlightStyle,
                        );
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: _selectedSearchResultIndex == resultListIndex
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    border: Border.all(
                      color: _selectedSearchResultIndex == resultListIndex
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: 1,
                    ),
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: InkWell(
                    onTap: () {
                      _navigateToSearchResult(
                        resultListIndex,
                        closePaneOnAndroid: true,
                      );
                    },
                    borderRadius: AppTokens.borderRadiusAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: RichText(
                        textAlign: TextAlign.justify,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: settingsState.fontFamily,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.5,
                          ),
                          children: highlightedSnippet,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      isNoResults:
          searchResults.isEmpty &&
          searchTextController.text.isNotEmpty &&
          !_isSearching,
      errorMessage: _searchErrorMessage,
      onSearchTextChanged: (value) {
        final activeParameters = _activeSearchParameters;
        context.read<TextBookBloc>().add(
          UpdateSearchText(
            value,
            searchOptions: activeParameters.searchOptions,
            alternativeWords: activeParameters.alternativeWords,
            spacingValues: activeParameters.customSpacing,
            searchMode: _searchMode,
            searchDistance: _searchDistance,
          ),
        );
        _searchTextUpdated();
      },
      resetSearchCallback: () {
        setState(() {
          searchResults = [];
          _searchErrorMessage = null;
          _selectedSearchResultIndex = null;
          _selectedResultLine = null;
          _selectedResultOffset = null;
          _forceSearchEngine = false;
          _searchOptions = {};
          _alternativeWords = {};
          _spacingValues = {};
          _searchMode = SearchMode.exact;
          _searchDistance = 0;
        });
        context.read<TextBookBloc>().add(
          const UpdateSearchText(
            '',
            searchOptions: {},
            alternativeWords: {},
            spacingValues: {},
            searchMode: SearchMode.exact,
            searchDistance: 0,
          ),
        );
      },
      additionalActions: const [],
      hintText: 'חפש כאן...',
      onSubmitted: () => _moveBetweenResults(1),
      onAdvancedSearch: () async {
        // מטמיעים את ה-configuration ישירות ב-Bloc במקום events, כי events
        // אסינכרוניים עלולים לרוץ אחרי שה-dialog פותח חיפוש ראשון.
        final tempTab = SearchingTab(
          'חיפוש',
          searchTextController.text,
          initialConfiguration: SearchConfiguration(
            searchMode: _searchMode,
            distance: _searchDistance,
          ),
        );
        tempTab.searchOptions.addAll(_searchOptions);
        tempTab.alternativeWords.addAll(_alternativeWords);
        tempTab.spacingValues.addAll(_spacingValues);
        // התוצאה החוזרת מהדיאלוג היא תמיד מפת פר-מילה; קריאה במצב גלובלי
        // הייתה קוראת מהמפה הגלובלית הריקה ומאבדת את הבחירות המשוחזרות.
        tempTab.useGlobalSearchOptions.value = false;

        final bookTitle =
            (context.read<TextBookBloc>().state as TextBookLoaded).book.title;

        final result = await showDialog<SearchDialogResult>(
          context: context,
          builder: (dialogContext) => SearchDialog(
            existingTab: tempTab,
            bookTitle: bookTitle,
            returnResultOnSubmit: true,
          ),
        );

        // dispose נדחה כדי לחכות ל-fade-out animation של ה-dialog (~200ms)
        // ולכל ה-animations הפנימיים של ה-TextField (cursor blink וכו') —
        // אחרת ה-FocusNode של ה-tempTab משוחרר בזמן ש-Widget tree של ה-dialog
        // עדיין rebuilds, וגורם ל-"FocusNode used after being disposed" crash.
        Future.delayed(const Duration(milliseconds: 500), () {
          tempTab.dispose();
        });

        if (!mounted || result == null) {
          return;
        }

        final normalizedParameters =
            SearchQueryBuilder.normalizeParametersForMode(
              result.searchMode,
              customSpacing: result.spacingValues,
              alternativeWords: result.alternativeWords,
              searchOptions: result.searchOptions,
            );
        applyInBookSearchQuery(
          controller: searchTextController,
          query: result.query,
          onQueryChanged: (value) {
            context.read<TextBookBloc>().add(
              UpdateSearchText(
                value,
                searchOptions: normalizedParameters.searchOptions,
                alternativeWords: normalizedParameters.alternativeWords,
                spacingValues: normalizedParameters.customSpacing,
                searchMode: result.searchMode,
                searchDistance: result.distance,
              ),
            );
          },
        );
        setState(() {
          _searchOptions = normalizedParameters.searchOptions;
          _alternativeWords = normalizedParameters.alternativeWords;
          _spacingValues = normalizedParameters.customSpacing;
          _searchMode = result.searchMode;
          _searchDistance = result.distance;
          _updateForceSearchEngine();
        });
        _searchTextUpdated();
      },
    );
  }

  Widget _buildSearchResultNavigationBar() {
    final isAtFirstResult =
        (_selectedSearchResultIndex ?? 0) <= 0 || searchResults.isEmpty;
    final isAtLastResult =
        searchResults.isEmpty ||
        (_selectedSearchResultIndex ?? 0) >= searchResults.length - 1;

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 12,
        end: 12,
        bottom: 2,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildResultNavigationButton(
              icon: FluentIcons.chevron_up_24_regular,
              tooltip: 'התוצאה הקודמת',
              onPressed: isAtFirstResult ? null : () => _moveBetweenResults(-1),
            ),
            const SizedBox(width: 4),
            _buildResultNavigationButton(
              icon: FluentIcons.chevron_down_24_regular,
              tooltip: 'התוצאה הבאה',
              onPressed: isAtLastResult ? null : () => _moveBetweenResults(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultNavigationButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppTokens.borderRadiusAll,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isEnabled
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh,
            borderRadius: AppTokens.borderRadiusAll,
            border: Border.all(
              color: isEnabled
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isEnabled
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
