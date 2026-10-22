import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

/// כרטיסיית קורא PDF עם מצב המשתמש ובקר התצוגה שלה.
class PdfBookTab extends OpenedTab {
  /// The PDF book.
  final PdfBook book;

  /// The current page number.
  int pageNumber;

  /// The pdf viewer controller.
  PdfViewerController pdfViewerController = PdfViewerController();
  final navigationHistory = PdfLocationHistory();

  /// האם הדף רחב מהתצוגה (זום מוגדל), כך שיש לאן לגלול לרוחב.
  bool get canPanHorizontally {
    final controller = pdfViewerController;
    return controller.isReady &&
        controller.visibleRect.width < controller.documentSize.width - 1;
  }

  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);

  final documentRef = ValueNotifier<PdfDocumentRef?>(null);

  final TextEditingController searchController = TextEditingController();

  String searchText;
  Map<String, Map<String, bool>> searchOptions;
  Map<int, List<String>> alternativeWords;
  Map<String, String> spacingValues;
  SearchMode searchMode;
  int searchDistance;

  /// טווח הקרבה ומצב התאמת המילים שבהם נמצאה התוצאה — ראו [SearchMatchPolicy].
  SearchMatchPolicy matchPolicy;

  List<PdfTextSearchResult>? pdfSearchMatches;
  int? pdfSearchCurrentMatchIndex;

  /// תצורת חיפוש חיצונית שממתינה להחלה בחלונית החיפוש.
  final ValueNotifier<ReadingTabSearchState?> incomingSearchConfiguration =
      ValueNotifier<ReadingTabSearchState?>(null);

  /// עמודי התאמה ממנוע חיפוש חיצוני (תוסף) — ראו [ExternalBookMatches].
  /// מתעדכן גם על-ידי חיפוש-בתוך-ספר שמנותב לספק חיצוני; null = אין.
  final ValueNotifier<ExternalBookMatches?> externalMatches;

  final currentTitle = ValueNotifier<String>("");

  ///a flag that tells if the left pane should be shown
  late final ValueNotifier<bool> showLeftPane;

  ///a flag that tells if the left pane should be pinned on scrolling
  final pinLeftPane = ValueNotifier<bool>(false);

  /// counter שמתגלגל עם כל בקשה לטוגל חלונית הניווט (השמאלית) מקיצור מקלדת
  /// גלובלי. המאזין הוא [PdfBookScreen] בלבד; כל הגדלה = toggle יחיד.
  final ValueNotifier<int> toggleNavPaneNotifier = ValueNotifier<int>(0);

  /// counter שמתגלגל עם כל בקשה לטוגל חלונית המפרשים (הימנית) מקיצור מקלדת
  /// גלובלי. המאזין הוא [PdfBookScreen] בלבד; כל הגדלה = toggle יחיד.
  final ValueNotifier<int> toggleCommentatorsPaneNotifier = ValueNotifier<int>(
    0,
  );

  /// counter שמתגלגל עם כל בקשה למעבר למהדורת הטקסט מקיצור מקלדת גלובלי.
  /// המאזין הוא [PdfBookScreen] בלבד; כל הגדלה = מעבר יחיד.
  final ValueNotifier<int> toggleTextViewNotifier = ValueNotifier<int>(0);

  /// PDF headings mapping for commentaries and links
  PdfHeadings? pdfHeadings;

  /// Links for the current book
  List<Link> links = [];

  /// true כשהכרטיסייה מחזיקה את כל קישורי הספר, כדי שטעינת חלון לא תדרוס אותם.
  bool linksAreComplete = false;

  /// Active commentators to show
  Set<String> activeCommentators = <String>{};

  /// מצב הטעינה שמשותף לקורא ולכרטיסיית המפרשים.
  final ValueNotifier<bool> linksLoadingNotifier = ValueNotifier<bool>(true);

  /// Current line number in text (based on PDF heading)
  int? currentTextLineNumber;

  /// End line number in text for the current page (start of next page - 1)
  int? currentTextLineNumberEnd;

  /// Saved zoom level for restoration after rebuild
  double? savedZoom;

  /// Saved layout mode for restoration after rebuild
  PdfLayoutMode? get savedLayoutMode => _savedMode;
  PdfLayoutMode? _savedMode;

  /// תצוגת ספר רחבה פי שניים, ולכן [savedZoom] שנמדד בתצוגה השנייה פסול.
  set savedLayoutMode(PdfLayoutMode? mode) {
    final previous = _savedMode;
    if (previous != null &&
        mode != null &&
        previous.isBookView != mode.isBookView) {
      savedZoom = null;
    }
    _savedMode = mode;
  }

  /// מבטל טעינה הדרגתית בפתיחה ישירה לעמוד גבוה, כדי שעדכון ממדי העמודים
  /// לא יזיז את המיקום הנראה. הפתיחה עצמה עשויה להיות איטית יותר.
  final bool requiresStableLayout;

  PdfBookTab({
    required this.book,
    required this.pageNumber,
    bool openLeftPane = false,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.pdfSearchMatches,
    this.pdfSearchCurrentMatchIndex,
    super.isPinned,
    super.dedupeKey,
    this.requiresStableLayout = false,
    ExternalBookMatches? externalMatches,
  }) : externalMatches = ValueNotifier<ExternalBookMatches?>(externalMatches),
       super(book.title) {
    debugPrint(
      '🔧 PdfBookTab created: book=${book.title}, pageNumber=$pageNumber',
    );
    showLeftPane = ValueNotifier<bool>(openLeftPane);
    searchController.text = searchText;
    pinLeftPane.value = Settings.getValue<bool>('key-pin-sidebar') ?? false;
  }

  @override
  OpenedTab clone() => PdfReadingSnapshot._capture(this).createTab();

  /// מחיל תצורת חיפוש חיצונית בלי לחשוף שאילתה לתצורה הישנה.
  void applyIncomingSearchConfiguration(ReadingTabSearchState configuration) {
    searchText = configuration.searchText;
    searchOptions = configuration.searchOptions;
    alternativeWords = configuration.alternativeWords;
    spacingValues = configuration.spacingValues;
    searchMode = configuration.searchMode;
    searchDistance = configuration.searchDistance;
    matchPolicy = configuration.matchPolicy;

    incomingSearchConfiguration.value = configuration;
    if (incomingSearchConfiguration.value != null) {
      searchController.text = configuration.searchText;
    }
  }

  /// משחזר כרטיסייה בפורמט הקיים, כולל שמירות ללא נתוני ספר מקוננים.
  factory PdfBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane = resolveRestoredReadingLeftPaneState(json);

    final PdfBook restoredBook = json['book'] != null
        ? Book.fromJson(Map<String, dynamic>.from(json['book'])) as PdfBook
        : PdfBook(title: getTitleFromPath(json['path']), path: json['path']);

    final int pageNumber = json['pageNumber'] ?? 1;

    PdfLayoutMode? savedLayoutMode;
    if (json['savedLayoutMode'] != null) {
      savedLayoutMode = PdfLayoutMode.values.firstWhere(
        (e) => e.name == json['savedLayoutMode'],
        orElse: () => PdfLayoutMode.regularView,
      );
    }

    // קונפיגורציית החיפוש נטענת מהדיסק — ראו [ReadingTabSearchState].
    final searchState = ReadingTabSearchState.fromJson(json);

    final tab = PdfBookTab(
      book: restoredBook,
      pageNumber: pageNumber,
      openLeftPane: shouldOpenLeftPane,
      isPinned: json['isPinned'] ?? false,
      requiresStableLayout: json['requiresStableLayout'] ?? false,
      searchText: searchState.searchText,
      searchOptions: searchState.searchOptions,
      alternativeWords: searchState.alternativeWords,
      spacingValues: searchState.spacingValues,
      searchMode: searchState.searchMode,
      searchDistance: searchState.searchDistance,
      matchPolicy: searchState.matchPolicy,
      externalMatches: ExternalBookMatches.fromJson(json['externalMatches']),
    );

    tab.savedLayoutMode = savedLayoutMode;
    final active = (json['activeCommentators'] as List?)?.cast<String>();
    if (active != null) tab.activeCommentators = active.toSet();
    tab.savedZoom = (json['savedZoom'] as num?)?.toDouble();
    tab.historySlot = json['historySlot'] as String?;

    return tab;
  }

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    searchController.dispose();
    outline.dispose();
    documentRef.dispose();
    currentTitle.dispose();
    linksLoadingNotifier.dispose();
    showLeftPane.dispose();
    pinLeftPane.dispose();
    toggleNavPaneNotifier.dispose();
    toggleCommentatorsPaneNotifier.dispose();
    toggleTextViewNotifier.dispose();
    incomingSearchConfiguration.dispose();
    externalMatches.dispose();
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() => PdfReadingSnapshot._capture(this).toJson();
}

/// מצב המשתמש בקורא PDF; קישורים ומיפויי טקסט נגזרים נטענים בנפרד.
class PdfReadingSnapshot {
  PdfReadingSnapshot._capture(PdfBookTab tab)
    : _book = tab.book,
      _pageNumber = tab.pageNumber,
      _persistedPageNumber = tab.pageNumber,
      _showLeftPane = tab.showLeftPane.value,
      _isPinned = tab.isPinned,
      _dedupeKey = tab.dedupeKey,
      _historySlot = tab.historySlot,
      _requiresStableLayout = tab.requiresStableLayout,
      _externalMatches = tab.externalMatches.value,
      _activeCommentators = Set.of(tab.activeCommentators),
      _savedZoom = tab.savedZoom,
      _savedLayoutMode = tab.savedLayoutMode,
      _persistedSearchText = tab.searchController.text,
      _search = ReadingTabSearchState(
        searchText: tab.searchText,
        searchOptions: tab.searchOptions,
        alternativeWords: tab.alternativeWords,
        spacingValues: tab.spacingValues,
        searchMode: tab.searchMode,
        searchDistance: tab.searchDistance,
        matchPolicy: tab.matchPolicy,
      ).copy() {
    // השמירה קוראת את העמוד החי; לשכפול מספיק העמוד המסונכרן של הטאב.
    try {
      if (tab.pdfViewerController.isReady) {
        _persistedPageNumber =
            tab.pdfViewerController.pageNumber ?? _pageNumber;
      }
    } catch (_) {
      _persistedPageNumber = _pageNumber;
    }
  }

  final PdfBook _book;
  final int _pageNumber;
  int _persistedPageNumber;
  final bool _showLeftPane;
  final bool _isPinned;
  final String? _dedupeKey;
  final String? _historySlot;
  final bool _requiresStableLayout;
  final ExternalBookMatches? _externalMatches;
  final Set<String> _activeCommentators;
  final double? _savedZoom;
  final PdfLayoutMode? _savedLayoutMode;
  final String _persistedSearchText;
  final ReadingTabSearchState _search;

  /// יוצר טאב עם בקרים משלו, בלי להעתיק מצב נגזר של המסמך.
  PdfBookTab createTab() {
    final search = _search.copy();
    return PdfBookTab(
        book: _book,
        pageNumber: _pageNumber,
        openLeftPane: _showLeftPane,
        searchText: search.searchText,
        searchOptions: search.searchOptions,
        alternativeWords: search.alternativeWords,
        spacingValues: search.spacingValues,
        searchMode: search.searchMode,
        searchDistance: search.searchDistance,
        matchPolicy: search.matchPolicy,
        isPinned: _isPinned,
        dedupeKey: _dedupeKey,
        requiresStableLayout: _requiresStableLayout,
        externalMatches: _externalMatches,
      )
      ..activeCommentators = Set.of(_activeCommentators)
      ..savedZoom = _savedZoom
      ..savedLayoutMode = _savedLayoutMode
      ..historySlot = _historySlot;
  }

  /// השדה החי נשמר גם כשהחיפוש נוקה, בלי להחזיר טקסט ישן מהטאב.
  Map<String, dynamic> toJson() {
    return {
      'path': _book.path,
      'book': _book.toJson(),
      'pageNumber': _persistedPageNumber,
      'showLeftPane': _showLeftPane,
      'isPinned': _isPinned,
      'type': 'PdfBookTab',
      'historySlot': ?_historySlot,
      'requiresStableLayout': _requiresStableLayout,
      if (_externalMatches case final matches?)
        'externalMatches': matches.toJson(),
      if (_savedLayoutMode != null) 'savedLayoutMode': _savedLayoutMode.name,
      if (_activeCommentators.isNotEmpty)
        'activeCommentators': _activeCommentators.toList(),
      'savedZoom': ?_savedZoom,
      ..._search.copy(searchText: _persistedSearchText).toJson(),
    };
  }
}
