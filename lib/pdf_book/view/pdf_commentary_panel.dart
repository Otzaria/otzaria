import 'package:flutter/foundation.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/layout/commentators_filter_screen.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_content.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'dart:async'; // Added for Timer
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Type alias לתאימות - משתמש ב-LinkGroup מה-Service
typedef CommentaryGroup = LinkGroup;

/// האם קישור (לפי [linkIndex1]) בתחום המוצג: בטווח הראשי [startLine]–[endLine]
/// או באחת השורות הנוספות של ריבוי-הבחירה ([extraLineIndices], Ctrl+לחיצה).
@visibleForTesting
bool pdfLinkInVisibleScope(
  int linkIndex1,
  int startLine,
  int endLine,
  Set<int>? extraLineIndices,
) {
  if (linkIndex1 >= startLine && linkIndex1 <= endLine) return true;
  return extraLineIndices?.contains(linkIndex1) ?? false;
}

/// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
/// משתמש ב-CommentaryService
List<CommentaryGroup> _groupConsecutiveLinks(List<Link> links) {
  return CommentaryService.groupConsecutiveLinks(links);
}

/// תוצאת סיווג יעדי הקישורים לבניית קבוצות המפרשים: מפרשים (סוגים תלויי-טקסט)
/// עם ספירה פר-מפרש לזיהוי "מפרש נדיר", יעדים שאינם מפרשים (ל-preload דורות),
/// והשורה הגבוהה ביותר עם קישור (אומדן גיבוי למספר שורות הספר).
typedef LinkTargetsAggregation = ({
  Set<String> commentators,
  Map<String, int> linkCountByTitle,
  Set<String> nonCommentaryTitles,
  int maxSourceLine,
});

/// סיווג מתוך רשימת קישורים טעונה — הרשימה המלאה, או חלון הקישורים
/// כ-fallback כששאילתת הסיכום נכשלת.
@visibleForTesting
LinkTargetsAggregation aggregateLinkTargetsFromLinks(Iterable<Link> links) {
  final commentators = <String>{};
  final linkCountByTitle = <String, int>{};
  final nonCommentaryTitles = <String>{};
  var maxSourceLine = 0;
  for (final link in links) {
    if (link.index1 > maxSourceLine) maxSourceLine = link.index1;
    final title = utils.getTitleFromPath(link.path2);
    if (LinkTypes.isDependentTextLink(link.connectionType)) {
      commentators.add(title);
      linkCountByTitle[title] = (linkCountByTitle[title] ?? 0) + 1;
    } else {
      nonCommentaryTitles.add(title);
    }
  }
  return (
    commentators: commentators,
    linkCountByTitle: linkCountByTitle,
    nonCommentaryTitles: nonCommentaryTitles,
    maxSourceLine: maxSourceLine,
  );
}

/// סיווג מתוך סיכום המסד (getBookLinkTargetsSummary) — אותם כללים בדיוק
/// כמו [aggregateLinkTargetsFromLinks], בלי לטעון את הקישורים עצמם.
@visibleForTesting
LinkTargetsAggregation aggregateLinkTargetsFromSummary(
    List<LinkTargetSummary> targets, int maxSourceLine) {
  final commentators = <String>{};
  final linkCountByTitle = <String, int>{};
  final nonCommentaryTitles = <String>{};
  for (final target in targets) {
    final title = utils.getTitleFromPath(target.targetTitle);
    if (LinkTypes.isDependentTextLink(target.connectionType)) {
      commentators.add(title);
      linkCountByTitle[title] =
          (linkCountByTitle[title] ?? 0) + target.linkCount;
    } else {
      nonCommentaryTitles.add(title);
    }
  }
  return (
    commentators: commentators,
    linkCountByTitle: linkCountByTitle,
    nonCommentaryTitles: nonCommentaryTitles,
    maxSourceLine: maxSourceLine,
  );
}

/// Widget שמציג מפרשים וקישורים עבור PDF
class PdfCommentaryPanel extends StatefulWidget {
  final PdfBookTab tab;
  final int linksCount;
  final bool linksLoading;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final VoidCallback? onClose;
  final int? initialTabIndex;
  final ValueChanged<int>? onTabChanged;
  final ValueListenable<int>? openFilterRequest;
  final ValueNotifier<int>? openFilterNotifier;

  /// כשאמת — מציג כמסך מלא (כמו CommentatorsTabScreen) ללא כרטיסיות פאנל
  final bool isFullScreen;

  /// כשאמת (ברירת מחדל) — בחירת המפרשים מתבצעת ב-overlay פנימי של הפאנל.
  /// כשמכובה — הבחירה מנוהלת חיצונית (לשונית "מפרשים" בפאנל הצד של הכרטיסייה),
  /// וכל בקשה לבחירת מפרשים מנותבת ל-[onSelectCommentatorsRequested].
  final bool enableInternalFilter;

  /// נקרא כשהמשתמש מבקש לבחור מפרשים ו-[enableInternalFilter] מכובה.
  final VoidCallback? onSelectCommentatorsRequested;

  /// override לטווח השורות בטקסט (לכרטסייה עצמאית)
  final int? lineStartOverride;
  final int? lineEndOverride;

  /// שורות נוספות (לא רצופות) להצגת מפרשים — ריבוי-בחירה ב'ניווט' (Ctrl+לחיצה).
  /// כשמסופק, קישור נכלל אם הוא בטווח הראשי או ש-index1 שלו נמצא בקבוצה זו.
  final Set<int>? extraLineIndices;

  /// חיפוש חיצוני — כשמסופק, מסתיר שורת חיפוש פנימית
  final TextEditingController? externalSearchController;
  final ValueNotifier<int>? externalTotalResultsNotifier;
  final ValueNotifier<int>? externalCurrentIndexNotifier;

  /// משקף החוצה את מצב "הכל מורחב" (לכפתור הכיווץ/הרחבה בסרגל הכרטיסייה).
  final ValueNotifier<bool>? externalAllExpandedNotifier;

  /// הסרת ניקוד/פיסוק מתוכן המפרשים (כמו בכרטיסיית הטקסט).
  final bool removeNikud;
  final bool removePunctuation;

  const PdfCommentaryPanel({
    super.key,
    required this.tab,
    required this.linksCount,
    this.linksLoading = false,
    required this.openBookCallback,
    required this.fontSize,
    this.onClose,
    this.initialTabIndex,
    this.onTabChanged,
    this.openFilterRequest,
    this.openFilterNotifier,
    this.isFullScreen = false,
    this.enableInternalFilter = true,
    this.onSelectCommentatorsRequested,
    this.lineStartOverride,
    this.lineEndOverride,
    this.extraLineIndices,
    this.externalSearchController,
    this.externalTotalResultsNotifier,
    this.externalCurrentIndexNotifier,
    this.externalAllExpandedNotifier,
    this.removeNikud = false,
    this.removePunctuation = false,
  });

  @override
  State<PdfCommentaryPanel> createState() => PdfCommentaryPanelState();
}

class PdfCommentaryPanelState extends State<PdfCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late VoidCallback _tabControllerListener;
  int _lastNotifiedTabIndex = 0;
  bool _showFilterTab = false;
  // ערך בסיס של counter ה-openFilterRequest שראינו ב-init. רק עליות מעבר
  // לערך הזה מטריגרות פתיחה — counter ישן לא ייספג שוב ביצירה מחודשת.
  int _lastSeenFilterRequest = 0;

  void _handleOpenFilterRequest() {
    if (!mounted) return;
    final newValue = widget.openFilterRequest?.value ?? 0;
    if (newValue <= _lastSeenFilterRequest) return;
    _lastSeenFilterRequest = newValue;
    setState(() => _showFilterTab = true);
  }

  String? _savedSelectedText;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _currentSearchIndex = 0;
  int _totalSearchResults = 0;
  bool _allExpanded = true;
  // האם להציג את שדה החיפוש (true) או את שורת ארבעת הלחצנים (false)
  bool _showSearchField = false;
  final Map<String, bool> _expansionStates = {};

  // Anti-jitter search stats
  final Map<String, int> _searchResultsPerLink = {};
  Timer? _searchUpdateDebounce;
  final Map<String, int> _pendingCounts = {};
  // חישוב ספירות חיפוש ברקע על כל הקישורים — הרשימה וירטואלית ופריטים שלא
  // נבנו אינם מדווחים, לכן אסור להסתמך על ה-widgets לספירה.
  Timer? _searchComputeDebounce;
  int _searchComputeGen = 0;
  int _lastLinksSignature = 0;

  // Scroll support
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  final FocusNode _commentaryFocusNode = FocusNode();
  final Map<String, GlobalKey> _itemKeys = {};
  final Map<String, Future<String>> _linkContentCache = {};
  final Map<String, bool> _expandedLinkStates = {};
  List<Link> _orderedLinks = [];
  List<CommentaryGroup> _orderedGroups = [];
  _PdfVisibleContentCache? _visibleContentCache;
  List<CommentatorGroup> _commentatorGroups = [];

  /// מפרשים "נדירים" שמוסתרים מלשונית הבחירה (ספרים גדולים בלבד).
  Set<String> _rareCommentators = {};

  String _getLinkKey(Link link) =>
      '${link.path2}_${link.index1}_${link.index2}';

  Future<String> _getCachedLinkContent(String keyStr, Link link) {
    final cachedFuture = _linkContentCache[keyStr];
    if (cachedFuture != null) {
      return cachedFuture;
    }

    late final Future<String> future;
    future = link.content.catchError((Object error, StackTrace stackTrace) {
      if (_linkContentCache[keyStr] == future) {
        _linkContentCache.remove(keyStr);
      }
      Error.throwWithStackTrace(error, stackTrace);
    });

    _linkContentCache[keyStr] = future;
    return future;
  }

  // Helper to determine relative index for highlighting
  int _getItemSearchIndex(Link link) {
    if (_searchResultsPerLink.isEmpty) return -1;

    int cumulativeIndex = 0;
    final linkKey = _getLinkKey(link);

    for (final orderedLink in _orderedLinks) {
      final currentKey = _getLinkKey(orderedLink);

      // Found the link
      if (currentKey == linkKey) {
        final itemResults = _searchResultsPerLink[linkKey] ?? 0;
        if (itemResults == 0) return -1;

        final relativeIndex = _currentSearchIndex - cumulativeIndex;
        // Check if the current global index falls within this item's range
        return (relativeIndex >= 0 && relativeIndex < itemResults)
            ? relativeIndex
            : -1;
      }

      cumulativeIndex += _searchResultsPerLink[currentKey] ?? 0;
    }

    return -1;
  }

  void _handleSearchFocusChange() {
    if (!mounted) return;
    if (!_searchFocusNode.hasFocus &&
        _showSearchField &&
        _searchController.text.isEmpty) {
      setState(() => _showSearchField = false);
    }
  }

  void _openInlineSearch() {
    setState(() => _showSearchField = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _clearSearchAndCloseField() {
    _searchComputeDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _currentSearchIndex = 0;
      _totalSearchResults = 0;
      _searchResultsPerLink.clear();
      _showSearchField = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3, // מפרשים, קישורים, הערות
      vsync: this,
      initialIndex: widget.initialTabIndex ?? 0,
    );
    _lastNotifiedTabIndex = _tabController.index;
    _tabControllerListener = () {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == _lastNotifiedTabIndex) return;
      _lastNotifiedTabIndex = _tabController.index;
      widget.onTabChanged?.call(_tabController.index);
    };
    _tabController.addListener(_tabControllerListener);
    widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
    _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    widget.externalSearchController?.addListener(_onExternalSearchChanged);
    _searchFocusNode.addListener(_handleSearchFocusChange);
    _loadCommentatorGroups();
  }

  void _onExternalSearchChanged() {
    final text = widget.externalSearchController!.text;
    if (!mounted) return;
    setState(() {
      _searchQuery = text;
      _currentSearchIndex = 0;
      if (text.isEmpty) {
        _searchResultsPerLink.clear();
        _totalSearchResults = 0;
      }
    });
    widget.externalTotalResultsNotifier?.value = _totalSearchResults;
    widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
    _scheduleSearchCompute();
  }

  void _onOpenFilterRequest() {
    if (mounted) {
      setState(() => _showFilterTab = true);
    }
  }

  /// מספר השורות האמיתי של הספר המלווה (מקור ה-index1 של הקישורים) מה-DB,
  /// לצורך גזירת המפרשים הנדירים — זהה למקור בכרטיסיית הטקסט. null אם אין
  /// ספר מלווה ב-DB (אז המתודה הקוראת נופלת לאומדן).
  Future<int?> _resolveSourceBookTotalLines() async {
    try {
      final library = await DataRepository.instance.library;
      final companion =
          library.getCompanionBook(widget.tab.book, TextBook) as TextBook?;
      if (companion == null) return null;
      final repo = SqliteDataProvider.instance.repository;
      if (repo == null) return null;
      final dbBook = companion.categoryId != null
          ? await repo.getBookByTitleAndCategory(
              companion.title, companion.categoryId!)
          : await repo.getBookByTitle(companion.title);
      final lines = dbBook?.totalLines ?? 0;
      return lines > 0 ? lines : null;
    } catch (_) {
      return null;
    }
  }

  /// סיכום קישורי הספר (יעדים + ספירות) מהמסד — תחליף קל לסריקת כל הקישורים
  /// כש-tab.links מחזיק רק חלון סביב המיקום הנוכחי.
  Future<({List<LinkTargetSummary> targets, int maxSourceLine})?>
      _loadLinkTargetsSummary() async {
    try {
      final library = await DataRepository.instance.library;
      final companion =
          library.getCompanionBook(widget.tab.book, TextBook) as TextBook?;
      if (companion == null || companion.categoryId == null) return null;
      final provider = LibraryProviderManager.instance.getProviderForBook(
        companion.title,
        categoryId: companion.categoryId,
        fileType: companion.fileType ?? 'txt',
      );
      if (provider is! DatabaseLibraryProvider) return null;
      return provider.getBookLinkTargetsSummary(
          companion.title, companion.categoryId!);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCommentatorGroups() async {
    LinkTargetsAggregation aggregation;
    if (widget.tab.linksAreComplete) {
      aggregation = aggregateLinkTargetsFromLinks(widget.tab.links);
    } else {
      final summary = await _loadLinkTargetsSummary();
      aggregation = summary != null
          ? aggregateLinkTargetsFromSummary(
              summary.targets, summary.maxSourceLine)
          // הסיכום נכשל — נבנה לפחות מחלון הקישורים הטעון (חלקי, עדיף מריק).
          : aggregateLinkTargetsFromLinks(widget.tab.links);
    }
    final linkCountByTitle = aggregation.linkCountByTitle;
    final nonCommentaryTitles = aggregation.nonCommentaryTitles;

    final availableCommentators = aggregation.commentators.toList();
    final rare = computeRareCommentators(
      bookTotalLines:
          await _resolveSourceBookTotalLines() ?? aggregation.maxSourceLine,
      linkCountByCommentator: linkCountByTitle,
    );

    // טעינת דורות הקישורים הרגילים (לא מפרשים) מראש - fire-and-forget כדי לא
    // לחסום את בניית קבוצות המפרשים. כשתסתיים, מאפסים את מטמון התוכן הנראה
    // ומרעננים, כדי שסדר fallback (אלפבתי) שאולי נקבע מוקדם לא יישאר תקוע.
    if (nonCommentaryTitles.isNotEmpty) {
      CommentaryService.preloadEras(nonCommentaryTitles).then((_) {
        if (mounted) {
          setState(() => _visibleContentCache = null);
        }
      });
    }

    final eras = await utils.splitByEra(availableCommentators);
    final known = <String>{
      ...?eras['תורה שבכתב'],
      ...?eras['חז"ל'],
      ...?eras['ראשונים'],
      ...?eras['אחרונים'],
      ...?eras['מחברי זמננו'],
    };
    final others = (eras['מפרשים נוספים'] ?? [])
        .toSet()
        .union(availableCommentators.where((c) => !known.contains(c)).toSet())
        .toList();
    if (!mounted) return;
    setState(() {
      _rareCommentators = rare;
      _commentatorGroups = [
        CommentatorGroup(
            title: 'תורה שבכתב', commentators: eras['תורה שבכתב'] ?? const []),
        CommentatorGroup(title: 'חז"ל', commentators: eras['חז"ל'] ?? const []),
        CommentatorGroup(
            title: 'ראשונים', commentators: eras['ראשונים'] ?? const []),
        CommentatorGroup(
            title: 'אחרונים', commentators: eras['אחרונים'] ?? const []),
        CommentatorGroup(
            title: 'מחברי זמננו',
            commentators: eras['מחברי זמננו'] ?? const []),
        CommentatorGroup(title: 'שאר מפרשים', commentators: others),
      ];
    });
  }

  @override
  void didUpdateWidget(PdfCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם initialTabIndex השתנה, מעדכן את הטאב
    if (oldWidget.initialTabIndex != widget.initialTabIndex &&
        widget.initialTabIndex != null) {
      _tabController.animateTo(widget.initialTabIndex!);
      _lastNotifiedTabIndex = widget.initialTabIndex!;
    }

    if (oldWidget.openFilterRequest != widget.openFilterRequest) {
      oldWidget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
      widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
      // איפוס ה-baseline ל-notifier החדש — אחרת ערך גבוה מה-notifier הקודם
      // עלול לחסום פתיחות עתידיות עד שה-counter החדש "ישיג" אותו.
      _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    }
    if (oldWidget.openFilterNotifier != widget.openFilterNotifier) {
      oldWidget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
      widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    }

    if (oldWidget.tab != widget.tab) {
      _visibleContentCache = null;
      _linkContentCache.clear();
      _expandedLinkStates.clear();
      _orderedLinks = [];
      _orderedGroups = [];
      _itemKeys.clear();
      _commentatorGroups = [];
      _loadCommentatorGroups();
    } else if (oldWidget.linksCount != widget.linksCount) {
      _visibleContentCache = null;
      // בחלון-קישורים linksCount משתנה בכל דפדוף, אבל רשימת המפרשים של
      // הספר קבועה — אין לבנות אותה מחדש (ולירות שאילתת סיכום) בכל רענון.
      if (_commentatorGroups.isEmpty || widget.tab.linksAreComplete) {
        _commentatorGroups = [];
        _loadCommentatorGroups();
      }
    }
  }

  @override
  void dispose() {
    _searchUpdateDebounce?.cancel();
    _searchComputeDebounce?.cancel();
    _tabController.removeListener(_tabControllerListener);
    widget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
    widget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
    widget.externalSearchController?.removeListener(_onExternalSearchChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _commentaryFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// ניווט לתוצאת חיפוש קודמת (להפעלה מ-PdfCommentatorsTabScreen)
  void navigateSearchPrev() {
    if (_currentSearchIndex > 0) {
      setState(() => _currentSearchIndex--);
      widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
      _scrollToSearchResult();
    }
  }

  /// ניווט לתוצאת חיפוש הבאה (להפעלה מ-PdfCommentatorsTabScreen)
  void navigateSearchNext() {
    if (_currentSearchIndex < _totalSearchResults - 1) {
      setState(() => _currentSearchIndex++);
      widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
      _scrollToSearchResult();
    }
  }

  /// ממקד את אזור הגלילה (לגלילה עם החיצים) — נקרא מכרטיסיית המפרשים
  /// כשהטאב הופך פעיל.
  void requestScrollFocus() {
    if (_commentaryFocusNode.canRequestFocus) {
      _commentaryFocusNode.requestFocus();
    }
  }

  /// מרחיב/מכווץ את כל קבוצות המפרשים (להפעלה מסרגל הכלים של הכרטיסייה).
  void toggleAllExpanded() {
    setState(() {
      final nextExpanded = !_allExpanded;
      _allExpanded = nextExpanded;
      for (final key in _expansionStates.keys.toList()) {
        _expansionStates[key] = nextExpanded;
      }
      for (final group in _orderedGroups) {
        _expansionStates[group.bookTitle] = nextExpanded;
      }
    });
    widget.externalAllExpandedNotifier?.value = _allExpanded;
  }

  void _scheduleSearchCompute() {
    _searchComputeDebounce?.cancel();
    // כשאין קישורים אין מה לחשב — טעינתם תפעיל תזמון מחדש (לפי חתימה).
    if (_orderedLinks.isEmpty) return;
    _searchComputeDebounce =
        Timer(const Duration(milliseconds: 250), _computeSearchCounts);
  }

  /// עובר על כל הקישורים ומזין את משפך העדכון של ספירות החיפוש, במקביל
  /// לדיווח (הזהה) מה-widgets שנבנו בפועל.
  Future<void> _computeSearchCounts() async {
    if (!mounted || _searchQuery.isEmpty) return;
    final query = _searchQuery;
    final links = List<Link>.from(_orderedLinks);
    if (links.isEmpty) return;
    final gen = ++_searchComputeGen;

    for (final link in links) {
      String data;
      try {
        data = await link.content;
      } catch (_) {
        data = '';
      }
      if (!mounted || gen != _searchComputeGen || _searchQuery != query) {
        return;
      }
      _updateSearchResultsCount(
        link,
        countCommentarySearchMatches(
          content: data,
          query: query,
          removePunctuation: widget.removePunctuation,
        ),
      );
    }
  }

  void _updateSearchResultsCount(Link link, int count) {
    if (!mounted) return;

    final key = _getLinkKey(link);
    final currentValue = _searchResultsPerLink[key];
    final pendingValue = _pendingCounts[key];
    if (currentValue == count && pendingValue == count) {
      return;
    }

    _pendingCounts[key] = count;

    if (_searchUpdateDebounce?.isActive ?? false) return;

    _searchUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final bool hasActualChange = _pendingCounts.entries.any(
        (entry) => _searchResultsPerLink[entry.key] != entry.value,
      );

      if (!hasActualChange) {
        _pendingCounts.clear();
        return;
      }

      setState(() {
        _searchResultsPerLink.addAll(_pendingCounts);
        _pendingCounts.clear();
        _totalSearchResults =
            _searchResultsPerLink.values.fold(0, (sum, count) => sum + count);

        // Reset current index if out of bounds
        if (_currentSearchIndex >= _totalSearchResults &&
            _totalSearchResults > 0) {
          _currentSearchIndex = 0;
        }
        widget.externalTotalResultsNotifier?.value = _totalSearchResults;
        widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
      });
    });
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  Future<void> _copyFormattedText() async {
    await ContextMenuUtils.copyFormattedText(
      context: context,
      savedSelectedText: _savedSelectedText,
      fontSize: widget.fontSize,
    );
  }

  /// בניית תפריט הקשר למפרש ספציפי
  List<AppContextMenuEntry> _buildCommentaryContextMenuEntries(
      BuildContext menuCtx, Link link) {
    return ContextMenuUtils.buildCommentaryContextMenu(
      context: menuCtx,
      link: link,
      openBookCallback: widget.openBookCallback,
      fontSize: widget.fontSize,
      savedSelectedText: _savedSelectedText,
      onCopySelected: _copyFormattedText,
    );
  }

  /// עוטף תוכן ב-SelectionArea (לבחירת טקסט) + מעקב כיוון גרירה ל-RTL.
  /// יירוט Ctrl+C ממוקם *מעל* ה-SelectionArea — שם מנגנון ה-override של
  /// CopySelectionTextIntent מאתר אותו (מתחתיו הוא נשאר בלתי-נראה).
  Widget _wrapWithSelection(Widget child) {
    return SelectionCopyShortcuts(
      onCopy: _copyFormattedText,
      child: RtlSelectionShortcuts(
        child: SelectionArea(
          contextMenuBuilder: (context, _) => const SizedBox.shrink(),
          onSelectionChanged: (selection) {
            trackRtlSelection(selection?.plainText);
            if (rtlSelectionPriming) return;
            final text = selection?.plainText ?? '';
            setState(() {
              _savedSelectedText = text.isNotEmpty ? text : null;
            });
          },
          child: child,
        ),
      ),
    );
  }

  /// עוטף את תוכן המפרשים ב-ProgressiveScroll מעל ה-SelectionArea, כדי
  /// שגלילת החיצים תיקלט גם כש-SelectableRegion הוא ה-primaryFocus. autofocus
  /// במצב מסך-מלא (כרטיסייה) בלבד.
  Widget _wrapCommentariesScrollable(Widget child) {
    return ProgressiveScroll(
      focusNode: _commentaryFocusNode,
      autofocus: widget.isFullScreen,
      scrollController: _scrollOffsetController,
      maxSpeed: 10000.0,
      curve: 10.0,
      accelerationFactor: 5,
      itemScrollController: _itemScrollController,
      child: _wrapWithSelection(child),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isFullScreen) {
      // במצב fullscreen: הכותרת + הניווט מופעלים מ-PdfCommentatorsTabScreen.
      // הפאנל מציג רק את תוכן המפרשים (כולל שורת חיפוש ופילטר)
      return _wrapCommentariesScrollable(_buildCommentariesView());
    }

    return Column(
      children: [
        // שורת הכרטיסיות
        PanelTabHeader(
          controller: _tabController,
          onClose: widget.onClose,
          onTap: (index) {
            if (index == 0 && _showFilterTab) {
              setState(() => _showFilterTab = false);
            }
          },
          tabs: const [
            PanelTab(
              icon: FluentIcons.book_24_regular,
              label: 'מפרשים',
            ),
            PanelTab(
              icon: FluentIcons.link_24_regular,
              label: 'קישורים',
            ),
            PanelTab(
              icon: FluentIcons.note_24_regular,
              label: 'הערות',
            ),
          ],
        ),
        // כל לשונית עוטפת את עצמה ב-SelectionArea; המפרשים בנוסף ב-
        // ProgressiveScroll (מעל ה-SelectionArea) כדי שגלילת החיצים תעבוד.
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _KeepAliveTab(
                key: ValueKey(
                  'commentary_${widget.tab.currentTextLineNumber}_${widget.tab.activeCommentators.hashCode}_$_showFilterTab',
                ),
                child: _wrapCommentariesScrollable(_buildCommentariesView()),
              ),
              _KeepAliveTab(
                key: ValueKey(
                  'links_${widget.tab.currentTextLineNumber}',
                ),
                child: _wrapWithSelection(_buildLinksView()),
              ),
              _KeepAliveTab(
                key: ValueKey(
                  'notes_${widget.tab.currentTextLineNumber}',
                ),
                child: _wrapWithSelection(_buildNotesView()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// מפרשים נדירים שכן יוצגו בלשונית הבחירה כי הטווח הנוכחי כולל קישור מהם.
  Set<String> _lineRelevantRareCommentators() {
    if (_rareCommentators.isEmpty) return const {};
    final currentLine =
        widget.lineStartOverride ?? widget.tab.currentTextLineNumber;
    if (currentLine == null) return const {};
    final range = _getCurrentRange(currentLine);
    final extra = widget.extraLineIndices;
    final relevant = <String>{};
    for (final link in widget.tab.links) {
      if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
      if (!pdfLinkInVisibleScope(
          link.index1, range.startLine, range.endLine, extra)) {
        continue;
      }
      final title = utils.getTitleFromPath(link.path2);
      if (_rareCommentators.contains(title)) relevant.add(title);
    }
    return relevant;
  }

  Widget _buildCommentatorsFilter() {
    return CommentatorsFilterScreen(
      onBack: () {
        setState(() {
          _showFilterTab = false;
          // כפיית rebuild של התצוגה אחרי שינוי מפרשים
        });
        // עדכון נוסף אחרי frame אחד כדי לוודא שהתצוגה מתעדכנת
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
          }
        });
      },
      child: CommentatorsSelectionPanel(
        groups: _commentatorGroups,
        selectedCommentators: widget.tab.activeCommentators.toList(),
        bookTitle: widget.tab.book.title,
        rareCommentators: _rareCommentators,
        lineRelevantCommentators: _lineRelevantRareCommentators(),
        onSelectionChanged: (list) async {
          setState(() {
            widget.tab.activeCommentators
              ..clear()
              ..addAll(list);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          // שמירה פר-ספר תמיד (לא תלוי ב-enablePerBookSettings) כדי שהבחירה
          // תיטען בכל פתיחה.
          final settings = PdfBookPerBookSettings(
            activeCommentators: List.from(widget.tab.activeCommentators),
          );
          await settings.save(widget.tab.book);
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: _showSearchField ? _buildSearchFieldRow() : _buildButtonsRow(),
    );
  }

  Widget _buildButtonsRow() {
    const double gap = 16;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. בחירת מפרשים
        CommentatorsFilterButton(
          isActive: false,
          onPressed: () {
            setState(() {
              _showFilterTab = true;
            });
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          iconSize: 20,
        ),
        // 2. הרחב/כווץ הכל — רק כשיש מפרשים פעילים (לוגיקה מקורית)
        if (widget.tab.activeCommentators.isNotEmpty) ...[
          const SizedBox(width: gap),
          IconButton(
            icon: Icon(
              _allExpanded
                  ? FluentIcons.arrow_collapse_all_24_regular
                  : FluentIcons.arrow_expand_all_24_regular,
            ),
            tooltip: _allExpanded ? 'כווץ את כל המפרשים' : 'הרחב את כל המפרשים',
            onPressed: toggleAllExpanded,
          ),
        ],
        const SizedBox(width: gap),
        // 3. פתיחה בכרטיסייה חדשה
        IconButton(
          icon: const Icon(FluentIcons.open_24_regular),
          tooltip: 'פתח כרטסיית מפרשים',
          onPressed: () => context.read<TabsBloc>().add(
                AddTab(
                  PdfCommentatorsTab(sourceTab: widget.tab),
                  insertAdjacent: true,
                ),
              ),
        ),
        const SizedBox(width: gap),
        // 4. הפעלת שדה החיפוש
        IconButton(
          icon: const Icon(FluentIcons.search_24_regular),
          tooltip: 'חיפוש',
          onPressed: _openInlineSearch,
        ),
      ],
    );
  }

  /// פותח את מסך ההדפסה עם המפרשים המוצגים כעת (מקובצים לפי מפרש).
  /// פומבי כדי שכרטיסיית המפרשים הייעודית תפעיל אותו מהסרגל/קיצור המקלדת.
  Future<void> printDisplayedCommentaries() async {
    final visibleContent = _getVisibleContent();
    if (visibleContent == null || visibleContent.commentaryLinks.isEmpty) {
      UiSnack.show('אין מפרשים להדפסה');
      return;
    }

    final groups = await visibleContent.sortedGroupsFuture;
    final blocks = await buildCommentaryPrintBlocks(groups);
    if (blocks.isEmpty) {
      UiSnack.show('אין מפרשים להדפסה');
      return;
    }
    if (!mounted) return;

    final bookTitle = widget.tab.book.title;
    final removeTaamim = !context.read<SettingsBloc>().state.showTeamim;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Future.value(''),
        bookId: bookTitle,
        documentTitle: bookTitle,
        prebuiltBlocks: blocks,
        removeNikud: widget.removeNikud,
        removeTaamim: removeTaamim,
      ),
    );
  }

  Widget _buildSearchFieldRow() {
    return RtlTextField(
      focusNode: _searchFocusNode,
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'חפש בתוך המפרשים המוצגים...',
        prefixIcon: const Icon(FluentIcons.search_24_regular),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_searchQuery.isNotEmpty && _totalSearchResults > 0) ...[
              Text(
                '${_currentSearchIndex + 1}/$_totalSearchResults',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(FluentIcons.chevron_up_24_regular),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: _currentSearchIndex > 0
                    ? () {
                        setState(() {
                          _currentSearchIndex--;
                        });
                        _scrollToSearchResult();
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(FluentIcons.chevron_down_24_regular),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: _currentSearchIndex < _totalSearchResults - 1
                    ? () {
                        setState(() {
                          _currentSearchIndex++;
                        });
                        _scrollToSearchResult();
                      }
                    : null,
              ),
            ],
            IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              tooltip: 'סגור חיפוש',
              onPressed: _clearSearchAndCloseField,
            ),
          ],
        ),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: AppTokens.borderRadiusAll,
        ),
      ),
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
          _currentSearchIndex = 0;
          if (value.isEmpty) {
            _searchResultsPerLink.clear();
            _totalSearchResults = 0;
          }
        });
        _scheduleSearchCompute();
      },
    );
  }

  Widget _buildCommentariesView() {
    if (_showFilterTab) {
      return _buildCommentatorsFilter();
    }

    return Column(
      children: [
        // במצב fullscreen עם חיפוש חיצוני, מסתיר שורת חיפוש פנימית
        if (widget.externalSearchController == null) _buildSearchBar(),
        Expanded(
          child: _buildCommentariesListContent(),
        ),
      ],
    );
  }

  Widget _buildCommentariesListContent() {
    final visibleContent = _getVisibleContent();
    if (visibleContent == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'טוען מפרשים...',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    if (visibleContent.commentaryLinks.isEmpty) {
      if (widget.linksLoading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'טוען מפרשים...',
              style: TextStyle(
                fontSize: widget.fontSize * 0.9,
                color: Colors.grey,
              ),
            ),
          ),
        );
      }

      final hasCommentaryLinks = visibleContent.hasAnyCommentaryLinks;

      if (hasCommentaryLinks &&
          widget.tab.activeCommentators.isEmpty &&
          widget.enableInternalFilter) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showFilterTab) {
            setState(() {
              _showFilterTab = true;
            });
          }
        });
        return const Center(child: CircularProgressIndicator());
      }

      // אין מפרשים בכלל לקטע הזה, או שיש מפרשים נבחרים אבל הם לא רלוונטיים לדף
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                hasCommentaryLinks
                    ? 'לא נמצאו מפרשים מהנבחרים לדף זה'
                    : 'לא נמצאו מפרשים לקטע הנבחר',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasCommentaryLinks) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    if (widget.enableInternalFilter) {
                      setState(() {
                        _showFilterTab = true;
                      });
                    } else {
                      widget.onSelectCommentatorsRequested?.call();
                    }
                  },
                  icon: const Icon(FluentIcons.apps_list_24_regular),
                  label: const Text('בחר מפרשים'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return FutureBuilder<List<CommentaryGroup>>(
      future: visibleContent.sortedGroupsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sortedGroups = snapshot.data!;
        _orderedGroups = sortedGroups;

        // Rebuild _orderedLinks based on groups
        _orderedLinks = [];
        for (final group in sortedGroups) {
          // We need to verify link order inside group.
          // In _buildCommentariesView, relevantLinks are sorted by title then index.
          // _groupConsecutiveLinks groups them.
          // So the links inside group.links should already be in order.
          _orderedLinks.addAll(group.links);
        }

        // Initialize keys
        final currentLinkKeys =
            _orderedLinks.map((l) => _getLinkKey(l)).toSet();

        // קישורים חדשים (טעינה/מעבר קטע) — חישוב ספירות חיפוש מחדש אם יש
        // שאילתה פעילה.
        final linksSignature = Object.hashAll(currentLinkKeys);
        if (linksSignature != _lastLinksSignature) {
          _lastLinksSignature = linksSignature;
          _scheduleSearchCompute();
        }
        _itemKeys.removeWhere((key, value) => !currentLinkKeys.contains(key));
        for (final key in currentLinkKeys) {
          if (!_itemKeys.containsKey(key)) {
            _itemKeys[key] = GlobalKey();
          }
        }

        // ניקוי ספירות חיפוש מקישורים שאינם בקטע הנוכחי
        final staleSearchKeys = _searchResultsPerLink.keys
            .where((key) => !currentLinkKeys.contains(key))
            .toList();
        if (staleSearchKeys.isNotEmpty) {
          for (final key in staleSearchKeys) {
            _searchResultsPerLink.remove(key);
          }
          _pendingCounts
              .removeWhere((key, _) => !currentLinkKeys.contains(key));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final newTotal =
                _searchResultsPerLink.values.fold(0, (sum, c) => sum + c);
            if (_totalSearchResults != newTotal ||
                _currentSearchIndex >= newTotal) {
              setState(() {
                _totalSearchResults = newTotal;
                if (_currentSearchIndex >= newTotal) {
                  _currentSearchIndex = 0;
                }
              });
            }
          });
        }

        return ScrollablePositionedList.builder(
          key: PageStorageKey(
              'commentary_${widget.tab.currentTextLineNumber}_${widget.tab.activeCommentators.hashCode}_$_allExpanded'),
          itemCount: sortedGroups.length,
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          scrollOffsetController: _scrollOffsetController,
          itemBuilder: (context, index) {
            final group = sortedGroups[index];
            return _buildCommentaryGroupTile(group);
          },
        );
      },
    );
  }

  void _scrollToSearchResult() {
    if (_totalSearchResults == 0 ||
        _orderedLinks.isEmpty ||
        !_itemScrollController.isAttached) {
      return;
    }

    int cumulativeIndex = 0;
    Link? targetLink;

    // 1. מוצא את ה-link שמכיל את תוצאת החיפוש הנוכחית
    for (final link in _orderedLinks) {
      final linkKey = _getLinkKey(link);
      final itemResults = _searchResultsPerLink[linkKey] ?? 0;
      if (_currentSearchIndex < cumulativeIndex + itemResults) {
        targetLink = link;
        break;
      }
      cumulativeIndex += itemResults;
    }

    if (targetLink == null) return;

    // 2. מוצא את ה-group שמכיל את ה-link
    // Since we have _orderedGroups
    int targetGroupIndex = -1;
    CommentaryGroup? targetGroup;

    for (int i = 0; i < _orderedGroups.length; i++) {
      final group = _orderedGroups[i];
      // Check if link is in group. Note: link instances might differ if rebuilt, so compare by key
      final targetLinkKey = _getLinkKey(targetLink);
      if (group.links.any((l) => _getLinkKey(l) == targetLinkKey)) {
        targetGroupIndex = i;
        targetGroup = group;
        break;
      }
    }

    if (targetGroupIndex == -1 || targetGroup == null) return;

    // 3. מבטיח שה-ExpansionTile של הקבוצה פתוח
    final groupKey = targetGroup.bookTitle;
    final bool isCurrentlyExpanded = _expansionStates[groupKey] ?? _allExpanded;

    if (!isCurrentlyExpanded) {
      setState(() {
        _expansionStates[groupKey] = true;
      });
    }

    // 4. ביצוע הגלילה
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (!isCurrentlyExpanded) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }

      final linkKey = _getLinkKey(targetLink!);
      final itemKey = _itemKeys[linkKey];
      final BuildContext? itemContext = itemKey?.currentContext;

      // בודק אם הפריט כבר בעץ הרינדור (לא נדרשת גלילה גסה)
      final bool itemInRenderTree = itemContext != null &&
          itemContext.mounted &&
          itemContext.findRenderObject() is RenderBox;

      if (!itemInRenderTree) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: targetGroupIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.05,
          );
        }
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
      }

      final BuildContext? ctx = itemKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          final scrollable = Scrollable.of(ctx);
          scrollable.position.ensureVisible(
            ctx.findRenderObject()!,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: 0.1,
          );
        } catch (e) {
          debugPrint('Error scrolling to item: $e');
        }
      }
    });
  }

  Widget _buildCommentaryGroupTile(CommentaryGroup group) {
    final groupKey = group.bookTitle;
    if (!_expansionStates.containsKey(groupKey)) {
      _expansionStates[groupKey] = _allExpanded;
    }
    final isExpanded = _expansionStates[groupKey] ?? _allExpanded;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return _CollapsibleCommentaryGroup(
          key: PageStorageKey(
              '${group.bookTitle}_${widget.tab.currentTextLineNumber}'),
          group: group,
          settingsState: settingsState,
          tab: widget.tab,
          fontSize: widget.fontSize,
          openBookCallback: widget.openBookCallback,
          buildContextMenu: _buildCommentaryContextMenuEntries,
          getSavedSelectedText: () => _savedSelectedText,
          isExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _expansionStates[groupKey] = expanded;
            });
          },
          searchQuery: _searchQuery,
          onSearchResultsCountUpdate: _updateSearchResultsCount,
          getKeyForLink: _getLinkKeyObject,
          getItemSearchIndex: _getItemSearchIndex, // Pass the function
          removeNikud: widget.removeNikud,
          removePunctuation: widget.removePunctuation,
        );
      },
    );
  }

  // Helper method used in _scrollToSearchResult to inject keys
  Key? _getLinkKeyObject(Link link) {
    return _itemKeys[_getLinkKey(link)];
  }

  Widget _buildLinksView() {
    final visibleContent = _getVisibleContent();
    if (visibleContent == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'טוען קישורים...',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    final relevantLinks = visibleContent.links;

    if (relevantLinks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            widget.linksLoading ? 'טוען קישורים...' : 'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: relevantLinks.length,
      itemBuilder: (context, index) {
        final link = relevantLinks[index];
        return _buildLinkTile(link);
      },
    );
  }

  Widget _buildLinkTile(Link link) {
    final keyStr = _getLinkKey(link);

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final restoredExpanded = PageStorage.maybeOf(context)?.readState(
          context,
          identifier: keyStr,
        ) as bool?;
        final isExpanded =
            _expandedLinkStates[keyStr] ?? restoredExpanded ?? false;

        return ExpansionTile(
          key: PageStorageKey(keyStr),
          initiallyExpanded: isExpanded,
          maintainState: true,
          showTrailingIcon: false,
          leading: AnimatedRotation(
            turns: isExpanded ? -0.25 : 0,
            duration: const Duration(milliseconds: 200),
            child: RtlIcon(
              FluentIcons.chevron_left_24_regular,
              size: 20,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.surface,
          collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            utils.getTitleFromPath(link.path2),
            style: TextStyle(
              fontSize: settingsState.commentatorsFontSize - 2,
              fontWeight: FontWeight.bold,
              fontFamily: settingsState.commentatorsFontFamily,
            ),
          ),
          subtitle: FutureBuilder<String>(
            future: link.displayReference,
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? link.fallbackDisplayReference,
                style: TextStyle(
                  fontSize: settingsState.commentatorsFontSize - 4,
                  fontWeight: FontWeight.normal,
                  fontFamily: settingsState.commentatorsFontFamily,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              );
            },
          ),
          onExpansionChanged: (expanded) {
            if (expanded && !_linkContentCache.containsKey(keyStr)) {
              _getCachedLinkContent(keyStr, link);
            }

            if (_expandedLinkStates[keyStr] != expanded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _expandedLinkStates[keyStr] = expanded;
                });
              });
            }
          },
          children: [
            if (isExpanded)
              AppContextMenuRegion(
                // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה (התנהגות
                // ברירת המחדל של SelectableRegion ב-Windows); לחיצה על חלק
                // לא-מסומן מבטלת כרגיל. הבחירה מנוהלת ע"י SelectionArea יחיד.
                shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                  final selected = _savedSelectedText;
                  if (selected == null || selected.isEmpty) return false;
                  final root = context.findRenderObject();
                  if (root == null) return true; // סלחני
                  return clickIsOnSelectionWithinArea(
                        root: root,
                        globalPosition: globalPosition,
                        selectedText: selected,
                      ) ??
                      true; // לא הוכרע — סלחני
                },
                menuBuilder: (menuCtx, _) =>
                    _buildCommentaryContextMenuEntries(menuCtx, link),
                child: GestureDetector(
                  onTap: () {
                    widget.openBookCallback(
                      TextBookTab(
                        book: TextBook(
                          title: utils.getTitleFromPath(link.path2),
                        ),
                        index: link.index2 - 1,
                        openLeftPane:
                            (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false) ||
                                (Settings.getValue<bool>(
                                        'key-default-sidebar-open') ??
                                    false),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: FutureBuilder<String>(
                      future: _getCachedLinkContent(keyStr, link),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          debugPrint(
                              'Error loading link content: ${snapshot.error}');
                          debugPrint('Stack trace: ${snapshot.stackTrace}');
                          return Text('שגיאה: ${snapshot.error}');
                        }
                        return BlocBuilder<SettingsBloc, SettingsState>(
                          builder: (context, settingsState) {
                            return Text(
                              utils.stripHtmlPreservingBreaks(
                                  snapshot.data ?? ''),
                              textAlign: TextAlign.justify,
                              style: TextStyle(
                                fontSize: settingsState.commentatorsFontSize,
                                fontFamily:
                                    settingsState.commentatorsFontFamily,
                                fontWeight: settingsState.commentatorsFontBold
                                    ? FontWeight.bold
                                    : null,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNotesView() {
    final bookId = widget.tab.book.title;

    return PersonalNotesSidebar(
      key: ValueKey(bookId),
      bookId: bookId,
      categoryId: widget.tab.book.categoryId,
      isPdf: true,
      pdfOutline: widget.tab.outline,
      visibleLineIndices: _getVisibleLineIndicesForCurrentPage(),
      onNavigateToLine: (lineNumber) {
        // lineNumber הוא מספר שורה לוגי — ממירים אותו לעמוד דרך ה-heading
        // הקרוב לפניו, ונופלים לפרשנות-עמוד-ישירה בספרים ללא headings.
        if (widget.tab.pdfHeadings != null) {
          final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();

          for (int i = sortedHeadings.length - 1; i >= 0; i--) {
            if (sortedHeadings[i].value <= lineNumber) {
              final headingTitle = sortedHeadings[i].key;
              final targetPage = _findPageForHeading(headingTitle);

              if (targetPage != null) {
                if (widget.tab.pdfViewerController.isReady) {
                  widget.tab.pdfViewerController
                      .goToPage(pageNumber: targetPage);
                }
                return;
              }
              break;
            }
          }
        }

        if (widget.tab.pdfViewerController.isReady) {
          widget.tab.pdfViewerController.goToPage(pageNumber: lineNumber);
        }
      },
    );
  }

  _PdfVisibleContentCache? _getVisibleContent() {
    final currentLine =
        widget.lineStartOverride ?? widget.tab.currentTextLineNumber;
    if (currentLine == null) {
      _visibleContentCache = null;
      return null;
    }

    final range = _getCurrentRange(currentLine);
    final commentatorsKey =
        (widget.tab.activeCommentators.toList()..sort()).join('|');
    final extraKey = widget.extraLineIndices == null
        ? ''
        : (widget.extraLineIndices!.toList()..sort()).join(',');
    final cacheKey =
        '${range.startLine}:${range.endLine}:$extraKey:$commentatorsKey:${widget.tab.links.length}';

    final existingCache = _visibleContentCache;
    if (existingCache != null && existingCache.cacheKey == cacheKey) {
      return existingCache;
    }

    final commentaryLinks = <Link>[];
    final nonCommentaryLinks = <Link>[];
    var hasAnyCommentaryLinks = false;

    // בכרטסיית המפרשים (ללא הפילטר הפנימי), בחירה ריקה משמעה "הצג את כל
    // המפרשים הזמינים לקטע" — זהה ל-useAvailableCommentators בכרטסיית הטקסט —
    // כדי שלא יוצג "לא נמצאו מפרשים" מיד עם הפתיחה לפני בחירה.
    final showAllWhenEmpty =
        !widget.enableInternalFilter && widget.tab.activeCommentators.isEmpty;

    final extraLines = widget.extraLineIndices;
    for (final link in widget.tab.links) {
      if (!pdfLinkInVisibleScope(
          link.index1, range.startLine, range.endLine, extraLines)) {
        continue;
      }

      final isCommentary = LinkTypes.isDependentTextLink(link.connectionType);

      if (isCommentary) {
        hasAnyCommentaryLinks = true;
        if (showAllWhenEmpty ||
            widget.tab.activeCommentators
                .contains(utils.getTitleFromPath(link.path2))) {
          commentaryLinks.add(link);
        }
        continue;
      }

      if (link.start == null && link.end == null) {
        nonCommentaryLinks.add(link);
      }
    }

    commentaryLinks.sort((a, b) {
      final titleA = utils.getTitleFromPath(a.path2);
      final titleB = utils.getTitleFromPath(b.path2);
      final titleCompare = titleA.compareTo(titleB);
      if (titleCompare != 0) {
        return titleCompare;
      }
      return a.index1.compareTo(b.index1);
    });
    final sortedNonCommentaryLinks =
        CommentaryService.sortLinksByEraSync(nonCommentaryLinks);

    final groups = _groupConsecutiveLinks(commentaryLinks);
    final cache = _PdfVisibleContentCache(
      cacheKey: cacheKey,
      commentaryLinks: List.unmodifiable(commentaryLinks),
      links: List.unmodifiable(sortedNonCommentaryLinks),
      hasAnyCommentaryLinks: hasAnyCommentaryLinks,
      sortedGroupsFuture: CommentaryService.sortGroupsByEra(groups),
    );
    _visibleContentCache = cache;
    return cache;
  }

  ({int startLine, int endLine}) _getCurrentRange(int currentLine) {
    final endLine = widget.lineEndOverride ??
        (widget.tab.currentTextLineNumberEnd ?? currentLine + 50);
    return (startLine: currentLine, endLine: endLine);
  }

  List<int>? _getVisibleLineIndicesForCurrentPage() {
    final currentLine = widget.tab.currentTextLineNumber;
    if (currentLine == null) return null;

    final endLine = widget.tab.currentTextLineNumberEnd ?? currentLine + 50;

    return List<int>.generate(
      endLine - currentLine + 1,
      (index) => currentLine + index - 1,
    );
  }

  // מוצא את העמוד של כותרת מסוימת
  int? _findPageForHeading(String heading) {
    final outline = widget.tab.outline.value;
    if (outline == null) return null;

    int? findInNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        if (node.title == heading) {
          return node.dest?.pageNumber;
        }
        final childResult = findInNodes(node.children);
        if (childResult != null) return childResult;
      }
      return null;
    }

    return findInNodes(outline);
  }
}

class _PdfVisibleContentCache {
  final String cacheKey;
  final List<Link> commentaryLinks;
  final List<Link> links;
  final bool hasAnyCommentaryLinks;
  final Future<List<CommentaryGroup>> sortedGroupsFuture;

  const _PdfVisibleContentCache({
    required this.cacheKey,
    required this.commentaryLinks,
    required this.links,
    required this.hasAnyCommentaryLinks,
    required this.sortedGroupsFuture,
  });
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveTab({super.key, required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Widget מותאם אישית להצגת קבוצת מפרשים עם אפשרות כיווץ/הרחבה
/// שלא מפריע לבחירת טקסט והעתקה (במקום ExpansionTile)
class _CollapsibleCommentaryGroup extends StatefulWidget {
  final CommentaryGroup group;
  final SettingsState settingsState;
  final PdfBookTab tab;
  final double fontSize;
  final Function(OpenedTab) openBookCallback;
  final List<AppContextMenuEntry> Function(BuildContext, Link) buildContextMenu;
  // מחזיר את הטקסט הנבחר הנוכחי (מנוהל ע"י ה-SelectionArea היחיד של הפאנל),
  // לבדיקה אם לחיצה ימנית נופלת על הבחירה ולכן יש לשמרה.
  final String? Function() getSavedSelectedText;
  final bool isExpanded;
  final Function(bool) onExpansionChanged;
  final String searchQuery;
  final Function(Link, int)? onSearchResultsCountUpdate;
  final Key? Function(Link)? getKeyForLink; // Support linking keys
  final int Function(Link)? getItemSearchIndex; // Support highlighting
  final bool removeNikud;
  final bool removePunctuation;

  const _CollapsibleCommentaryGroup({
    super.key,
    required this.group,
    required this.settingsState,
    required this.tab,
    required this.fontSize,
    required this.openBookCallback,
    required this.buildContextMenu,
    required this.getSavedSelectedText,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.searchQuery,
    this.onSearchResultsCountUpdate,
    this.getKeyForLink,
    this.getItemSearchIndex,
    this.removeNikud = false,
    this.removePunctuation = false,
  });

  @override
  State<_CollapsibleCommentaryGroup> createState() =>
      _CollapsibleCommentaryGroupState();
}

class _CollapsibleCommentaryGroupState
    extends State<_CollapsibleCommentaryGroup> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת הקבוצה - ניתנת ללחיצה להרחבה/כיווץ
        InkWell(
          onTap: () {
            widget.onExpansionChanged(!widget.isExpanded);
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: widget.isExpanded ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: RtlIcon(
                    FluentIcons.chevron_left_24_regular,
                    size: 20,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.group.bookTitle,
                    style: TextStyle(
                      fontSize: widget.settingsState.commentatorsFontSize - 2,
                      fontWeight: FontWeight.bold,
                      fontFamily: widget.settingsState.commentatorsFontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // תוכן המפרשים - מוצג רק כשמורחב
        if (widget.isExpanded)
          ...widget.group.links.map((link) {
            return Padding(
              key: widget.getKeyForLink
                  ?.call(link), // Attach the key here for scrolling
              padding: const EdgeInsets.only(
                  right: 32.0, left: 16.0, top: 8.0, bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<String>(
                    future: link.displayReference,
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? link.fallbackDisplayReference,
                        style: TextStyle(
                          fontSize:
                              widget.settingsState.commentatorsFontSize - 4,
                          fontWeight: FontWeight.normal,
                          fontFamily:
                              widget.settingsState.commentatorsFontFamily,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  AppContextMenuRegion(
                    // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה
                    // (התנהגות ברירת המחדל של SelectableRegion ב-Windows); לחיצה
                    // על חלק לא-מסומן מבטלת כרגיל. הבחירה מנוהלת ע"י SelectionArea
                    // יחיד, לכן מחשבים את קטע הבחירה ישירות מול הפסקה שעליה לחצו.
                    shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                      final selected = widget.getSavedSelectedText();
                      if (selected == null || selected.isEmpty) return false;
                      final root = context.findRenderObject();
                      if (root == null) return true; // סלחני
                      return clickIsOnSelectionWithinArea(
                            root: root,
                            globalPosition: globalPosition,
                            selectedText: selected,
                          ) ??
                          true; // לא הוכרע — סלחני
                    },
                    menuBuilder: (menuCtx, _) =>
                        widget.buildContextMenu(menuCtx, link),
                    child: PdfCommentaryContent(
                      key: ValueKey(
                          '${link.path2}_${link.index1}_${link.index2}_${widget.tab.currentTextLineNumber}'),
                      link: link,
                      fontSize: widget.fontSize,
                      openBookCallback: widget.openBookCallback,
                      searchQuery: widget.searchQuery,
                      onSearchResultsCountChanged: (count) {
                        widget.onSearchResultsCountUpdate?.call(link, count);
                      },
                      currentSearchIndex:
                          widget.getItemSearchIndex?.call(link) ?? -1,
                      removeNikud: widget.removeNikud,
                      removePunctuation: widget.removePunctuation,
                    ),
                  ),
                ],
              ),
            );
          }),
        const Divider(height: 1),
      ],
    );
  }
}
