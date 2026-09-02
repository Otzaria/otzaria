import 'dart:async';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
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
import 'package:otzaria/text_book/models/text_search_range.dart';
import 'package:otzaria/text_book/view/text_search_range_picker.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/search/view/search_range_action.dart';
import 'package:otzaria/search/view/whole_word_search_action.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
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
  final SearchMatchPolicy initialMatchPolicy;

  /// מריץ את המסלול הפשוט; מוזרק בבדיקות בלבד. [range] — טווח השורות
  /// שאליו הוגבל החיפוש, או `null` לכל הספר.
  final Future<List<TextSearchResult>> Function(
    List<String> content,
    String query,
    TextSearchRange? range,
  )?
  simpleSearchRunner;

  /// מנוע החיפוש שמריץ את מסלול החיפוש המורכב. מוזרק בבדיקות בלבד.
  final SearchRepository searchRepository;

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
    this.initialMatchPolicy = SearchMatchPolicy.standard,
    this.simpleSearchRunner,
    this.searchRepository = const SearchRepository(),
  });

  @override
  TextBookSearchViewState createState() => TextBookSearchViewState();
}

class TextBookSearchViewState extends State<TextBookSearchView>
    with AutomaticKeepAliveClientMixin<TextBookSearchView> {
  TextEditingController searchTextController = TextEditingController();
  List<TextSearchResult> searchResults = [];
  bool _resultsTruncated = false;
  late ItemScrollController scrollControler;
  bool _isSearching = false;

  /// הודעת שגיאה אחרונה בחיפוש (כשל מנוע/FFI). ראו doc ב-[SearchPaneBase].
  String? _searchErrorMessage;
  List<String>? _content;
  Future<List<String>>? _contentFuture;
  String? _bookPath;
  String? _bookTitle;
  Future<void>? _bookPathFuture;
  bool _forceSearchEngine = false;
  Map<String, Map<String, bool>> _searchOptions = {};
  Map<int, List<String>> _alternativeWords = {};
  Map<String, String> _spacingValues = {};
  SearchMode _searchMode = SearchMode.exact;
  int _searchDistance = 0;
  SearchMatchPolicy _matchPolicy = SearchMatchPolicy.standard;
  bool _wholeWord = InBookSearchPreferences.loadWholeWord();

  /// טווח השורות שאליו מוגבל החיפוש; `null` — כל הספר.
  TextSearchRange? _searchRange;
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

  /// המתג חל רק על הסריקה הליטרלית. במסלול המנוע ההדגשה נגזרת מהתבנית
  /// שהמנוע בנה, ולכן הוא מדווח "מילים שלמות" ללא תלות במתג.
  bool get _effectiveWholeWord => _isSimpleSearch ? _wholeWord : true;

  static const int _maxResultSnippetChars = 220;

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
    _forceSearchEngine = !InBookSearchRouting.canRunAsSimpleSearch(
      searchMode: _searchMode,
      distance: _searchDistance,
      searchOptions: _searchOptions,
      alternativeWords: _alternativeWords,
      spacingValues: _spacingValues,
      matchPolicy: _matchPolicy,
    );
  }

  void _syncSearchConfigurationFromWidget() {
    // ההעדפה גלובלית ונקראת מחדש: החלפת המתג בטאב אחר משאירה כאן ערך ישן,
    // וההדגשה בגוף הספר הייתה סותרת את רשימת התוצאות.
    _wholeWord = InBookSearchPreferences.loadWholeWord();
    _searchOptions = widget.initialSearchOptions;
    _alternativeWords = widget.initialAlternativeWords;
    _spacingValues = widget.initialSpacingValues;
    _searchMode = widget.initialSearchMode;
    _searchDistance = widget.initialSearchDistance;
    _matchPolicy = widget.initialMatchPolicy;
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
        matchPolicy: _matchPolicy,
        searchWholeWord: _effectiveWholeWord,
      ),
    );
  }

  /// החלפת מצב ההתאמה: מעדכן את ההדגשה בגוף הספר ומריץ את החיפוש מחדש,
  /// אחרת הרשימה נשארת עם תוצאות המצב הקודם.
  void _toggleWholeWord() {
    setState(() => _wholeWord = !_wholeWord);
    unawaited(InBookSearchPreferences.saveWholeWord(_wholeWord));
    _syncBlocSearchTextState();
    _searchTextUpdated();
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
      if (!mounted) return;
      if (searchTextController.text.isNotEmpty) {
        _searchTextUpdated();
      } else {
        unawaited(_ensureBookPath());
      }
    });
  }

  /// [TickerMode] כבוי מסמן שהטאב עבר לרקע (ראו `TickerMode` ב-`ReadingScreen`).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _releaseContentCache();
    }
  }

  @override
  void didUpdateWidget(TextBookSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // עדכון שדה החיפוש אם initialQuery השתנה
    final queryChanged = widget.initialQuery != oldWidget.initialQuery;
    final needsControllerSync =
        widget.initialQuery != searchTextController.text;
    final normalizedSearchMode = widget.initialSearchMode;
    final searchConfigurationChanged =
        !_searchOptionsEqual(_searchOptions, widget.initialSearchOptions) ||
        !_alternativeWordsEqual(
          _alternativeWords,
          widget.initialAlternativeWords,
        ) ||
        !mapEquals(_spacingValues, widget.initialSpacingValues) ||
        _searchMode != normalizedSearchMode ||
        _searchDistance != widget.initialSearchDistance ||
        _matchPolicy != widget.initialMatchPolicy;

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

  /// מזהה את הספר לחיפוש המנוע פעם אחת ושומר את הזיהוי. זיהוי שלא הצליח —
  /// למשל כשהספר עדיין נטען — אינו נשמר, כדי שהחיפוש הבא ינסה שוב במקום
  /// להיתקע. האיפוס אחרי ה-await ולא ב-[_resolveBookPath], כי כשל לפני
  /// ה-await הראשון קורה עוד לפני שהשדה קיבל את ה-Future.
  Future<void> _ensureBookPath() async {
    final existing = _bookPathFuture;
    if (existing != null) return existing;
    final future = _resolveBookPath();
    _bookPathFuture = future;
    try {
      await future;
    } finally {
      if (_bookPath == null || _bookTitle == null) {
        _bookPathFuture = null;
      }
    }
  }

  Future<void> _resolveBookPath() async {
    if (!mounted) return;
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    final bookTitle = state.book.title;

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

    _bookTitle = bookTitle;
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
  }

  /// טוען את תוכן הספר פעם אחת ושומר אותו עד לשחרור. כישלון — או שחרור בזמן
  /// הטעינה — מאפס את ה-Future כדי לאפשר ניסיון חוזר בחיפוש הבא.
  Future<List<String>> _ensureContent() async {
    final existing = _contentFuture;
    if (existing != null) {
      return existing;
    }
    final future = widget.contentLoader();
    _contentFuture = future;
    try {
      final lines = await future;
      if (identical(_contentFuture, future)) {
        _content = lines;
      }
      return lines;
    } catch (_) {
      if (identical(_contentFuture, future)) {
        _contentFuture = null;
      }
      rethrow;
    }
  }

  /// משחרר את עותק שורות הספר שנטען לחיפוש, כך שטאבי רקע אינם מחזיקים עותק כל
  /// אחד. התוצאות שעל המסך נשמרות, והחיפוש הבא יטען מחדש לפי הצורך.
  void _releaseContentCache() {
    _content = null;
    _contentFuture = null;
  }

  /// השאילתה שתרוץ בפועל, מנורמלת, או `null` כשאין מה לחפש עליה.
  String? _searchableQuery(String raw) {
    var query = raw.trim();
    if (utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }
    return InBookSearchRouting.isSearchableQuery(
          query,
          wholeWord: _effectiveWholeWord,
        )
        ? query
        : null;
  }

  Future<void> _searchTextUpdated() async {
    final requestId = ++_activeSearchRequestId;
    final searchable = _searchableQuery(searchTextController.text);
    if (searchable == null) {
      setState(() {
        searchResults = [];
        _isSearching = false;
        _searchErrorMessage = null;
      });
      return;
    }

    final query = searchable;

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
            _searchErrorMessage = TextBookMessages.searchContentLoadFailed;
          });
        }
        return;
      }
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }

      var truncated = false;
      final effectiveResults = widget.simpleSearchRunner != null
          ? await widget.simpleSearchRunner!(content, query, _searchRange)
          : await searchInContent(
              content: content,
              query: query,
              wholeWord: _wholeWord,
              startLine: _searchRange?.startLine ?? 0,
              endLine: _searchRange?.endLine,
              onTruncated: (t) => truncated = t,
            );

      if (mounted && requestId == _activeSearchRequestId) {
        _applySearchResults(effectiveResults, truncated: truncated);
      }
      return;
    }

    try {
      // ממתינים לזיהוי הספר במקום לבדוק אותו מקדימה, ובתוך ה-try — כך חיפוש
      // שנשלח לפני שהזיהוי הסתיים אינו מציג "אין תוצאות" ואינו נתקע ב"מחפש".
      await _ensureBookPath();
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      if (_bookPath == null || _bookTitle == null) {
        setState(() {
          searchResults = [];
          _isSearching = false;
          _searchErrorMessage = LibraryMessages.searchError;
        });
        return;
      }

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
      rawResults = await widget.searchRepository.searchTexts(
        query,
        [_bookPath!],
        rawLimit,
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

      final expectedTitle = _bookTitle!.trim();

      final range = _searchRange;
      final filtered = rawResults
          .where((r) => !r.isPdf && r.title.trim() == expectedTitle)
          .where((r) => range == null || range.contains(r.segment.toInt()))
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
      final truncated = sorted.length > displayLimit;

      debugPrint(
        '📚 TextBookSearch: rawResults=${rawResults.length}, '
        'filteredResults=${results.length}, title="$expectedTitle"',
      );

      if (mounted && requestId == _activeSearchRequestId) {
        _applySearchResults(
          _convertSearchResults(results),
          truncated: truncated,
        );
        // מספרי השורות מהמנוע הם הבסיס לגלילה ולהדגשה — דריפט תוכן מחטיא
        // בשקט, ולכן מוצגת אזהרה לא-חוסמת לצד התוצאות.
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded) {
          unawaited(
            IndexFreshnessWarner.instance.warnIfContentDrifted(state.book),
          );
        }
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

  void _applySearchResults(
    List<TextSearchResult> results, {
    bool truncated = false,
  }) {
    // השורות שהתקבלו הן מקור האמת להדגשה במדיניות התאמה שאינה ברירת המחדל:
    // האפליקציה אינה מנחשת מה המנוע היה מחזיר (ראו TextBookLoaded).
    context.read<TextBookBloc>().add(
      UpdateSearchResultLines({for (final result in results) result.index}),
    );

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
      _resultsTruncated = truncated;
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
        ? matchFractionFromLineLength(
            matchOffset: result.matchOffset,
            lineLength: result.lineLength,
          )
        : matchFractionInLine(
            lineText,
            result.query,
            matchOffset: result.matchOffset,
            wholeWord: _effectiveWholeWord,
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

  /// טקסט השורה לצורך דיוק גלילה אל המילה: קודם התוכן שנטען לחיפוש, ואם אינו
  /// זמין — התוכן שב-state. null כשהשורה אינה זמינה.
  ///
  /// שורה שתוכנה שוחרר מוחזרת מה-state כ-placeholder ריק, ולכן ריק נחשב כאן
  /// כלא-זמין — אחרת החישוב היה נותן שבר 0 ומאבד את הגלילה אל ההופעה.
  String? _lineTextAt(int index, TextBookLoaded loadedState) {
    if (index < 0) {
      return null;
    }
    final content = _content;
    if (content != null && index < content.length) {
      return content[index].isEmpty ? null : content[index];
    }
    if (index < loadedState.content.length) {
      final line = loadedState.content[index];
      return line.isEmpty ? null : line;
    }
    return null;
  }

  List<TextSearchResult> _convertSearchResults(List<SearchResult> results) {
    // רק עותק השורות המלא תוחם את מספרי השורות. `state.content` יכול להיות
    // חלון חלקי סביב מקום הקריאה, ולפיו היו נזרקות תוצאות מנוע תקפות.
    final int? contentLength = _content?.length;
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

  Future<void> _pickSearchRange() async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    if (searchRangeHeadings(state.tableOfContents).isEmpty) {
      UiSnack.show(TextBookMessages.noTocForSearchRange);
      return;
    }
    final range = await pickTextSearchRange(
      context: context,
      toc: state.tableOfContents,
    );
    if (range == null || !mounted) return;
    setState(() => _searchRange = range);
    _searchTextUpdated();
  }

  void _clearSearchRange() {
    setState(() => _searchRange = null);
    _searchTextUpdated();
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
          ? (_resultsTruncated
                ? 'מוצגות ${searchResults.length} התוצאות הראשונות'
                : 'נמצאו ${searchResults.length} תוצאות')
          : null,
      // כשתבנית ההדגשה מבוססת-האינדקס מגיעה (אסינכרונית), ה-snippets מחושבים
      // מחדש כדי לכלול את הווריאנטים שה-fallback החמיץ.
      resultsWidget: ListenableBuilder(
        listenable: utils.highlightPatternRevision,
        builder: (context, _) => NavTreeFocusGroup(
          child: ScrollablePositionedList.builder(
            itemScrollController: _resultsScrollController,
            itemPositionsListener: _resultsPositionsListener,
            padding: kNavTreeListPadding,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              // הקבוצה נפתחת אחרי כותרת קבוצה ונסגרת לפני הכותרת הבאה.
              final isGroupStart = index == 0 || items[index - 1].isHeader;
              final isGroupEnd =
                  index == items.length - 1 || items[index + 1].isHeader;

              // אם זו כותרת קבוצה
              if (item.isHeader) {
                return BlocBuilder<SettingsBloc, SettingsState>(
                  builder: (context, settingsState) {
                    String text = item.header!;
                    if (settingsState.replaceHolyNames) {
                      text = utils.replaceHolyNames(
                        text,
                        style: settingsState.holyNameStyle,
                      );
                    }
                    return NavTreeHeader(title: text);
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
                    snippet = utils.replaceHolyNames(
                      snippet,
                      style: settingsState.holyNameStyle,
                    );
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
                      wholeWord: _wholeWord,
                    );
                    highlightedSnippet = SnippetBuilder.highlightLiteral(
                      plainText: excerpt,
                      query: result.query,
                      defaultStyle: defaultStyle,
                      highlightStyle: highlightStyle,
                      wholeWord: _wholeWord,
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
                      matchPolicy: _matchPolicy,
                      isSearchResultLine: true,
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

                  return NavTreeGroupCard(
                    isGroupStart: isGroupStart,
                    isGroupEnd: isGroupEnd,
                    child: NavTreeContentRow(
                      isSelected: _selectedSearchResultIndex == resultListIndex,
                      onTap: () => _navigateToSearchResult(
                        resultListIndex,
                        closePaneOnAndroid: true,
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
                  );
                },
              );
            },
          ),
        ),
      ),
      isNoResults:
          searchResults.isEmpty &&
          _searchableQuery(searchTextController.text) != null &&
          !_isSearching,
      errorMessage: _searchErrorMessage,
      onSearchTextChanged: (value) {
        final activeParameters = _activeSearchParameters;
        context.read<TextBookBloc>().add(
          UpdateSearchText(
            _searchableQuery(value) ?? '',
            searchOptions: activeParameters.searchOptions,
            alternativeWords: activeParameters.alternativeWords,
            spacingValues: activeParameters.customSpacing,
            searchMode: _searchMode,
            searchDistance: _searchDistance,
            matchPolicy: _matchPolicy,
            searchWholeWord: _effectiveWholeWord,
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
          _searchRange = null;
          _forceSearchEngine = false;
          _searchOptions = {};
          _alternativeWords = {};
          _spacingValues = {};
          _searchMode = SearchMode.exact;
          _searchDistance = 0;
          _matchPolicy = SearchMatchPolicy.standard;
        });
        context.read<TextBookBloc>().add(
          UpdateSearchText(
            '',
            searchOptions: const {},
            alternativeWords: const {},
            spacingValues: const {},
            searchMode: SearchMode.exact,
            searchDistance: 0,
            matchPolicy: SearchMatchPolicy.standard,
            searchWholeWord: _wholeWord,
          ),
        );
      },
      searchFieldActions: [
        if (_isSimpleSearch)
          wholeWordSearchAction(
            context: context,
            wholeWord: _wholeWord,
            onToggle: _toggleWholeWord,
          ),
        searchRangeAction(
          context: context,
          isActive: _searchRange != null,
          onPressed: _pickSearchRange,
        ),
      ],
      searchFieldActionsKey: (
        _isSimpleSearch,
        _wholeWord,
        _searchRange != null,
      ),
      scopeIndicator: _searchRange == null
          ? null
          : SearchRangeChip(
              label: _searchRange!.label,
              onRemove: _clearSearchRange,
            ),
      hintText: 'חפש כאן...',
      onSubmitted: () => _moveBetweenResults(1),
      onArrowDown: () => _moveBetweenResults(1),
      onArrowUp: () => _moveBetweenResults(-1),
      onAdvancedSearch: () async {
        // מטמיעים את ה-configuration ישירות ב-Bloc במקום events, כי events
        // אסינכרוניים עלולים לרוץ אחרי שה-dialog פותח חיפוש ראשון.
        final tempTab = SearchingTab(
          'חיפוש',
          searchTextController.text,
          initialConfiguration: SearchConfiguration.forInBookSearch(
            searchMode: _searchMode,
            distance: _searchDistance,
            matchPolicy: _matchPolicy,
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
        // הניתוב החדש נקבע לפני ה-setState, כדי שההדגשה שנשלחת ל-bloc תתאים
        // למסלול שירוץ בפועל ולא למסלול הקודם.
        final willRunSimpleSearch = InBookSearchRouting.canRunAsSimpleSearch(
          searchMode: result.searchMode,
          distance: result.distance,
          searchOptions: normalizedParameters.searchOptions,
          alternativeWords: normalizedParameters.alternativeWords,
          spacingValues: normalizedParameters.customSpacing,
          matchPolicy: result.matchPolicy,
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
                matchPolicy: result.matchPolicy,
                searchWholeWord: willRunSimpleSearch ? _wholeWord : true,
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
          _matchPolicy = result.matchPolicy;
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
      padding: const EdgeInsetsDirectional.only(start: 12, end: 12, bottom: 2),
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
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
