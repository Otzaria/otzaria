import 'package:otzaria/widgets/navigation/search_result_navigator.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'dart:async';

import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/search/view/in_book_snippet_style.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/search/view/whole_word_search_action.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria/pdf_book/utils/pdf_user_regex_pattern.dart';
import 'package:otzaria/pdf_book/utils/proximity_highlight_pattern.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/search/utils/search_query_sync.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
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
    this.source = BookSource.official,
    this.externalLibraryId,
    this.pdfFilePath,
    this.initialSearchOptions = const {},
    this.initialAlternativeWords = const {},
    this.initialSpacingValues = const {},
    this.initialSearchMode = SearchMode.exact,
    this.initialSearchDistance = 0,
    this.initialMatchPolicy = SearchMatchPolicy.standard,
    this.initialSearchOrigin = InBookSearchOrigin.inBook,
    this.initialSearchTemplate,
    this.incomingSearchConfiguration,
    this.onSearchResultNavigated,
    this.onNavigationStarted,
    this.takeCenterMatchPage,
    this.searchRepository = const SearchRepository(),
    super.key,
  });

  final PdfTextSearchSession textSearcher;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final List<PdfOutlineNode>? outline;
  final String? bookTitle;
  final String? bookTopics;
  final String? bookCategoryPath;

  /// מזהי הספר לבניית נתיב ה-facet — חייבים להיכלל בדיוק כמו באינדוקס
  /// (id:/uid:/ext:), אחרת מסלול המנוע מחפש תחת facet שאינו קיים.
  final int? bookId;
  final BookSource source;
  final String? externalLibraryId;

  /// Absolute path to the currently opened PDF file.
  ///
  /// Used to ensure in-book PDF search doesn't return results from a same-title
  /// text book (TXT) that shares the same facet path in the search index.
  final String? pdfFilePath;

  final Map<String, Map<String, bool>> initialSearchOptions;
  final Map<int, List<String>> initialAlternativeWords;
  final Map<String, String> initialSpacingValues;
  final SearchMode initialSearchMode;
  final int initialSearchDistance;
  final SearchMatchPolicy initialMatchPolicy;
  final InBookSearchOrigin initialSearchOrigin;
  final InBookSearchTemplate? initialSearchTemplate;

  /// תצורת חיפוש שממתינה להחלה אטומית בחלונית.
  final ValueNotifier<ReadingTabSearchState?>? incomingSearchConfiguration;

  final VoidCallback? onSearchResultNavigated;
  final ValueChanged<int>? onNavigationStarted;

  /// עמוד התוצאה שפתחה את הספר; בקשה זמנית שנצרכת פעם אחת.
  final int? Function()? takeCenterMatchPage;

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

    var resultIndex = 0;
    var visualIndex = 0;
    var lastHeaderIndex = 0;

    // הקלט כבר ממוין לפי עמוד. מעבר יחיד מספיק גם לאיתור עמוד היעד וגם
    // לספירת כותרות/תוצאות שקודמות לו; אין צורך ב-Set, העתקה ומיון חוזר.
    while (resultIndex < resultsPageNumbersSorted.length) {
      final page = resultsPageNumbersSorted[resultIndex];
      lastHeaderIndex = visualIndex;
      if (page >= currentPage) return visualIndex;

      visualIndex++; // כותרת העמוד
      do {
        visualIndex++;
        resultIndex++;
      } while (resultIndex < resultsPageNumbersSorted.length &&
          resultsPageNumbersSorted[resultIndex] == page);
    }

    // כל התוצאות לפני המיקום הנוכחי — כותרת העמוד האחרון.
    return lastHeaderIndex;
  }

  /// הודעה כשמסלול המנוע החזיר 0 תוצאות והספר כלל אינו באינדקס —
  /// בלעדיה "אין תוצאות" הגנרי מסתיר מהמשתמש את הסיבה האמיתית.
  @visibleForTesting
  static String? missingFromIndexNotice({
    required String? indexedFilePath,
    required bool indexInitialized,
    required Set<String> indexedFilePaths,
    bool excludedByIndexMode = false,
  }) {
    if (indexedFilePath == null || indexedFilePath.isEmpty) return null;
    if (!indexInitialized) return null;
    if (indexedFilePaths.contains(indexedFilePath)) return null;
    return excludedByIndexMode
        ? PdfMessages.personalBookNotInSearchIndex
        : PdfMessages.bookNotInSearchIndex;
  }

  /// אותיות עבריות ואנגליות — שכבת טקסט עם ספרות ופיסוק בלבד אינה שמישה.
  static final RegExp _searchableLetter = RegExp(r'[A-Za-zא-ת]');

  /// האם בטקסט שנדגם מהעמודים יש אות שאפשר לחפש בה.
  @visibleForTesting
  static bool hasSearchableText(Iterable<String> pageTexts) =>
      pageTexts.any(_searchableLetter.hasMatch);

  /// שורת ההקשר של ההתאמה, מוגבלת גם כששכבת הטקסט חסרה ירידות שורה.
  @visibleForTesting
  static String matchLineSnippet(PdfTextSearchResult match, String fallback) {
    final text = match.contextText;
    final start = match.start - match.contextStart;
    final end = match.end - match.contextStart;
    if (start < 0 || end < start || end > text.length) return fallback;
    const maxChars = 240;
    final leftLimit = (start - 80).clamp(0, text.length);
    final rightLimit = (leftLimit + maxChars).clamp(0, text.length);
    var lineStart = start;
    while (lineStart > leftLimit && text.codeUnitAt(lineStart - 1) != 10) {
      lineStart--;
    }
    var lineEnd = end.clamp(lineStart, rightLimit);
    while (lineEnd < rightLimit && text.codeUnitAt(lineEnd) != 10) {
      lineEnd++;
    }
    final line = text.substring(lineStart, lineEnd).trim();
    if (line.isEmpty) return fallback;
    final before = lineStart > 0
        ? text.codeUnitAt(lineStart - 1) != 10
        : match.contextStart > 0;
    final after = lineEnd < text.length
        ? text.codeUnitAt(lineEnd) != 10
        : match.contextStart + lineEnd < match.pageTextLength;
    return '${before ? '…' : ''}$line${after ? '…' : ''}';
  }

  /// כמה מ-[previous] נשארות בראש [matches]: ה-searcher מפרסם תמונות מצב
  /// מצטברות, ולכן ממפים רק את מה שנוסף; חיפוש חדש מחזיר 0.
  @visibleForTesting
  static int keptMatchCount(
    List<PdfTextSearchResult> previous,
    List<PdfTextSearchResult> matches,
  ) {
    if (previous.isEmpty || matches.length < previous.length) return 0;
    final extendsPrevious =
        identical(matches.first, previous.first) &&
        identical(matches[previous.length - 1], previous.last);
    return extendsPrevious ? previous.length : 0;
  }

  /// העמודים שנדגמים לבדיקת קיום טקסט: העמוד שהמשתמש רואה ועוד שניים
  /// פרושׂים על הספר — עמוד בודד עלול להיות שער או לוח תמונות.
  @visibleForTesting
  static List<int> textLayerProbePages({
    required int currentPage,
    required int totalPages,
  }) {
    if (totalPages <= 0) return const [];
    int clamped(int page) => page.clamp(1, totalPages);
    return <int>{
      clamped(currentPage),
      clamped((totalPages / 3).ceil()),
      clamped((totalPages * 2 / 3).ceil()),
    }.toList();
  }

  /// תקרת מונחים ייחודיים לתבנית ההדגשה, כדי שהרגקס לא יתנפח.
  static const int _maxHighlightTerms = 50;

  /// תבנית הדגשה לעמודים: המתאם של הקורא הטקסטואלי כשהוא מוצא את [resultHtmls],
  /// ואחרת (מקורב, טווח פסקה) המונחים שהמנוע סימן. null כשאין מה להדגיש.
  @visibleForTesting
  static Pattern? buildAdvancedHighlightPattern(
    Iterable<String> resultHtmls, {
    String query = '',
    InBookSearchSettings settings = const InBookSearchSettings(),
  }) {
    final proximity = _proximityPattern(resultHtmls, query, settings);
    if (proximity != null) return proximity;

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

  /// כמה קטעים נבדקים לפני שמוותרים על המתאם: כל קטע מפוענח כ-HTML.
  static const int _maxProximityProbes = 20;

  static ProximityHighlightPattern? _proximityPattern(
    Iterable<String> resultHtmls,
    String query,
    InBookSearchSettings settings,
  ) {
    if (query.isEmpty || settings.searchMode == SearchMode.fuzzy) return null;
    final policy = settings.matchPolicy;
    // בטווח פסקה/כותרת או "לפחות N מילים" המתאם מדגיש מילה-מילה, לא רצף.
    if (policy.proximityScope != SearchScope.wordDistance ||
        policy.wordMatchMode != WordMatchMode.all) {
      return null;
    }
    final pattern = ProximityHighlightPattern(query, settings);
    for (final html in resultHtmls.take(_maxProximityProbes)) {
      if (pattern.spans(SnippetBuilder.htmlToPlainText(html)).isNotEmpty) {
        return pattern;
      }
    }
    return null;
  }

  /// התבנית של החיפוש הפשוט. עם [reversed] היא נבנית על סדר המילים ההפוך —
  /// מסלול הנסיגה לשכבת טקסט סרוקה ששומרת כל שורה בסדר ויזואלי.
  ///
  /// בסדר ההפוך מוחזר `null` כשאין מה להפוך: מילה אחת, או שאילתה שסדרה
  /// ההפוך זהה לה.
  @visibleForTesting
  static LiteralSearchPattern? buildSimpleSearchPattern(
    String query, {
    bool wholeWord = true,
    bool reversed = false,
  }) {
    if (!reversed) return buildLiteralPattern(query, wholeWord: wholeWord);

    final normalized = normalizeLiteralQuery(query);
    final words = normalized.split(' ');
    if (words.length < 2) return null;
    final reversedQuery = words.reversed.join(' ');
    if (reversedQuery == normalized) return null;

    return buildLiteralPattern(reversedQuery, wholeWord: wholeWord);
  }

  @override
  State<PdfBookSearchView> createState() => PdfBookSearchViewState();
}

class PdfBookSearchViewState extends State<PdfBookSearchView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ItemScrollController _resultsScrollController = ItemScrollController();

  bool _isSearching = false;
  List<SearchResult> _searchResults = [];

  /// Whether the engine found more results than the pane shows.
  bool _resultsTruncated = false;
  List<PdfTextSearchResult> _mappedMatches = const [];

  List<SearchResult>? _groupedSource;
  final List<dynamic> _groupedItems = [];
  int _groupedCount = 0;
  int? _lastGroupedPage;

  /// מוצגת במקום "אין תוצאות" הגנרי: כשל מנוע/FFI או ספר שאינו באינדקס.
  String? _searchErrorMessage;
  String? _bookPath;
  bool _bookPathResolved = false;
  final Map<int, String> _pageTitles = <int, String>{};

  InBookSearchSettings _settings = const InBookSearchSettings();

  // הגדרות מתוצאה גלובלית חלות רק על השאילתה שהגיעה איתן.
  String? _carriedInQuery;
  InBookSearchOrigin get _searchOrigin => _carriedInQuery == null
      ? InBookSearchOrigin.inBook
      : InBookSearchOrigin.globalResult;

  // מסכת PDF מצורפת אינה מאונדקסת, וברירת מחדל שדורשת מנוע הייתה חוסמת בה.
  InBookSearchSettings get _paneDefaults => _isBundledTalmudPdf
      ? const InBookSearchSettings()
      : InBookSearchSettings.savedDefaults();

  Map<String, Map<String, bool>> get _searchOptions => _settings.searchOptions;
  Map<int, List<String>> get _alternativeWords => _settings.alternativeWords;
  Map<String, String> get _spacingValues => _settings.spacingValues;
  SearchMode get _searchMode => _settings.searchMode;
  int get _searchDistance => _settings.distance;
  SearchMatchPolicy get _matchPolicy => _settings.matchPolicy;

  String _lastPdfHighlightSource = '';
  int _searchGeneration = 0;
  int _navigationRequest = 0;

  /// הדור שעבורו כבר נבדק אם לספר יש טקסט — הסריקה מודיעה על כל עמוד,
  /// והבדיקה צריכה לרוץ פעם אחת בסיומה. הוא גם מונע נסיגה חוזרת: חיפוש
  /// הנסיגה אינו מקדם דור, ולכן אינו מפעיל נסיגה נוספת.
  int _textLayerCheckedGeneration = -1;

  /// האם התוצאות המוצגות הן של חיפוש הנסיגה בסדר המילים ההפוך.
  bool _simpleSearchReversed = false;

  /// התבנית שנבנתה מהמונחים שהמנוע מצא בפועל — לשימוש חוזר בלחיצה על תוצאה.
  Pattern? _lastAdvancedHighlightPattern;

  /// השאילתה שעבורה תוזמנה גלילה לעמוד הנוכחי בסיום חיפוש פשוט.
  /// בחיפוש פשוט התוצאות מגיעות אסינכרונית דרך ה-listener של pdfrx, ולכן
  /// אי אפשר לגלול ב-_searchTextUpdated. השדה נדלק שם וייושם בסיום החיפוש —
  /// רק אם השאילתה עדיין תואמת למה שהמשתמש מקליד, כדי למנוע גלילה על
  /// תוצאות מיושנות (race) של חיפוש קודם.
  String? _pendingSimpleSearchScrollFor;

  bool _wholeWord = InBookSearchPreferences.loadWholeWord();

  /// `/…/` also scans the pages: the engine's matcher runs on each text layer.
  bool get _isSimpleSearch =>
      _settings.isSimpleSearch ||
      UserRegexQuery.isValid(widget.searchController.text) ||
      (_isBundledTalmudPdf &&
          _matchPolicy.querySemantics == SearchQuerySemantics.smart);

  /// מסכת PDF מצורפת אינה מאונדקסת בכוונה, ולכן מסלול המנוע ריק בה תמיד.
  bool get _isBundledTalmudPdf =>
      widget.source.isOfficial &&
      DatabaseConstants.isTalmudBavliPdfExternalLibraryId(
        widget.externalLibraryId,
      );

  /// המפתח שבו רשומות מסמכי הספר באינדקס. לספר בעל מזהה חיצוני זה אינו
  /// נתיב הקובץ, ולכן השוואה ל-[pdfFilePath] הייתה משליכה את כל התוצאות.
  String get _indexedFilePath => BookIdentity.indexedPdfFilePath(
    externalLibraryId: widget.externalLibraryId,
    filePath: widget.pdfFilePath,
    source: widget.source,
    bookId: widget.bookId,
  );

  /// החלפת מצב ההתאמה: הסריקה של pdfrx רצה מחדש עם התבנית המתאימה.
  void _toggleWholeWord() {
    setState(() {
      _carriedInQuery = null;
      _wholeWord = !_wholeWord;
    });
    _syncSearchOptions(context.read<PdfBookBloc>());
    unawaited(InBookSearchPreferences.saveWholeWord(_wholeWord));
    _searchTextUpdated();
  }

  int _getPdfPageNumber(SearchResult result) => result.segment.toInt() + 1;

  void _schedulePdfHighlight(Pattern? pattern) {
    final source = switch (pattern) {
      RegExp regExp => regExp.pattern,
      ProximityHighlightPattern proximity => proximity.key,
      _ => '',
    };
    if (source == _lastPdfHighlightSource) return;
    _lastPdfHighlightSource = source;
    widget.textSearcher.startTextSearch(
      pattern ?? '',
      goToFirstMatch: false,
      searchImmediately: true,
    );
  }

  int? _centerOnOpenTargetPage;

  void _centerOpenTargetMatch() {
    final page = _centerOnOpenTargetPage;
    _centerOnOpenTargetPage = null;
    if (page == null || _carriedInQuery == null) return;
    unawaited(_goToMatchOnPage(page, (_) => 0, onlyIfShown: true));
  }

  /// תוצאת מנוע: ההתאמה בעמוד שהטקסט שלה הוא הרצף של התוצאה.
  Future<bool?> _goToEngineResultMatch(SearchResult result, int pageNumber) {
    _schedulePdfHighlight(_lastAdvancedHighlightPattern);
    return _goToMatchOnPage(
      pageNumber,
      (pageMatches) => _engineResultMatchIndex(result, pageNumber, pageMatches),
      beforeNavigate: () => widget.onNavigationStarted?.call(pageNumber),
      revealPageIfPending: () => _revealResultPage(pageNumber),
    );
  }

  Future<bool> _revealResultPage(int pageNumber) async {
    final controller = widget.textSearcher.controller;
    if (controller == null ||
        !controller.isReady ||
        controller.layout.pageLayouts.isEmpty) {
      return false;
    }
    final layout = controller.layout;
    final page =
        layout.pageLayouts[pageNumber.clamp(1, layout.pageLayouts.length) - 1];
    final halfViewHeight =
        controller.viewSize.height / 2 / controller.value.zoom;
    widget.onNavigationStarted?.call(pageNumber);
    await controller.goTo(
      controller.calcMatrixFor(page.topCenter.translate(0, halfViewHeight)),
    );
    return true;
  }

  /// לפי הרצף של התוצאה, ובתוצאות עם אותו רצף — לפי הסדר ביניהן. בלי רצף
  /// תואם: לפי מקום התוצאה בין תוצאות העמוד.
  int _engineResultMatchIndex(
    SearchResult result,
    int pageNumber,
    List<PdfTextSearchResult> pageMatches,
  ) {
    final pattern = _lastAdvancedHighlightPattern;
    String? spanKey(SearchResult r) => pattern is ProximityHighlightPattern
        ? _resultSpanKey(pattern, r)
        : null;
    final key = spanKey(result);
    var k = 0;
    var sameSpanBefore = 0;
    for (final other in _searchResults) {
      if (identical(other, result)) break;
      if (_getPdfPageNumber(other) != pageNumber) continue;
      k++;
      if (key != null && spanKey(other) == key) sameSpanBefore++;
    }
    if (key != null) {
      var seen = 0;
      for (var i = 0; i < pageMatches.length; i++) {
        if (_normalizedSpan(pageMatches[i].text) == key &&
            seen++ == sameSpanBefore) {
          return i;
        }
      }
    }
    return k;
  }

  static String? _resultSpanKey(
    ProximityHighlightPattern pattern,
    SearchResult result,
  ) {
    final plain = SnippetBuilder.htmlToPlainText(result.text);
    final spans = pattern.spans(plain);
    return spans.isEmpty
        ? null
        : _normalizedSpan(plain.substring(spans.first[0], spans.first[1]));
  }

  static final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// אותיות וספרות בלבד: הפיסוק והרווחים בקטע ובשכבת הטקסט אינם זהים.
  static String _normalizedSpan(String text) =>
      utils.removeVolwels(text).replaceAll(_nonWord, ' ').trim();

  /// ההמתנה לסריקת עמוד של המעבר האחרון. מושלמת כשהמעבר כבר לא רלוונטי:
  /// dispose של pdfrx מנקה מאזינים בלי להודיע, וההמתנה הייתה נתקעת.
  Completer<void>? _pageScanWaiter;

  void _cancelPageScanWait() {
    final waiter = _pageScanWaiter;
    _pageScanWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// ממרכז את ההתאמה ש-[pick] בוחר בעמוד אחרי שנסרק. false — אין בו התאמה;
  /// null — מעבר או חיפוש חדש החליפו את המעבר הזה.
  Future<bool?> _goToMatchOnPage(
    int pageNumber,
    int Function(List<PdfTextSearchResult> pageMatches) pick, {
    bool onlyIfShown = false,
    VoidCallback? beforeNavigate,
    Future<bool> Function()? revealPageIfPending,
  }) async {
    _cancelPageScanWait();
    final waiter = _pageScanWaiter = Completer<void>();
    final searcher = widget.textSearcher;
    final generation = _searchGeneration;
    bool isCurrent() =>
        mounted &&
        generation == _searchGeneration &&
        identical(searcher, widget.textSearcher) &&
        identical(waiter, _pageScanWaiter);
    var revealed = false;
    try {
      if (searcher.getMatchesRangeForPage(pageNumber) == null &&
          searcher.isSearching) {
        revealed = await revealPageIfPending?.call() ?? false;
        if (!isCurrent()) return null;
        if (searcher.getMatchesRangeForPage(pageNumber) == null &&
            searcher.isSearching) {
          void onUpdate() {
            if (searcher.getMatchesRangeForPage(pageNumber) != null ||
                !searcher.isSearching) {
              if (!waiter.isCompleted) waiter.complete();
            }
          }

          searcher.addListener(onUpdate);
          try {
            onUpdate();
            await waiter.future;
          } finally {
            searcher.removeListener(onUpdate);
          }
        }
      }
      if (!mounted || !isCurrent()) return null;
      final range = searcher.getMatchesRangeForPage(pageNumber);
      if (onlyIfShown || revealed) {
        final state = context.read<PdfBookBloc>().state;
        if (state is! PdfBookLoaded || _currentPage(state) != pageNumber) {
          return null;
        }
      }
      if (range == null || range.end <= range.start) return revealed;
      final pageMatches = searcher.matches.sublist(range.start, range.end);
      final index = pick(pageMatches).clamp(0, pageMatches.length - 1);
      if (!revealed) beforeNavigate?.call();
      await searcher.goToMatchOfIndex(range.start + index);
      return isCurrent() ? true : null;
    } finally {
      if (identical(waiter, _pageScanWaiter)) _pageScanWaiter = null;
    }
  }

  /// מדגיש על העמוד את מה שהמנוע מצא בפועל (כולל fuzzy/מילים חלופיות).
  void _updateAdvancedHighlight(List<SearchResult> results, String query) {
    final pattern = PdfBookSearchView.buildAdvancedHighlightPattern(
      results.map((r) => r.text),
      query: query,
      settings: _settings,
    );
    _lastAdvancedHighlightPattern = pattern;
    _schedulePdfHighlight(pattern);
  }

  @override
  void initState() {
    super.initState();
    _settings = InBookSearchSettings(
      searchOptions: widget.initialSearchOptions,
      alternativeWords: widget.initialAlternativeWords,
      spacingValues: widget.initialSpacingValues,
      searchMode: widget.initialSearchMode,
      distance: widget.initialSearchDistance,
      matchPolicy:
          widget.initialSearchTemplate?.requestedPolicy ??
          widget.initialMatchPolicy,
      optionsForEveryWord: widget.initialSearchTemplate?.wordDefaults,
    );
    _carriedInQuery =
        widget.initialSearchOrigin == InBookSearchOrigin.globalResult
        ? searchableInBookQuery(widget.searchController.text)
        : null;
    _centerOnOpenTargetPage = widget.takeCenterMatchPage?.call();
    if (!_isBundledTalmudPdf &&
        searchableInBookQuery(widget.searchController.text) == null) {
      _settings = InBookSearchSettings.savedDefaults();
      _syncSearchOptions(context.read<PdfBookBloc>());
    }
    // התצורה הממתינה כבר משוקפת בערכי האתחול; אין להחילה שוב.
    widget.incomingSearchConfiguration?.value = null;
    widget.incomingSearchConfiguration?.addListener(
      _onIncomingSearchConfiguration,
    );
    widget.textSearcher.addListener(_onTextSearcherMatchesChanged);
    // The engine search waits for the book's facet path; until then the pane
    // shows it as running rather than as "no results".
    _isSearching =
        !_isSimpleSearch &&
        searchableInBookQuery(widget.searchController.text) != null;
    _initializeBookPath();
  }

  @override
  void didUpdateWidget(covariant PdfBookSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.outline, widget.outline)) {
      _pageTitles.clear();
      _groupedSource = null;
    }
    if (identical(oldWidget.textSearcher, widget.textSearcher)) return;
    oldWidget.textSearcher.removeListener(_onTextSearcherMatchesChanged);
    widget.textSearcher.addListener(_onTextSearcherMatchesChanged);
    _searchGeneration++;
    _centerOnOpenTargetPage = null;
    _cancelPageScanWait();
    _lastPdfHighlightSource = '';
    _lastAdvancedHighlightPattern = null;
    _mappedMatches = const [];
    _searchResults = [];
    _resultsTruncated = false;
    _pageTitles.clear();
    _isSearching = false;
    _searchErrorMessage = null;
    _pendingSimpleSearchScrollFor = null;
    if (searchableInBookQuery(widget.searchController.text) != null) {
      final generation = _searchGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchGeneration == generation) {
          unawaited(_searchTextUpdated());
        }
      });
    }
  }

  /// מחילה קונפיגורציית חיפוש שהגיעה מפתיחת תוצאה בספר שכבר פתוח.
  void _onIncomingSearchConfiguration() {
    final notifier = widget.incomingSearchConfiguration;
    final configuration = notifier?.value;
    if (configuration == null) return;
    // הריקון מונע מהטאב לכתוב את השאילתה במסלול נפרד עם תצורה ישנה.
    notifier!.value = null;
    if (!mounted) return;

    _carriedInQuery =
        configuration.searchOrigin == InBookSearchOrigin.globalResult
        ? searchableInBookQuery(configuration.searchText)
        : null;
    _centerOnOpenTargetPage = widget.takeCenterMatchPage?.call();
    _applySearchConfiguration(
      query: configuration.searchText,
      settings: InBookSearchSettings(
        searchOptions: configuration.searchOptions,
        alternativeWords: configuration.alternativeWords,
        spacingValues: configuration.spacingValues,
        searchMode: configuration.searchMode,
        distance: configuration.searchDistance,
        matchPolicy:
            configuration.searchTemplate?.requestedPolicy ??
            configuration.matchPolicy,
        optionsForEveryWord: configuration.searchTemplate?.wordDefaults,
      ),
      pdfBookBloc: context.read<PdfBookBloc>(),
    );
  }

  Future<void> _initializeBookPath() async {
    final title = widget.bookTitle?.trim();
    if (title != null && title.isNotEmpty) {
      try {
        await _resolveBookPath(title);
      } catch (e, st) {
        debugPrint('[PdfSearch] resolving the book path failed: $e\n$st');
      }
      if (!mounted) return;
    }
    _bookPathResolved = true;

    if (widget.searchController.text.isNotEmpty) {
      _searchTextUpdated();
    }
  }

  Future<void> _resolveBookPath(String title) async {
    final topics = await BookFacet.resolveTopics(
      title: title,
      initialTopics: widget.bookTopics ?? '',
      type: PdfBook,
      categoryPath: widget.bookCategoryPath,
      externalLibraryId: widget.externalLibraryId,
      bookId: widget.bookId,
      source: widget.source,
      fileType: 'pdf',
      filePath: widget.pdfFilePath,
    );

    if (!mounted) return;

    _bookPath = BookFacet.buildFacetPath(
      title: title,
      topics: topics,
      bookId: widget.bookId,
      source: widget.source,
      externalLibraryId: widget.externalLibraryId,
      categoryPath: widget.bookCategoryPath,
      fileType: 'pdf',
      filePath: widget.pdfFilePath,
    );
  }

  void _onTextSearcherMatchesChanged() {
    if (_isSimpleSearch) {
      if (mounted) {
        setState(() {
          final query = widget.searchController.text;
          final matches = widget.textSearcher.matches;
          final keptCount = _searchResults.length == _mappedMatches.length
              ? PdfBookSearchView.keptMatchCount(_mappedMatches, matches)
              : 0;
          if (keptCount == 0) _searchResults = [];
          for (var i = keptCount; i < matches.length; i++) {
            _searchResults.add(
              SearchResult(
                // בחיפוש הפשוט: אינדקס ההתאמה ב-searcher, לניווט למקומה המדויק.
                id: BigInt.from(i),
                title: widget.bookTitle ?? '',
                reference: '', // Populated by _pageTitles in build
                text: PdfBookSearchView.matchLineSnippet(matches[i], query),
                segment: BigInt.from(matches[i].pageNumber - 1),
                isPdf: true,
                filePath: widget.pdfFilePath ?? '',
                mergedCount: 1,
                merged: const [],
                textStatus: TextStatus.ok,
                continuesToNextLine: false,
              ),
            );
          }
          _mappedMatches = matches;
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

        if (!_isSearching &&
            _searchResults.isEmpty &&
            _searchErrorMessage == null &&
            _textLayerCheckedGeneration != _searchGeneration &&
            searchableInBookQuery(widget.searchController.text) != null) {
          _textLayerCheckedGeneration = _searchGeneration;
          unawaited(_onEmptySimpleSearch(_searchGeneration));
        }
      }
    }
  }

  /// סריקה שהסתיימה בלי אף התאמה: קודם נבדק אם לספר יש טקסט לחפש בו,
  /// ורק אם יש — נסיגה לסדר המילים ההפוך. בספר סרוק בלי טקסט אין מה
  /// לחפש בשום סדר, ולכן שם מוצגת ההודעה בלבד.
  Future<void> _onEmptySimpleSearch(int generation) async {
    if (!await _checkTextLayer(generation)) return;
    if (!mounted || generation != _searchGeneration) return;
    _startReversedOrderSearch();
  }

  /// חיפוש חוזר בסדר המילים ההפוך. שכבת הטקסט של חלק מהספרים הסרוקים
  /// שומרת כל שורה בסדר ויזואלי, ושם הסדר התקין מחזיר תמיד אפס.
  void _startReversedOrderSearch() {
    final query = searchableInBookQuery(widget.searchController.text);
    if (query == null || UserRegexQuery.isValid(query)) return;
    final reversed = PdfBookSearchView.buildSimpleSearchPattern(
      query,
      wholeWord: _wholeWord,
      reversed: true,
    );
    if (reversed == null) return;

    _simpleSearchReversed = true;
    _lastPdfHighlightSource = reversed.source;
    widget.textSearcher.startTextSearch(
      reversed.regExp,
      goToFirstMatch: false,
      searchImmediately: true,
    );
  }

  /// בודקת אם לספר בכלל יש טקסט לחפש בו, כדי שספר סרוק לא יציג
  /// "אין תוצאות" מטעה על מילה שרואים על העמוד. מחזירה אם יש טקסט שמיש.
  Future<bool> _checkTextLayer(int generation) async {
    final pdfState = context.read<PdfBookBloc>().state;
    final pages = PdfBookSearchView.textLayerProbePages(
      currentPage: pdfState is PdfBookLoaded ? _currentPage(pdfState) : 1,
      totalPages: pdfState is PdfBookLoaded ? pdfState.totalPages : 1,
    );

    final texts = <String>[];
    for (final page in pages) {
      final pageText = await widget.textSearcher.loadText(pageNumber: page);
      if (pageText != null) texts.add(pageText.fullText);
    }

    if (!mounted || generation != _searchGeneration) return false;
    // בלי טקסט כלל אי אפשר להכריע (המסמך עדיין לא נטען) — נשארים ב"אין תוצאות".
    if (texts.isEmpty) return false;
    if (PdfBookSearchView.hasSearchableText(texts)) return true;
    setState(() => _searchErrorMessage = PdfMessages.noTextLayer);
    return false;
  }

  /// הקודמת/הבאה, ועצירה בזמן סריקה — רק בחיפוש הפשוט, שבו כל תוצאה היא התאמה.
  Widget? _buildResultToolbar() {
    if (!_isSimpleSearch) return null;
    final searcher = widget.textSearcher;
    final isScanning = _isSearching;
    if (_searchResults.isEmpty && !isScanning) return null;
    final current = searcher.currentIndex;
    final hasResults = _searchResults.isNotEmpty;
    return SearchResultNavigator(
      previousTooltip: 'התוצאה הקודמת',
      nextTooltip: 'התוצאה הבאה',
      onStop: isScanning ? searcher.stopTextSearch : null,
      onPrevious: hasResults && (current ?? 0) > 0
          ? () => navigateSearchMatch(forward: false)
          : null,
      onNext:
          hasResults && (current == null || current < _searchResults.length - 1)
          ? () => navigateSearchMatch(forward: true)
          : null,
    );
  }

  String? _resultCountString() {
    if (_searchResults.isEmpty) return null;
    final current = widget.textSearcher.currentIndex;
    if (_isSimpleSearch && current != null && current < _searchResults.length) {
      return 'תוצאה ${current + 1} מתוך ${_searchResults.length}';
    }
    if (_resultsTruncated) {
      return 'מוצגות ${_searchResults.length} התוצאות הראשונות';
    }
    return 'נמצאו ${_searchResults.length} תוצאות';
  }

  int _beginResultNavigation() {
    _centerOnOpenTargetPage = null;
    _cancelPageScanWait();
    return ++_navigationRequest;
  }

  void navigateSearchMatch({required bool forward}) {
    _beginResultNavigation();
    final searcher = widget.textSearcher;
    final index = forward
        ? (searcher.currentIndex ?? -1) + 1
        : (searcher.currentIndex ?? searcher.matches.length) - 1;
    if (index < 0 || index >= searcher.matches.length) return;
    widget.onNavigationStarted?.call(searcher.matches[index].pageNumber);
    unawaited(forward ? searcher.goToNextMatch() : searcher.goToPrevMatch());
  }

  /// currentPageNumber ב-state נקבע בפתיחה בלבד; העמוד המוצג בפועל נמצא בקונטרולר.
  int _currentPage(PdfBookLoaded state) =>
      widget.textSearcher.controller?.pageNumber ?? state.currentPageNumber;

  void _scheduleScrollToCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final pdfState = context.read<PdfBookBloc>().state;
      if (pdfState is! PdfBookLoaded) return;

      final resultsPageNumbers = _searchResults.map(_getPdfPageNumber).toList();
      if (resultsPageNumbers.isEmpty) return;

      final visualIdx = PdfBookSearchView.computeTargetVisualIndexForTesting(
        resultsPageNumbersSorted: resultsPageNumbers,
        currentPage: _currentPage(pdfState),
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
    _cancelPageScanWait();
    super.dispose();
  }

  /// מחיל את הפרמטרים שחזרו מדיאלוג החיפוש המתקדם ומריץ חיפוש מחדש.
  ///
  /// חוזרים למסלול החיפוש הפשוט כשכל הפרמטרים ריקים והמצב מדויק.
  void applySearchDialogResult(
    SearchDialogResult result,
    PdfBookBloc pdfBookBloc,
  ) {
    _carriedInQuery = null;
    _applySearchConfiguration(
      query: result.query,
      settings: InBookSearchSettings.fromDialogResult(result),
      pdfBookBloc: pdfBookBloc,
    );
  }

  /// מחילה את התצורה לפני השאילתה ומריצה חיפוש אחד בלבד.
  void _applySearchConfiguration({
    required String query,
    required InBookSearchSettings settings,
    required PdfBookBloc pdfBookBloc,
  }) {
    setState(() {
      _settings = settings.forQuery(searchableInBookQuery(query) ?? '');
      // The preference is global; a toggle in another tab leaves a stale value.
      _wholeWord = InBookSearchPreferences.loadWholeWord();
    });
    _syncSearchOptions(pdfBookBloc);

    // שינוי תוכניתי של ה-controller אינו מפעיל את onChanged של השדה, ולכן
    // החיפוש מורץ כאן ישירות.
    syncSearchControllerQuery(widget.searchController, query);
    _searchTextUpdated();
  }

  void _syncSearchOptions(PdfBookBloc pdfBookBloc) {
    pdfBookBloc.add(
      UpdateSearchOptions(
        searchOptions: _searchOptions,
        alternativeWords: _alternativeWords,
        spacingValues: _spacingValues,
        searchMode: _searchMode,
        searchDistance: _searchDistance,
        matchPolicy: _matchPolicy,
        searchOrigin: _searchOrigin,
        searchTemplate: _settings.template,
      ),
    );
  }

  Future<void> _searchTextUpdated() async {
    // כל שינוי בשאילתה/במצב החיפוש מבטל תוצאות אסינכרוניות ישנות. בלי מזהה
    // דור, חיפוש איטי קודם יכול להסתיים אחרי החדש ולדרוס תוצאות והדגשות.
    final generation = ++_searchGeneration;
    _cancelPageScanWait();
    _resultsTruncated = false;
    // הדגל שייך לדור הקודם: כל מסלול יוצא מכאן בסדר השאילתה, והנסיגה
    // תדליק אותו מחדש אם תרוץ.
    _simpleSearchReversed = false;
    final searchable = searchableInBookQuery(widget.searchController.text);
    _settings = _settings.forQuery(searchable ?? '');
    if (_settings.optionsForEveryWord != null) {
      _syncSearchOptions(context.read<PdfBookBloc>());
    }

    // בלי ההודעה הזו מסלול המנוע במסכת PDF מצורפת מציג "אין תוצאות" גנרי.
    if (searchable != null && !_isSimpleSearch && _isBundledTalmudPdf) {
      _pendingSimpleSearchScrollFor = null;
      _lastAdvancedHighlightPattern = null;
      _schedulePdfHighlight(null);
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _searchErrorMessage =
              PdfMessages.advancedSearchUnavailableInTalmudPdf;
        });
      }
      return;
    }

    if (searchable != null && !_isSimpleSearch && _bookPath == null) {
      // _initializeBookPath runs the search again once the path is resolved.
      _pendingSimpleSearchScrollFor = null;
      _lastAdvancedHighlightPattern = null;
      _schedulePdfHighlight(null);
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = !_bookPathResolved;
          _searchErrorMessage = _bookPathResolved
              ? LibraryMessages.searchError
              : null;
        });
      }
      return;
    }

    if (searchable == null) {
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

    final query = searchable;

    // איפוס השגיאה לפני פיצול המסלול — במסלול הפשוט התוצאות מגיעות
    // אסינכרונית, ובלי האיפוס כאן שגיאת מנוע קודמת נשארת מוצגת.
    if (mounted) {
      setState(() {
        _searchErrorMessage = null;
        if (!_isSimpleSearch) _isSearching = true;
      });
    }

    if (_isSimpleSearch) {
      _pendingSimpleSearchScrollFor = query;
      final userRegex = PdfUserRegexPattern.tryParse(query);
      // תבנית סובלנית-ניקוד מהמנוע, כדי שגם PDF ששכבת הטקסט שלו מנוקדת יודגש.
      final literal = userRegex != null
          ? null
          : PdfBookSearchView.buildSimpleSearchPattern(
              // כמו הדגשת התוצאות: רווח בקצה השדה מעגן התאמה חלקית לגבול מילה.
              widget.searchController.text,
              wholeWord: _wholeWord,
            );
      _lastPdfHighlightSource = literal?.source ?? query;
      // שדה החיפוש כבר ממתין להפסקת ההקלדה; השהיית pdfrx הייתה מוסיפה עוד 500ms.
      widget.textSearcher.startTextSearch(
        userRegex ?? literal?.regExp ?? query,
        goToFirstMatch: false,
        searchImmediately: true,
      );
      _centerOpenTargetMatch();
      return;
    }

    try {
      final rawResults = await searchBookWithEngine(
        widget.searchRepository,
        query: query,
        bookPath: _bookPath!,
        limit: kInBookEngineFetchLimit,
        settings: _settings,
      );

      final indexedFilePath = _indexedFilePath;
      final sorted =
          rawResults
              .where((r) {
                if (!r.isPdf) return false;
                if (indexedFilePath.isEmpty) return true;
                return r.filePath == indexedFilePath;
              })
              .toList(growable: true)
            ..sort((a, b) {
              final sa = a.segment.toInt();
              final sb = b.segment.toInt();
              if (sa != sb) return sa.compareTo(sb);
              return a.reference.compareTo(b.reference);
            });
      final (shown: results, :truncated) = limitInBookResults(sorted);

      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = results;
        _resultsTruncated = truncated;
        _isSearching = false;
        if (results.isEmpty) {
          _searchErrorMessage = PdfBookSearchView.missingFromIndexNotice(
            indexedFilePath: _indexedFilePath,
            indexInitialized: TantivyDataProvider.instance.isInitialized.value,
            indexedFilePaths: TantivyDataProvider.instance.indexedFilePaths,
            excludedByIndexMode:
                widget.source.isUser &&
                !IndexUpdateMode.readStored().indexesPersonalBooks,
          );
        }
      });
      _updateAdvancedHighlight(results, query);
      _centerOpenTargetMatch();
      _scheduleScrollToCurrentPage();
    } catch (e, st) {
      debugPrint('[PdfSearch] search failed for "$query": $e\n$st');
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchErrorMessage = LibraryMessages.searchError;
      });
      _updateAdvancedHighlight(const [], query);
      UiSnack.showError(LibraryMessages.searchError);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!identical(_groupedSource, _searchResults)) {
      _groupedSource = _searchResults;
      _groupedItems.clear();
      _groupedCount = 0;
      _lastGroupedPage = null;
    }

    // pdfrx סורק לפי עמוד; תוצאות המנוע ממוינות לפני ההשמה.
    for (var i = _groupedCount; i < _searchResults.length; i++) {
      final result = _searchResults[i];
      final page = _getPdfPageNumber(result);
      if (page != _lastGroupedPage) {
        _groupedItems.add(page);
        _lastGroupedPage = page;
        _pageTitles.putIfAbsent(
          page,
          () => referenceFromPageNumber(page, widget.outline, widget.bookTitle),
        );
      }
      _groupedItems.add(result);
    }
    _groupedCount = _searchResults.length;
    final items = _groupedItems;

    return SearchPaneBase(
      searchController: widget.searchController,
      searchFieldExtraActions: const PluginSearchFieldExtraActions(
        PluginSearchField.inBook,
      ),
      focusNode: widget.focusNode,
      progressWidget: _isSearching
          ? LinearProgressIndicator(
              minHeight: 4,
              // המנוע אינו מדווח התקדמות; החיפוש הפשוט עובר עמוד-עמוד.
              value: _isSimpleSearch
                  ? widget.textSearcher.searchProgress
                  : null,
            )
          : null,
      resultCountString: _resultCountString(),
      resultToolbar: _buildResultToolbar(),
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
                  final text = _pageTitles[item]?.isNotEmpty == true
                      ? _pageTitles[item]!
                      : 'עמוד $item';
                  return NavTreeHeader(
                    title: withHolyNamesSetting(text, settingsState),
                  );
                },
              );
            }

            final result = item as SearchResult;
            return NavTreeGroupCard(
              isGroupStart: isGroupStart,
              isGroupEnd: isGroupEnd,
              child: SearchResultTile(
                key: ValueKey(
                  '${result.segment}_${result.id}_${result.text.hashCode}',
                ),
                result: result,
                onTap: () async {
                  final request = _beginResultNavigation();
                  final generation = _searchGeneration;
                  final searcher = widget.textSearcher;
                  final pageNumber = _getPdfPageNumber(result);
                  final matchIndex = result.id.toInt();
                  if (_isSimpleSearch &&
                      matchIndex < widget.textSearcher.matches.length &&
                      widget.textSearcher.matches[matchIndex].pageNumber ==
                          pageNumber) {
                    // גלילה למקום ההתאמה בעמוד וסימונה כהתאמה הנוכחית.
                    widget.onNavigationStarted?.call(pageNumber);
                    await widget.textSearcher.goToMatchOfIndex(matchIndex);
                  } else {
                    final navigated = _isSimpleSearch
                        ? false
                        : await _goToEngineResultMatch(result, pageNumber);
                    if (navigated == null) return;
                    if (!navigated) {
                      await _revealResultPage(pageNumber);
                    }
                  }

                  if (!mounted ||
                      generation != _searchGeneration ||
                      request != _navigationRequest ||
                      !identical(searcher, widget.textSearcher)) {
                    return;
                  }
                  _schedulePdfHighlight(
                    _isSimpleSearch
                        ? PdfBookSearchView.buildSimpleSearchPattern(
                            widget.searchController.text,
                            wholeWord: _wholeWord,
                            reversed: _simpleSearchReversed,
                          )?.regExp
                        : _lastAdvancedHighlightPattern,
                  );
                  widget.onSearchResultNavigated?.call();
                },
                query: widget.searchController.text,
                isSimpleSearch: _isSimpleSearch,
                wholeWord: _wholeWord,
              ),
            );
          },
        ),
      ),
      isNoResults:
          searchableInBookQuery(widget.searchController.text) != null &&
          _searchResults.isEmpty &&
          !_isSearching,
      errorMessage: _searchErrorMessage,
      onSearchTextChanged: (_) {
        // value מה-debounce עשוי להקדים שאילתה חיצונית שכבר נכתבה לשדה.
        final query = searchableInBookQuery(widget.searchController.text);
        if (_carriedInQuery != null && query != _carriedInQuery) {
          _carriedInQuery = null;
          _settings = _paneDefaults;
          _syncSearchOptions(context.read<PdfBookBloc>());
        }
        _searchTextUpdated();
      },
      resetSearchCallback: () {
        _pendingSimpleSearchScrollFor = null;
        _lastAdvancedHighlightPattern = null;
        setState(() {
          _searchResults = [];
          _resultsTruncated = false;
          _searchErrorMessage = null;
          _carriedInQuery = null;
          _settings = _paneDefaults;
        });
        _syncSearchOptions(context.read<PdfBookBloc>());
        _schedulePdfHighlight(null);
      },
      searchFieldActions: [
        if (_isSimpleSearch)
          wholeWordSearchAction(
            context: context,
            wholeWord: _wholeWord,
            onToggle: _toggleWholeWord,
          ),
      ],
      hintText: 'חפש כאן...',
      onAdvancedSearch: () async {
        final pdfBookBloc = context.read<PdfBookBloc>();
        final result = await showInBookAdvancedSearchDialog(
          context,
          bookTitle: widget.bookTitle,
          query: widget.searchController.text,
          settings: _settings,
        );

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
    required this.query,
    required this.isSimpleSearch,
    required this.wholeWord,
    super.key,
  });

  final SearchResult result;
  final void Function() onTap;
  final String query;
  final bool isSimpleSearch;
  final bool wholeWord;

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
    final style = InBookSnippetStyle(context, settingsState);
    final defaultStyle = style.text;
    final html = withHolyNamesSetting(text, settingsState);

    if (query.isEmpty) {
      return Text(
        utils.stripHtmlIfNeeded(html),
        style: defaultStyle,
      );
    }

    final highlightStyle = style.highlight;

    if (isSimpleSearch) {
      final spans = SnippetBuilder.highlightLiteral(
        plainText: utils.stripHtmlIfNeeded(html),
        query: query,
        defaultStyle: defaultStyle,
        highlightStyle: highlightStyle,
        wholeWord: wholeWord,
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
