import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/toc_filter.dart';
import 'package:otzaria/text_book/view/toc_navigator_internals.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

class TocViewer extends StatefulWidget {
  const TocViewer({
    super.key,
    required this.scrollController,
    required this.closeLeftPaneCallback,
    required this.focusNode,
  });

  final void Function() closeLeftPaneCallback;
  final ItemScrollController scrollController;
  final FocusNode focusNode;

  @override
  State<TocViewer> createState() => _TocViewerState();
}

/// סף שמעליו עוברים לרשימה וירטואלית שטוחה.
const int _kTocFlattenThreshold = 500;

class _TocDisplayData {
  final List<TocEntry> entries;
  final int totalCount;
  final bool isSearching;

  const _TocDisplayData(this.entries, this.totalCount, this.isSearching);
}

class _TocViewerState extends State<TocViewer>
    with AutomaticKeepAliveClientMixin<TocViewer> {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController searchController = TextEditingController();
  final ScrollController _tocScrollController = ScrollController();
  final Map<int, GlobalKey> _tocItemKeys = {};
  bool _isManuallyScrolling = false;
  int? _lastScrolledTocIndex;
  final Map<int, bool> _expanded = {};

  // הסינון והספירה משתנים רק כשהספר או השאילתה משתנים.
  List<TocEntry>? _displaySource;
  String? _displayQuery;
  _TocDisplayData? _displayResult;

  // השיטוח משתנה רק כשהתצוגה או מצב ההרחבה משתנים.
  _TocDisplayData? _flatDisplay;
  List<TocFlatItem>? _flatResult;
  int _expandedRevision = 0;
  int _flatExpandedRevision = -1;

  List<TocEntry>? _collapsedSource;
  Map<int, bool> _collapsedExpansion = const {};

  // הסינון רץ על השאילתה שהוחלה, ולא על כל תו בזמן ההקלדה.
  Timer? _searchDebounce;
  String _appliedQuery = '';

  // סימון הדפדוף בחיצים בין תוצאות החיפוש (index של TocEntry). הפוקוס נשאר
  // בשדה החיפוש, כמו ב"איתור". מתאפס בכל שינוי שאילתה.
  int? _highlightedEntryIndex;

  // משמשים במסלול הוירטואלי בלבד. ScrollablePositionedList מאפשר גלילה
  // לפי אינדקס פריט גם אם הפריט עוד לא נבנה בעץ.
  final ItemScrollController _virtualScrollController = ItemScrollController();
  final ItemPositionsListener _virtualPositionsListener =
      ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    // הפאנל בונה את TocViewer רק כשהוא נפתח, כלומר showLeftPane כבר true
    // וה-BlocListener לא יירה על ה-state ההתחלתי. גלילה ראשונית למיקום הפעיל.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<TextBookBloc>().state;
      if (state is TextBookLoaded) _scrollToActiveItem(state);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tocScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  /// מחיל את השאילתה בהשהיה, כדי שההקלדה עצמה לא תחכה לסינון.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // ניקוי הוא חזרה לעץ המלא - זול, ואין סיבה להשהות אותו.
    if (value.isEmpty) {
      setState(() {
        _appliedQuery = '';
        _highlightedEntryIndex = null;
      });
      return;
    }
    // רענון מיידי של השדה (כפתור הניקוי) - הסינון עצמו ממתין לטיימר,
    // וה-build בינתיים חוזר לתוצאה הממוטמנת של _appliedQuery.
    setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _appliedQuery = value;
        _highlightedEntryIndex = null;
      });
    });
  }

  /// מזיז את סימון הדפדוף בין תוצאות החיפוש בלי להוציא את הפוקוס מהשדה.
  void _moveHighlight(int delta) {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    final display = _displayDataFor(state.tableOfContents);
    if (!display.isSearching) return;
    final flat = _flatItemsFor(display);
    if (flat.isEmpty) return;

    final current = _highlightedEntryIndex == null
        ? -1
        : flat.indexWhere((item) => item.entry.index == _highlightedEntryIndex);
    final start = current >= 0 ? current : (delta >= 0 ? -1 : flat.length);
    final next = (start + delta).clamp(0, flat.length - 1);
    if (next == current) return;

    final targetIndex = flat[next].entry.index;
    setState(() => _highlightedEntryIndex = targetIndex);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _displayDataFor(state.tableOfContents);
      _scrollEntryIntoView(
        targetIndex,
        display: current,
        useFlat: current.totalCount > _kTocFlattenThreshold,
      );
    });
  }

  /// גולל את הספר אל השורה של ערך ה-TOC (לחיצה על שורה או אנטר בחיפוש).
  void _navigateToLine(int lineIndex) {
    setState(() {
      _isManuallyScrolling = false;
      _lastScrolledTocIndex = null;
    });
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }
    final navigation = scrollToSourceLine(
      scrollController: widget.scrollController,
      scrollOffsetController: state.scrollOffsetController,
      positionsListener: state.positionsListener,
      segments: state.readingSegments,
      lineIndex: lineIndex,
      viewportExtent: context.size?.height ?? MediaQuery.sizeOf(context).height,
      duration: const Duration(milliseconds: 250),
      curve: Curves.ease,
    );
    if (Platform.isAndroid) {
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

  /// אנטר בשדה החיפוש: פתיחת התוצאה המסומנת, ובהיעדר סימון — הראשונה.
  void _openHighlightedEntry() {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    final display = _displayDataFor(state.tableOfContents);
    if (!display.isSearching) return;
    final flat = _flatItemsFor(display);
    if (flat.isEmpty) return;

    final target = _highlightedEntryIndex == null
        ? flat.first.entry.index
        : _highlightedEntryIndex!;
    _navigateToLine(target);
  }

  void _ensureParentsOpen(List<TocEntry> entries, int targetIndex) {
    final path = _findPath(entries, targetIndex);
    if (path.isEmpty) return;

    var changed = false;
    for (final entry in path) {
      if (entry.children.isNotEmpty && _expanded[entry.index] != true) {
        _expanded[entry.index] = true;
        changed = true;
      }
    }
    if (changed) _expandedRevision++;
  }

  List<TocEntry> _findPath(List<TocEntry> entries, int targetIndex) {
    for (final entry in entries) {
      if (entry.index == targetIndex) {
        return [entry];
      }

      final subPath = _findPath(entry.children, targetIndex);
      if (subPath.isNotEmpty) {
        return [entry, ...subPath];
      }
    }
    return [];
  }

  void _scrollToActiveItem(TextBookLoaded state) {
    if (_isManuallyScrolling) return;
    // כשהפאנל סגור הגלילה נכשלת (רוחב 0) אך משבשת את _lastScrolledTocIndex
    // ואז חוסמת את הגלילה האמיתית בפתיחה הבאה.
    if (!state.showLeftPane) return;

    final int? activeIndex =
        state.selectedIndex ??
        (state.visibleIndices.isNotEmpty
            ? closestTocEntryIndex(
                state.tableOfContents,
                state.visibleIndices.first,
              )
            : null);

    if (activeIndex == null || activeIndex == _lastScrolledTocIndex) return;

    _ensureParentsOpen(state.tableOfContents, activeIndex);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isManuallyScrolling) return;
        // ההחלטה וירטואלי/רקורסיבי נלקחת כאן ולא בזמן התזמון: שני frames
        // עברו, וניקוי חיפוש בינתיים מחליף מסלול ומנתק את בקר הגלילה.
        final display = _displayDataFor(state.tableOfContents);
        final bool useFlat = display.totalCount > _kTocFlattenThreshold;
        if (_scrollEntryIntoView(
          activeIndex,
          display: display,
          useFlat: useFlat,
        )) {
          _lastScrolledTocIndex = activeIndex;
        }
      });
    });
  }

  /// גולל את הערך אל תוך אזור התצוגה אם אינו גלוי במלואו.
  /// מחזיר אמת כשהערך גלוי או שהגלילה בוצעה, ושקר כשהערך לא נמצא.
  bool _scrollEntryIntoView(
    int targetIndex, {
    required _TocDisplayData display,
    required bool useFlat,
  }) {
    if (useFlat) {
      // במסלול הוירטואלי הפריט עשוי לא להיות בעץ. גוללים לפי אינדקס ברשימה
      // השטוחה דרך ItemScrollController, שמטפל בגלילה לפריטים שאינם מורכבים.
      if (!_virtualScrollController.isAttached) return false;
      final flat = _flatItemsFor(display);
      final flatEntryIndex = flat.indexWhere(
        (item) => item.entry.index == targetIndex,
      );
      if (flatEntryIndex < 0) return false;
      // +1: פריט 0 ברשימה הוא הכותרת הראשית.
      final flatIndex = flatEntryIndex + 1;

      final positions = _virtualPositionsListener.itemPositions.value;
      ItemPosition? current;
      for (final p in positions) {
        if (p.index == flatIndex) {
          current = p;
          break;
        }
      }
      // כבר גלוי במלואו - לא גוללים.
      if (current != null &&
          current.itemLeadingEdge >= 0 &&
          current.itemTrailingEdge <= 1) {
        return true;
      }

      // לא גלוי - מביאים לקצה הקרוב (עליון/תחתון), לא למרכז.
      final bool below = current != null
          ? current.itemLeadingEdge >= 1
          : (positions.isNotEmpty &&
                flatIndex >
                    positions
                        .map((p) => p.index)
                        .reduce((a, b) => a > b ? a : b));
      _virtualScrollController.scrollTo(
        index: flatIndex,
        alignment: below ? 0.85 : 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return true;
    }

    // מסלול רקורסיבי - הפריט תמיד בנוי בעץ, ניתן להשתמש ב-GlobalKey
    final key = _tocItemKeys[targetIndex];
    final itemContext = key?.currentContext;
    if (itemContext == null) return false;

    final itemRenderObject = itemContext.findRenderObject();
    if (itemRenderObject is! RenderBox) return false;

    final scrollableBox =
        _tocScrollController.position.context.storageContext.findRenderObject()
            as RenderBox;

    final itemOffset = itemRenderObject
        .localToGlobal(Offset.zero, ancestor: scrollableBox)
        .dy;
    final viewportHeight = scrollableBox.size.height;
    final itemHeight = itemRenderObject.size.height;

    final itemBottom = itemOffset + itemHeight;
    // כבר גלוי במלואו - לא גוללים.
    if (itemOffset >= 0 && itemBottom <= viewportHeight) {
      return true;
    }

    // לא גלוי - גוללים לקצה הקרוב (עליון/תחתון), לא למרכז.
    const double margin = 8.0;
    final double target = itemOffset < 0
        ? _tocScrollController.offset + itemOffset - margin
        : _tocScrollController.offset + (itemBottom - viewportHeight) + margin;

    _tocScrollController.animateTo(
      target.clamp(
        0.0,
        _tocScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    return true;
  }

  _TocDisplayData _displayDataFor(List<TocEntry> tableOfContents) {
    final query = _appliedQuery;
    if (!identical(_displaySource, tableOfContents) || _displayQuery != query) {
      final isSearching = query.isNotEmpty;
      final entries = isSearching
          ? filterTocEntriesForSearch(tableOfContents, query)
          : tableOfContents;
      _displaySource = tableOfContents;
      _displayQuery = query;
      _displayResult = _TocDisplayData(
        entries,
        countAllTocEntries(entries),
        isSearching,
      );
      _flatDisplay = null;
      _flatResult = null;
      _flatExpandedRevision = -1;
    }
    return _displayResult!;
  }

  List<TocFlatItem> _flatItemsFor(_TocDisplayData display) {
    if (!identical(_flatDisplay, display) ||
        _flatExpandedRevision != _expandedRevision) {
      _flatDisplay = display;
      _flatExpandedRevision = _expandedRevision;
      _flatResult = flattenVisibleToc(
        display.entries,
        _expanded,
        expandByDefault: display.isSearching,
      );
    }
    return _flatResult!;
  }

  /// בונה שורה יחידה של TOC ללא ילדיו. משמש בשני המסלולים:
  /// 1. הרקורסיבי (`_buildTocItem`) - לספרים קטנים עם Column מקונן.
  /// 2. השטוח (`_buildVirtualizedTocList`) - לספרים גדולים עם וירטואליזציה.
  Widget _buildTocRow(
    TocEntry entry, {
    bool showFullText = false,
    required int? activeIndex,
    required bool isExpanded,
    bool isGroupStart = false,
    bool isGroupEnd = false,
  }) {
    final itemKey = _tocItemKeys.putIfAbsent(entry.index, () => GlobalKey());
    void navigateToEntry() => _navigateToLine(entry.index);

    // בזמן דפדוף בחיצים הסימון הוא של תוצאת הדפדוף, לא של מיקום הקריאה.
    final bool selected = _highlightedEntryIndex != null
        ? _highlightedEntryIndex == entry.index
        : activeIndex == entry.index;
    final title = showFullText ? entry.fullText : entry.text;
    // רמות ה-TOC מתחילות ב-1, ורמת ההזחה של עץ הניווט מתחילה ב-0.
    final level = (entry.level - 1).clamp(0, 100);

    final hasChildren = entry.children.isNotEmpty;
    final tile = NavTreeTile.heading(
      title: title,
      level: level,
      isSelected: selected,
      isExpanded: isExpanded,
      hasChildren: hasChildren,
      onTap: navigateToEntry,
      onToggleExpand: hasChildren
          ? () {
              setState(() {
                _expanded[entry.index] = !isExpanded;
                _expandedRevision++;
              });
            }
          : null,
    );

    return NavTreeGroupCard(
      isGroupStart: isGroupStart,
      isGroupEnd: isGroupEnd,
      child: KeyedSubtree(key: itemKey, child: tile),
    );
  }

  /// כותרת העץ עם כפתור "כווץ/הרחב הכל", שמוצג רק כשיש מה לכווץ.
  Widget _buildTreeHeader(String title, _TocDisplayData display) {
    Widget? toggle;
    if (!display.isSearching) {
      if (!identical(_collapsedSource, display.entries)) {
        _collapsedSource = display.entries;
        _collapsedExpansion = collapsedTocExpansion(display.entries);
      }
      if (_collapsedExpansion.containsValue(false)) {
        final collapsed = isTocCollapsed(
          _flatItemsFor(display),
          _collapsedExpansion,
        );
        toggle = SizedBox.square(
          dimension: 28,
          child: IconButton(
            tooltip: collapsed ? 'הרחב הכל' : 'כווץ הכל',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              collapsed
                  ? FluentIcons.arrow_expand_all_24_regular
                  : FluentIcons.arrow_collapse_all_24_regular,
              size: 18,
            ),
            onPressed: () => setState(() {
              _expanded
                ..clear()
                ..addAll(
                  collapsed
                      ? expandedTocExpansion(display.entries)
                      : _collapsedExpansion,
                );
              _expandedRevision++;
            }),
          ),
        );
      }
    }
    return NavTreeHeader(
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [?toggle, const NavPanelSearchToggle()],
      ),
    );
  }

  /// בונה רשימה וירטואלית מהעץ השטוח והממוטמן.
  Widget _buildVirtualizedTocList(
    List<TocFlatItem> flat,
    int? activeIndex, {
    required bool isSearching,
    required String title,
    required _TocDisplayData display,
  }) {
    return ScrollablePositionedList.builder(
      itemScrollController: _virtualScrollController,
      itemPositionsListener: _virtualPositionsListener,
      // +1 עבור הכותרת הראשית, שנגללת עם הרשימה (פריט 0).
      itemCount: flat.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTreeHeader(title, display);
        }
        final item = flat[index - 1];
        return _buildTocRow(
          item.entry,
          showFullText: isSearching,
          activeIndex: activeIndex,
          isExpanded: item.isExpanded,
          isGroupStart: index == 1,
          isGroupEnd: index == flat.length,
        );
      },
      padding: kNavTreeListPadding,
    );
  }

  // אופטימיזציה: activeIndex מחושב פעם אחת ב-build הראשי ומועבר כפרמטר.
  // לפני האופטימיזציה כל ערך עטף BlocBuilder<TextBookBloc> וקרא בעצמו
  // ל-closestTocEntryIndex (O(n)), מה שיצר O(n²) בספרים עם אלפי ערכי TOC.
  Widget _buildTocItem(
    TocEntry entry, {
    bool showFullText = false,
    bool isFirstChild = false,
    bool? defaultExpanded,
    required int? activeIndex,
    bool isGroupStart = false,
    bool isGroupEnd = false,
  }) {
    if (entry.children.isEmpty) {
      return _buildTocRow(
        entry,
        showFullText: showFullText,
        activeIndex: activeIndex,
        isExpanded: false,
        isGroupStart: isGroupStart,
        isGroupEnd: isGroupEnd,
      );
    }

    final bool fallbackExpanded = entry.level == 1 || isFirstChild;
    final bool isExpanded =
        _expanded[entry.index] ?? (defaultExpanded ?? fallbackExpanded);

    return Column(
      children: [
        _buildTocRow(
          entry,
          showFullText: showFullText,
          activeIndex: activeIndex,
          isExpanded: isExpanded,
          isGroupStart: isGroupStart,
          // הקבוצה נסגרת אצל הצאצא האחרון כשהערך פתוח.
          isGroupEnd: isGroupEnd && !isExpanded,
        ),
        if (isExpanded)
          ...entry.children.asMap().entries.map(
            (e) => _buildTocItem(
              e.value,
              isFirstChild: isFirstChild && e.key == 0,
              defaultExpanded: defaultExpanded,
              showFullText: showFullText,
              activeIndex: activeIndex,
              isGroupEnd: isGroupEnd && e.key == entry.children.length - 1,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocListener<TextBookBloc, TextBookState>(
      listenWhen: (previous, current) {
        if (current is! TextBookLoaded) return false;
        if (previous is! TextBookLoaded) return true;

        // הפעל רק אם האינדקס הנבחר או האינדקס הנראה השתנו
        final prevVisibleIndex = previous.visibleIndices.isNotEmpty
            ? previous.visibleIndices.first
            : -1;
        final currVisibleIndex = current.visibleIndices.isNotEmpty
            ? current.visibleIndices.first
            : -1;

        return previous.selectedIndex != current.selectedIndex ||
            prevVisibleIndex != currVisibleIndex ||
            previous.showLeftPane != current.showLeftPane;
      },
      listener: (context, state) {
        if (state is TextBookLoaded) {
          _scrollToActiveItem(state);
        }
      },
      child: BlocBuilder<TextBookBloc, TextBookState>(
        bloc: context.read<TextBookBloc>(),
        // אופטימיזציה: build רק כש-activeIndex עשוי להשתנות. בלי buildWhen
        // הבנייה הייתה רצה בכל emit של ה-bloc (גם בגלילה רגילה),
        // ובספרים עם אלפי ערכי TOC זה יצר frames של 5+ שניות.
        buildWhen: (previous, current) {
          if (current is! TextBookLoaded) return true;
          if (previous is! TextBookLoaded) return true;
          final prevFirst = previous.visibleIndices.isNotEmpty
              ? previous.visibleIndices.first
              : -1;
          final currFirst = current.visibleIndices.isNotEmpty
              ? current.visibleIndices.first
              : -1;
          return previous.selectedIndex != current.selectedIndex ||
              prevFirst != currFirst ||
              !identical(previous.tableOfContents, current.tableOfContents);
        },
        builder: (context, state) {
          if (state is! TextBookLoaded) return const Center();
          // חישוב יחיד של ה"ערך הפעיל" - מועבר כפרמטר ל-_buildTocItem
          // במקום שכל פריט יחשב בעצמו (שזה מה שיצר את ה-O(n²)).
          final int? activeIndex =
              state.selectedIndex ??
              (state.visibleIndices.isNotEmpty
                  ? closestTocEntryIndex(
                      state.tableOfContents,
                      state.visibleIndices.first,
                    )
                  : null);

          // גם חיפוש עשוי להציג עשרות אלפי ערכים, ולכן הסף נגזר מהפלט.
          final display = _displayDataFor(
            state.tableOfContents,
          );
          final bool useFlat = display.totalCount > _kTocFlattenThreshold;

          final delegate = NavPanelSearchDelegate(
            controller: searchController,
            hintText: 'איתור כותרת...',
            focusNode: widget.focusNode,
            onChanged: _onSearchChanged,
            onSubmitted: (_) {
              _openHighlightedEntry();
              widget.focusNode.requestFocus();
            },
            onClear: () => _onSearchChanged(''),
            onArrowDown: display.isSearching ? () => _moveHighlight(1) : null,
            onArrowUp: display.isSearching ? () => _moveHighlight(-1) : null,
          );
          return NavPanelCollapsibleSearch(
            delegate: delegate,
            child: display.isSearching && display.entries.isEmpty
                ? const OtzariaEmptyState(
                    isCompact: true,
                    icon: OtzariaIcons.search_in_titles_24_regular,
                    title: 'לא נמצאו תוצאות',
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification &&
                          notification.dragDetails != null) {
                        _isManuallyScrolling = true;
                      } else if (notification is ScrollEndNotification) {
                        _isManuallyScrolling = false;
                      }
                      return false;
                    },
                    child: NavTreeFocusGroup(
                      child: useFlat
                          ? _buildVirtualizedTocList(
                              _flatItemsFor(display),
                              activeIndex,
                              isSearching: display.isSearching,
                              title: state.book.title,
                              display: display,
                            )
                          : SingleChildScrollView(
                              controller: _tocScrollController,
                              padding: kNavTreeListPadding,
                              child: Column(
                                children: [
                                  _buildTreeHeader(state.book.title, display),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: display.entries.length,
                                    itemBuilder: (context, index) =>
                                        _buildTocItem(
                                          display.entries[index],
                                          isFirstChild: index == 0,
                                          isGroupStart: index == 0,
                                          isGroupEnd:
                                              index ==
                                              display.entries.length - 1,
                                          showFullText: display.isSearching,
                                          defaultExpanded: display.isSearching
                                              ? shouldExpandInSearch(
                                                  _expanded[display
                                                      .entries[index]
                                                      .index],
                                                )
                                              : null,
                                          activeIndex: activeIndex,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
