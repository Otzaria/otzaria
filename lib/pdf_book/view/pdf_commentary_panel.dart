import 'package:otzaria/book_common/bloc/commentary_search_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_commentary_subblock.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/book_common/view/content_width.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';
import 'package:otzaria/book_common/selection/commentary_copy_guard.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_common/utils/commentary_search_results.dart';
import 'package:otzaria/book_common/utils/commentary_flat_items.dart';
import 'package:otzaria/book_common/utils/commentary_plugin_menu_entries.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/layout/commentators_filter_screen.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/pdf_book/utils/pdf_commentary_visibility.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/pdf_book/utils/pdf_plugin_menu_entries.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/models/commentary_scroll_request.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/commentary/links_list_view.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/models/text_display_slot.dart';
import 'package:otzaria/book_common/utils/commentary_type_filter.dart';
import 'package:otzaria/book_common/utils/commentator_group_builder.dart';
import 'package:otzaria/book_common/utils/default_commentators.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
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

import 'dart:async';

import 'package:positioned_sliver_list/positioned_list.dart';

/// Type alias לתאימות - משתמש ב-LinkGroup מה-Service
typedef CommentaryGroup = LinkGroup;

/// האם קישור (לפי [linkIndex1]) בתחום המוצג: בטווח הראשי [startLine]–[endLine]
/// או באחת השורות הנוספות של ריבוי-הבחירה ([extraLineIndices], Ctrl+לחיצה).
@visibleForTesting
bool pdfLinkInVisibleScope(
  int linkIndex1,
  int startLine,
  int endLine,
  Set<int>? extraLineIndices, {
  int? linkIndex1End,
}) {
  final lastLinkLine = linkIndex1End ?? linkIndex1;
  if (linkIndex1 <= endLine && lastLinkLine >= startLine) return true;
  return extraLineIndices?.any(
        (line) => linkIndex1 <= line && line <= lastLinkLine,
      ) ??
      false;
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
      linkIndex1End: link.index1End,
    )) {
      continue;
    }
    if (showAllWhenEmpty ||
        activeCommentators.contains(utils.getTitleFromPath(link.path2))) {
      scoped.add(link);
    }
  }
  return dedupeLinksByTarget(scoped);
}

/// מפתח ה-PageStorage של רשימת המפרשים. תלוי בבחירת המפרשים בלבד: הכללת
/// העמוד או מצב הכיווץ יוצרת רשימה חדשה ומאבדת את מיקום הגלילה.
@visibleForTesting
String pdfCommentaryListStorageKey(Iterable<String> activeCommentators) =>
    'commentary_${(activeCommentators.toList()..sort()).join(',')}';

// המיון משווה כל קישור פעמים רבות; שם המפרש נגזר מהנתיב פעם אחת לקישור.
final Expando<String> _sortTitles = Expando();
String _sortTitle(Link link) =>
    _sortTitles[link] ??= utils.getTitleFromPath(link.path2);

/// סדר מפרשי הקטע: לפי מפרש, שורת מקור, ואז שורת היעד במפרש. בלי [Link.index2]
/// קטעים על אותה שורה יוצאים בסדר שרירותי — המיון של Dart אינו יציב (#1330).
@visibleForTesting
int comparePdfCommentaryLinks(Link a, Link b) {
  final titleCompare = _sortTitle(a).compareTo(_sortTitle(b));
  if (titleCompare != 0) return titleCompare;
  final sourceCompare = a.index1.compareTo(b.index1);
  if (sourceCompare != 0) return sourceCompare;
  return a.index2.compareTo(b.index2);
}

/// מסדר את [groups] לפי סדר [commentatorOrder] (סדר רשימת הבחירה), ומפרש
/// שאינו ברשימה נשאר אחריהם בסדרו הקיים.
@visibleForTesting
List<CommentaryGroup> orderPdfCommentaryGroups(
  List<CommentaryGroup> groups,
  List<String> commentatorOrder,
) {
  if (groups.length < 2 || commentatorOrder.isEmpty) return groups;
  final rank = {
    for (var i = commentatorOrder.length - 1; i >= 0; i--)
      commentatorOrder[i]: i,
  };
  int rankOf(int i) => rank[groups[i].bookTitle] ?? commentatorOrder.length;
  final indexes = List.generate(groups.length, (i) => i)
    ..sort((a, b) {
      final byRank = rankOf(a).compareTo(rankOf(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return [for (final i in indexes) groups[i]];
}

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
    final lastLine = link.index1End ?? link.index1;
    if (lastLine > maxSourceLine) maxSourceLine = lastLine;
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

/// בוחר את מקור רשימת המפרשים: סיכום כלל־ספרי כשהקישורים נטענו בחלון,
/// או את רשימת הקישורים עצמה כשהיא מלאה/כשאין סיכום זמין.
@visibleForTesting
LinkTargetsAggregation aggregateLinkTargetsForCommentatorSelection({
  required bool linksAreComplete,
  required Iterable<Link> links,
  List<LinkTargetSummary>? summaryTargets,
  int summaryMaxSourceLine = 0,
}) {
  if (!linksAreComplete && summaryTargets != null) {
    return aggregateLinkTargetsFromSummary(
      summaryTargets,
      summaryMaxSourceLine,
    );
  }
  return aggregateLinkTargetsFromLinks(links);
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

  /// רוחב מרבי לרשימת המפרשים (הגדרת רוחב הטקסט); null = ללא הגבלה.
  final double? contentMaxWidth;
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

  /// פרופיל תצוגת המפרשים (כמו בכרטיסיית הטקסט).
  final TextDisplayProfile displayProfile;

  /// פרופיל ערוץ ההעתקה; null = כמו התצוגה.
  final TextDisplayProfile? copyDisplayProfile;

  @visibleForTesting
  final Future<List<CommentaryGroup>> Function(List<Link>)?
  commentaryGroupsLoader;

  const PdfCommentaryPanel({
    super.key,
    required this.tab,
    required this.linksCount,
    this.linksLoading = false,
    this.contentMaxWidth,
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
    this.displayProfile = TextDisplayProfile.defaults,
    this.copyDisplayProfile,
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
  Object? _fullSelectionScope;
  List<String? Function()>? _fullSelectionLines;
  String? get _fullSelectionText {
    final lines = _fullSelectionLines?.map((line) => line()).toList();
    if (lines == null || lines.any((line) => line == null)) return null;
    return lines.join('\n');
  }

  late final _commentarySelectionDelegate = _PdfCommentarySelectionDelegate(
    scope: () => _fullSelectionScope,
    fullText: () => _fullSelectionText,
  );
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _currentSearchIndex = 0;
  int _totalSearchResults = 0;
  bool _allExpanded = true;
  // האם להציג את שדה החיפוש (true) או את שורת ארבעת הלחצנים (false)
  bool _showSearchField = false;
  final Map<String, bool> _expansionStates = {};

  Map<String, int> get _searchResultsPerLink => _searchBloc.state.counts;

  /// הטקסט המרונדר של כל מפרש מוצג — לשחזור מעברי שורה בהעתקה רב-שורתית,
  /// ש-Flutter מחזיר שטוחה.
  final Map<String, String> _renderedTextByKey = {};

  /// הכותרת המרונדרת של כל מפרש מוצג. הבחירה יכולה לכלול גם כותרות, ולכן הן
  /// חלק מרצף השורות שממנו משוחזרים מעברי השורה.
  final Map<String, String> _renderedTitleByKey = {};

  /// המפרש שנלחץ לאחרונה. ל-SelectionArea היחיד אין מידע על המפרש הספציפי,
  /// והוא נדרש לייחוס כותרת המקור בהעתקה.
  Link? _lastSelectedLink;

  // Scroll support
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ListController _listController = ListController();
  final Map<String, GlobalKey> _headerKeys = {};
  HeaderAnchorHandle? _headerAnchor;
  Map<Key, int> _flatIndexByKey = const {};
  int _searchScrollGeneration = 0;
  final FocusNode _commentaryFocusNode = FocusNode();
  final Map<String, GlobalKey> _itemKeys = {};
  List<Link> _orderedLinks = [];
  List<CommentaryGroup> _orderedGroups = [];

  /// One item per group header and one per commentary of an expanded group,
  /// so the list builds only what is on screen (#844).
  List<CommentaryFlatItem> _flatItems = const [];
  Map<String, int> _linkFlatIndex = const {};
  ({
    List<CommentaryGroup> groups,
    Map<String, bool> expansion,
    List<CommentaryFlatItem> items,
  })?
  _flatSnapshot;

  /// נשמרות כדי להשאיר את עץ הרשימה חי ומוסתר בזמן טעינת הקטע הבא.
  List<CommentaryGroup>? _lastResolvedGroups;
  _PdfVisibleContentCache? _visibleContentCache;
  final _visibleLinksCache = PdfCommentaryVisibleLinksCache();
  List<CommentatorGroup> _commentatorGroups = [];
  PdfCommentaryVisibility? _visibility =
      const HiddenLibraryStore().load().isEmpty
      ? PdfCommentaryVisibility.empty()
      : null;
  StreamSubscription<void>? _hiddenSelectionSubscription;
  int _visibilityLoadGeneration = 0;

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

  /// סינון צ׳יפי לשונית הקישורים (סוג הקישור / דור המחבר). נוטיפייר ולא
  /// setState, כדי ששינוי הסינון לא יבנה מחדש את רשימת המפרשים.
  final ValueNotifier<Set<String>> _selectedLinkTypes = ValueNotifier(const {});

  String _getLinkKey(Link link) => commentaryLinkKey(link);

  /// היסט התוצאה הראשונה של כל פריט בסדר התצוגה. מחושב פעם אחת לכל build:
  /// סריקה מלאה לכל פריט שנבנה הייתה ריבועית בקבוצה מורחבת גדולה.
  Map<String, int>? _searchResultOffsets;
  List<Link>? _searchResultOffsetsFor;

  // Helper to determine relative index for highlighting
  int _getItemSearchIndex(Link link) {
    if (_searchResultsPerLink.isEmpty) return -1;

    final linkKey = _getLinkKey(link);
    if ((_searchResultsPerLink[linkKey] ?? 0) == 0) return -1;

    if (!identical(_searchResultOffsetsFor, _orderedLinks)) {
      _searchResultOffsets = null;
      _searchResultOffsetsFor = _orderedLinks;
    }
    final offsets = _searchResultOffsets ??= commentarySearchOffsets(
      _orderedLinks.map(_getLinkKey),
      _searchResultsPerLink,
    );
    return commentarySearchRelativeIndex(
      key: linkKey,
      currentIndex: _currentSearchIndex,
      offsets: offsets,
      countsByKey: _searchResultsPerLink,
    );
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
    _cancelSearchScroll();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _currentSearchIndex = 0;
      _totalSearchResults = 0;

      _showSearchField = false;
    });
    _scheduleSearchCompute();
  }

  @override
  void initState() {
    super.initState();
    _searchSubscription = _searchBloc.stream.listen(_applySearchState);
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
    _hiddenSelectionSubscription = const HiddenLibraryStore().visibilityChanges
        .listen((_) => _refreshVisibility());
    _loadCommentatorGroups();
    _scrolledRangeKey = _currentRangeKey();
    _searchScopeKey = _currentLinksScopeKey();
    if (widget.externalSearchController != null) _onExternalSearchChanged();
  }

  void _onExternalSearchChanged() {
    _cancelSearchScroll();
    final text = widget.externalSearchController!.text;
    if (!mounted) return;
    setState(() {
      _searchQuery = text;
      _currentSearchIndex = -1;
      if (text.isEmpty) {
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

  void _refreshVisibility() {
    if (!mounted) return;
    setState(() {
      _visibility = null;
      _visibleContentCache = null;
      _commentatorGroups = [];
    });
    _loadCommentatorGroups();
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
      if (provider is! DatabaseLibraryProvider &&
          !companion.source.isAttached) {
        return null;
      }
      return await DatabaseLibraryProvider.instance.getBookLinkTargetsSummary(
        companion.title,
        companion.categoryId!,
        source: companion.source,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCommentatorGroups() async {
    final generation = ++_visibilityLoadGeneration;
    final visibility = await PdfCommentaryVisibility.current();
    if (!mounted || generation != _visibilityLoadGeneration) return;
    final summary = widget.tab.linksAreComplete
        ? null
        : await _loadLinkTargetsSummary();
    if (!mounted || generation != _visibilityLoadGeneration) return;
    final visibleLinks = widget.tab.links.where(visibility.allowsLink).toList();
    final aggregation = aggregateLinkTargetsForCommentatorSelection(
      linksAreComplete: widget.tab.linksAreComplete,
      links: visibleLinks,
      summaryTargets: summary?.targets
          .where(
            (target) =>
                visibility.allowsSummary(target, widget.tab.book.source),
          )
          .toList(),
      summaryMaxSourceLine: summary?.maxSourceLine ?? 0,
    );
    final nonCommentaryTitles = aggregation.nonCommentaryTitles;

    final availableCommentators = aggregation.commentators.toList();
    final eraPreload = CommentaryService.preloadEras(availableCommentators);

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

    await eraPreload;
    final groups = await groupCommentatorsByEra(
      availableCommentators,
      source: widget.tab.book.source,
      sourceByTitle: {
        for (final target
            in summary?.targets.where(
                  (target) =>
                      visibility.allowsSummary(target, widget.tab.book.source),
                ) ??
                const <LinkTargetSummary>[])
          utils.getTitleFromPath(target.targetTitle): ?target.targetSource,
        for (final link in visibleLinks)
          utils.getTitleFromPath(link.path2): link.targetSource,
      },
      baseCommentators: await DefaultCommentators.getBaseCommentators(
        widget.tab.book,
      ),
    );
    if (!mounted || generation != _visibilityLoadGeneration) return;
    setState(() {
      _visibility = visibility;
      _visibleContentCache = null;
      _commentatorGroups = groups;
    });
  }

  @override
  void didUpdateWidget(PdfCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalTotalResultsNotifier !=
            widget.externalTotalResultsNotifier ||
        oldWidget.externalCurrentIndexNotifier !=
            widget.externalCurrentIndexNotifier ||
        oldWidget.externalSearchSnippetsNotifier !=
            widget.externalSearchSnippetsNotifier ||
        oldWidget.externalAllExpandedNotifier !=
            widget.externalAllExpandedNotifier) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.externalTotalResultsNotifier?.value = _totalSearchResults;
        widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
        widget.externalAllExpandedNotifier?.value = _allExpanded;
        _publishSearchSnippets();
      });
    }
    if (oldWidget.externalSearchController != widget.externalSearchController) {
      oldWidget.externalSearchController?.removeListener(
        _onExternalSearchChanged,
      );
      widget.externalSearchController?.addListener(_onExternalSearchChanged);
      if (widget.externalSearchController != null) {
        _onExternalSearchChanged();
      } else {
        _clearSearchAndCloseField();
      }
    }
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
    if (oldWidget.displayProfile != widget.displayProfile) {
      if (_searchQuery.isNotEmpty) _scheduleSearchCompute();
    }

    if (oldWidget.tab != widget.tab) {
      _visibleContentCache = null;
      _lastResolvedGroups = null;
      _orderedLinks = [];
      _orderedGroups = [];
      _cancelSearchScroll();
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
    unawaited(_searchSubscription?.cancel());
    unawaited(_searchBloc.close());
    _cancelSearchScroll();
    _cancelHeaderAnchor();
    _listController.dispose();
    _commentarySelectionDelegate.dispose();
    _hiddenSelectionSubscription?.cancel();

    _tabController.removeListener(_tabControllerListener);
    widget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
    widget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
    widget.externalSearchController?.removeListener(_onExternalSearchChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    widget.typeSelection?.removeListener(_onTypeSelectionChanged);
    _searchFocusNode.dispose();
    _commentaryFocusNode.dispose();
    _selectedLinkTypes.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// טווח השורות שהרשימה גוללה עבורו. מפתחות הרשימה קבועים ולכן ה-State שורד
  /// דפדוף; בלי איפוס מפורש הדף החדש נפתח על היסט הדף הקודם.
  String? _scrolledRangeKey;
  String? _searchScopeKey;

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
    final scopeKey = _currentLinksScopeKey();
    if (scopeKey == null || _searchScopeKey == scopeKey) return;
    final isFirstRange = _searchScopeKey == null;
    final rangeChanged = _scrolledRangeKey != rangeKey;
    _scrolledRangeKey = rangeKey;
    _searchScopeKey = scopeKey;
    if (isFirstRange) return;
    _searchScrollGeneration++;

    _orderedLinks = [];
    _orderedGroups = [];
    _cancelSearchScroll();
    _totalSearchResults = 0;
    _currentSearchIndex = -1;
    _scheduleSearchCompute();
    final generation = _searchScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchScopeKey != scopeKey) return;
      widget.externalTotalResultsNotifier?.value = _totalSearchResults;
      widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
      _publishSearchSnippets();
      if (rangeChanged &&
          generation == _searchScrollGeneration &&
          _itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: 0);
      }
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
    _cancelPendingNavigation();
    final generation = _searchScrollGeneration;
    final anchorTitle = _topVisibleGroupTitle();
    final preserved = _preserveGroupHeader(anchorTitle);
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
    if (anchorTitle == null || preserved) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _searchScrollGeneration ||
          !_itemScrollController.isAttached) {
        return;
      }
      final index = _flatItems.indexWhere(
        (item) => item.link == null && item.group.bookTitle == anchorTitle,
      );
      if (index >= 0) _itemScrollController.jumpTo(index: index);
    });
  }

  String? _topVisibleGroupTitle() {
    final visible = _itemPositionsListener.itemPositions.value.where(
      (position) => position.itemTrailingEdge > 0,
    );
    if (visible.isEmpty) return null;
    final top = visible.reduce((a, b) => a.index <= b.index ? a : b).index;
    return top < _flatItems.length ? _flatItems[top].group.bookTitle : null;
  }

  late final CommentarySearchBloc _searchBloc = CommentarySearchBloc(
    keyOf: _getLinkKey,
  );
  StreamSubscription<CommentarySearchState>? _searchSubscription;

  void _scheduleSearchCompute() {
    _searchBloc.add(
      CommentarySearchRequested(
        links: _orderedLinks,
        query: _searchQuery,
        displayProfile: widget.displayProfile,
        includeSnippets: widget.externalSearchSnippetsNotifier != null,
      ),
    );
  }

  void _applySearchState(CommentarySearchState state) {
    if (!mounted) return;
    setState(() {
      _searchResultOffsets = null;
      _totalSearchResults = state.total;
      if (_currentSearchIndex >= state.total && state.total > 0) {
        _currentSearchIndex = 0;
      }
    });
    widget.externalTotalResultsNotifier?.value = state.total;
    widget.externalCurrentIndexNotifier?.value = _currentSearchIndex;
    _publishSearchSnippets();
  }

  void _publishSearchSnippets() {
    widget.externalSearchSnippetsNotifier?.value =
        _searchQuery.isEmpty || _orderedLinks.isEmpty
        ? []
        : _searchBloc.state.snippets;
  }

  void _updateSearchResultsCount(Link link, int count, int generation) {
    if (!mounted) return;
    _searchBloc.add(
      CommentarySearchReported(
        generation: generation,
        key: _getLinkKey(link),
        count: count,
      ),
    );
  }

  /// משחזר מעברי שורה בבחירה רב-שורתית לפי הטקסט המרונדר של המפרשים המוצגים.
  String? _restoreLineBreaks(String? flat) => restoreCommentaryLineBreaks(
    flat,
    orderedKeys: _orderedLinks.map(_getLinkKey),
    titlesByKey: _renderedTitleByKey,
    textsByKey: _renderedTextByKey,
  );

  bool _selectionSpansMultipleItems() {
    if (_commentarySelectionDelegate.hasCurrentFullSelection &&
        _flatItems.where((item) => item.link != null).take(2).length > 1) {
      return true;
    }
    return selectionSpansMultipleItems(_itemKeys);
  }

  String? get _currentSelectedText =>
      _commentarySelectionDelegate.hasCurrentFullSelection
      ? _fullSelectionText
      : _savedSelectedText;

  /// העתקת טקסט מעוצב (HTML) ללוח
  Future<void> _copyFormattedText() => _copySelection(context, null);

  /// הגבלת ההעתקה של הבחירה: בחירה החוצה כמה מפרשים (או "בחר הכול") כפופה
  /// להגבלה המחמירה של המפרשים שבה.
  Future<CommentaryCopyGuard> _selectionCopyGuard(
    List<Link> selectedLinks,
  ) {
    final selectAll = _commentarySelectionDelegate.hasCurrentFullSelection;
    return buildCommentaryCopyGuard(
      selectAll ? _orderedLinks : selectedLinks,
      selectAll: selectAll,
      selectionOf: (link) => CommentarySelectionTracker.selectionIn(
        _itemKeys[_getLinkKey(link)]!,
      ),
      renderSettings: RenderSettings.fromProfile(widget.displayProfile),
    );
  }

  Future<void> _copySelection(
    BuildContext menuContext,
    Link? fallbackLink, {
    bool removeNikud = false,
  }) async {
    final spansItems = _selectionSpansMultipleItems();
    final selectedLinks = selectedItemLinks(
      _itemKeys,
      _orderedLinks,
      _getLinkKey,
    );
    final guard = await _selectionCopyGuard(selectedLinks);
    if (!menuContext.mounted) return;
    await ContextMenuUtils.copyFormattedText(
      context: menuContext,
      savedSelectedText: _restoreLineBreaks(_currentSelectedText),
      fontSize: widget.fontSize,
      link: spansItems
          ? null
          : _lastSelectedLink ??
                fallbackLink ??
                (selectedLinks.length == 1 ? selectedLinks.single : null),
      removeNikud: removeNikud,
      protection: guard.protection,
      segmentCount: guard.segmentCount,
    );
  }

  /// פותח את יעד הקישור בכרטיסייה חדשה (טקסט או PDF, לפי תבנית הפתיחה).
  Future<void> _navigateToLink(Link link) async {
    final tab = await buildLinkTargetTab(link);
    if (!mounted) return;
    widget.openBookCallback(tab);
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
      displayProfile: widget.displayProfile,
      copyDisplayProfile: widget.copyDisplayProfile,
      savedSelectedText: _currentSelectedText,
      onNavigateToLink: _navigateToLink,
      onCopySelected: () => _copySelection(menuCtx, link),
      onCopySelectedWithoutNikud: () =>
          _copySelection(menuCtx, link, removeNikud: true),
    )..addAll(_pluginEntries(menuCtx, link));
  }

  /// פריטי התוספים בהקשרי המפרש, על הספר הנקרא — ה-PDF בעמוד הנוכחי. עם
  /// סימון — על המפרש המסומן, כמו בהעתקה.
  List<AppContextMenuEntry> _pluginEntries(BuildContext menuCtx, Link link) {
    if (!hasPluginContextMenuItems) return const [];
    final tab = widget.tab;
    final text = _restoreLineBreaks(_currentSelectedText) ?? '';
    final selectedLinks = selectedItemLinks(
      _itemKeys,
      _orderedLinks,
      _getLinkKey,
    );
    final target = text.trim().isEmpty
        ? link
        : _lastSelectedLink ?? selectedLinks.firstOrNull ?? link;
    return buildCommentaryPluginMenuEntries(
      target: commentaryTargetForLink(target),
      mainBook: (
        book: tab.book,
        currentRef: pdfPageRef(tab, tab.pageNumber),
        sectionIndex: tab.pageNumber,
        pageNumber: tab.pageNumber,
      ),
      selectedText: text,
      copyGuard: () async {
        if (selectedLinks.isNotEmpty ||
            _commentarySelectionDelegate.hasCurrentFullSelection) {
          return _selectionCopyGuard(selectedLinks);
        }
        return (
          protection: await BookProtectionRepository.instance.forLink(target),
          segmentCount: countTextSegments(text),
        );
      },
      menuContext: menuCtx,
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
      scrollController: _itemScrollController,
      onNavigationStart: _cancelPendingNavigation,
      maxSpeed: 10000.0,
      curve: 10.0,
      accelerationFactor: 312.5,
      onKeyEvent: (_, event) => ContextMenuUtils.reportCommentaryErrorShortcut(
        context,
        event,
        link:
            _lastSelectedLink ??
            selectedItemLinks(
              _itemKeys,
              _orderedLinks,
              _getLinkKey,
            ).singleOrNull,
        selectedText: _currentSelectedText,
        fontSize: widget.fontSize,
      ),
      child: _wrapWithSelection(child),
    );
  }

  @override
  Widget build(BuildContext context) {
    _searchResultOffsets = null;
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
            PanelTab(icon: OtzariaIcons.book_24_regular, label: 'מפרשים'),
            PanelTab(icon: OtzariaIcons.links_24_regular, label: 'קישורים'),
            PanelTab(icon: FluentIcons.note_24_regular, label: 'הערות'),
          ],
        ),
        // כל לשונית עוטפת את עצמה ב-SelectionArea; המפרשים בנוסף ב-
        // ProgressiveScroll (מעל ה-SelectionArea) כדי שגלילת החיצים תעבוד.
        Expanded(
          child: TabBarView(
            controller: _tabController,
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

  Widget _buildCommentatorsFilter() {
    final visibleContent = _getVisibleContent();
    final availableTitles = {
      for (final group in _commentatorGroups) ...group.commentators,
    };
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
        selectedCommentators: widget.tab.activeCommentators
            .where(availableTitles.contains)
            .toList(),
        bookTitle: widget.tab.book.title,
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
        heCategories: bookCategoriesSource(widget.tab.book),
        onCategoryDefaultsSaved: () =>
            PdfBookPerBookSettings.clearActiveCommentators(widget.tab.book),
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
    // גובה 36 כשדה החיפוש המצומצם, כדי שפתיחת החיפוש לא תזיז את הרשימה.
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: (Theme.of(context).iconButtonTheme.style ?? const ButtonStyle())
            .copyWith(
              visualDensity:
                  Theme.of(context).extension<AppMenuMetrics>()?.compactMenus ==
                      true
                  ? const VisualDensity(vertical: -1)
                  : null,
            ),
      ),
      child: Row(
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
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            iconSize: 20,
          ),
          // 2. הרחב/כווץ הכל — רק כשיש מפרשים פעילים
          if (widget.tab.activeCommentators.isNotEmpty) ...[
            const SizedBox(width: gap),
            IconButton(
              icon: Icon(
                _allExpanded
                    ? FluentIcons.arrow_collapse_all_24_regular
                    : FluentIcons.arrow_expand_all_24_regular,
              ),
              tooltip: _allExpanded
                  ? 'כווץ את כל המפרשים'
                  : 'הרחב את כל המפרשים',
              onPressed: toggleAllExpanded,
            ),
          ],
          const SizedBox(width: gap),
          // 3. פתיחה בכרטיסייה חדשה
          IconButton(
            icon: const Icon(FluentIcons.open_24_regular),
            tooltip: 'פתח כרטסיית מפרשים',
            onPressed: () => context.read<TabsBloc>().add(
              AddTab(PdfCommentatorsTab.of(widget.tab), insertAdjacent: true),
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
      ),
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
    final blocks = await buildCommentaryPrintBlocks(groups, keepHtml: true);
    if (blocks.isEmpty) {
      UiSnack.show(PdfMessages.noCommentariesToPrint);
      return;
    }
    final protection = await BookProtectionRepository.instance
        .strictestForLinks(groups.expand((group) => group.links));
    if (!mounted) return;

    final bookTitle = widget.tab.book.title;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Future.value(''),
        bookId: bookTitle,
        documentTitle: bookTitle,
        prebuiltBlocks: blocks,
        protection: protection,
        activeCommentators: groups
            .map((group) => group.bookTitle)
            .toList(growable: false),
        removeNikud: widget.displayProfile.removeNikud,
        removeTaamim: widget.displayProfile.removeTeamim,
        commentaryDisplayProfile: context
            .read<SettingsBloc>()
            .state
            .textDisplayPolicy
            .resolve(
              TextDisplaySlot.commentaryDisplay.copyWith(
                channel: TextChannel.export,
              ),
            ),
      ),
    );
  }

  Widget _buildSearchFieldRow() {
    return OtzariaSearchField(
      focusNode: _searchFocusNode,
      controller: _searchController,
      hintText: 'חפש בתוך המפרשים המוצגים...',
      icon: OtzariaIcons.search_in_library_24_regular,
      // Enter moves to the next match and keeps focus in the field; selecting
      // all on focus would erase the query on the next key.
      selectAllOnFocus: false,
      trailingActions: [
        if (_searchQuery.isNotEmpty && _totalSearchResults > 1) ...[
          if (_currentSearchIndex >= 0)
            OtzariaSearchAction.resultCounter(
              current: _currentSearchIndex + 1,
              total: _totalSearchResults,
              context: context,
            ),
          OtzariaSearchAction.prevResult(
            onPressed: _currentSearchIndex > 0 ? navigateSearchPrev : null,
          ),
          OtzariaSearchAction.nextResult(
            onPressed: _currentSearchIndex < _totalSearchResults - 1
                ? navigateSearchNext
                : null,
          ),
        ],
        OtzariaSearchAction.icon(
          iconData: FluentIcons.dismiss_24_regular,
          tooltip: 'סגור חיפוש',
          onPressed: _clearSearchAndCloseField,
        ),
      ],
      onChanged: (value) {
        _cancelSearchScroll();
        setState(() {
          _searchQuery = value;
          // No current match until the first Enter, so it lands on the first.
          _currentSearchIndex = -1;
          if (value.isEmpty) {
            _totalSearchResults = 0;
          }
        });
        _scheduleSearchCompute();
      },
      onSubmitted: (_) {
        navigateSearchNext();
        _searchFocusNode.requestFocus();
      },
    );
  }

  Widget _buildCommentariesView() {
    if (_showFilterTab) {
      _cancelSearchScroll();
      return _buildCommentatorsFilter();
    }

    return Column(
      children: [
        // במצב fullscreen עם חיפוש חיצוני, מסתיר שורת חיפוש פנימית
        if (widget.externalSearchController == null) _buildSearchBar(),
        Expanded(child: _buildCommentariesListContent()),
      ],
    );
  }

  void _invalidateFullSelection() {
    _fullSelectionScope = null;
    _fullSelectionLines = null;
    _savedSelectedText = null;
  }

  void _prepareFullSelection(
    List<CommentaryGroup> groups,
    List<CommentaryFlatItem> items,
    SettingsState settings,
  ) {
    final scope = (
      groups,
      widget.displayProfile,
      settings.replaceHolyNames,
      settings.holyNameStyle,
      _allExpanded,
      items,
    );
    if (_fullSelectionScope == scope) return;
    _fullSelectionScope = scope;
    _fullSelectionLines = null;
    _savedSelectedText = null;
    final renderSettings = RenderSettings.fromProfile(widget.displayProfile);
    _fullSelectionLines = items.map((item) {
      final link = item.link;
      if (link == null) {
        return () => _pdfCommentaryTitle(item.group.bookTitle, settings);
      }
      var title = link.fallbackDisplayReference;
      unawaited(link.displayReference.then((value) => title = value));
      final isRashi =
          LinkTypes.isDependentTextLink(link.connectionType) &&
          isRashiTitle(utils.getTitleFromPath(link.path2));
      final dictionary = DictionaryLookupRepository.instance;
      if (isRashi && !dictionary.areLaazLinksLoaded) {
        unawaited(dictionary.ensureLaazLinksLoaded().catchError((_) {}));
      }
      final loaded = link.loadedContent;
      String? content = loaded == null
          ? null
          : renderSelectionLine(rawText: loaded, settings: renderSettings);
      unawaited(
        link.content.then(
          (data) {
            content = renderSelectionLine(
              rawText: data,
              settings: renderSettings,
            );
          },
          onError: (Object error) {
            content = 'שגיאה בטעינת הפרשן: $error';
          },
        ),
      );
      return () {
        if (content == null) return null;
        final laaz = isRashi && dictionary.areLaazLinksLoaded
            ? dictionary
                  .laazForRashiLine(
                    rashiBookTitle: utils.getTitleFromPath(link.path2),
                    rashiLineIndex: link.index2,
                  )
                  .map(
                    (entry) =>
                        laazCommentaryEntrySpan(entry: entry).toPlainText(),
                  )
            : const <String>[];
        return [
          _pdfCommentaryLinkTitle(link, title, settings),
          content,
          ...laaz,
        ].join('\n');
      };
    }).toList();
  }

  Widget _buildCommentariesListContent() {
    final visibleContent = _getVisibleContent();
    if (visibleContent == null) {
      _invalidateFullSelection();
      _cancelSearchScroll();
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
      _orderedLinks = [];
      _scheduleSearchCompute();
      _invalidateFullSelection();
      _cancelSearchScroll();
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
        child: OtzariaEmptyState(
          isCompact: true,
          icon: OtzariaIcons.links_24_regular,
          title: hasCommentaryLinks
              ? 'לא נמצאו מפרשים מהנבחרים לדף זה'
              : 'לא נמצאו מפרשים לקטע הנבחר',
          action: hasCommentaryLinks
              ? ActionButton.recommended(
                  onPressed: () {
                    if (widget.enableInternalFilter) {
                      setState(() {
                        _showFilterTab = true;
                      });
                    } else {
                      widget.onSelectCommentatorsRequested?.call();
                    }
                  },
                  icon: OtzariaIcons.apps_list_24_regular,
                  text: 'בחר מפרשים',
                )
              : null,
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
        if (currentGroups == null) {
          _invalidateFullSelection();
          _cancelSearchScroll();
        }
        final sortedGroups = currentGroups ?? _lastResolvedGroups;
        if (sortedGroups == null) {
          return const Center(child: CircularProgressIndicator());
        }
        for (final group in sortedGroups) {
          _expansionStates.putIfAbsent(group.bookTitle, () => _allExpanded);
        }
        final flatItems = _flatItems = _buildFlatItems(sortedGroups);
        // הבחירה המלאה תלויה רק בהגדרות שמות הקודש.
        context.select(
          (SettingsBloc bloc) =>
              (bloc.state.replaceHolyNames, bloc.state.holyNameStyle),
        );
        if (currentGroups != null) {
          _prepareFullSelection(
            currentGroups,
            flatItems,
            context.read<SettingsBloc>().state,
          );
          _lastResolvedGroups = currentGroups;
          if (!identical(currentGroups, _orderedGroups) ||
              _orderedLinks.isEmpty) {
            _orderedGroups = currentGroups;
            _orderedLinks = [for (final group in currentGroups) ...group.links];
          }
        }

        _scheduleSearchCompute();
        _syncItemKeys();

        return SelectionContainer(
          delegate: _commentarySelectionDelegate,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Visibility(
                visible: currentGroups != null,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: ScrollablePositionedListScrollbar(
                  scrollController: _itemScrollController,
                  itemCount: flatItems.length,
                  onNavigationStart: _cancelPendingNavigation,
                  labelForIndex: (index) =>
                      index >= 0 && index < flatItems.length
                      ? flatItems[index].group.bookTitle
                      : '',
                  child: constrainToContentWidth(
                    _trackHeaderScroll(
                      ScrollablePositionedList.builder(
                        key: PageStorageKey(
                          pdfCommentaryListStorageKey(
                            widget.tab.activeCommentators,
                          ),
                        ),
                        restorePosition: true,
                        itemCount: flatItems.length,
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        listController: _listController,
                        findChildIndexCallback: (key) => _flatIndexByKey[key],
                        itemBuilder: (context, index) =>
                            _buildFlatItem(flatItems[index]),
                      ),
                    ),
                    widget.contentMaxWidth,
                  ),
                ),
              ),
              if (currentGroups == null)
                ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  /// הפריטים השטוחים של [groups] לפי מצב הכיווץ, ומיפויי האינדקסים שלהם.
  /// נבנים מחדש רק כשהקבוצות או הכיווץ משתנים, לא בכל הקשה בחיפוש.
  List<CommentaryFlatItem> _buildFlatItems(List<CommentaryGroup> groups) {
    final snapshot = _flatSnapshot;
    if (snapshot != null &&
        identical(snapshot.groups, groups) &&
        groups.every(
          (group) =>
              snapshot.expansion[group.bookTitle] ==
              (_expansionStates[group.bookTitle] ?? _allExpanded),
        )) {
      return snapshot.items;
    }
    final linkFlatIndex = <String, int>{};
    final items = buildCommentaryFlatItems(
      groups: groups,
      isGroupExpanded: (title) => _expansionStates[title] ?? _allExpanded,
      linkKey: _getLinkKey,
      headerIndexOut: <String, int>{},
      linkIndexOut: linkFlatIndex,
    );
    _linkFlatIndex = linkFlatIndex;
    _flatIndexByKey = {
      for (var index = 0; index < items.length; index++)
        _flatItemKey(items[index]): index,
    };
    final titles = groups.map((group) => group.bookTitle).toSet();
    _headerKeys.removeWhere((title, _) => !titles.contains(title));
    _flatSnapshot = (
      groups: groups,
      expansion: {
        for (final group in groups)
          group.bookTitle: _expansionStates[group.bookTitle] ?? _allExpanded,
      },
      items: items,
    );
    return items;
  }

  /// [_orderedLinks] שלפיו עודכנו מפתחות הפריטים.
  List<Link>? _keyedLinks;

  void _syncItemKeys() {
    if (identical(_keyedLinks, _orderedLinks)) return;
    _keyedLinks = _orderedLinks;
    final currentLinkKeys = _orderedLinks.map(_getLinkKey).toSet();
    _itemKeys.removeWhere((key, _) => !currentLinkKeys.contains(key));
    for (final key in currentLinkKeys) {
      _itemKeys.putIfAbsent(key, GlobalKey.new);
    }
    _renderedTextByKey.removeWhere((key, _) => !currentLinkKeys.contains(key));
  }

  Future<void> _scrollToSearchResult() async {
    _cancelSearchScroll();
    final generation = _searchScrollGeneration;
    if (_totalSearchResults == 0 || _orderedLinks.isEmpty) return;
    var cumulativeIndex = 0;
    Link? targetLink;
    for (final link in _orderedLinks) {
      final count = _searchResultsPerLink[_getLinkKey(link)] ?? 0;
      if (_currentSearchIndex < cumulativeIndex + count) {
        targetLink = link;
        break;
      }
      cumulativeIndex += count;
    }
    if (targetLink == null) return;
    final linkKey = _getLinkKey(targetLink);
    final group = _orderedGroups
        .where(
          (group) => group.links.any((link) => _getLinkKey(link) == linkKey),
        )
        .firstOrNull;
    if (group == null) return;
    if (!(_expansionStates[group.bookTitle] ?? _allExpanded)) {
      setState(() => _expansionStates[group.bookTitle] = true);
    }
    WidgetsBinding.instance.ensureVisualUpdate();
    await WidgetsBinding.instance.endOfFrame;
    while (mounted && generation == _searchScrollGeneration) {
      final index = _linkFlatIndex[linkKey];
      if (index == null || !_itemScrollController.isAttached) return;
      await _itemScrollController.jumpToAsync(index: index, alignment: 0.1);
      if (_linkFlatIndex[linkKey] == index) return;
    }
  }

  void _cancelSearchScroll() {
    _searchScrollGeneration++;
    _listController.cancelPositioning();
  }

  Key _flatItemKey(CommentaryFlatItem item) => item.link == null
      ? ValueKey('h:${item.group.bookTitle}')
      : ValueKey('l:${_getLinkKey(item.link!)}');

  bool _preserveGroupHeader(String? title) {
    final render = _headerKeys[title]?.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport is! RenderBox) return false;
    final viewportBox = viewport as RenderBox;
    final top = render.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    if (top + render.size.height <= 0 || top >= viewportBox.size.height) {
      return false;
    }
    final scroll = _itemScrollController.scrollController;
    if (scroll != null &&
        scroll.hasClients &&
        scroll.position.isScrollingNotifier.value) {
      scroll.jumpTo(scroll.offset);
    }
    final handle = _listController.preserveHeader(render);
    if (handle == null) return false;
    _headerAnchor = handle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      handle.cancel();
      if (identical(_headerAnchor, handle)) _headerAnchor = null;
    });
    return true;
  }

  void _cancelHeaderAnchor() {
    _headerAnchor?.cancel();
    _headerAnchor = null;
  }

  void _cancelPendingNavigation() {
    _cancelHeaderAnchor();
    _cancelSearchScroll();
  }

  Widget _trackHeaderScroll(Widget child) => Listener(
    onPointerDown: (_) => _cancelPendingNavigation(),
    onPointerSignal: (_) => _cancelPendingNavigation(),
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _cancelHeaderAnchor();
        return false;
      },
      child: child,
    ),
  );

  Widget _buildFlatItem(CommentaryFlatItem item) {
    final group = item.group;
    final link = item.link;
    return BlocBuilder<SettingsBloc, SettingsState>(
      key: _flatItemKey(item),
      builder: (context, settingsState) {
        final Widget child;
        if (link == null) {
          final groupKey = group.bookTitle;
          final isExpanded = _expansionStates[groupKey] ?? _allExpanded;
          child = _PdfCommentaryGroupHeader(
            key: _headerKeys.putIfAbsent(groupKey, GlobalKey.new),
            bookTitle: groupKey,
            settingsState: settingsState,
            isExpanded: isExpanded,
            onTap: () {
              if (isExpanded) _preserveGroupHeader(groupKey);
              setState(() => _expansionStates[groupKey] = !isExpanded);
            },
          );
        } else {
          final generation = _searchBloc.generation;
          child = _PdfCommentaryLinkItem(
            link: link,
            settingsState: settingsState,
            fontSize: widget.fontSize,
            openBookCallback: widget.openBookCallback,
            buildContextMenu: _buildCommentaryContextMenuEntries,
            getSavedSelectedText: () => _currentSelectedText,
            searchQuery: _searchQuery,
            onSearchResultsCountUpdate: (link, count) =>
                _updateSearchResultsCount(link, count, generation),
            getKeyForLink: _getLinkKeyObject,
            getItemSearchIndex: _getItemSearchIndex,
            displayProfile: widget.displayProfile,
            onLinkRendered: (link, text) =>
                _renderedTextByKey[_getLinkKey(link)] = text,
            onLinkTitleRendered: (link, title) =>
                _renderedTitleByKey[_getLinkKey(link)] = title
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim(),
            onLinkPointerDown: (link) => _lastSelectedLink = link,
          );
        }
        if (!item.showDivider) return child;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [child, const Divider(height: 1)],
        );
      },
    );
  }

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
    return ValueListenableBuilder<Set<String>>(
      valueListenable: _selectedLinkTypes,
      builder: (context, selectedLinkTypes, _) => LinksListView(
        links: relevantLinks,
        chipSourceLinks: widget.tab.links,
        openBookTitle: widget.tab.book.title,
        selectedLinkTypes: selectedLinkTypes,
        onSelectedLinkTypesChanged: (types) => _selectedLinkTypes.value = types,
        openBookCallback: widget.openBookCallback,
        fontSize: widget.fontSize,
        displayProfile: widget.displayProfile,
        copyDisplayProfile: widget.copyDisplayProfile,
        contentScopeKey: _currentLinksScopeKey(),
        emptyMessage: 'לא נמצאו קישורים לדף זה',
      ),
    );
  }

  Widget _buildNotesView() {
    final bookId = personalNotesBookKey(widget.tab.book);

    return PersonalNotesSidebar(
      key: ValueKey(bookId),
      bookId: bookId,
      categoryId: widget.tab.book.categoryId,
      isPdf: true,
      pdfOutline: widget.tab.outline,
      visibleLineIndices: _getVisibleLineIndicesForCurrentPage(),
      onNavigateToLine: (lineNumber, {note}) {
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
    final visibility = _visibility;
    if (visibility == null) return null;
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
    final visibleLinks = _visibleLinksCache.forSource(
      widget.tab.links,
      visibility,
    );
    for (final link in visibleLinks) {
      if (!pdfLinkInVisibleScope(
        link.index1,
        range.startLine,
        range.endLine,
        extraLines,
        linkIndex1End: link.index1End,
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
        links: visibleLinks,
        startLine: range.startLine,
        endLine: range.endLine,
        extraLineIndices: extraLines,
        activeCommentators: widget.tab.activeCommentators,
        showAllWhenEmpty: showAllWhenEmpty,
      ),
    );

    // הצ׳יפים נגזרים מכל הקישורים הטעונים ולא מהעמוד הנוכחי: צ׳יפ שנגזר
    // מהעמוד נעלם בדפדוף לעמוד שאין בו אותו סוג, והסינון נכבה בשקט.
    final typeChipKeys = showAllWhenEmpty
        ? CommentaryTypeFilter.chipKeys(visibleLinks)
        : CommentaryTypeFilter.chipKeysForCommentators(
            links: visibleLinks,
            selectedCommentators: widget.tab.activeCommentators.toList(
              growable: false,
            ),
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

    commentaryLinks.sort(comparePdfCommentaryLinks);
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
      commentatorsByType: CommentaryTypeFilter.commentatorsByType(visibleLinks),
      // אסינכרוני: קיבוץ סינכרוני על ה-UI thread קפא בדפי גמרא עם מפרשים רבים.
      sortedGroupsFuture:
          (widget.commentaryGroupsLoader ??
                  CommentaryService.groupAndSortLinks)(commentaryLinks)
              .then(
                (groups) => orderPdfCommentaryGroups(groups, [
                  for (final g in _commentatorGroups) ...g.commentators,
                ]),
              ),
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
/// The header of a commentator group: tapping it expands or collapses the
/// group.
class _PdfCommentaryGroupHeader extends StatelessWidget {
  final String bookTitle;
  final SettingsState settingsState;
  final bool isExpanded;
  final VoidCallback onTap;

  const _PdfCommentaryGroupHeader({
    super.key,
    required this.bookTitle,
    required this.settingsState,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? -0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: RtlIcon(
                FluentIcons.chevron_left_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _pdfCommentaryTitle(bookTitle, settingsState),
                style: TextStyle(
                  fontSize: settingsState.commentatorsFontSize - 2,
                  fontWeight: FontWeight.bold,
                  fontVariations: AppFonts.boldFontVariations(
                    settingsState.commentatorsFontFamily,
                  ),
                  fontFamily: AppFonts.renderFontFamily(
                    settingsState.commentatorsFontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One commentary of a group: its reference title and its content.
class _PdfCommentaryLinkItem extends StatelessWidget {
  final Link link;
  final SettingsState settingsState;
  final double fontSize;
  final Function(OpenedTab) openBookCallback;
  final List<AppContextMenuEntry> Function(BuildContext, Link) buildContextMenu;
  final String? Function() getSavedSelectedText;
  final String searchQuery;
  final Function(Link, int)? onSearchResultsCountUpdate;
  final Key? Function(Link)? getKeyForLink;
  final int Function(Link)? getItemSearchIndex;
  final TextDisplayProfile displayProfile;
  final void Function(Link link, String renderedPlainText)? onLinkRendered;
  final void Function(Link link, String renderedTitle)? onLinkTitleRendered;
  final void Function(Link link)? onLinkPointerDown;

  const _PdfCommentaryLinkItem({
    required this.link,
    required this.settingsState,
    required this.fontSize,
    required this.openBookCallback,
    required this.buildContextMenu,
    required this.getSavedSelectedText,
    required this.searchQuery,
    this.onSearchResultsCountUpdate,
    this.getKeyForLink,
    this.getItemSearchIndex,
    this.displayProfile = TextDisplayProfile.defaults,
    this.onLinkRendered,
    this.onLinkTitleRendered,
    this.onLinkPointerDown,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      // מזהה על איזה מפרש לחץ המשתמש — ל-SelectionArea היחיד אין מידע
      // כזה, והוא נדרש לייחוס כותרת המקור בהעתקת מקלדת.
      onPointerDown: (_) => onLinkPointerDown?.call(link),
      child: Padding(
        key: getKeyForLink?.call(link), // Attach the key here for scrolling
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
                final displayTitle = _pdfCommentaryLinkTitle(
                  link,
                  snapshot.data ?? link.fallbackDisplayReference,
                  settingsState,
                );
                final reportedTitle = displayTitle;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onLinkTitleRendered?.call(link, reportedTitle);
                });
                return Text(
                  displayTitle,
                  style: TextStyle(
                    fontSize: settingsState.commentatorsFontSize - 4,
                    fontWeight: FontWeight.normal,
                    fontFamily: AppFonts.renderFontFamily(
                      settingsState.commentatorsFontFamily,
                    ),
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            AppContextMenuRegion(
              // ריחוף מקדים את טעינת קישורי קטע היעד, כדי שהתפריט
              // ייבנה עם נתונים מוכנים. הלחיצה מכסה מגע/עט (אין ריחוף).
              onHoverEnter: () =>
                  TargetLineLinksService.instance.prefetchOnHover(link),
              onSecondaryTapDown: (_) =>
                  TargetLineLinksService.instance.prefetch(link),
              // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה
              // (התנהגות ברירת המחדל של SelectableRegion ב-Windows); לחיצה
              // על חלק לא-מסומן מבטלת כרגיל. הבחירה מנוהלת ע"י SelectionArea
              // יחיד, לכן מחשבים את קטע הבחירה ישירות מול הפסקה שעליה לחצו.
              shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                final selected = getSavedSelectedText();
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
              menuBuilder: (menuCtx, _) => buildContextMenu(menuCtx, link),
              child: CommentaryContent(
                key: ValueKey(commentaryLinkKey(link)),
                link: link,
                fontSize: fontSize,
                openBookCallback: openBookCallback,
                searchQuery: searchQuery,
                onSearchResultsCountChanged: (count) {
                  onSearchResultsCountUpdate?.call(link, count);
                },
                currentSearchIndex: getItemSearchIndex?.call(link) ?? -1,
                displayProfile: displayProfile,
                onRendered: (text) => onLinkRendered?.call(link, text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _pdfCommentaryTitle(String title, SettingsState settings) =>
    settings.replaceHolyNames
    ? utils.replaceHolyNames(title, style: settings.holyNameStyle)
    : title;

String _pdfCommentaryLinkTitle(
  Link link,
  String title,
  SettingsState settings,
) {
  final marker = link.anchorStart == null ? null : anchorMarkerText(link);
  return _pdfCommentaryTitle(
    marker == null ? title : '$marker $title',
    settings,
  );
}

// הבחירה המלאה כוללת גם קטעים שלא נבנו; בחירה חלקית נשארת בידי Flutter.
class _PdfCommentarySelectionDelegate extends StaticSelectionContainerDelegate {
  _PdfCommentarySelectionDelegate({
    required this.scope,
    required this.fullText,
  });

  final Object? Function() scope;
  final String? Function() fullText;
  Object? _selectedScope;
  bool _selectAll = false;

  bool get hasCurrentFullSelection =>
      _selectAll && _selectedScope != null && _selectedScope == scope();

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    _selectAll = event.type == SelectionEventType.selectAll;
    _selectedScope = scope();
    return super.dispatchSelectionEvent(event);
  }

  @override
  SelectionGeometry getSelectionGeometry() {
    final geometry = super.getSelectionGeometry();
    if (!hasCurrentFullSelection) return geometry;
    // קצות הבחירה המלאה יכולים להיות מחוץ למסך גם כשאין שורה נבחרת בנויה.
    return SelectionGeometry(
      startSelectionPoint: geometry.startSelectionPoint,
      endSelectionPoint: geometry.endSelectionPoint,
      selectionRects: geometry.selectionRects,
      status: SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  @override
  SelectedContent? getSelectedContent() {
    if (!_selectAll) return super.getSelectedContent();
    final text = hasCurrentFullSelection ? fullText() : null;
    return text == null ? null : SelectedContent(plainText: text);
  }

  @override
  void ensureChildUpdated(Selectable selectable) {
    if (hasCurrentFullSelection) {
      selectable.dispatchSelectionEvent(const SelectAllSelectionEvent());
    } else {
      super.ensureChildUpdated(selectable);
    }
  }
}
