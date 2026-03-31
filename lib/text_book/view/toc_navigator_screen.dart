import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/view/toc_filter.dart';

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

    final int? activeIndex = state.selectedIndex ??
        (state.visibleIndices.isNotEmpty
            ? closestTocEntryIndex(
                state.tableOfContents, state.visibleIndices.first)
            : null);

    if (activeIndex == null || activeIndex == _lastScrolledTocIndex) return;

    _ensureParentsOpen(state.tableOfContents, activeIndex);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isManuallyScrolling) return;

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

  Widget _buildFilteredList(List<TocEntry> entries, BuildContext context) {
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
            ));
  }

  Widget _buildTocItem(TocEntry entry,
      {bool showFullText = false,
      bool isFirstChild = false,
      bool? defaultExpanded}) {
    final itemKey = _tocItemKeys.putIfAbsent(entry.index, () => GlobalKey());
    void navigateToEntry() {
      setState(() {
        _isManuallyScrolling = false;
        _lastScrolledTocIndex = null;
      });
      // תמיד השתמש ב-scrollController - זה עובד גם בצורת הדף
      widget.scrollController.scrollTo(
        index: entry.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
      );
      if (Platform.isAndroid) {
        widget.closeLeftPaneCallback();
      }
    }

    if (entry.children.isEmpty) {
      return BlocBuilder<TextBookBloc, TextBookState>(
        key: itemKey,
        builder: (context, state) {
          final int? autoIndex = state is TextBookLoaded &&
                  state.selectedIndex == null &&
                  state.visibleIndices.isNotEmpty
              ? closestTocEntryIndex(
                  state.tableOfContents, state.visibleIndices.first)
              : null;
          final bool selected = state is TextBookLoaded &&
              ((state.selectedIndex != null &&
                      state.selectedIndex == entry.index) ||
                  autoIndex == entry.index);

          return InkWell(
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      final bool fallbackExpanded = entry.level == 1 || isFirstChild;
      final bool isExpanded =
          _expanded[entry.index] ?? (defaultExpanded ?? fallbackExpanded);

      return Column(
        key: itemKey,
        children: [
          BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, state) {
              final int? autoIndex = state is TextBookLoaded &&
                      state.selectedIndex == null &&
                      state.visibleIndices.isNotEmpty
                  ? closestTocEntryIndex(
                      state.tableOfContents, state.visibleIndices.first)
                  : null;
              final bool selected = state is TextBookLoaded &&
                  ((state.selectedIndex != null &&
                          state.selectedIndex == entry.index) ||
                      autoIndex == entry.index);

              return Container(
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
            },
          ),
          if (isExpanded)
            ...entry.children.asMap().entries.map((e) => _buildTocItem(
                  e.value,
                  isFirstChild: isFirstChild && e.key == 0,
                  defaultExpanded: defaultExpanded,
                  showFullText: showFullText,
                )),
        ],
      );
    }
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
            prevVisibleIndex != currVisibleIndex;
      },
      listener: (context, state) {
        if (state is TextBookLoaded) {
          _scrollToActiveItem(state);
        }
      },
      child: BlocBuilder<TextBookBloc, TextBookState>(
          bloc: context.read<TextBookBloc>(),
          builder: (context, state) {
            if (state is! TextBookLoaded) return const Center();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceSM),
                  child: OtzariaSearchField(
                    controller: searchController,
                    focusNode: widget.focusNode,
                    autofocus: true,
                    hintText: 'איתור כותרת...',
                    onChanged: (value) => setState(() {}),
                    onSubmitted: (_) => widget.focusNode.requestFocus(),
                    onClear: () => setState(() => searchController.clear()),
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
                    child: SingleChildScrollView(
                      controller: _tocScrollController,
                      child: searchController.text.isEmpty
                          ? ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: state.tableOfContents.length,
                              itemBuilder: (context, index) => _buildTocItem(
                                  state.tableOfContents[index],
                                  isFirstChild: index == 0))
                          : _buildFilteredList(state.tableOfContents, context),
                    ),
                  ),
                ),
              ],
            );
          }),
    );
  }
}
