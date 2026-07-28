import 'package:flutter/foundation.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/text_book/utils/commentary_type_filter.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
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
import 'package:otzaria/core/messages/pdf_messages.dart';
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

/// מפרשי הקטע המוצג *לפני* סינון הסוגים — הבסיס גם לרשימה וגם לצ׳יפים.
/// [showAllWhenEmpty] = בחירה ריקה משמעה "הצג את כל המפרשים הזמינים לקטע".
///
/// משותף לחלונית שבתוך הספר ולכרטיסיית המפרשים, כדי ששתיהן יגזרו את אותם
/// צ׳יפים מאותה קבוצת קישורים.
List<Link> pdfScopedCommentaryLinks({
  required Iterable<Link> links,
  required int startLine,
  required int endLine,
  required Set<int>? extraLineIndices,
  required Set<String> activeCommentators,
  required bool showAllWhenEmpty,
}) {
  final scoped = <Link>[];
  for (final link in links) {
    if (!LinkTypes.isDependentTextLink(link.connectionType)) continue;
    if (!pdfLinkInVisibleScope(
      link.index1,
      startLine,
      endLine,
      extraLineIndices,
    )) {
      continue;
    }
    if (showAllWhenEmpty ||
        activeCommentators.contains(utils.getTitleFromPath(link.path2))) {
      scoped.add(link);
    }
  }
  return scoped;
}

/// מפתח הזהות של פריט מפרש. חייב להיות תלוי-קישור בלבד: מפתח שכולל את העמוד
/// הנוכחי מחריב את ה-State של כל פריט בכל דפדוף וגורם לטעינת התוכן מחדש.
@visibleForTesting
String pdfCommentaryItemKey(Link link) =>
    '${link.index1}_${link.path2}_${link.index2}';

/// מפתח ה-PageStorage של רשימת המפרשים. תלוי בבחירת המפרשים בלבד: הכללת
/// העמוד או מצב הכיווץ יוצרת רשימה חדשה ומאבדת את מיקום הגלילה.
@visibleForTesting
String pdfCommentaryListStorageKey(Iterable<String> activeCommentators) =>
    'commentary_${(activeCommentators.toList()..sort()).join(',')}';

/// מפתח מטמון התוכן הנראה. [linksIdentity] חייב להיות זהות רשימת הקישורים
/// ולא אורכה: רענון חלון-קישורים מחליף את הרשימה, ואורך זהה אינו מבדיל.
@visibleForTesting
String pdfVisibleContentCacheKey({
  required int startLine,
  required int endLine,
  required Set<int>? extraLineIndices,
  required Iterable<String> activeCommentators,
  required int linksIdentity,
  Set<String> commentaryTypes = const {},
}) {
  final extraKey = extraLineIndices == null
      ? ''
      : (extraLineIndices.toList()..sort()).join(',');
  final commentatorsKey = (activeCommentators.toList()..sort()).join('|');
  final typesKey = (commentaryTypes.toList()..sort()).join('+');
  return '$startLine:$endLine:$extraKey:$commentatorsKey:$linksIdentity'
      ':$typesKey';
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
  List<LinkTargetSummary> targets,
  int maxSourceLine,
) {
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

  /// רשימת קטעי תוצאות החיפוש לתצוגה בפאנל הצד (כמו בכרטיסיית הטקסט).
  final ValueNotifier<List<CommentarySearchSnippet>>?
  externalSearchSnippetsNotifier;

  /// בחירת סוגי המפרשים כשההורה מציג את הצ׳יפים בפאנל צד. כשהוא null הבחירה
  /// מנוהלת מקומית (ה-overlay הפנימי של החלונית).
  final CommentaryTypeSelection? typeSelection;

  /// משקף החוצה את מצב "הכל מורחב" (לכפתור הכיווץ/הרחבה בסרגל הכרטיסייה).
  final ValueNotifier<bool>? externalAllExpandedNotifier;

  /// הסרת ניקוד/פיסוק מתוכן המפרשים (כמו בכרטיסיית הטקסט).
  final bool removeNikud;
  final bool removePunctuation;

  @visibleForTesting
  final Future<List<CommentaryGroup>> Function(List<Link>)?
  commentaryGroupsLoader;

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
    this.externalSearchSnippetsNotifier,
    this.typeSelection,
    this.externalAllExpandedNotifier,
    this.removeNikud = false,
    this.removePunctuation = false,
    this.commentaryGroupsLoader,
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

  /// קטע התצוגה של תוצאת החיפוש בכל מפרש (link key → snippet).
  final Map<String, String> _searchSnippetsPerLink = {};

  /// הטקסט המרונדר של כל מפרש מוצג — לשחזור מעברי שורה בהעתקה רב-שורתית,
  /// ש-Flutter מחזיר שטוחה.
  final Map<String, String> _renderedTextByKey = {};

  /// הכותרת המרונדרת של כל מפרש מוצג. הבחירה יכולה לכלול גם כותרות, ולכן הן
  /// חלק מרצף השורות שממנו משוחזרים מעברי השורה.
  final Map<String, String> _renderedTitleByKey = {};

  /// המפרש שנלחץ לאחרונה. ל-SelectionArea היחיד אין מידע על המפרש הספציפי,
  /// והוא נדרש לייחוס כותרת המקור בהעתקה.
  Link? _lastSelectedLink;
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
  List<Link> _orderedLinks = [];
  List<CommentaryGroup> _orderedGroups = [];

  /// נשמרות כדי להשאיר את עץ הרשימה חי ומוסתר בזמן טעינת הקטע הבא.
  List<CommentaryGroup>? _lastResolvedGroups;
  _PdfVisibleContentCache? _visibleContentCache;
  List<CommentatorGroup> _commentatorGroups = [];

  /// מפרשים "נדירים" שמוסתרים מלשונית הבחירה (ספרים גדולים בלבד).
  Set<String> _rareCommentators = {};

  /// סינון לפי סוג מפרש (תרגום/מדרש וכו׳). מצב מקומי ולא מוגדר: הצ׳יפים תלויים
  /// בקטע הנוכחי, ובחירה שנשמרה הייתה מסננת בשקט ספר אחר שנפתח אחריו.
  Set<String> _localCommentaryTypes = const {};

  /// הבחירה האפקטיבית: חיצונית כשההורה מציג את הצ׳יפים בפאנל צד, אחרת מקומית.
  Set<String> get _selectedCommentaryTypes =>
      widget.typeSelection?.value ?? _localCommentaryTypes;

  void _setSelectedCommentaryTypes(Set<String> types) {
    final external = widget.typeSelection;
    if (external != null) {
      external.value = types;
      return;
    }
    setState(() => _localCommentaryTypes = types);
  }

  void _onTypeSelectionChanged() {
    if (mounted) setState(() => _visibleContentCache = null);
  }

  /// סינון צ׳יפי לשונית הקישורים (סוג הקישור / דור המחבר).
  Set<String> _selectedLinkTypes = const {};

  String _getLinkKey(Link link) => pdfCommentaryItemKey(link);

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
      _searchSnippetsPerLink.clear();
      _showSearchField = false;
    });
    _publishSearchSnippets();
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
    widget.typeSelection?.addListener(_onTypeSelectionChanged);
    _loadCommentatorGroups();
    _scrolledRangeKey = _currentRangeKey();
  }

  void _onExternalSearchChanged() {
    final text = widget.externalSearchController!.text;
    if (!mounted) return;
    setState(() {
      _searchQuery = text;
      _currentSearchIndex = 0;
      if (text.isEmpty) {
        _searchResultsPerLink.clear();
        _searchSnippetsPerLink.clear();
        _totalSearchResults = 0;
      }
    });
    widget.externalTotalResultsNotifier?.value = _totalSearchResults;
    widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
    if (text.isEmpty) _publishSearchSnippets();
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
              companion.title,
              companion.categoryId!,
            )
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
        companion.title,
        companion.categoryId!,
      );
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
              summary.targets,
              summary.maxSourceLine,
            )
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
    final groups = buildCommentatorGroups(eras, availableCommentators);
    if (!mounted) return;
    setState(() {
      _rareCommentators = rare;
      _commentatorGroups = groups;
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
    if (oldWidget.typeSelection != widget.typeSelection) {
      oldWidget.typeSelection?.removeListener(_onTypeSelectionChanged);
      widget.typeSelection?.addListener(_onTypeSelectionChanged);
    }
    _resetScrollIfRangeChanged();
    // הספירות והקטעים נגזרים מהתוכן אחרי הסרת ניקוד/פיסוק, ולכן שינוי ההגדרה
    // בזמן חיפוש פעיל מחייב חישוב מחדש.
    if (oldWidget.removeNikud != widget.removeNikud ||
        oldWidget.removePunctuation != widget.removePunctuation) {
      if (_searchQuery.isNotEmpty) _scheduleSearchCompute();
    }

    if (oldWidget.tab != widget.tab) {
      _visibleContentCache = null;
      _lastResolvedGroups = null;
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
    widget.typeSelection?.removeListener(_onTypeSelectionChanged);
    _searchFocusNode.dispose();
    _commentaryFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// טווח השורות שהרשימה גוללה עבורו. מפתחות הרשימה קבועים ולכן ה-State שורד
  /// דפדוף; בלי איפוס מפורש הדף החדש נפתח על היסט הדף הקודם.
  String? _scrolledRangeKey;

  /// מזהה הטווח הנוכחי, או null כשאין מיקום. נגזר מאותם override-ים שמזינים
  /// את הרשימה, כדי שהאיפוס יתרחש בדיוק כשהתוכן מתחלף.
  String? _currentRangeKey() {
    final currentLine =
        widget.lineStartOverride ?? widget.tab.currentTextLineNumber;
    if (currentLine == null) return null;
    final range = _getCurrentRange(currentLine);
    return '${range.startLine}:${range.endLine}';
  }

  String? _currentLinksScopeKey() {
    final rangeKey = _currentRangeKey();
    if (rangeKey == null) return null;
    final extraLines = widget.extraLineIndices?.toList();
    extraLines?.sort();
    return '$rangeKey|${extraLines?.join(',') ?? ''}';
  }

  void _resetScrollIfRangeChanged() {
    final rangeKey = _currentRangeKey();
    if (rangeKey == null || _scrolledRangeKey == rangeKey) return;
    final isFirstRange = _scrolledRangeKey == null;
    _scrolledRangeKey = rangeKey;
    if (isFirstRange) return;
    _orderedLinks = [];
    _orderedGroups = [];
    _totalSearchResults = 0;
    _currentSearchIndex = 0;
    _searchResultsPerLink.clear();
    _searchSnippetsPerLink.clear();
    _pendingCounts.clear();
    widget.externalTotalResultsNotifier?.value = 0;
    widget.externalCurrentIndexNotifier?.value = 0;
    _publishSearchSnippets();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(index: 0);
    });
  }

  /// ניווט אל היקרות לפי אינדקס גלובלי — נקרא מלחיצה על קטע תוצאה בפאנל הצד.
  void navigateToGlobalIndex(int index) {
    if (index < 0 || index >= _totalSearchResults) return;
    setState(() => _currentSearchIndex = index);
    widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
    _scrollToSearchResult();
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
    _searchComputeDebounce = Timer(
      const Duration(milliseconds: 250),
      _computeSearchCounts,
    );
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
      final count = countCommentarySearchMatches(
        content: data,
        query: query,
        removePunctuation: widget.removePunctuation,
      );
      // גזירה באותו מעבר שכבר טען את התוכן — כך הרשימה שלמה גם לפריטים
      // שהרשימה הווירטואלית לא בנתה.
      if (count > 0) {
        _searchSnippetsPerLink[_getLinkKey(
          link,
        )] = buildCommentarySearchSnippet(
          content: data,
          query: query,
          removeNikud: widget.removeNikud,
          removePunctuation: widget.removePunctuation,
        );
      } else {
        _searchSnippetsPerLink.remove(_getLinkKey(link));
      }
      _updateSearchResultsCount(link, count);
    }
  }

  /// מפרסם את רשימת קטעי החיפוש להורה, בסדר התצוגה ועם ה-globalIndex שממנו
  /// הניווט 'תוצאה הבאה' יודע לאיזה מפרש לגלול.
  void _publishSearchSnippets() {
    final notifier = widget.externalSearchSnippetsNotifier;
    if (notifier == null || !mounted) return;
    final result = <CommentarySearchSnippet>[];
    var globalIndex = 0;
    for (final link in _orderedLinks) {
      final key = _getLinkKey(link);
      final count = _searchResultsPerLink[key] ?? 0;
      final snippet = _searchSnippetsPerLink[key];
      if (snippet != null && count > 0) {
        result.add(
          CommentarySearchSnippet(
            path: link.path2,
            snippet: snippet,
            globalIndex: globalIndex,
          ),
        );
      }
      globalIndex += count;
    }
    notifier.value = result;
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
        // ספירות זהות עדיין יכולות לשאת קטעים חדשים (שאילתה אחרת, אותו מספר
        // התאמות), ולכן הפרסום נדרש גם כאן.
        _publishSearchSnippets();
        return;
      }

      setState(() {
        _searchResultsPerLink.addAll(_pendingCounts);
        _pendingCounts.clear();
        _totalSearchResults = _searchResultsPerLink.values.fold(
          0,
          (sum, count) => sum + count,
        );

        // Reset current index if out of bounds
        if (_currentSearchIndex >= _totalSearchResults &&
            _totalSearchResults > 0) {
          _currentSearchIndex = 0;
        }
        widget.externalTotalResultsNotifier?.value = _totalSearchResults;
        widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
      });
      // חובה כאן: הקטעים נגזרים מהספירות, והן נכנסות רק בתוך ה-flush הזה.
      // פרסום מחוץ לו מייצר רשימה לפי ספירות של השאילתה הקודמת.
      _publishSearchSnippets();
    });
  }

  /// משחזר מעברי שורה בבחירה רב-שורתית לפי הטקסט המרונדר של המפרשים המוצגים.
  String? _restoreLineBreaks(String? flat) {
    if (flat == null || flat.isEmpty || flat.contains('\n')) return flat;
    final lines = <String>[];
    for (final link in _orderedLinks) {
      final key = _getLinkKey(link);
      final title = _renderedTitleByKey[key];
      if (title != null && title.isNotEmpty) lines.add(title);
      final content = _renderedTextByKey[key];
      if (content != null && content.isNotEmpty) lines.add(content);
    }
    if (lines.isEmpty) return flat;
    return restoreSelectedTextLineBreaks(
      selectedText: flat,
      visibleLines: lines,
    );
  }

  /// האם הבחירה חוצה יותר ממפרש אחד, לפי מיקום שני קצותיה. בחירה כזו אינה
  /// מיוחסת למפרש בודד, אחרת הייתה מקבלת כותרת מקור שגויה.
  bool _selectionSpansMultipleItems() {
    SelectableRegionState? sa;
    for (final k in _itemKeys.values) {
      sa = k.currentContext?.findAncestorStateOfType<SelectableRegionState>();
      if (sa != null) break;
    }
    final saRender = sa?.context.findRenderObject();
    if (saRender is! RenderBox) return false;
    final List<TextSelectionPoint> eps;
    try {
      eps = sa!.selectionEndpoints;
    } catch (_) {
      return false;
    }
    if (eps.length < 2) return false;
    final p1 = saRender.localToGlobal(eps.first.point);
    final p2 = saRender.localToGlobal(eps.last.point);
    String? k1;
    String? k2;
    for (final entry in _itemKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(p1)) k1 = entry.key;
      if (rect.contains(p2)) k2 = entry.key;
    }
    return k1 != null && k2 != null && k1 != k2;
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  Future<void> _copyFormattedText() async {
    await ContextMenuUtils.copyFormattedText(
      context: context,
      savedSelectedText: _restoreLineBreaks(_savedSelectedText),
      fontSize: widget.fontSize,
      link: _selectionSpansMultipleItems() ? null : _lastSelectedLink,
    );
  }

  /// בניית תפריט הקשר למפרש ספציפי
  List<AppContextMenuEntry> _buildCommentaryContextMenuEntries(
    BuildContext menuCtx,
    Link link,
  ) {
    return ContextMenuUtils.buildCommentaryContextMenu(
      context: menuCtx,
      link: link,
      openBookCallback: widget.openBookCallback,
      fontSize: widget.fontSize,
      removeNikud: widget.removeNikud,
      removePunctuation: widget.removePunctuation,
      savedSelectedText: _savedSelectedText,
      onCopySelected: () => ContextMenuUtils.copyFormattedText(
        context: menuCtx,
        savedSelectedText: _restoreLineBreaks(_savedSelectedText),
        fontSize: widget.fontSize,
        link: _selectionSpansMultipleItems()
            ? null
            : (_lastSelectedLink ?? link),
      ),
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
              // מפתחות חייבים להישאר קבועים: מפתח תלוי-עמוד הורס את שלושת
              // התתי-עצים בכל דפדוף ומאפס את מטמוני התוכן שלהם.
              _KeepAliveTab(
                key: const ValueKey('pdf_panel_commentary'),
                child: _wrapCommentariesScrollable(_buildCommentariesView()),
              ),
              // ללא עוטף בחירה: LinksListView מנהל SelectionArea פר-קישור,
              // וקינון תחת אזור חיצוני שובר את הבחירה והעתקתה.
              _KeepAliveTab(
                key: const ValueKey('pdf_panel_links'),
                child: _buildLinksView(),
              ),
              _KeepAliveTab(
                key: const ValueKey('pdf_panel_notes'),
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
        link.index1,
        range.startLine,
        range.endLine,
        extra,
      )) {
        continue;
      }
      final title = utils.getTitleFromPath(link.path2);
      if (_rareCommentators.contains(title)) relevant.add(title);
    }
    return relevant;
  }

  Widget _buildCommentatorsFilter() {
    final visibleContent = _getVisibleContent();
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
        typeChipKeys: visibleContent?.typeChipKeys ?? const [],
        selectedTypeChips: visibleContent?.effectiveTypes ?? const {},
        typeChipLabelBuilder: LinkTypes.hebrewLabel,
        commentatorsByType: visibleContent?.commentatorsByType ?? const {},
        onTypeChipsChanged: _setSelectedCommentaryTypes,
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
      UiSnack.show(PdfMessages.noCommentariesToPrint);
      return;
    }

    final groups = await visibleContent.sortedGroupsFuture;
    final blocks = await buildCommentaryPrintBlocks(groups);
    if (blocks.isEmpty) {
      UiSnack.show(PdfMessages.noCommentariesToPrint);
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
            _searchSnippetsPerLink.clear();
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        final currentGroups =
            snapshot.connectionState == ConnectionState.done && snapshot.hasData
            ? snapshot.data
            : null;
        final sortedGroups = currentGroups ?? _lastResolvedGroups;
        if (sortedGroups == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (currentGroups != null) {
          _lastResolvedGroups = currentGroups;
          _orderedGroups = currentGroups;
        }

        // Rebuild _orderedLinks based on groups
        final orderedLinks = <Link>[];
        for (final group in currentGroups ?? const <CommentaryGroup>[]) {
          // We need to verify link order inside group.
          // In _buildCommentariesView, relevantLinks are sorted by title then index.
          // _groupConsecutiveLinks groups them.
          // So the links inside group.links should already be in order.
          orderedLinks.addAll(group.links);
        }
        if (currentGroups != null) _orderedLinks = orderedLinks;

        // Initialize keys
        final currentLinkKeys = _orderedLinks
            .map((l) => _getLinkKey(l))
            .toSet();

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
        _renderedTextByKey.removeWhere(
          (key, value) => !currentLinkKeys.contains(key),
        );

        // ניקוי ספירות חיפוש מקישורים שאינם בקטע הנוכחי
        final staleSearchKeys = _searchResultsPerLink.keys
            .where((key) => !currentLinkKeys.contains(key))
            .toList();
        if (staleSearchKeys.isNotEmpty) {
          for (final key in staleSearchKeys) {
            _searchResultsPerLink.remove(key);
            _searchSnippetsPerLink.remove(key);
          }
          _pendingCounts.removeWhere(
            (key, _) => !currentLinkKeys.contains(key),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final newTotal = _searchResultsPerLink.values.fold(
              0,
              (sum, c) => sum + c,
            );
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

        return Stack(
          fit: StackFit.expand,
          children: [
            Visibility(
              visible: currentGroups != null,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: ScrollablePositionedListScrollbar(
                scrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                itemCount: sortedGroups.length,
                labelForIndex: (index) =>
                    index >= 0 && index < sortedGroups.length
                    ? sortedGroups[index].bookTitle
                    : '',
                child: ScrollablePositionedList.builder(
                  key: PageStorageKey(
                    pdfCommentaryListStorageKey(
                      widget.tab.activeCommentators,
                    ),
                  ),
                  itemCount: sortedGroups.length,
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  scrollOffsetController: _scrollOffsetController,
                  itemBuilder: (context, index) {
                    final group = sortedGroups[index];
                    return _buildCommentaryGroupTile(group);
                  },
                ),
              ),
            ),
            if (currentGroups == null)
              ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
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
      final bool itemInRenderTree =
          itemContext != null &&
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
          key: PageStorageKey(group.bookTitle),
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
          onLinkRendered: (link, text) =>
              _renderedTextByKey[_getLinkKey(link)] = text,
          onLinkTitleRendered: (link, title) =>
              _renderedTitleByKey[_getLinkKey(link)] = title
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim(),
          onLinkPointerDown: (link) => _lastSelectedLink = link,
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final relevantLinks = visibleContent.links;

    if (relevantLinks.isEmpty && widget.linksLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'טוען קישורים...',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // אותה רשימה בדיוק כמו בכרטיסיית הטקסט: צ׳יפי סוג ודור, חיפוש בכותרת
    // ובתוכן, ורינדור SmartText.
    return LinksListView(
      links: relevantLinks,
      chipSourceLinks: widget.tab.links,
      openBookTitle: widget.tab.book.title,
      selectedLinkTypes: _selectedLinkTypes,
      onSelectedLinkTypesChanged: (types) =>
          setState(() => _selectedLinkTypes = types),
      openBookCallback: widget.openBookCallback,
      fontSize: widget.fontSize,
      removeNikud: widget.removeNikud,
      removePunctuation: widget.removePunctuation,
      contentScopeKey: _currentLinksScopeKey(),
      emptyMessage: 'לא נמצאו קישורים לדף זה',
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
                  widget.tab.pdfViewerController.goToPage(
                    pageNumber: targetPage,
                  );
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
    final cacheKey = pdfVisibleContentCacheKey(
      startLine: range.startLine,
      endLine: range.endLine,
      extraLineIndices: widget.extraLineIndices,
      activeCommentators: widget.tab.activeCommentators,
      linksIdentity: identityHashCode(widget.tab.links),
      commentaryTypes: _selectedCommentaryTypes,
    );

    final existingCache = _visibleContentCache;
    if (existingCache != null && existingCache.cacheKey == cacheKey) {
      return existingCache;
    }

    // כל מפרשי הקטע לפני סינון הסוגים — מהם נבנים הצ׳יפים, כדי שצ׳יפ לא ייעלם
    // ברגע שנבחר (ואז לא הייתה דרך לבטל את הסינון).
    final scopedCommentaryLinks = <Link>[];
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
        link.index1,
        range.startLine,
        range.endLine,
        extraLines,
      )) {
        continue;
      }

      if (LinkTypes.isDependentTextLink(link.connectionType)) {
        hasAnyCommentaryLinks = true;
        continue;
      }

      if (link.start == null && link.end == null) {
        nonCommentaryLinks.add(link);
      }
    }

    scopedCommentaryLinks.addAll(
      pdfScopedCommentaryLinks(
        links: widget.tab.links,
        startLine: range.startLine,
        endLine: range.endLine,
        extraLineIndices: extraLines,
        activeCommentators: widget.tab.activeCommentators,
        showAllWhenEmpty: showAllWhenEmpty,
      ),
    );

    // הצ׳יפים נגזרים מכל הקישורים הטעונים ולא מהעמוד הנוכחי: צ׳יפ שנגזר
    // מהעמוד נעלם בדפדוף לעמוד שאין בו אותו סוג, והסינון נכבה בשקט.
    final typeChipKeys = CommentaryTypeFilter.chipKeysForCommentators(
      links: widget.tab.links,
      selectedCommentators: showAllWhenEmpty
          ? widget.tab.links
                .map((link) => utils.getTitleFromPath(link.path2))
                .toList(growable: false)
          : widget.tab.activeCommentators.toList(growable: false),
    );
    final effectiveTypes = CommentaryTypeFilter.effectiveTypes(
      selectedTypes: _selectedCommentaryTypes,
      availableKeys: typeChipKeys,
    );
    for (final link in scopedCommentaryLinks) {
      if (effectiveTypes.isEmpty ||
          effectiveTypes.contains(
            LinkTypes.canonicalType(link.connectionType),
          )) {
        commentaryLinks.add(link);
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
    final sortedNonCommentaryLinks = CommentaryService.sortLinksByEraSync(
      nonCommentaryLinks,
    );

    final cache = _PdfVisibleContentCache(
      cacheKey: cacheKey,
      commentaryLinks: List.unmodifiable(commentaryLinks),
      links: List.unmodifiable(sortedNonCommentaryLinks),
      hasAnyCommentaryLinks: hasAnyCommentaryLinks,
      typeChipKeys: CommentaryTypeFilter.visibleChipKeys(
        chipKeys: typeChipKeys,
        effectiveTypes: effectiveTypes,
      ),
      effectiveTypes: effectiveTypes,
      // אותה רשימה שממנה נגזרו הצ׳יפים — וגם מאפשר ל-Expando של המימוש
      // לפגוע, שכן זהות tab.links יציבה לכל חלון קישורים.
      commentatorsByType: CommentaryTypeFilter.commentatorsByType(
        widget.tab.links,
      ),
      // אסינכרוני: קיבוץ סינכרוני על ה-UI thread קפא בדפי גמרא עם מפרשים רבים.
      sortedGroupsFuture:
          (widget.commentaryGroupsLoader ??
          CommentaryService.groupAndSortLinks)(commentaryLinks),
    );
    _visibleContentCache = cache;
    return cache;
  }

  ({int startLine, int endLine}) _getCurrentRange(int currentLine) {
    final endLine =
        widget.lineEndOverride ??
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

  /// מפרשי הקטע אחרי סינון הסוגים — אלה שמוצגים בפועל.
  final List<Link> commentaryLinks;
  final List<Link> links;
  final bool hasAnyCommentaryLinks;

  /// צ׳יפי סוגי המפרשים להצגה, והבחירה האפקטיבית מתוכם (ריקה = הצג הכל).
  final List<String> typeChipKeys;
  final Set<String> effectiveTypes;
  final Map<String, Set<String>> commentatorsByType;

  final Future<List<CommentaryGroup>> sortedGroupsFuture;

  const _PdfVisibleContentCache({
    required this.cacheKey,
    required this.commentaryLinks,
    required this.links,
    required this.hasAnyCommentaryLinks,
    required this.typeChipKeys,
    required this.effectiveTypes,
    required this.commentatorsByType,
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

  /// מדווח את הטקסט המרונדר של פריט — לשחזור מעברי שורה בהעתקה רב-שורתית.
  final void Function(Link link, String renderedPlainText)? onLinkRendered;

  /// מדווח את הכותרת המרונדרת של פריט — לאותה מטרה.
  final void Function(Link link, String renderedTitle)? onLinkTitleRendered;

  /// נקרא בלחיצת עכבר על פריט — לסימון המפרש שאליו תיוחס כותרת ההעתקה.
  final void Function(Link link)? onLinkPointerDown;

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
    this.onLinkRendered,
    this.onLinkTitleRendered,
    this.onLinkPointerDown,
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: widget.isExpanded ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: RtlIcon(
                    FluentIcons.chevron_left_24_regular,
                    size: 20,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.settingsState.replaceHolyNames
                        ? utils.replaceHolyNames(widget.group.bookTitle)
                        : widget.group.bookTitle,
                    style: TextStyle(
                      fontSize: widget.settingsState.commentatorsFontSize - 2,
                      fontWeight: FontWeight.bold,
                      fontVariations: AppFonts.boldFontVariations(
                        widget.settingsState.commentatorsFontFamily,
                      ),
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
            return Listener(
              // מזהה על איזה מפרש לחץ המשתמש — ל-SelectionArea היחיד אין מידע
              // כזה, והוא נדרש לייחוס כותרת המקור בהעתקת מקלדת.
              onPointerDown: (_) => widget.onLinkPointerDown?.call(link),
              child: Padding(
                key: widget.getKeyForLink?.call(
                  link,
                ), // Attach the key here for scrolling
                padding: const EdgeInsets.only(
                  right: 32.0,
                  left: 16.0,
                  top: 8.0,
                  bottom: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: link.displayReference,
                      builder: (context, snapshot) {
                        var displayTitle =
                            snapshot.data ?? link.fallbackDisplayReference;
                        // קישור עם עוגן-מילה: אות הסימון שמופיעה בגוף הטקסט
                        // מוצגת גם לפני כותרת ההערה.
                        if (link.anchorStart != null) {
                          final markerLetter = anchorMarkerLetter(link);
                          if (markerLetter != null) {
                            displayTitle = '($markerLetter) $displayTitle';
                          }
                        }
                        if (widget.settingsState.replaceHolyNames) {
                          displayTitle = utils.replaceHolyNames(displayTitle);
                        }
                        final reportedTitle = displayTitle;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          widget.onLinkTitleRendered?.call(link, reportedTitle);
                        });
                        return Text(
                          displayTitle,
                          style: TextStyle(
                            fontSize:
                                widget.settingsState.commentatorsFontSize - 4,
                            fontWeight: FontWeight.normal,
                            fontFamily:
                                widget.settingsState.commentatorsFontFamily,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                      child: CommentaryContent(
                        key: ValueKey(pdfCommentaryItemKey(link)),
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
                        onRendered: (text) =>
                            widget.onLinkRendered?.call(link, text),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        const Divider(height: 1),
      ],
    );
  }
}
