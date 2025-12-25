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
import 'package:otzaria/widgets/rtl_text_field.dart';

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
    List<TocEntry> matchingEntries = [];

    void findMatchingEntries(List<TocEntry> entries) {
      for (final TocEntry entry in entries) {
        // דילוג על רמה 1 (כותרת ראשית של הספר) כדי למנוע התאמות שגויות
        // לאותיות שמופיעות בשם הספר
        if (entry.level > 1 && entry.text.contains(searchController.text)) {
          matchingEntries.add(entry);
        }
        findMatchingEntries(entry.children);
      }
    }

    findMatchingEntries(entries);

    return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: matchingEntries.length,
        itemBuilder: (context, index) {
          final entry = matchingEntries[index];

          // אם לכותרת יש ילדים, הצג אותה עם אפשרות לפתוח/לסגור
          if (entry.children.isNotEmpty) {
            final bool isExpanded = _expanded[entry.index] ?? false;

            return Column(
              children: [
                Container(
                  decoration: BoxDecoration(
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
                          onTap: () {
                            setState(() {
                              _isManuallyScrolling = false;
                              _lastScrolledTocIndex = null;
                            });
                            widget.scrollController.scrollTo(
                              index: entry.index,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.ease,
                            );
                            if (Platform.isAndroid) {
                              widget.closeLeftPaneCallback();
                            }
                          },
                          child: Container(
                            padding: EdgeInsets.only(
                              right: 16.0 + (entry.level * 24.0),
                              left: 8.0,
                              top: 10.0,
                              bottom: 10.0,
                            ),
                            child: Row(
                              children: [
                                Icon(
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
                                    entry.fullText,
                                    style: TextStyle(
                                      fontSize: entry.level == 1 ? 15 : 14,
                                      fontWeight: entry.level == 1
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
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
                            top: 10.0,
                            bottom: 10.0,
                          ),
                          child: Icon(
                            isExpanded
                                ? FluentIcons.chevron_up_24_regular
                                : FluentIcons.chevron_down_24_regular,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // הצג את הילדים אם הכותרת פתוחה
                if (isExpanded)
                  ...entry.children.map((child) => _buildTocItem(child)),
              ],
            );
          } else {
            // כותרת ללא ילדים - הצג כרגיל
            return InkWell(
              onTap: () {
                setState(() {
                  _isManuallyScrolling = false;
                  _lastScrolledTocIndex = null;
                });
                widget.scrollController.scrollTo(
                  index: entry.index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.ease,
                );
                if (Platform.isAndroid) {
                  widget.closeLeftPaneCallback();
                }
              },
              child: Container(
                padding: EdgeInsets.only(
                  right: 16.0 + (entry.level * 24.0),
                  left: 16.0,
                  top: 10.0,
                  bottom: 10.0,
                ),
                decoration: BoxDecoration(
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
                        entry.fullText,
                        style: const TextStyle(
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        });
  }

  Widget _buildTocItem(TocEntry entry, {bool showFullText = false}) {
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
                      entry.text,
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
      final bool isExpanded = _expanded[entry.index] ?? (entry.level == 1);

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
            ...entry.children.map((child) => _buildTocItem(child)),
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
                  padding: const EdgeInsets.all(8.0),
                  child: RtlTextField(
                    controller: searchController,
                    onChanged: (value) => setState(() {}),
                    focusNode: widget.focusNode,
                    autofocus: true,
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
                    child: SingleChildScrollView(
                      controller: _tocScrollController,
                      child: searchController.text.isEmpty
                          ? ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: state.tableOfContents.length,
                              itemBuilder: (context, index) =>
                                  _buildTocItem(state.tableOfContents[index]))
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
