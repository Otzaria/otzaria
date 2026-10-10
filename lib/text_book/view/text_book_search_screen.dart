import 'dart:async';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/search/view/in_book_snippet_style.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
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
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/search/view/whole_word_search_action.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
import 'package:otzaria/search/utils/result_text_status.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/search/utils/search_query_sync.dart';
import 'package:otzaria/utils/text/ref_helper.dart' show tocSectionAt;
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/navigation/search_result_nav_button.dart';

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
  final Future<List<TextSearchResult>> Function(
    List<String> content,
    String query,
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
  InBookSearchSettings _settings = const InBookSearchSettings();
  bool _wholeWord = InBookSearchPreferences.loadWholeWord();

  /// חיפוש רק בקטע שתחת הכותרת הקרובה למקום הקריאה (issue #1093).
  bool _limitToSection = false;
  ({int start, int? end, String title})? _activeSection;
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

  Map<String, Map<String, bool>> get _searchOptions => _settings.searchOptions;
  Map<int, List<String>> get _alternativeWords => _settings.alternativeWords;
  Map<String, String> get _spacingValues => _settings.spacingValues;
  SearchMode get _searchMode => _settings.searchMode;
  int get _searchDistance => _settings.distance;
  SearchMatchPolicy get _matchPolicy => _settings.matchPolicy;

  bool get _isSimpleSearch => _settings.isSimpleSearch;

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

  SearchModeScopedParameters get _activeSearchParameters =>
      _settings.activeParameters;

  void _syncSearchConfigurationFromWidget() {
    // ההעדפה גלובלית ונקראת מחדש: החלפת המתג בטאב אחר משאירה כאן ערך ישן,
    // וההדגשה בגוף הספר הייתה סותרת את רשימת התוצאות.
    _wholeWord = InBookSearchPreferences.loadWholeWord();
    _settings = InBookSearchSettings(
      searchOptions: widget.initialSearchOptions,
      alternativeWords: widget.initialAlternativeWords,
      spacingValues: widget.initialSpacingValues,
      searchMode: widget.initialSearchMode,
      distance: widget.initialSearchDistance,
      matchPolicy: widget.initialMatchPolicy,
    );
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

  void _toggleLimitToSection() {
    setState(() => _limitToSection = !_limitToSection);
    _searchTextUpdated();
  }

  /// הקטע שתחת הכותרת הקרובה למקום הקריאה הנוכחי, כשההגבלה פעילה.
  ({int start, int? end, String title})? _resolveActiveSection() {
    if (!_limitToSection) return null;
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded || state.visibleIndices.isEmpty) return null;
    return tocSectionAt(state.tableOfContents, state.visibleIndices.first);
  }

  @override
  void initState() {
    super.initState();
    searchTextController.text = widget.initialQuery;
    _syncSearchConfigurationFromWidget();
    if (widget.initialQuery.isEmpty) {
      _settings = InBookSearchSettings.savedDefaults();
    }
    _syncBlocSearchTextState();

    scrollControler = widget.scrollControler;

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
    // ה-BLoC מקבל את השאילתה המנורמלת (בלי ניקוד ורווחים), וערך שתואם לה
    // הוא הד של השדה עצמו, לא שינוי חיצוני שדורס את ההקלדה (issue #1430).
    final controllerQuery = searchTextController.text;
    final needsControllerSync =
        widget.initialQuery != controllerQuery &&
        widget.initialQuery != (searchableInBookQuery(controllerQuery) ?? '');
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
      source: state.book.source,
      fileType: state.book.fileType,
      filePath: state.book.filePath,
    );

    if (!mounted) return;

    _bookTitle = bookTitle;
    _bookPath = BookFacet.buildFacetPath(
      title: bookTitle,
      topics: topics,
      bookId: state.book.id,
      source: state.book.source,
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

  Future<void> _searchTextUpdated() async {
    final requestId = ++_activeSearchRequestId;
    final searchable = searchableInBookQuery(searchTextController.text);
    if (searchable == null) {
      setState(() {
        searchResults = [];
        _isSearching = false;
        _searchErrorMessage = null;
      });
      return;
    }

    final query = searchable;
    final section = _resolveActiveSection();

    setState(() {
      _activeSection = section;
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
          ? await widget.simpleSearchRunner!(content, query)
          : await searchInContent(
              content: content,
              query: query,
              wholeWord: _wholeWord,
              range: section == null
                  ? null
                  : (start: section.start, end: section.end),
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

      final List<SearchResult> rawResults;
      rawResults = await searchBookWithEngine(
        widget.searchRepository,
        query: query,
        bookPath: _bookPath!,
        limit: kInBookEngineFetchLimit,
        settings: _settings,
      );

      final expectedTitle = _bookTitle!.trim();

      final filtered = rawResults
          .where((r) => !r.isPdf && r.title.trim() == expectedTitle)
          .where((r) {
            if (section == null) return true;
            final line = r.segment.toInt();
            final end = section.end;
            return line >= section.start && (end == null || line < end);
          })
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

      final (shown: results, :truncated) = limitInBookResults(sorted);

      debugPrint(
        '📚 TextBookSearch: rawResults=${rawResults.length}, '
        'filteredResults=${results.length}, title="$expectedTitle"',
      );

      // בחיפוש בספר התוכן הטעון קובע; בלעדיו נשארת הודעת "אינו זמין".
      if (results.any(isResultTextUnavailable)) {
        try {
          await _ensureContent();
        } catch (e) {
          debugPrint('טעינת תוכן הספר לתוצאות נכשלה: $e');
        }
      }

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
      UpdateSearchResultLines({
        for (final result in results) ...[
          result.index,
          if (result.continuesToNextLine) result.index + 1,
        ],
      }),
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
    final activeParameters = _activeSearchParameters;
    // תוצאת מנוע שנמשכת לשורה הבאה מתחילה בסוף השורה, ולשורה לבדה אין התאמה.
    final intraLineFraction =
        result.continuesToNextLine && result.matchOffset == null
        ? 1.0
        : lineText == null
        ? matchFractionFromLineLength(
            matchOffset: result.matchOffset,
            lineLength: result.lineLength,
          )
        : matchFractionInLine(
            lineText,
            result.query,
            matchOffset: result.matchOffset,
            wholeWord: _effectiveWholeWord,
            searchOptions: activeParameters.searchOptions,
            alternativeWords: activeParameters.alternativeWords,
            spacingValues: activeParameters.customSpacing,
            isFuzzy: _searchMode == SearchMode.fuzzy,
            searchDistance: _searchDistance,
            matchPolicy: _matchPolicy,
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

  /// השורה מהתוכן הטעון, כקטע מוברח כמו טקסט המנוע (בלי הדגשה — היא
  /// מחושבת בתצוגה). null כשהשורה אינה טעונה.
  String? _loadedLineSnippet(int index, TextBookState state) {
    final line = state is TextBookLoaded ? _lineTextAt(index, state) : null;
    if (line == null) return null;
    final query = searchTextController.text;
    // מרווחים ווריאנטים של המנוע אינם בתבנית הליטרלית; מעגנים כמו ההדגשה.
    int? firstHighlight(String text) {
      final ranges = utils.computeHighlightRanges(
        text,
        query,
        searchOptions: _searchOptions,
        alternativeWords: _alternativeWords,
        spacingValues: _spacingValues,
        isFuzzy: _searchMode == SearchMode.fuzzy,
        searchDistance: _searchDistance,
        matchPolicy: _matchPolicy,
        isSearchResultLine: true,
      );
      return ranges.isEmpty ? null : ranges.first.first;
    }

    final excerpt = SnippetBuilder.buildExcerptText(
      fullText: SnippetBuilder.htmlToPlainText(line),
      query: query,
      maxChars: _maxResultSnippetChars,
      wholeWord: _wholeWord,
      anchorOf: firstHighlight,
    );
    return const HtmlEscape(HtmlEscapeMode.element).convert(excerpt);
  }

  List<TextSearchResult> _convertSearchResults(List<SearchResult> results) {
    // רק עותק השורות המלא תוחם את מספרי השורות. `state.content` יכול להיות
    // חלון חלקי סביב מקום הקריאה, ולפיו היו נזרקות תוצאות מנוע תקפות.
    final int? contentLength = _content?.length;
    final state = context.read<TextBookBloc>().state;
    final List<TextSearchResult> converted = [];
    for (final result in results) {
      try {
        final lineNumber = result.segment.toInt();
        if (lineNumber >= 0 &&
            (contentLength == null || lineNumber < contentLength)) {
          converted.add(
            TextSearchResult(
              index: lineNumber,
              snippet: isResultTextUnavailable(result)
                  ? _loadedLineSnippet(lineNumber, state) ??
                        unavailableResultText
                  : result.text,
              address: result.reference,
              query: searchTextController.text,
              continuesToNextLine: result.continuesToNextLine,
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
      pluginActionsField: PluginSearchField.inBook,
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
                    : 'נמצאו ${searchResults.length} תוצאות') +
                (_activeSection != null ? ' בקטע הנוכחי' : '')
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
                    return NavTreeHeader(
                      title: withHolyNamesSetting(item.header!, settingsState),
                    );
                  },
                );
              }

              // אם זו תוצאה רגילה
              final result = item.result!;
              final resultListIndex = item.resultListIndex!;
              return BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  final snippet = withHolyNamesSetting(
                    result.snippet,
                    settingsState,
                  );
                  final style = InBookSnippetStyle(context, settingsState);
                  final defaultStyle = style.text;
                  final highlightStyle = style.highlight;

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
                          style: defaultStyle,
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
          searchableInBookQuery(searchTextController.text) != null &&
          !_isSearching,
      errorMessage: _searchErrorMessage,
      onSearchTextChanged: (value) {
        _settings = _settings.forQuery(searchableInBookQuery(value) ?? '');
        final activeParameters = _activeSearchParameters;
        context.read<TextBookBloc>().add(
          UpdateSearchText(
            searchableInBookQuery(value) ?? '',
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
          _settings = InBookSearchSettings.savedDefaults();
        });
        context.read<TextBookBloc>().add(
          UpdateSearchText(
            '',
            searchOptions: const {},
            alternativeWords: const {},
            spacingValues: const {},
            searchMode: _searchMode,
            searchDistance: _searchDistance,
            matchPolicy: _matchPolicy,
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
        OtzariaSearchAction.icon(
          // חוברת ריקה = החיפוש כבר מצומצם לקטע; חוברת עם תוכן = כל הספר.
          iconData: _limitToSection
              ? OtzariaIcons.booklet_empty_24_regular
              : OtzariaIcons.booklet_24_regular,
          onPressed: _toggleLimitToSection,
          tooltip: _limitToSection
              ? (_activeSection != null
                    ? 'מחפש רק תחת "${_activeSection!.title}" — לחץ לכל הספר'
                    : 'מחפש רק בקטע הנוכחי — לחץ לכל הספר')
              : 'חפש רק בקטע הנוכחי',
          color: _limitToSection ? Theme.of(context).colorScheme.primary : null,
        ),
      ],
      hintText: 'חפש כאן...',
      onSubmitted: () => _moveBetweenResults(1),
      onArrowDown: () => _moveBetweenResults(1),
      onArrowUp: () => _moveBetweenResults(-1),
      onAdvancedSearch: () async {
        final bookTitle =
            (context.read<TextBookBloc>().state as TextBookLoaded).book.title;

        final result = await showInBookAdvancedSearchDialog(
          context,
          bookTitle: bookTitle,
          query: searchTextController.text,
          searchMode: _searchMode,
          distance: _searchDistance,
          matchPolicy: _matchPolicy,
          searchOptions: _searchOptions,
          alternativeWords: _alternativeWords,
          spacingValues: _spacingValues,
          optionsForEveryWord: _settings.optionsForEveryWord,
        );

        if (!mounted || result == null) {
          return;
        }

        final settings = InBookSearchSettings.fromDialogResult(result);
        // הניתוב החדש נקבע לפני ה-setState, כדי שההדגשה שנשלחת ל-bloc תתאים
        // למסלול שירוץ בפועל ולא למסלול הקודם.
        final willRunSimpleSearch = !settings.requiresEngine;
        applyInBookSearchQuery(
          controller: searchTextController,
          query: result.query,
          onQueryChanged: (value) {
            context.read<TextBookBloc>().add(
              UpdateSearchText(
                value,
                searchOptions: settings.searchOptions,
                alternativeWords: settings.alternativeWords,
                spacingValues: settings.spacingValues,
                searchMode: settings.searchMode,
                searchDistance: settings.distance,
                matchPolicy: settings.matchPolicy,
                searchWholeWord: willRunSimpleSearch ? _wholeWord : true,
              ),
            );
          },
        );
        setState(() => _settings = settings);
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
            SearchResultNavButton(
              icon: FluentIcons.chevron_up_24_regular,
              tooltip: 'התוצאה הקודמת',
              onPressed: isAtFirstResult ? null : () => _moveBetweenResults(-1),
            ),
            const SizedBox(width: 4),
            SearchResultNavButton(
              icon: FluentIcons.chevron_down_24_regular,
              tooltip: 'התוצאה הבאה',
              onPressed: isAtLastResult ? null : () => _moveBetweenResults(1),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
