import 'dart:async';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/view/toc_filter.dart';
import 'package:otzaria/text_book/view/toc_navigator_internals.dart';

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

  // הסינון רץ על השאילתה שהוחלה, ולא על כל תו בזמן ההקלדה.
  Timer? _searchDebounce;
  String _appliedQuery = '';

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
      setState(() => _appliedQuery = '');
      return;
    }
    // רענון מיידי של השדה (כפתור הניקוי) - הסינון עצמו ממתין לטיימר,
    // וה-build בינתיים חוזר לתוצאה הממוטמנת של _appliedQuery.
    setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _appliedQuery = value);
    });
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

    // החלטה בין מסלול וירטואלי לרקורסיבי - חייב להיות זהה ללוגיקה ב-build,
    // אחרת ננסה לגלול בקונטרולר שלא מחובר.
    final display = _displayDataFor(state.tableOfContents);
    final bool useFlat = display.totalCount > _kTocFlattenThreshold;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isManuallyScrolling) return;

        if (useFlat) {
          // במסלול הוירטואלי הפריט הפעיל עשוי לא להיות בעץ. גוללים לפי
          // אינדקס ברשימה השטוחה דרך ItemScrollController, שמטפל בגלילה
          // לפריטים שאינם מורכבים.
          if (!_virtualScrollController.isAttached) return;
          final flat = _flatItemsFor(display);
          final flatIndex = flat.indexWhere(
            (item) => item.entry.index == activeIndex,
          );
          if (flatIndex < 0) return;

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
            _lastScrolledTocIndex = activeIndex;
            return;
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
          _lastScrolledTocIndex = activeIndex;
          return;
        }

        // מסלול רקורסיבי - הפריט תמיד בנוי בעץ, ניתן להשתמש ב-GlobalKey
        final key = _tocItemKeys[activeIndex];
        final itemContext = key?.currentContext;
        if (itemContext == null) return;

        final itemRenderObject = itemContext.findRenderObject();
        if (itemRenderObject is! RenderBox) return;

        final scrollableBox =
            _tocScrollController.position.context.storageContext
                    .findRenderObject()
                as RenderBox;

        final itemOffset = itemRenderObject
            .localToGlobal(Offset.zero, ancestor: scrollableBox)
            .dy;
        final viewportHeight = scrollableBox.size.height;
        final itemHeight = itemRenderObject.size.height;

        final itemBottom = itemOffset + itemHeight;
        // כבר גלוי במלואו - לא גוללים.
        if (itemOffset >= 0 && itemBottom <= viewportHeight) {
          _lastScrolledTocIndex = activeIndex;
          return;
        }

        // לא גלוי - גוללים לקצה הקרוב (עליון/תחתון), לא למרכז.
        const double margin = 8.0;
        final double target = itemOffset < 0
            ? _tocScrollController.offset + itemOffset - margin
            : _tocScrollController.offset +
                  (itemBottom - viewportHeight) +
                  margin;

        _tocScrollController.animateTo(
          target.clamp(
            0.0,
            _tocScrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );

        _lastScrolledTocIndex = activeIndex;
      });
    });
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
  }) {
    final itemKey = _tocItemKeys.putIfAbsent(entry.index, () => GlobalKey());
    void navigateToEntry() {
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
        lineIndex: entry.index,
        viewportExtent:
            context.size?.height ?? MediaQuery.sizeOf(context).height,
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

    final bool selected = activeIndex == entry.index;

    if (entry.children.isEmpty) {
      return InkWell(
        key: itemKey,
        onTap: navigateToEntry,
        child: Container(
          padding: EdgeInsets.only(
            right: 16.0 + (entry.level * 24.0),
            left: 16.0,
            top: 10.0,
            bottom: 10.0,
          ),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.text_bullet_list_24_regular,
                color: Theme.of(context).colorScheme.secondary,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  showFullText ? entry.fullText : entry.text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ערך עם ילדים (header בלבד - בלי לרנדר את הילדים).
    return Container(
      key: itemKey,
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // אזור הטקסט לניווט
          Expanded(
            child: InkWell(
              onTap: navigateToEntry,
              child: Container(
                padding: EdgeInsets.only(
                  right: 16.0 + (entry.level * 24.0),
                  left: 8.0,
                  top: 12.0,
                  bottom: 12.0,
                ),
                child: Row(
                  children: [
                    Icon(
                      // רק רמה 1 מקבלת אייקון ספר, שאר הרמות מקבלות רשימה
                      entry.level == 1
                          ? FluentIcons.book_24_regular
                          : FluentIcons.text_bullet_list_24_regular,
                      color: entry.level == 1
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                      size: entry.level == 1 ? 20 : 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        showFullText ? entry.fullText : entry.text,
                        style: TextStyle(
                          fontSize: entry.level == 1 ? 15 : 14,
                          fontWeight: entry.level == 1
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: entry.level == 1
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // כפתור החץ לפתיחה/סגירה
          InkWell(
            onTap: () {
              setState(() {
                _expanded[entry.index] = !isExpanded;
                _expandedRevision++;
              });
            },
            child: Container(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 8.0,
                top: 12.0,
                bottom: 12.0,
              ),
              child: Icon(
                isExpanded
                    ? FluentIcons.chevron_up_24_regular
                    : FluentIcons.chevron_down_24_regular,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// בונה רשימה וירטואלית מהעץ השטוח והממוטמן.
  Widget _buildVirtualizedTocList(
    List<TocFlatItem> flat,
    int? activeIndex, {
    required bool isSearching,
  }) {
    return ScrollablePositionedList.builder(
      itemScrollController: _virtualScrollController,
      itemPositionsListener: _virtualPositionsListener,
      itemCount: flat.length,
      itemBuilder: (context, index) {
        final item = flat[index];
        return _buildTocRow(
          item.entry,
          showFullText: isSearching,
          activeIndex: activeIndex,
          isExpanded: item.isExpanded,
        );
      },
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
  }) {
    if (entry.children.isEmpty) {
      return _buildTocRow(
        entry,
        showFullText: showFullText,
        activeIndex: activeIndex,
        isExpanded: false,
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
        ),
        if (isExpanded)
          ...entry.children.asMap().entries.map(
            (e) => _buildTocItem(
              e.value,
              isFirstChild: isFirstChild && e.key == 0,
              defaultExpanded: defaultExpanded,
              showFullText: showFullText,
              activeIndex: activeIndex,
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
          final display = _displayDataFor(state.tableOfContents);
          final bool useFlat = display.totalCount > _kTocFlattenThreshold;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: RtlTextField(
                  controller: searchController,
                  onChanged: _onSearchChanged,
                  // ללא autofocus: הפוקוס מנוהל אך ורק דרך focusNode מהמסך
                  // האב (_focusActiveTabSearchField), שמכבד את ההגנה מפני
                  // פוקוס אוטומטי באנדרואיד. autofocus היה עוקף הגנה זו.
                  focusNode: widget.focusNode,
                  onSubmitted: (_) {
                    widget.focusNode.requestFocus();
                  },
                  decoration: InputDecoration(
                    hintText: 'איתור כותרת...',
                    prefixIcon: const Icon(FluentIcons.search_24_regular),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: () {
                              searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      setState(() {
                        _isManuallyScrolling = true;
                      });
                    } else if (notification is ScrollEndNotification) {
                      setState(() {
                        _isManuallyScrolling = false;
                      });
                    }
                    return false;
                  },
                  child: useFlat
                      ? _buildVirtualizedTocList(
                          _flatItemsFor(display),
                          activeIndex,
                          isSearching: display.isSearching,
                        )
                      : SingleChildScrollView(
                          controller: _tocScrollController,
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: display.entries.length,
                            itemBuilder: (context, index) => _buildTocItem(
                              display.entries[index],
                              isFirstChild: index == 0,
                              showFullText: display.isSearching,
                              defaultExpanded: display.isSearching
                                  ? shouldExpandInSearch(
                                      _expanded[display.entries[index].index],
                                    )
                                  : null,
                              activeIndex: activeIndex,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
