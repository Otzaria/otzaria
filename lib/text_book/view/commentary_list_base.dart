import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/text_book/view/combined_view/commentary_content.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentary_search_utils.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/layout/commentators_filter_screen.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    as inline_notes;
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/printing/view/printing_screen.dart';

// Type alias לתאימות לאחור - משתמש ב-LinkGroup מה-Service
typedef CommentaryGroup = LinkGroup;

/// האם לחיצת ה-pointer צריכה למקד את אזור הגלילה (ProgressiveScroll).
/// לחיצה שכוללת כפתור ימני מוחרגת: מיקוד ה-ProgressiveScroll (אב ל-SelectionArea)
/// גוזל פוקוס מ-SelectableRegion ומוחק את ההדגשה בזמן פתיחת תפריט ההקשר.
/// [buttons] הוא bitmask, ולכן בודקים את הביט הימני ולא שוויון מלא.
bool shouldFocusScrollOnPointerDown(int buttons) =>
    (buttons & kSecondaryButton) == 0;

/// לוכד snapshot של הטקסט הנבחר לשימוש בפעולת ההעתקה של תפריט ההקשר.
/// נדרש כי לחיצה ימנית עלולה לשחרר את הבחירה (onSelectionChanged(null)) לפני
/// שהמשתמש בוחר "העתק" — קריאה חיה מהנוטיפייר באותו רגע הייתה מחזירה null.
String? captureSelectedTextForMenu(ValueListenable<String?> saved) =>
    saved.value;

/// מייצג תוצאת חיפוש בודדת עם קטע טקסט וכתובת גלובלית לניווט
class CommentarySearchSnippet {
  final String path;
  final String snippet;
  final int globalIndex;

  const CommentarySearchSnippet({
    required this.path,
    required this.snippet,
    required this.globalIndex,
  });
}

class CommentaryListBase extends StatefulWidget {
  final Function(TextBookTab) openBookCallback;
  final double fontSize;
  final List<int>? indexes;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final bool shrinkWrap;
  final ItemPositionsListener? itemPositionsListener;
  final List<String>? selectedCommentatorsOverride;
  final List<CommentatorGroup>? commentatorGroupsOverride;
  final String? bookTitleOverride;
  final ValueChanged<List<String>>? onSelectedCommentatorsOverrideChanged;
  final SelectionSyncController? selectionSyncController;
  final ValueListenable<int>? openFilterRequest;
  final ValueNotifier<int>? openFilterNotifier;
  final ValueNotifier<int>? closeFilterNotifier;
  // כאשר מסופק, CommentaryListBase ישתמש בו לחיפוש ולא יציג שורת חיפוש פנימית
  final TextEditingController? externalSearchController;
  final ValueNotifier<int>? externalCurrentIndexNotifier;
  final ValueNotifier<int>? externalTotalResultsNotifier;

  /// מפה חיצונית: path של מפרש → מספר תוצאות חיפוש בו (ריק אם אין חיפוש)
  final ValueNotifier<Map<String, int>>? externalSearchResultsByPathNotifier;

  /// רשימת קטעי חיפוש חיצונית עם מידע לניווט (ריקה אם אין חיפוש)
  final ValueNotifier<List<CommentarySearchSnippet>>?
      externalSearchSnippetsNotifier;

  /// כשהדגל מופעל, ישתמש ב-availableCommentators (כל מפרשי הספר) ולא ב-activeCommentators
  final bool useAvailableCommentators;

  /// קולבק לפתיחת המפרשים בכרטיסייה חדשה. כש-null הלחצן לא יוצג.
  final VoidCallback? onOpenInNewTab;

  /// נוטיפייר חיצוני שמשתקף ממצב הכיווץ הגלובלי. שימוש: הורה רוצה להציג
  /// מחוץ לפאנל כפתור כווץ/הרחב מסונכרן.
  final ValueNotifier<bool>? externalAllExpandedNotifier;

  /// אם סופק, יקרא במקום פתיחת חלון בחירת המפרשים הפנימי (פופ-אפ).
  /// מאפשר להורה (למשל CommentatorsTabScreen) להפנות בחירת מפרשים ללשונית
  /// בסרגל הצד במקום פופ-אפ.
  final VoidCallback? onFilterOpenRequested;

  /// כשאמת, חלונית המפרשים תתפוס פוקוס אוטומטית כשהיא נטענת (לכרטיסיית
  /// המפרשים העצמאית, לא לתצוגה בתוך הספר שבה הפוקוס שייך לגוף הטקסט).
  final bool autofocus;

  /// מדגיש מחרוזת חיפוש חיצונית בלי להציג את ממשק החיפוש הפנימי.
  /// מיועד לתצוגה המשולבת, שבה החיפוש מנוהל ע"י ה-BLoC של הטקסט הראשי.
  final ValueListenable<String>? highlightQueryListenable;

  const CommentaryListBase({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.indexes,
    required this.showSearch,
    this.onClosePane,
    this.shrinkWrap = true,
    this.itemPositionsListener,
    this.selectedCommentatorsOverride,
    this.commentatorGroupsOverride,
    this.bookTitleOverride,
    this.onSelectedCommentatorsOverrideChanged,
    this.selectionSyncController,
    this.openFilterRequest,
    this.openFilterNotifier,
    this.closeFilterNotifier,
    this.externalSearchController,
    this.externalCurrentIndexNotifier,
    this.externalTotalResultsNotifier,
    this.externalSearchResultsByPathNotifier,
    this.externalSearchSnippetsNotifier,
    this.useAvailableCommentators = false,
    this.onOpenInNewTab,
    this.externalAllExpandedNotifier,
    this.onFilterOpenRequested,
    this.autofocus = false,
    this.highlightQueryListenable,
  });

  @override
  State<CommentaryListBase> createState() => CommentaryListBaseState();
}

class CommentaryListBaseState extends State<CommentaryListBase> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
  final ScrollOffsetController scrollController = ScrollOffsetController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, GlobalKey> _itemKeys = {};
  // טקסט פשוט מרונדר לכל מפרש מוצג — לשחזור מעברי שורה בהעתקה רב-שורתית.
  final Map<String, String> _renderedTextByKey = {};
  // כותרת מרונדרת (displayReference) לכל מפרש מוצג — לשחזור מעברי שורה כשהבחירה
  // כוללת גם כותרות.
  final Map<String, String> _renderedTitleByKey = {};
  final ValueNotifier<int> _currentSearchIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _totalSearchResultsNotifier = ValueNotifier<int>(0);
  final Map<String, int> _searchResultsPerLink = {};
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון
  // מצב גלובלי של פתיחה/סגירה של כל המפרשים — חשוף ככ-ValueListenable כדי
  // שצרכנים חיצוניים (למשל CommentatorsTabScreen) יוכלו להאזין ולעדכן UI.
  final ValueNotifier<bool> _allExpandedNotifier = ValueNotifier<bool>(true);
  bool get _allExpanded => _allExpandedNotifier.value;
  set _allExpanded(bool value) => _allExpandedNotifier.value = value;
  final Map<String, bool> _expansionStates =
      {}; // מעקב אחרי מצב כל קבוצת מפרשים
  String? _cachedGroupingSignature;
  Future<List<CommentaryGroup>>? _cachedGroupsFuture;

  // Anti-jitter search stats
  Timer? _searchUpdateDebounce;
  final Map<String, int> _pendingCounts = {};
  // חישוב ספירות חיפוש ברקע על כל הקישורים — הרשימה וירטואלית ופריטים שלא
  // נבנו אינם מדווחים, לכן אסור להסתמך על ה-widgets לספירה.
  Timer? _searchComputeDebounce;
  int _searchComputeGen = 0;
  int _lastLinksSignature = 0;
  // מפה: link key → path2 (לצורך קיבוץ תוצאות לפי מפרש)
  final Map<String, String> _linkKeyToPath = {};
  // מפה: link key → קטעי טקסט (snippets) לתוצאות החיפוש
  final Map<String, List<String>> _searchSnippetsPerLink = {};

  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null); // טקסט נבחר לתפריט הקשר
  final ValueNotifier<Link?> _lastSelectedLink =
      ValueNotifier<Link?>(null); // ה-link האחרון שנוגעו בו (לכותרות בהעתקה)
  final Object _selectionOwner = Object(); // מזהה ייחודי לבעלות על הבחירה
  int _selectionRevision = 0; // גרסה לאיפוס SelectionArea כשבחירה חיצונית מנקה
  bool _showCommentatorsFilter = false; // האם להציג את מסך בחירת המפרשים
  bool _filterWasAutoOpened = false; // האם מסך הסינון נפתח אוטומטית (לא ידנית)
  // latch חד-פעמי: מסמן שהפתיחה האוטומטית דרך onFilterOpenRequested כבר נשלחה.
  // בלעדיו הקולבק היה נקרא בכל rebuild שבו עדיין אין מפרשים נבחרים (כי המסלול
  // הזה אינו משנה את _showCommentatorsFilter), מה שמציף את ההורה ב-side effect
  // ועלול ליצור לולאת rebuild. מתאפס כשהבחירה אינה ריקה — כדי שריקון עתידי
  // יפתח שוב את הבחירה.
  bool _autoFilterOpenNotified = false;
  bool _userInteractedWithFilter =
      false; // האם המשתמש בחר בעצמו בתוך פאנל הסינון
  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  int _lastSeenFilterRequest = 0;
  bool _snippetsRebuildScheduled = false;
  // האם להציג את שדה החיפוש (true) או את שורת ארבעת הלחצנים (false)
  bool _showSearchField = false;

  String _getLinkKey(Link link) =>
      '${link.index1}_${link.path2}_${link.index2}';

  // רשימה של כל ה-links לפי סדר הופעתם (נבנית מחדש בכל build)
  List<Link> _orderedLinks = [];

  List<String> _allSelectedCommentators(TextBookLoaded state) {
    if (widget.selectedCommentatorsOverride != null) {
      return widget.selectedCommentatorsOverride!;
    }
    if (widget.useAvailableCommentators) {
      return state.availableCommentators;
    }
    return state.activeCommentators;
  }

  List<String> _selectedCommentators(TextBookLoaded state) {
    final selected = _allSelectedCommentators(state);
    return selected.where((title) => title != kNotesCommentatorTitle).toList();
  }

  String _buildGroupingSignature(List<Link> links) {
    return links
        .map((link) =>
            '${link.index1}|${link.path2}|${link.index2}|${link.connectionType}')
        .join('||');
  }

  Future<List<CommentaryGroup>> _getCachedGroups(List<Link> links) {
    final signature = _buildGroupingSignature(links);
    if (_cachedGroupingSignature == signature && _cachedGroupsFuture != null) {
      return _cachedGroupsFuture!;
    }

    _cachedGroupingSignature = signature;
    _cachedGroupsFuture = CommentaryService.groupConsecutiveLinksAsync(links);
    return _cachedGroupsFuture!;
  }

  List<CommentatorGroup> _commentatorGroups(TextBookLoaded state) {
    return widget.commentatorGroupsOverride ?? state.commentatorGroups;
  }

  String _bookTitle(TextBookLoaded state) {
    return widget.bookTitleOverride ?? state.book.title;
  }

  /// אינדקסי השורות הנוכחיים (בחירה מרובה אם יש, אחרת הנראות) — לקביעת אילו
  /// מפרשים נדירים כן להציג ברשימת הבחירה.
  List<int> _currentIndexes(TextBookLoaded state) {
    final raw = widget.indexes ??
        (state.selectedIndices.isNotEmpty
            ? state.selectedIndices.toList()
            : state.visibleIndices);
    if (raw.isNotEmpty) return raw;
    return [
      state.selectedIndex ??
          (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : 0)
    ];
  }

  int _getItemSearchIndex(Link link) {
    // מחשב את האינדקס המצטבר עד ל-link הנוכחי
    int cumulativeIndex = 0;
    final linkKey = _getLinkKey(link);

    for (final orderedLink in _orderedLinks) {
      final currentKey = _getLinkKey(orderedLink);
      if (currentKey == linkKey) {
        // מצאנו את ה-link הנוכחי
        final itemResults = _searchResultsPerLink[linkKey] ?? 0;
        if (itemResults == 0) return -1;

        // מחשב את האינדקס היחסי בתוך ה-link הזה
        final relativeIndex =
            _currentSearchIndexNotifier.value - cumulativeIndex;
        return (relativeIndex >= 0 && relativeIndex < itemResults)
            ? relativeIndex
            : -1;
      }
      cumulativeIndex += _searchResultsPerLink[currentKey] ?? 0;
    }

    return -1;
  }

  // מתודות ציבוריות לניווט בחיפוש (למשל מ-CommentatorsTabScreen)
  void navigateSearchPrev() {
    if (_currentSearchIndexNotifier.value > 0) {
      _currentSearchIndexNotifier.value--;
      _scrollToSearchResult();
    }
  }

  void navigateSearchNext() {
    if (_currentSearchIndexNotifier.value <
        _totalSearchResultsNotifier.value - 1) {
      _currentSearchIndexNotifier.value++;
      _scrollToSearchResult();
    }
  }

  /// ממקד את אזור הגלילה כדי שגלילה עם החיצים תעבוד בלי לחיצה. נקרא
  /// מכרטיסיית המפרשים כשהיא הופכת לטאב הפעיל.
  void requestScrollFocus() {
    if (_focusNode.canRequestFocus) _focusNode.requestFocus();
  }

  ValueNotifier<int> get totalSearchResultsNotifier =>
      _totalSearchResultsNotifier;
  ValueNotifier<int> get currentSearchIndexNotifier =>
      _currentSearchIndexNotifier;

  /// האזנה למצב הגלובלי של פתיחה/כיווץ כל המפרשים. שימושי לרכיבי הורה
  /// (כגון [CommentatorsTabScreen]) שמציגים לחצן כווץ/הרחב מחוץ לפאנל זה.
  ValueListenable<bool> get allExpandedListenable => _allExpandedNotifier;

  /// מתג מצב הכיווץ הגלובלי של כל המפרשים. מעדכן את כל הקבוצות בהתאם.
  void toggleAllExpanded() {
    setState(() {
      _allExpanded = !_allExpanded;
      for (final key in _expansionStates.keys) {
        _expansionStates[key] = _allExpanded;
      }
    });
  }

  /// ניווט לתוצאת חיפוש לפי אינדקס גלובלי (לשימוש חיצוני)
  void navigateToGlobalIndex(int index) {
    if (index < 0 || index >= _totalSearchResultsNotifier.value) return;
    _currentSearchIndexNotifier.value = index;
    _scrollToSearchResult();
  }

  void _onHighlightQueryChanged() {
    _searchUpdateDebounce?.cancel();
    _currentSearchIndexNotifier.value = 0;
    _totalSearchResultsNotifier.value = 0;
    _searchResultsPerLink.clear();
    _pendingCounts.clear();
    _scheduleSearchCompute();
  }

  void _onExternalSearchChanged() {
    final text = widget.externalSearchController!.text;
    if (_searchQueryNotifier.value != text) {
      _searchQueryNotifier.value = text;
      if (text.isNotEmpty) {
        setState(() {
          _allExpanded = true;
          for (final key in _expansionStates.keys) {
            _expansionStates[key] = true;
          }
        });
      }
      _currentSearchIndexNotifier.value = 0;
      _totalSearchResultsNotifier.value = 0;
      _searchResultsPerLink.clear();
      _pendingCounts.clear();
      _linkKeyToPath.clear();
      _searchSnippetsPerLink.clear();
      widget.externalSearchResultsByPathNotifier?.value = {};
      widget.externalSearchSnippetsNotifier?.value = [];
      _scheduleSearchCompute();
    }
  }

  void _handleSearchFocusChange() {
    if (!mounted) return;
    // אם איבדנו פוקוס והשדה ריק — חזור למצב לחצנים
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
    _searchQueryNotifier.value = '';
    _currentSearchIndexNotifier.value = 0;
    _totalSearchResultsNotifier.value = 0;
    _searchResultsPerLink.clear();
    _pendingCounts.clear();
    setState(() => _showSearchField = false);
  }

  Widget _buildClosePaneButton() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: AppTokens.borderRadiusAll,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        iconSize: 18,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        icon: const Icon(FluentIcons.dismiss_24_regular),
        onPressed: widget.onClosePane,
      ),
    );
  }

  Widget _buildButtonsRow(List<String> selectedCommentators) {
    const double gap = 16;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. בחירת מפרשים
        CommentatorsFilterButton(
          isActive: false,
          onPressed: _openCommentatorsFilter,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          iconSize: 20,
        ),
        // 2. הרחב/כווץ הכל — רק כשיש מפרשים נבחרים (לוגיקה מקורית)
        if (selectedCommentators.isNotEmpty) ...[
          const SizedBox(width: gap),
          IconButton(
            icon: Icon(
              _allExpanded
                  ? FluentIcons.arrow_collapse_all_24_regular
                  : FluentIcons.arrow_expand_all_24_regular,
            ),
            tooltip: _allExpanded ? 'כווץ את כל המפרשים' : 'הרחב את כל המפרשים',
            onPressed: () {
              setState(() {
                _allExpanded = !_allExpanded;
                for (var key in _expansionStates.keys) {
                  _expansionStates[key] = _allExpanded;
                }
              });
            },
          ),
        ],
        // 3. פתיחה בכרטיסייה חדשה
        if (widget.onOpenInNewTab != null) ...[
          const SizedBox(width: gap),
          IconButton(
            icon: const Icon(FluentIcons.open_24_regular),
            tooltip: 'פתח כרטסיית מפרשים',
            onPressed: widget.onOpenInNewTab,
          ),
        ],
        const SizedBox(width: gap),
        // 4. הפעלת שדה החיפוש
        IconButton(
          icon: const Icon(FluentIcons.search_24_regular),
          tooltip: 'חיפוש',
          onPressed: _openInlineSearch,
        ),
        // לחצן סגירת הפאנל — נשאר רק אם הקולבק קיים
        if (widget.onClosePane != null) ...[
          const SizedBox(width: gap),
          _buildClosePaneButton(),
        ],
      ],
    );
  }

  /// פותח את מסך ההדפסה עם המפרשים המוצגים כעת (מקובצים לפי מפרש).
  /// פומבי כדי שכרטיסיית המפרשים הייעודית תפעיל אותו מהסרגל/קיצור המקלדת.
  Future<void> printDisplayedCommentaries() async {
    final blocState = context.read<TextBookBloc>().state;
    if (blocState is! TextBookLoaded) return;

    final selectedCommentators = _selectedCommentators(blocState);
    final rawIndexes = widget.indexes ??
        (blocState.selectedIndices.isNotEmpty
            ? blocState.selectedIndices.toList()
            : blocState.visibleIndices);
    final indexes = rawIndexes.isNotEmpty
        ? rawIndexes
        : [
            blocState.selectedIndex ??
                (blocState.visibleIndices.isNotEmpty
                    ? blocState.visibleIndices.first
                    : 0)
          ];

    final links = await getLinksforIndexs(
      indexes: indexes,
      links: blocState.links,
      commentatorsToShow: selectedCommentators,
    );
    if (links.isEmpty) {
      UiSnack.show('אין מפרשים להדפסה');
      return;
    }

    final groups = await _getCachedGroups(links);
    final blocks = await buildCommentaryPrintBlocks(groups);
    if (blocks.isEmpty) {
      UiSnack.show('אין מפרשים להדפסה');
      return;
    }
    if (!mounted) return;

    final bookTitle = _bookTitle(blocState);
    final removeTaamim = !context.read<SettingsBloc>().state.showTeamim;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Future.value(''),
        bookId: bookTitle,
        documentTitle: bookTitle,
        prebuiltBlocks: blocks,
        removeNikud: blocState.removeNikud,
        removeTaamim: removeTaamim,
      ),
    );
  }

  Widget _buildSearchFieldRow() {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _searchQueryNotifier,
            builder: (context, query, _) {
              return ValueListenableBuilder<int>(
                valueListenable: _totalSearchResultsNotifier,
                builder: (context, total, __) {
                  return ValueListenableBuilder<int>(
                    valueListenable: _currentSearchIndexNotifier,
                    builder: (context, currentIndex, ___) {
                      return RtlTextField(
                        focusNode: _searchFocusNode,
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'חפש בתוך המפרשים המוצגים...',
                          prefixIcon: const Icon(FluentIcons.search_24_regular),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (query.isNotEmpty && total > 1) ...[
                                if (currentIndex >= 0)
                                  Text(
                                    '${currentIndex + 1}/$total',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                      FluentIcons.chevron_up_24_regular),
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: currentIndex > 0
                                      ? () {
                                          _currentSearchIndexNotifier.value =
                                              currentIndex - 1;
                                          _scrollToSearchResult();
                                        }
                                      : null,
                                ),
                                IconButton(
                                  icon: const Icon(
                                      FluentIcons.chevron_down_24_regular),
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: currentIndex < total - 1
                                      ? () {
                                          _currentSearchIndexNotifier.value =
                                              currentIndex + 1;
                                          _scrollToSearchResult();
                                        }
                                      : null,
                                ),
                              ],
                              IconButton(
                                icon:
                                    const Icon(FluentIcons.dismiss_24_regular),
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
                          if (_searchQueryNotifier.value != value) {
                            _searchQueryNotifier.value = value;
                            _currentSearchIndexNotifier.value = -1;
                            _totalSearchResultsNotifier.value = 0;
                            _searchResultsPerLink.clear();
                            _pendingCounts.clear();
                            _scheduleSearchCompute();
                          }
                        },
                        onSubmitted: (_) {
                          navigateSearchNext();
                          _searchFocusNode.requestFocus();
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        if (widget.onClosePane != null) ...[
          const SizedBox(width: 8),
          _buildClosePaneButton(),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // האזנה לשינויים במיקום הגלילה כדי לשמור את המיקום האחרון
    _itemPositionsListener.itemPositions.addListener(_updateLastScrollIndex);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
    widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
    _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    widget.closeFilterNotifier?.addListener(_onCloseFilterRequest);
    _searchFocusNode.addListener(_handleSearchFocusChange);
    // חיפוש חיצוני
    widget.externalSearchController?.addListener(_onExternalSearchChanged);
    widget.highlightQueryListenable?.addListener(_onHighlightQueryChanged);
    if (widget.externalTotalResultsNotifier != null) {
      _totalSearchResultsNotifier.addListener(() {
        widget.externalTotalResultsNotifier!.value =
            _totalSearchResultsNotifier.value;
      });
    }
    if (widget.externalCurrentIndexNotifier != null) {
      _currentSearchIndexNotifier.addListener(() {
        widget.externalCurrentIndexNotifier!.value =
            _currentSearchIndexNotifier.value;
      });
    }
    // סנכרון מצב הכיווץ הגלובלי לנוטיפייר חיצוני (אם סופק)
    if (widget.externalAllExpandedNotifier != null) {
      widget.externalAllExpandedNotifier!.value = _allExpanded;
      _allExpandedNotifier.addListener(() {
        widget.externalAllExpandedNotifier!.value = _allExpanded;
      });
    }
  }

  @override
  void didUpdateWidget(CommentaryListBase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController
          ?.removeListener(_handleExternalSelectionChange);
      widget.selectionSyncController
          ?.addListener(_handleExternalSelectionChange);
    }
    if (oldWidget.openFilterRequest != widget.openFilterRequest) {
      oldWidget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
      widget.openFilterRequest?.addListener(_handleOpenFilterRequest);
      _lastSeenFilterRequest = widget.openFilterRequest?.value ?? 0;
    }
    if (oldWidget.openFilterNotifier != widget.openFilterNotifier) {
      oldWidget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
      widget.openFilterNotifier?.addListener(_onOpenFilterRequest);
    }
    if (oldWidget.closeFilterNotifier != widget.closeFilterNotifier) {
      oldWidget.closeFilterNotifier?.removeListener(_onCloseFilterRequest);
      widget.closeFilterNotifier?.addListener(_onCloseFilterRequest);
    }
    if (oldWidget.highlightQueryListenable != widget.highlightQueryListenable) {
      oldWidget.highlightQueryListenable
          ?.removeListener(_onHighlightQueryChanged);
      widget.highlightQueryListenable?.addListener(_onHighlightQueryChanged);
    }
    // סגירה אוטומטית של מסך הסינון כאשר המפרשים עוברים מריק לא-ריק
    // (קורה כאשר המשתמש בוחר "כל המפרשים" מהתפריט הימני)
    if (_showCommentatorsFilter &&
        _filterWasAutoOpened &&
        !_userInteractedWithFilter &&
        (oldWidget.selectedCommentatorsOverride?.isEmpty ?? true) &&
        (widget.selectedCommentatorsOverride?.isNotEmpty ?? false)) {
      setState(() {
        _showCommentatorsFilter = false;
        _filterWasAutoOpened = false;
      });
    }
  }

  void scrollToTop() {
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _updateLastScrollIndex() {
    // הרשימה מדווחת גם פריטים שנבנו מחוץ למסך (cache) — מסננים לנראים בלבד.
    final positions = _itemPositionsListener.itemPositions.value;
    ItemPosition? firstVisible;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0 || p.itemLeadingEdge >= 1) continue;
      if (firstVisible == null || p.index < firstVisible.index) {
        firstVisible = p;
      }
    }
    if (firstVisible != null) {
      _lastScrollIndex = firstVisible.index;
    }
  }

  /// גולל כדי שתוכן מפרש שזה עתה נפתח ייכנס לתצוגה, רק אם הוא חורג מתחתיתה.
  /// גולל את המינימום הנדרש; אם התוכן ארוך מהתצוגה מביא את הכותרת לראש.
  void _ensureExpandedGroupVisible(int groupIndex) {
    if (!_itemScrollController.isAttached) return;
    ItemPosition? pos;
    for (final p in _itemPositionsListener.itemPositions.value) {
      if (p.index == groupIndex) {
        pos = p;
        break;
      }
    }
    // התוכן כבר נכנס במלואו, או שהכותרת כבר בראש – אין צורך לגלול
    if (pos == null ||
        pos.itemTrailingEdge <= 1.0 ||
        pos.itemLeadingEdge <= 0.05) {
      return;
    }
    final double overflow = pos.itemTrailingEdge - 1.0;
    final double targetLeading =
        (pos.itemLeadingEdge - overflow).clamp(0.05, pos.itemLeadingEdge);
    _itemScrollController.scrollTo(
      index: groupIndex,
      alignment: targetLeading,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _openCommentatorsFilter() {
    setState(() {
      _showCommentatorsFilter = true;
      _filterWasAutoOpened = false;
    });
  }

  void _handleOpenFilterRequest() {
    if (!mounted) return;
    final newValue = widget.openFilterRequest?.value ?? 0;
    if (newValue <= _lastSeenFilterRequest) return;
    _lastSeenFilterRequest = newValue;
    _openCommentatorsFilter();
  }

  void _closeCommentatorsFilter() {
    setState(() {
      _showCommentatorsFilter = false;
      _userInteractedWithFilter = false;
    });
  }

  void _onOpenFilterRequest() {
    // אם ההורה ביקש להפנות בקשות פתיחה אליו (למשל לפתיחת לשונית בסרגל הצד),
    // קוראים לקולבק במקום לפתוח פופ-אפ פנימי.
    if (widget.onFilterOpenRequested != null) {
      widget.onFilterOpenRequested!();
      return;
    }
    setState(() {
      _showCommentatorsFilter = true;
      _userInteractedWithFilter = false;
    });
  }

  void _onCloseFilterRequest() {
    setState(() {
      _showCommentatorsFilter = false;
      _userInteractedWithFilter = false;
    });
  }

  @override
  void dispose() {
    _searchUpdateDebounce?.cancel();
    _searchComputeDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_updateLastScrollIndex);
    widget.selectionSyncController
        ?.removeListener(_handleExternalSelectionChange);
    widget.openFilterRequest?.removeListener(_handleOpenFilterRequest);
    widget.openFilterNotifier?.removeListener(_onOpenFilterRequest);
    widget.closeFilterNotifier?.removeListener(_onCloseFilterRequest);
    widget.externalSearchController?.removeListener(_onExternalSearchChanged);
    widget.highlightQueryListenable?.removeListener(_onHighlightQueryChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchController.dispose();
    _savedSelectedText.dispose();
    _lastSelectedLink.dispose();
    _searchQueryNotifier.dispose();
    _currentSearchIndexNotifier.dispose();
    _totalSearchResultsNotifier.dispose();
    _allExpandedNotifier.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null ||
        controller.activeOwner == null ||
        identical(controller.activeOwner, _selectionOwner)) {
      return;
    }
    if (!mounted) return;
    _savedSelectedText.value = null;
    _lastSelectedLink.value = null;
    setState(() {
      _selectionRevision = controller.revision;
    });
  }

  Future<void> _scrollToSearchResult() async {
    if (_totalSearchResultsNotifier.value == 0 ||
        _orderedLinks.isEmpty ||
        !_itemScrollController.isAttached) {
      return;
    }

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    int cumulativeIndex = 0;
    Link? targetLink;

    // 1. מוצא את ה-link שמכיל את תוצאת החיפוש הנוכחית
    for (final link in _orderedLinks) {
      final linkKey = _getLinkKey(link);
      final itemResults = _searchResultsPerLink[linkKey] ?? 0;
      if (_currentSearchIndexNotifier.value < cumulativeIndex + itemResults) {
        targetLink = link;
        break;
      }
      cumulativeIndex += itemResults;
    }

    if (targetLink == null) {
      return;
    }

    // 2. מוצא את ה-group שמכיל את ה-link
    final groups = await _getCachedGroups(_orderedLinks);
    int targetGroupIndex = -1;
    CommentaryGroup? targetGroup;

    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group.links.any((l) => _getLinkKey(l) == _getLinkKey(targetLink!))) {
        targetGroupIndex = i;
        targetGroup = group;
        break;
      }
    }

    if (targetGroupIndex == -1 || targetGroup == null) {
      return;
    }

    // 3. מבטיח שה-ExpansionTile של הקבוצה פתוח
    final groupKey = targetGroup.bookTitle;

    final bool isCurrentlyExpanded = _expansionStates[groupKey] ?? true;

    // אם צריך לפתוח, פותח ומחכה לאנימציה
    if (!isCurrentlyExpanded) {
      setState(() {
        _expansionStates[groupKey] = true;
      });
    }

    // 4. ביצוע הגלילה בתוך Callback
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // המתנה לסיום אנימציית הפתיחה אם הייתה
      if (!isCurrentlyExpanded) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }

      final linkKey = _getLinkKey(targetLink!);
      final itemKey = _itemKeys[linkKey];
      final BuildContext? itemContext = itemKey?.currentContext;

      // בודק אם הפריט כבר בעץ הרינדור (לא נדרשת גלילה גסה להכניסו לזיכרון)
      final bool itemInRenderTree = itemContext != null &&
          itemContext.mounted &&
          itemContext.findRenderObject() is RenderBox;

      // שלב א': גלילה גסה לקבוצה – רק אם הפריט לא בעץ הרינדור
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

      // שלב ב': גלילה עדינה לפריט הספציפי
      final BuildContext? ctx = itemKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          final RenderObject? itemRenderObj = ctx.findRenderObject();
          if (itemRenderObj is! RenderBox) return;
          final RenderBox itemBox = itemRenderObj;

          final ScrollableState scrollable = Scrollable.of(ctx);
          if (!scrollable.mounted) return;

          final RenderObject? viewportRenderObj =
              scrollable.context.findRenderObject();
          if (viewportRenderObj is! RenderBox) return;
          final RenderBox viewportBox = viewportRenderObj;

          final Offset itemOffset =
              itemBox.localToGlobal(Offset.zero, ancestor: viewportBox);

          // מביא את הפריט ל-10% מראש הרשימה
          final double targetY = viewportBox.size.height * 0.1;
          final double scrollDelta = itemOffset.dy - targetY;

          if (scrollDelta.abs() > 10) {
            scrollController.animateScroll(
                offset: scrollDelta,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut);
          }
        } catch (e) {
          debugPrint('Error during micro-scrolling: $e');
        }
      }
    });
  }

  void _scheduleSearchCompute() {
    _searchComputeDebounce?.cancel();
    // כשאין קישורים אין מה לחשב — טעינתם תפעיל תזמון מחדש (לפי חתימה).
    if (_orderedLinks.isEmpty) return;
    _searchComputeDebounce =
        Timer(const Duration(milliseconds: 250), _computeSearchCounts);
  }

  /// עובר על כל הקישורים ומזין את משפך העדכון של ספירות/קטעי חיפוש, במקביל
  /// לדיווח (הזהה) מה-widgets שנבנו בפועל.
  Future<void> _computeSearchCounts() async {
    if (!mounted) return;
    final internalQuery = widget.showSearch ? _searchQueryNotifier.value : '';
    final query = internalQuery.isNotEmpty
        ? internalQuery
        : (widget.highlightQueryListenable?.value ?? '');
    final links = List<Link>.from(_orderedLinks);
    if (query.isEmpty || links.isEmpty) return;
    final gen = ++_searchComputeGen;

    final blocState = context.read<TextBookBloc>().state;
    final removePunctuation =
        blocState is TextBookLoaded && blocState.removePunctuation;
    final stateRemoveNikud =
        blocState is TextBookLoaded && blocState.removeNikud;
    final settings = context.read<SettingsBloc>().state;
    final wantSnippets = widget.externalSearchSnippetsNotifier != null;

    for (final link in links) {
      String data;
      try {
        data = await link.content;
      } catch (_) {
        data = '';
      }
      if (!mounted || gen != _searchComputeGen) return;
      final count = countCommentarySearchMatches(
        content: data,
        query: query,
        removePunctuation: removePunctuation,
      );
      _updateSearchResultsCount(link, count);
      if (wantSnippets && count > 0) {
        final removeNikud = await resolveRemoveNikudForBook(
          title: utils.getTitleFromPath(link.path2),
          defaultRemoveNikud: settings.defaultRemoveNikud || stateRemoveNikud,
          removeNikudFromTanach: settings.removeNikudFromTanach,
        );
        if (!mounted || gen != _searchComputeGen) return;
        _updateSearchSnippets(link, [
          buildCommentarySearchSnippet(
            content: data,
            query: query,
            removeNikud: removeNikud,
            removePunctuation: removePunctuation,
          ),
        ]);
      }
    }
  }

  void _updateSearchResultsCount(Link link, int count) {
    if (!mounted) return;

    final key = _getLinkKey(link);
    // שמור את ה-path2 לצורך קיבוץ לפי מפרש
    _linkKeyToPath[key] = link.path2;
    // אם הכמות לא השתנתה, אין צורך לעשות כלום
    if (_searchResultsPerLink[key] == count) return;

    _pendingCounts[key] = count;

    // אם כבר יש טיימר פעיל, רק עדכנו את הרשימה הממתינה
    if (_searchUpdateDebounce?.isActive ?? false) return;

    // הפעלת הטיימר
    _searchUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _searchResultsPerLink.addAll(_pendingCounts);
      _pendingCounts.clear();
      _totalSearchResultsNotifier.value =
          _searchResultsPerLink.values.fold(0, (sum, count) => sum + count);

      // עדכון נוטיפייר חיצוני לתוצאות לפי מפרש
      if (widget.externalSearchResultsByPathNotifier != null) {
        final byPath = <String, int>{};
        for (final entry in _searchResultsPerLink.entries) {
          final path = _linkKeyToPath[entry.key] ?? '';
          if (path.isNotEmpty && entry.value > 0) {
            byPath[path] = (byPath[path] ?? 0) + entry.value;
          }
        }
        widget.externalSearchResultsByPathNotifier!.value = byPath;
      }

      // עדכון נוטיפייר קטעי החיפוש (snippets)
      _scheduleSnippetsNotifierRebuild();

      // תיקון אינדקס אם חרגנו מהגבולות
      if (_currentSearchIndexNotifier.value >=
              _totalSearchResultsNotifier.value &&
          _totalSearchResultsNotifier.value > 0) {
        _currentSearchIndexNotifier.value = 0;
      }
    });
  }

  void _updateSearchSnippets(Link link, List<String> snippets) {
    if (!mounted) return;
    final key = _getLinkKey(link);
    _searchSnippetsPerLink[key] = snippets;
    _scheduleSnippetsNotifierRebuild();
  }

  void _rebuildSnippetsNotifier() {
    if (widget.externalSearchSnippetsNotifier == null) return;
    final List<CommentarySearchSnippet> result = [];
    int globalIndex = 0;
    for (final link in _orderedLinks) {
      final key = _getLinkKey(link);
      final count = _searchResultsPerLink[key] ?? 0;
      final snippets = _searchSnippetsPerLink[key] ?? [];
      for (int i = 0; i < snippets.length; i++) {
        result.add(CommentarySearchSnippet(
          path: link.path2,
          snippet: snippets[i],
          globalIndex: globalIndex,
        ));
      }
      globalIndex += count;
    }
    widget.externalSearchSnippetsNotifier!.value = result;
  }

  void _scheduleSnippetsNotifierRebuild() {
    if (widget.externalSearchSnippetsNotifier == null ||
        _snippetsRebuildScheduled ||
        !mounted) {
      return;
    }
    _snippetsRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snippetsRebuildScheduled = false;
      if (!mounted) return;
      _rebuildSnippetsNotifier();
    });
  }

  void _updateGlobalExpansionState() {
    if (_expansionStates.isEmpty) return;

    // בודק אם כל המפרשים פתוחים
    final allExpanded = _expansionStates.values.every((state) => state == true);
    // בודק אם כל המפרשים סגורים
    final allCollapsed =
        _expansionStates.values.every((state) => state == false);

    // מעדכן את המצב הגלובלי רק אם כולם באותו מצב
    if (allExpanded) {
      _allExpanded = true;
    } else if (allCollapsed) {
      _allExpanded = false;
    }
    // אם יש מצב מעורב, לא משנים את _allExpanded
  }

  Widget _buildCommentaryGroupTile({
    required CommentaryGroup group,
    required TextBookLoaded state,
    required String indexesKey,
    required int groupIndex,
  }) {
    final groupKey = group.bookTitle;

    // אם אין מצב שמור עבור הקבוצה הזו, משתמש במצב הגלובלי
    if (!_expansionStates.containsKey(groupKey)) {
      _expansionStates[groupKey] = _allExpanded;
    }

    final isExpanded = _expansionStates[groupKey] ?? _allExpanded;

    return _CollapsibleCommentaryGroup(
      key: PageStorageKey(groupKey),
      group: group,
      isExpanded: isExpanded,
      fontSize: widget.fontSize,
      openBookCallback: widget.openBookCallback,
      removeNikud: state.removeNikud,
      removePunctuation: state.removePunctuation,
      showSearch: widget.showSearch,
      searchQueryListenable: _searchQueryNotifier,
      currentSearchIndexListenable: _currentSearchIndexNotifier,
      totalSearchResultsListenable: _totalSearchResultsNotifier,
      getItemSearchIndex: _getItemSearchIndex,
      updateSearchResultsCount: _updateSearchResultsCount,
      updateSearchSnippets: widget.externalSearchSnippetsNotifier != null
          ? _updateSearchSnippets
          : null,
      highlightQueryListenable: widget.highlightQueryListenable,
      itemKeys: _itemKeys,
      getLinkKey: _getLinkKey,
      indexesKey: indexesKey,
      savedSelectedTextListenable: _savedSelectedText,
      lastSelectedLinkListenable: _lastSelectedLink,
      onExpansionChanged: (expanded) {
        _expansionStates[groupKey] = expanded;
        // בודק אם כל המפרשים פתוחים או סגורים ומעדכן את המצב הגלובלי
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _updateGlobalExpansionState();
          });
          if (expanded) {
            _ensureExpandedGroupVisible(groupIndex);
          }
        });
      },
      // לחיצת עכבר על מפרש מסמנת אותו כיעד הייחוס להעתקת מקלדת (Ctrl+C),
      // כי ל-SelectionArea היחיד אין מידע על המפרש הספציפי שבו הבחירה.
      onLinkPointerDown: (link) => _lastSelectedLink.value = link,
      // מטמון הטקסט/הכותרת המרונדרים לכל מפרש מוצג — לשחזור מעברי שורה בהעתקה.
      onLinkRendered: (link, text) =>
          _renderedTextByKey[_getLinkKey(link)] = text,
      onLinkTitleRendered: (link, title) =>
          _renderedTitleByKey[_getLinkKey(link)] =
              title.replaceAll(RegExp(r'\s+'), ' ').trim(),
      restoreLineBreaks: _restoreLineBreaks,
    );
  }

  /// טיפול בשינוי בחירה ב-SelectionArea היחיד שעוטף את כל רשימת המפרשים
  /// (כשהרשימה אינה מקוננת בתוך SelectionArea חיצוני). מזין את הטקסט הנבחר
  /// לצורך העתקה ומסנכרן בעלות בחירה מול אזורים אחרים במסך.
  void _onListSelectionChanged(String? text) {
    // עדכון מעקב כיוון הגרירה (משמש את RtlSelectionShortcuts לבחירת הקצה).
    trackRtlSelection(text);
    // שינוי בחירה זמני בזמן priming — לא לעבד (שמירת טקסט/סנכרון).
    if (rtlSelectionPriming) return;
    if (text != null && text.trim().isNotEmpty) {
      _savedSelectedText.value = text;
      widget.selectionSyncController?.activate(_selectionOwner);
    } else {
      _savedSelectedText.value = null;
      _lastSelectedLink.value = null;
      widget.selectionSyncController?.clear(_selectionOwner);
    }
  }

  /// האם הבחירה הנוכחית חוצה יותר מפריט מפרש אחד (לפי מיקום שני קצותיה).
  /// משמש כדי לא לייחס כותרת מקור (copyWithHeaders) למפרש בודד בהעתקת מקלדת
  /// כשהטקסט הנבחר בא מכמה מפרשים. נכשל "בטוח" (false) כשלא ניתן לקבוע.
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

  /// משחזר מעברי שורה בטקסט נבחר רב-שורתי (Flutter מחזיר טקסט שטוח), לפי הטקסט
  /// המרונדר המוטמן של המפרשים המוצגים. אם לא נמצא — מחזיר את הטקסט כמות שהוא.
  String? _restoreLineBreaks(String? flat) {
    if (flat == null || flat.isEmpty || flat.contains('\n')) return flat;
    // סדר התצוגה לכל מפרש: כותרת (displayReference) ואז התוכן.
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
        selectedText: flat, visibleLines: lines);
  }

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
        buildWhen: (previous, current) {
          // מבטיח בניה מחדש רק כשיש שינוי בנתונים שמשפיעים על תצוגת המפרשים
          if (previous is! TextBookLoaded || current is! TextBookLoaded) {
            return true;
          }
          return !listEquals(
                  previous.activeCommentators, current.activeCommentators) ||
              !listEquals(previous.availableCommentators,
                  current.availableCommentators) ||
              previous.links != current.links || // השוואת רפרנס לביצועים
              !listEquals(previous.visibleIndices, current.visibleIndices) ||
              previous.selectedIndex != current.selectedIndex ||
              !setEquals(previous.selectedIndices, current.selectedIndices) ||
              previous.fontSize != current.fontSize ||
              previous.removeNikud != current.removeNikud ||
              previous.removePunctuation != current.removePunctuation;
        },
        loadingWidget: const Center(),
        builder: (context, state) {
          final selectedCommentators = _selectedCommentators(state);
          // איפוס ה-latch: ברגע שיש בחירה לא-ריקה, ריקון עתידי שלה צריך
          // לפתוח שוב את הבחירה (אך לא בכל rebuild בזמן שהבחירה נשארת ריקה).
          if (selectedCommentators.isNotEmpty) {
            _autoFilterOpenNotified = false;
          }
          final notesIsActive =
              _allSelectedCommentators(state).contains(kNotesCommentatorTitle);
          // כש'הערות' פעיל הוא משמש מפרש ברירת מחדל, ולכן בדרך כלל אין לפתוח
          // אוטומטית את בחירת המפרשים. חריג: כרטיסיית המפרשים מעבירה
          // onFilterOpenRequested ופותחת את הבחירה בלשונית צד נפרדת שאינה
          // מסתירה את ההערות — שם יש לפתוח גם כש'הערות' פעיל, אחרת כשאין
          // מפרשים נבחרים המשתמש נתקע על הודעת "אין הערות לקטע זה".
          final shouldAutoOpenOverrideFilter = widget.showSearch &&
              widget.onSelectedCommentatorsOverrideChanged != null &&
              selectedCommentators.isEmpty &&
              (widget.onFilterOpenRequested != null || !notesIsActive) &&
              !_autoFilterOpenNotified &&
              !_showCommentatorsFilter;

          if (shouldAutoOpenOverrideFilter) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  _showCommentatorsFilter ||
                  _autoFilterOpenNotified) {
                return;
              }
              // בדיקה מחדש: אם המפרשים הזמינים כבר נטענו מאז תזמון הקריאה, לא פותחים את הסינון
              final currentBlocState = context.read<TextBookBloc>().state;
              if (currentBlocState is TextBookLoaded) {
                final currentSelected = _selectedCommentators(currentBlocState);
                if (currentSelected.isNotEmpty) return;
              }
              // אם ההורה רוצה לטפל בעצמו (לפתוח לשונית בסרגל הצד), מעבירים אליו.
              // מסמנים את ה-latch לפני הקריאה כדי שלא נשלח שוב באותו rebuild-cycle.
              if (widget.onFilterOpenRequested != null) {
                _autoFilterOpenNotified = true;
                widget.onFilterOpenRequested!();
                return;
              }
              setState(() {
                _showCommentatorsFilter = true;
                _filterWasAutoOpened = true;
              });
            });
            // כאשר ההורה מטפל בפתיחה, אין סיבה להחזיר ספינר טעינה — נמשיך לבנות
            // את התצוגה הרגילה (שתציג הודעת "אין מפרשים נבחרים" בהמשך).
            if (widget.onFilterOpenRequested == null) {
              return const Center(child: CircularProgressIndicator());
            }
          }

          Widget buildList() {
            return Builder(
              builder: (context) {
                // כשמשתמשים ב-availableCommentators, ממתינים שהם ייטענו
                if (widget.useAvailableCommentators &&
                    state.availableCommentators.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                // בודק מראש אם יש קישורים רלוונטיים לאינדקסים הנוכחיים.
                // ריבוי-בחירה: כל הקטעים שנבחרו (Ctrl+לחיצה), לא רק העוגן.
                final currentIndexesRaw = widget.indexes ??
                    (state.selectedIndices.isNotEmpty
                        ? state.selectedIndices.toList()
                        : state.visibleIndices);

                // בהפעלה מחדש/מצבים נדירים יכול להגיע לכאן עם רשימת אינדקסים ריקה,
                // מה שגורם ל"אין מפרשים" גם כשיש. נבחר אינדקס ברירת מחדל יציב.
                final currentIndexes = currentIndexesRaw.isNotEmpty
                    ? currentIndexesRaw
                    : [
                        state.selectedIndex ??
                            (state.visibleIndices.isNotEmpty
                                ? state.visibleIndices.first
                                : 0)
                      ];

                Widget? notesWidget;
                if (notesIsActive) {
                  final relevantNotes =
                      inline_notes.notesForLines(state.content, currentIndexes);
                  if (relevantNotes.isNotEmpty) {
                    notesWidget = _NotesCommentaryWidget(
                      notes: relevantNotes,
                      fontSize: widget.fontSize,
                      removeNikud: state.removeNikud,
                      openBookCallback: widget.openBookCallback,
                    );
                  } else if (selectedCommentators.isEmpty) {
                    notesWidget = Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'אין הערות לקטע זה',
                          style: TextStyle(
                            fontSize: widget.fontSize * 0.7,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                }

                // בדיקה אם יש בכלל קישורים לאינדקסים הנוכחיים (ללא סינון מפרשים)
                final hasAnyCommentaryLinks = currentIndexes.any((idx) {
                  final lineLinks = state.linksByLine[idx + 1];
                  if (lineLinks == null) return false;
                  return lineLinks.any((link) =>
                      LinkTypes.isDependentTextLink(link.connectionType));
                });

                // סינון מהיר של קישורים רלוונטיים
                final hasRelevantLinks = currentIndexes.any((idx) {
                  final lineLinks = state.linksByLine[idx + 1];
                  if (lineLinks == null) return false;
                  return lineLinks.any((link) => selectedCommentators
                      .contains(utils.getTitleFromPath(link.path2)));
                });

                // אם אין קישורים רלוונטיים
                if (!hasRelevantLinks) {
                  if (state.linksLoading) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'טוען מפרשים...',
                          style: TextStyle(
                            fontSize: widget.fontSize * 0.7,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (notesWidget != null) {
                    return notesWidget;
                  }
                  // אם יש מפרשים זמינים אבל לא נבחרו בכלל - פתח אוטומטית את מסך הבחירה
                  // (לא במצב useAvailableCommentators — שם מוצג הכל אוטומטית)
                  if (widget.showSearch &&
                      !widget.useAvailableCommentators &&
                      hasAnyCommentaryLinks &&
                      selectedCommentators.isEmpty &&
                      !_showCommentatorsFilter) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _showCommentatorsFilter = true;
                          _filterWasAutoOpened = true;
                        });
                      }
                    });
                    return const Center(child: CircularProgressIndicator());
                  }

                  // אין מפרשים בכלל לקטע הזה, או שיש מפרשים נבחרים אבל הם לא רלוונטיים
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        hasAnyCommentaryLinks
                            ? 'לא נמצאו מפרשים מהנבחרים לקטע זה'
                            : 'לא נמצאו מפרשים לקטע הנבחר',
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.7,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final commentaryWidget = FutureBuilder<List<Link>>(
                  future: getLinksforIndexs(
                      indexes: currentIndexes,
                      links: state.links,
                      commentatorsToShow: selectedCommentators),
                  builder: (context, thisLinksSnapshot) {
                    if (!thisLinksSnapshot.hasData) {
                      // רק אם יש קישורים רלוונטיים, מציג אנימציית טעינה
                      return _buildSkeletonLoading();
                    }
                    if (thisLinksSnapshot.data!.isEmpty) {
                      // אם אין מפרשים, פשוט נציג מסך ריק
                      return const SizedBox.shrink();
                    }
                    final data = thisLinksSnapshot.data!;

                    // שומר את הסדר של ה-links לצורך חישוב אינדקס החיפוש
                    _orderedLinks = data;

                    // מנקה מפתחות ישנים ומכין מפתחות חדשים
                    final currentLinkKeys =
                        data.map((l) => _getLinkKey(l)).toSet();

                    // קישורים חדשים (טעינה/מעבר שורה) — חישוב ספירות חיפוש
                    // מחדש אם יש שאילתה פעילה.
                    final linksSignature = Object.hashAll(currentLinkKeys);
                    if (linksSignature != _lastLinksSignature) {
                      _lastLinksSignature = linksSignature;
                      _scheduleSearchCompute();
                    }
                    _itemKeys.removeWhere(
                        (key, value) => !currentLinkKeys.contains(key));
                    for (final key in currentLinkKeys) {
                      _itemKeys.putIfAbsent(key, () => GlobalKey());
                    }
                    _renderedTextByKey.removeWhere(
                        (key, value) => !currentLinkKeys.contains(key));
                    _renderedTitleByKey.removeWhere(
                        (key, value) => !currentLinkKeys.contains(key));

                    // ניקוי ספירות חיפוש מקישורים שאינם בקטע הנוכחי
                    // (מניעת ספירה מנופחת ממעבר בין קטעים)
                    final staleSearchKeys = _searchResultsPerLink.keys
                        .where((key) => !currentLinkKeys.contains(key))
                        .toList();
                    if (staleSearchKeys.isNotEmpty) {
                      for (final key in staleSearchKeys) {
                        _searchResultsPerLink.remove(key);
                      }
                      _pendingCounts.removeWhere(
                          (key, _) => !currentLinkKeys.contains(key));
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final newTotal = _searchResultsPerLink.values
                            .fold(0, (sum, c) => sum + c);
                        _totalSearchResultsNotifier.value = newTotal;
                        if (_currentSearchIndexNotifier.value >= newTotal) {
                          _currentSearchIndexNotifier.value = 0;
                        }
                      });
                    }

                    _expansionStates.removeWhere((key, value) => !data.any(
                        (link) => key == utils.getTitleFromPath(link.path2)));

                    final indexesKey = currentIndexes.join(',');

                    return Shortcuts(
                      shortcuts: <ShortcutActivator, Intent>{
                        LogicalKeySet(
                          LogicalKeyboardKey.control,
                          LogicalKeyboardKey.keyC,
                        ): const _CopyCommentaryIntent(),
                        LogicalKeySet(
                          LogicalKeyboardKey.meta,
                          LogicalKeyboardKey.keyC,
                        ): const _CopyCommentaryIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          _CopyCommentaryIntent:
                              CallbackAction<_CopyCommentaryIntent>(
                            onInvoke: (_) {
                              // בחירה החוצה כמה מפרשים — לא מייחסים כותרת מקור
                              // (היא הייתה משתייכת למפרש בודד בלבד).
                              final link = _selectionSpansMultipleItems()
                                  ? null
                                  : _lastSelectedLink.value;
                              ContextMenuUtils.copyFormattedText(
                                context: context,
                                savedSelectedText: _restoreLineBreaks(
                                    _savedSelectedText.value),
                                fontSize: widget.fontSize,
                                link: link,
                              );
                              return null;
                            },
                          ),
                        },
                        child: Listener(
                          // לחיצה בכל מקום בחלונית ממקדת את ה-ProgressiveScroll
                          // כדי שגלילה עם החיצים תעבוד בלי לבחור טקסט קודם.
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) {
                            if (!shouldFocusScrollOnPointerDown(
                                event.buttons)) {
                              return;
                            }
                            _focusNode.requestFocus();
                          },
                          child: AppFutureBuilder<List<CommentaryGroup>>(
                            future: _getCachedGroups(data),
                            loadingWidget: _buildSkeletonLoading(),
                            builder: (context, groups) {
                              for (final group in groups) {
                                final groupKey = group.bookTitle;
                                _expansionStates.putIfAbsent(
                                    groupKey, () => _allExpanded);
                              }

                              final Widget listView =
                                  ScrollablePositionedList.builder(
                                itemScrollController: _itemScrollController,
                                itemPositionsListener: _itemPositionsListener,
                                initialScrollIndex: _lastScrollIndex.clamp(
                                    0, groups.length - 1),
                                key: PageStorageKey(
                                    'commentary_${selectedCommentators.join(',')}'),
                                physics: const ClampingScrollPhysics(),
                                scrollOffsetController: scrollController,
                                shrinkWrap: widget.shrinkWrap,
                                itemCount: groups.length,
                                itemBuilder: (context, groupIndex) {
                                  final group = groups[groupIndex];
                                  return _buildCommentaryGroupTile(
                                    group: group,
                                    state: state,
                                    indexesKey: indexesKey,
                                    groupIndex: groupIndex,
                                  );
                                },
                              );

                              // ProgressiveScroll עוטף את SelectionArea (מעליו),
                              // כך שגלילת החיצים נקלטת גם כש-SelectableRegion הוא
                              // ה-primaryFocus — האירוע מתפשט כלפי מעלה דרכו.
                              return ProgressiveScroll(
                                focusNode: _focusNode,
                                autofocus: widget.autofocus,
                                scrollController: scrollController,
                                maxSpeed: 10000.0,
                                curve: 10.0,
                                accelerationFactor: 5,
                                itemScrollController: _itemScrollController,
                                child: RtlSelectionShortcuts(
                                  child: SelectionArea(
                                    key: ValueKey(
                                        'commentary_list_$_selectionRevision'),
                                    contextMenuBuilder: (context, _) =>
                                        const SizedBox.shrink(),
                                    onSelectionChanged: (selection) =>
                                        _onListSelectionChanged(
                                            selection?.plainText),
                                    child: listView,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );

                if (notesWidget == null) {
                  return commentaryWidget;
                }

                // "הערות" + מפרשים. אסור ש"הערות" יתפוס חצי קבוע: `Flexible`
                // ו-`Expanded` שניהם flex:1 התחלקו 50/50, כך שהמפרשים קיבלו רק
                // חצי מהגובה (וכש"הערות" קצר נותר חלל ריק). במקום זאת מגבילים
                // את "הערות" לגובה התוכן שלו (עד ~45% מהגובה; הוא SingleChild-
                // ScrollView ולכן יגלול אם ארוך), והמפרשים מקבלים את כל השאר.
                return LayoutBuilder(
                  builder: (ctx, c) {
                    final maxNotes = c.maxHeight.isFinite
                        ? c.maxHeight * 0.45
                        : double.infinity;
                    return Column(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: maxNotes),
                          child: notesWidget,
                        ),
                        const Divider(height: 1),
                        Expanded(child: commentaryWidget),
                      ],
                    );
                  },
                );
              },
            );
          }

          if (widget.showSearch) {
            // אם מסך בחירת המפרשים פתוח, מציג אותו במקום הרשימה
            if (_showCommentatorsFilter) {
              final groups = _commentatorGroups(state);
              final customSelection =
                  widget.onSelectedCommentatorsOverrideChanged;
              return CommentatorsFilterScreen(
                onBack: _closeCommentatorsFilter,
                child: customSelection != null
                    ? CommentatorsSelectionPanel(
                        groups: groups,
                        // מעבירים את הבחירה המלאה (כולל 'הערות') ולא את
                        // selectedCommentators המסונן — אחרת תיבת הסימון של
                        // 'הערות' לעולם לא תוצג כמסומנת, ובחירת מפרש אחר תמחק
                        // אותו מהבחירה הפעילה.
                        selectedCommentators: _allSelectedCommentators(state),
                        onSelectionChanged: (list) {
                          _userInteractedWithFilter = true;
                          customSelection(list);
                        },
                        bookTitle: _bookTitle(state),
                        rareCommentators: state.rareCommentators,
                        lineRelevantCommentators: lineRelevantRareCommentators(
                          rareCommentators: state.rareCommentators,
                          currentIndexes: _currentIndexes(state),
                          linksByLine: state.linksByLine,
                        ),
                      )
                    : CommentatorsListView(
                        onCommentatorSelected: _closeCommentatorsFilter,
                      ),
              );
            }

            // כאשר חיפוש חיצוני — מסתיר שורת חיפוש פנימית, רק רשימה
            if (widget.externalSearchController != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(fit: FlexFit.loose, child: buildList()),
                ],
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _showSearchField
                      ? _buildSearchFieldRow()
                      : _buildButtonsRow(selectedCommentators),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: buildList(),
                ),
              ],
            );
          } else {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // כפתור גלובלי מעל הרשימה
                if (selectedCommentators.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                        icon: Icon(
                          _allExpanded
                              ? FluentIcons.arrow_collapse_all_24_regular
                              : FluentIcons.arrow_expand_all_24_regular,
                        ),
                        tooltip: _allExpanded
                            ? 'כווץ את כל המפרשים'
                            : 'הרחב את כל המפרשים',
                        onPressed: () {
                          setState(() {
                            _allExpanded = !_allExpanded;
                            // מעדכן את כל המצבים של הקבוצות
                            for (var key in _expansionStates.keys) {
                              _expansionStates[key] = _allExpanded;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                // הרשימה
                Flexible(
                  child: buildList(),
                ),
              ],
            );
          }
        });
  }

  /// בניית skeleton loading לפרשנות - מספר פרשנויות עם כותרת ושלוש שורות
  Widget _buildSkeletonLoading() {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4, // מציג 4 שלדים של פרשנויות
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // כותרת הפרשן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _SkeletonLine(width: 0.3, height: 20, color: baseColor),
              ),
            ),
            // שלוש שורות תוכן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.95, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.92, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.88, height: 16, color: baseColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget של שורה סטטית לשלד טעינה
class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadiusAll,
      ),
    );
  }
}

/// Widget מותאם אישית להצגת קבוצת מפרשים עם אפשרות כיווץ/הרחבה
/// שלא מפריע לבחירת טקסט והעתקה (במקום ExpansionTile)
class _CollapsibleCommentaryGroup extends StatefulWidget {
  final CommentaryGroup group;
  final bool isExpanded;
  final double fontSize;
  final Function(TextBookTab) openBookCallback;
  final bool removeNikud;
  final bool removePunctuation;
  final bool showSearch;
  final ValueListenable<String> searchQueryListenable;
  final ValueListenable<int> currentSearchIndexListenable;
  final ValueListenable<int> totalSearchResultsListenable;
  final int Function(Link) getItemSearchIndex;
  final void Function(Link, int) updateSearchResultsCount;
  final void Function(Link, List<String>)? updateSearchSnippets;
  final Map<String, GlobalKey> itemKeys;
  final String Function(Link) getLinkKey;
  final String indexesKey;
  final ValueListenable<String?> savedSelectedTextListenable;
  final ValueListenable<Link?> lastSelectedLinkListenable;
  final void Function(bool) onExpansionChanged;

  /// נקרא בלחיצת עכבר על פריט מפרש — לסימון המפרש הנבחר לייחוס העתקה.
  final void Function(Link link)? onLinkPointerDown;

  /// מדווח את הטקסט המרונדר של פריט מפרש — לשחזור מעברי שורה בהעתקה.
  final void Function(Link link, String renderedPlainText)? onLinkRendered;

  /// מדווח את כותרת הפריט המרונדרת (displayReference) — לשחזור מעברי שורה.
  final void Function(Link link, String renderedTitle)? onLinkTitleRendered;

  /// משחזר מעברי שורה בטקסט נבחר רב-שורתי (להעתקה מתפריט ההקשר).
  final String? Function(String?)? restoreLineBreaks;

  /// מחרוזת להדגשה מה-BLoC החיצוני, ללא שדה החיפוש הפנימי.
  final ValueListenable<String>? highlightQueryListenable;

  const _CollapsibleCommentaryGroup({
    super.key,
    required this.group,
    required this.isExpanded,
    required this.fontSize,
    required this.openBookCallback,
    required this.removeNikud,
    required this.removePunctuation,
    required this.showSearch,
    required this.searchQueryListenable,
    required this.currentSearchIndexListenable,
    required this.totalSearchResultsListenable,
    required this.getItemSearchIndex,
    required this.updateSearchResultsCount,
    this.updateSearchSnippets,
    required this.itemKeys,
    required this.getLinkKey,
    required this.indexesKey,
    required this.savedSelectedTextListenable,
    required this.lastSelectedLinkListenable,
    required this.onExpansionChanged,
    this.onLinkPointerDown,
    this.onLinkRendered,
    this.onLinkTitleRendered,
    this.restoreLineBreaks,
    this.highlightQueryListenable,
  });

  @override
  State<_CollapsibleCommentaryGroup> createState() =>
      _CollapsibleCommentaryGroupState();
}

class _CollapsibleCommentaryGroupState
    extends State<_CollapsibleCommentaryGroup> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpanded;
  }

  @override
  void didUpdateWidget(_CollapsibleCommentaryGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isExpanded != widget.isExpanded) {
      _isExpanded = widget.isExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת הקבוצה - ניתנת ללחיצה להרחבה/כיווץ
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
            widget.onExpansionChanged(_isExpanded);
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _isExpanded ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_left,
                    size: 20,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BlocBuilder<SettingsBloc, SettingsState>(
                    builder: (context, settingsState) {
                      String displayTitle = widget.group.bookTitle;
                      if (settingsState.replaceHolyNames) {
                        displayTitle = utils.replaceHolyNames(displayTitle);
                      }
                      return Text(
                        displayTitle,
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.85,
                          fontWeight: FontWeight.bold,
                          fontFamily: settingsState.commentatorsFontFamily,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // תוכן המפרשים - מוצג רק כשמורחב
        if (_isExpanded)
          ...widget.group.links.map((link) {
            final Widget itemContent = ValueListenableBuilder<String?>(
              valueListenable: widget.savedSelectedTextListenable,
              child: Padding(
                key: widget.itemKeys[widget.getLinkKey(link)],
                padding: const EdgeInsets.only(
                    right: 32.0, left: 16.0, top: 8.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) {
                        return FutureBuilder<String>(
                          future: link.displayReference,
                          builder: (context, snapshot) {
                            String displayTitle =
                                snapshot.data ?? link.fallbackDisplayReference;
                            // קישור עם עוגן-מילה: אות הסימון שמופיעה בגוף
                            // הטקסט מוצגת גם לפני כותרת ההערה.
                            if (link.anchorStart != null) {
                              final markerLetter = anchorMarkerLetter(link);
                              if (markerLetter != null) {
                                displayTitle = '($markerLetter) $displayTitle';
                              }
                            }
                            if (settingsState.replaceHolyNames) {
                              displayTitle =
                                  utils.replaceHolyNames(displayTitle);
                            }
                            final reportedTitle = displayTitle;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              widget.onLinkTitleRendered
                                  ?.call(link, reportedTitle);
                            });
                            return Text(
                              displayTitle,
                              style: TextStyle(
                                fontSize: widget.fontSize * 0.75,
                                fontWeight: FontWeight.normal,
                                fontFamily:
                                    settingsState.commentatorsFontFamily,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        widget.searchQueryListenable,
                        widget.currentSearchIndexListenable,
                        widget.totalSearchResultsListenable,
                        if (widget.highlightQueryListenable != null)
                          widget.highlightQueryListenable!,
                      ]),
                      builder: (context, _) {
                        // שדה החיפוש הפנימי גובר כשהוקלד בו; כשהוא ריק נופלים
                        // להדגשת מונח החיפוש החיצוני (מתוצאה שנחתה בהערה).
                        final internalQuery = widget.showSearch
                            ? widget.searchQueryListenable.value
                            : '';
                        final searchQuery = internalQuery.isNotEmpty
                            ? internalQuery
                            : (widget.highlightQueryListenable?.value ?? '');
                        final currentSearchIndex = (widget.showSearch ||
                                widget.highlightQueryListenable != null)
                            ? widget.getItemSearchIndex(link)
                            : 0;
                        return AppContextMenuRegion(
                          // לחיצה ימנית על הטקסט המסומן בפועל לא תשחרר את הבחירה
                          // (התנהגות ברירת המחדל של SelectableRegion ב-Windows);
                          // לחיצה על חלק לא-מסומן מבטלת כרגיל. אין כאן מעקב
                          // פר-שורה — הבחירה מנוהלת ע"י SelectionArea יחיד — לכן
                          // מחשבים את קטע הבחירה ישירות מול הפסקה שעליה לחצו.
                          shouldPreserveSelectionOnSecondaryTap:
                              (globalPosition) {
                            final selected =
                                widget.savedSelectedTextListenable.value;
                            if (selected == null || selected.isEmpty) {
                              return false;
                            }
                            final root = context.findRenderObject();
                            if (root == null) return true; // סלחני
                            return clickIsOnSelectionWithinArea(
                                  root: root,
                                  globalPosition: globalPosition,
                                  selectedText: selected,
                                ) ??
                                true; // לא הוכרע — סלחני
                          },
                          menuBuilder: (menuCtx, _) {
                            final savedTextAtBuild = captureSelectedTextForMenu(
                                widget.savedSelectedTextListenable);
                            return ContextMenuUtils.buildCommentaryContextMenu(
                              context: menuCtx,
                              link: link,
                              openBookCallback: widget.openBookCallback,
                              fontSize: widget.fontSize,
                              savedSelectedText: savedTextAtBuild,
                              onCopySelected: () =>
                                  ContextMenuUtils.copyFormattedText(
                                context: menuCtx,
                                savedSelectedText: (widget.restoreLineBreaks ??
                                    (s) => s)(savedTextAtBuild),
                                fontSize: widget.fontSize,
                                // במצב הפאנל/כרטיסייה אין מעקב פר-פריט אחר
                                // המפרש הנבחר (אין SelectionArea פר-פריט), לכן
                                // נופלים חזרה ל-link של הפריט שעליו נפתח התפריט.
                                link: widget.lastSelectedLinkListenable.value ??
                                    link,
                              ),
                            );
                          },
                          child: CommentaryContent(
                            key: ValueKey(
                                '${link.index1}_${link.path2}_${link.index2}'),
                            link: link,
                            fontSize: widget.fontSize,
                            openBookCallback: widget.openBookCallback,
                            removeNikud: widget.removeNikud,
                            removePunctuation: widget.removePunctuation,
                            searchQuery: searchQuery,
                            currentSearchIndex: currentSearchIndex,
                            onSearchResultsCountChanged: (widget.showSearch ||
                                    widget.highlightQueryListenable != null)
                                ? (count) => widget.updateSearchResultsCount(
                                      link,
                                      count,
                                    )
                                : null,
                            onSearchSnippetsChanged: widget.showSearch &&
                                    widget.updateSearchSnippets != null
                                ? (snippets) =>
                                    widget.updateSearchSnippets!(link, snippets)
                                : null,
                            onRendered: (text) =>
                                widget.onLinkRendered?.call(link, text),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              builder: (context, selectedText, child) => child!,
            );

            // הרשימה כולה עטופה ב-SelectionArea יחיד (בפאנל/בכרטיסייה/בתצוגה
            // המשולבת), ולכן מחזירים את התוכן ישירות — בלי SelectionArea
            // פר-פריט (שהיה הופך כל פריט ל"בלוק אטום" בבחירת מקלדת). עוטפים
            // ב-Listener שקוף כדי לזהות על איזה מפרש לחץ המשתמש (לייחוס בהעתקת
            // מקלדת Ctrl+C, שאין לה פריט-יעד).
            return Listener(
              onPointerDown: (_) => widget.onLinkPointerDown?.call(link),
              child: itemContent,
            );
          }),
        const Divider(height: 1),
      ],
    );
  }
}

class _CopyCommentaryIntent extends Intent {
  const _CopyCommentaryIntent();
}

/// תצוגת המפרש הוירטואלי 'הערות' — מציגה את גוף ההערות ה-inline
/// (<i class="footnote">) של השורות הנבחרות כאילו היו רשימת מפרשים.
class _NotesCommentaryWidget extends StatefulWidget {
  final List<String> notes;
  final double fontSize;
  final bool removeNikud;
  final Function(TextBookTab) openBookCallback;

  const _NotesCommentaryWidget({
    required this.notes,
    required this.fontSize,
    required this.removeNikud,
    required this.openBookCallback,
  });

  @override
  State<_NotesCommentaryWidget> createState() => _NotesCommentaryWidgetState();
}

class _NotesCommentaryWidgetState extends State<_NotesCommentaryWidget> {
  String? _selectedText;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        // SelectionArea משלו: הרשימה הזו מוחזרת *מחוץ* ל-SelectionArea של
        // רשימת המפרשים (שנבנה רק סביב ה-ListView), ולכן בלעדיו לא ניתן
        // לבחור טקסט בהערות כלל.
        return RtlSelectionShortcuts(
          child: SelectionArea(
            // ביטול תפריט ברירת המחדל של Flutter — נשתמש ב-AppContextMenuRegion.
            contextMenuBuilder: (context, _) => const SizedBox.shrink(),
            onSelectionChanged: (selection) =>
                _selectedText = selection?.plainText,
            child: AppContextMenuRegion(
              // לחיצה ימנית על טקסט מסומן לא תשחרר את הבחירה (ברירת המחדל של
              // SelectableRegion ב-Windows); לחיצה מחוץ לבחירה מבטלת כרגיל.
              shouldPreserveSelectionOnSecondaryTap: (globalPosition) {
                final selected = _selectedText;
                if (selected == null || selected.isEmpty) return false;
                final root = context.findRenderObject();
                if (root == null) return true;
                return clickIsOnSelectionWithinArea(
                      root: root,
                      globalPosition: globalPosition,
                      selectedText: selected,
                    ) ??
                    true;
              },
              menuBuilder: (menuCtx, _) => [
                AppContextMenuEntry(
                  label: 'העתק',
                  icon: FluentIcons.copy_24_regular,
                  enabled:
                      _selectedText != null && _selectedText!.trim().isNotEmpty,
                  onTap: () => ContextMenuUtils.copyFormattedText(
                    context: menuCtx,
                    savedSelectedText: _selectedText,
                    fontSize: widget.fontSize,
                  ),
                ),
              ],
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 12.0),
                      child: Text(
                        kNotesCommentatorTitle,
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.85,
                          fontWeight: FontWeight.bold,
                          fontFamily: settingsState.commentatorsFontFamily,
                        ),
                      ),
                    ),
                    ...widget.notes.map((note) {
                      return Padding(
                        padding: const EdgeInsets.only(
                            right: 32.0, left: 16.0, bottom: 12.0),
                        child: SmartTextWidget(
                          text: note,
                          settings: RenderSettings(
                            removeNikud: widget.removeNikud,
                            removePunctuation: false,
                            removeTeamim: false,
                            replaceHolyNames: settingsState.replaceHolyNames,
                            searchText: '',
                            currentSearchIndex: -1,
                            fontSize: widget.fontSize * 0.85,
                            fontFamily: settingsState.commentatorsFontFamily,
                            fontWeight: settingsState.commentatorsFontBold
                                ? FontWeight.bold
                                : null,
                            lineHeight: settingsState.lineHeight,
                          ),
                          onOpenBook: (tab) {
                            if (tab is TextBookTab) {
                              widget.openBookCallback(tab);
                            }
                          },
                        ),
                      );
                    }),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
