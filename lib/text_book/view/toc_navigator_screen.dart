import 'dart:async';
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
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
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

/// סף שמעליו עוברים לרשימה שטוחה ו-ListView.builder וירטואלי.
/// מתחת לסף - שומרים על המבנה הרקורסיבי (Column) שמתאים לספרים קטנים
/// וכן לחיפוש (לא דורש וירטואליזציה).
const int _kTocFlattenThreshold = 500;

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
    _tocScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _ensureParentsOpen(List<TocEntry> entries, int targetIndex) {
    final path = _findPath(entries, targetIndex);
    if (path.isEmpty) return;

    for (final entry in path) {
      if (entry.children.isNotEmpty && _expanded[entry.index] != true) {
        _expanded[entry.index] = true;
      }
    }
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

    final int? activeIndex = state.selectedIndex ??
        (state.visibleIndices.isNotEmpty
            ? closestTocEntryIndex(
                state.tableOfContents, state.visibleIndices.first)
            : null);

    if (activeIndex == null || activeIndex == _lastScrolledTocIndex) return;

    _ensureParentsOpen(state.tableOfContents, activeIndex);

    // החלטה בין מסלול וירטואלי לרקורסיבי - חייב להיות זהה ללוגיקה ב-build,
    // אחרת ננסה לגלול בקונטרולר שלא מחובר.
    final bool useFlat = searchController.text.isEmpty &&
        countAllTocEntries(state.tableOfContents) > _kTocFlattenThreshold;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isManuallyScrolling) return;

        if (useFlat) {
          // במסלול הוירטואלי הפריט הפעיל עשוי לא להיות בעץ. גוללים לפי
          // אינדקס ברשימה השטוחה דרך ItemScrollController, שמטפל בגלילה
          // לפריטים שאינם מורכבים.
          if (!_virtualScrollController.isAttached) return;
          final flat = flattenVisibleToc(state.tableOfContents, _expanded);
          final flatIndex =
              flat.indexWhere((item) => item.entry.index == activeIndex);
          if (flatIndex < 0) return;

          _virtualScrollController.scrollTo(
            index: flatIndex,
            alignment: 0.4, // קרוב למרכז, מעט מעל
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

        final scrollableBox = _tocScrollController
            .position.context.storageContext
            .findRenderObject() as RenderBox;

        final itemOffset = itemRenderObject
            .localToGlobal(Offset.zero, ancestor: scrollableBox)
            .dy;
        final viewportHeight = scrollableBox.size.height;
        final itemHeight = itemRenderObject.size.height;

        final target = _tocScrollController.offset +
            itemOffset -
            (viewportHeight / 2) +
            (itemHeight / 2);

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

  Widget _buildFilteredList(
      List<TocEntry> entries, BuildContext context, int? activeIndex) {
    final normalizedQuery = utils.removeVolwels(
        SearchQueryBuilder.sanitizeQuery(searchController.text).trim());
    if (normalizedQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    final filteredEntries =
        filterTocEntriesForSearch(entries, searchController.text);

    return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: filteredEntries.length,
        itemBuilder: (context, index) => _buildTocItem(
              filteredEntries[index],
              isFirstChild: index == 0,
              showFullText: true,
              defaultExpanded: shouldExpandInSearch(
                _expanded[filteredEntries[index].index],
              ),
              activeIndex: activeIndex,
            ));
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
      unawaited(scrollToSourceLine(
        scrollController: widget.scrollController,
        scrollOffsetController: state.scrollOffsetController,
        positionsListener: state.positionsListener,
        segments: state.readingSegments,
        lineIndex: entry.index,
        viewportExtent:
            context.size?.height ?? MediaQuery.sizeOf(context).height,
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
      ));
      if (Platform.isAndroid) {
        widget.closeLeftPaneCallback();
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
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3)
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
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3)
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

  /// מסלול וירטואלי לספרים עם הרבה ערכי TOC. שיטוח העץ הגלוי לרשימה
  /// שטוחה והעברתה ל-ScrollablePositionedList - בונה רק את הפריטים הנראים
  /// על המסך (~30) במקום את כל אלפי הערכים. נבחר ScrollablePositionedList
  /// (ולא ListView.builder רגיל) כי הוא תומך בגלילה לפי אינדקס פריט גם
  /// כשהפריט הפעיל עוד לא נבנה בעץ - תנאי הכרחי ל-_scrollToActiveItem.
  Widget _buildVirtualizedTocList(List<TocEntry> entries, int? activeIndex) {
    final flat = flattenVisibleToc(entries, _expanded);
    return ScrollablePositionedList.builder(
      itemScrollController: _virtualScrollController,
      itemPositionsListener: _virtualPositionsListener,
      itemCount: flat.length,
      itemBuilder: (context, index) {
        final item = flat[index];
        return _buildTocRow(
          item.entry,
          activeIndex: activeIndex,
          isExpanded: item.isExpanded,
        );
      },
    );
  }

  // אופטימיזציה: activeIndex מחושב פעם אחת ב-build הראשי ומועבר כפרמטר.
  // לפני האופטימיזציה כל ערך עטף BlocBuilder<TextBookBloc> וקרא בעצמו
  // ל-closestTocEntryIndex (O(n)), מה שיצר O(n²) בספרים עם אלפי ערכי TOC.
  Widget _buildTocItem(TocEntry entry,
      {bool showFullText = false,
      bool isFirstChild = false,
      bool? defaultExpanded,
      required int? activeIndex}) {
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
          ...entry.children.asMap().entries.map((e) => _buildTocItem(
                e.value,
                isFirstChild: isFirstChild && e.key == 0,
                defaultExpanded: defaultExpanded,
                showFullText: showFullText,
                activeIndex: activeIndex,
              )),
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
            final int? activeIndex = state.selectedIndex ??
                (state.visibleIndices.isNotEmpty
                    ? closestTocEntryIndex(
                        state.tableOfContents, state.visibleIndices.first)
                    : null);

            // החלטה בין מסלול רקורסיבי לוירטואלי. וירטואליזציה מופעלת רק
            // כשיש הרבה ערכי TOC ולא במצב חיפוש (החיפוש כבר מצמצם את התוצאות).
            final bool useFlat = searchController.text.isEmpty &&
                countAllTocEntries(state.tableOfContents) >
                    _kTocFlattenThreshold;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: RtlTextField(
                    controller: searchController,
                    onChanged: (value) => setState(() {}),
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
                                setState(() {
                                  searchController.clear();
                                });
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
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
                            state.tableOfContents, activeIndex)
                        : SingleChildScrollView(
                            controller: _tocScrollController,
                            child: searchController.text.isEmpty
                                ? ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: state.tableOfContents.length,
                                    itemBuilder: (context, index) =>
                                        _buildTocItem(
                                            state.tableOfContents[index],
                                            isFirstChild: index == 0,
                                            activeIndex: activeIndex))
                                : _buildFilteredList(state.tableOfContents,
                                    context, activeIndex),
                          ),
                  ),
                ),
              ],
            );
          }),
    );
  }
}
