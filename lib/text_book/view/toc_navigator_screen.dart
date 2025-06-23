import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/models/books.dart';

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

  TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Map<int, GlobalKey> _indexKeys = {};
  int? _lastIndex;

  @override
  void initState() {
    super.initState();
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      _populateKeys(state.tableOfContents);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (state.selectedIndex != null) {
          _scrollToIndex(state.selectedIndex!);
          _lastIndex = state.selectedIndex;
        }
      });
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _populateKeys(List<TocEntry> entries) {
    _indexKeys.clear();
    void traverse(List<TocEntry> nodes) {
      for (final e in nodes) {
        _indexKeys.putIfAbsent(e.index, () => GlobalKey());
        traverse(e.children);
      }
    }

    traverse(entries);
  }

  void _scrollToIndex(int index) {
    final key = _indexKeys[index];
    if (key == null) return;
    final context = key.currentContext;
    if (context == null) return;
    final render = context.findRenderObject();
    if (render == null) return;
    final viewport = RenderAbstractViewport.of(render);
    if (viewport == null) return;
    final offset = viewport.getOffsetToReveal(render, 0.5).offset;
    scrollController.animateTo(
      offset.clamp(
        scrollController.position.minScrollExtent,
        scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.ease,
    );
  }

  Widget _buildFilteredList(List<TocEntry> entries, BuildContext context) {
    List<TocEntry> allEntries = [];
    void getAllEntries(List<TocEntry> entries) {
      for (final TocEntry entry in entries) {
        allEntries.add(entry);
        getAllEntries(entry.children);
      }
    }

    getAllEntries(entries);
    allEntries = allEntries
        .where((e) => e.text.contains(searchController.text))
        .toList();

    return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: allEntries.length,
        itemBuilder: (context, index) {
          final entry = allEntries[index];
          final key = _indexKeys.putIfAbsent(entry.index, () => GlobalKey());
          return Padding(
            key: key,
            padding:
                EdgeInsets.fromLTRB(0, 0, 10 * entry.level.toDouble(), 0),
            child: entry.children.isEmpty
                ? ListTile(
                    title: Text(entry.fullText),
                    onTap: () {
                      widget.scrollController.scrollTo(
                        index: entry.index,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.ease,
                      );
                      if (Platform.isAndroid) {
                        widget.closeLeftPaneCallback();
                      }
                    },
                  )
                : _buildTocItem(entry, showFullText: true),
          );
        });
  }

  Widget _buildTocItem(TocEntry entry, {bool showFullText = false}) {
    void navigateToEntry() {
      widget.scrollController.scrollTo(
        index: entry.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.ease,
      );
      if (Platform.isAndroid) {
        widget.closeLeftPaneCallback();
      }
    }

    final key = _indexKeys.putIfAbsent(entry.index, () => GlobalKey());

    if (entry.children.isEmpty) {
      return Padding(
        key: key,
        padding: EdgeInsets.fromLTRB(0, 0, 10 * entry.level.toDouble(), 0),
        child: BlocBuilder<TextBookBloc, TextBookState>(
          builder: (context, state) {
            final bool selected = state is TextBookLoaded &&
                state.selectedIndex == entry.index;
            return ListTile(
              title: Text(entry.text),
              selected: selected,
              selectedColor: Theme.of(context).colorScheme.onSecondary,
              selectedTileColor:
                  Theme.of(context).colorScheme.secondary.withOpacity(0.2),
              onTap: navigateToEntry,
            );
          },
        ),
      );
    } else {
      return Padding(
        key: key,
        padding: EdgeInsets.fromLTRB(0, 0, 10 * entry.level.toDouble(), 0),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: entry.level == 1,
            title: BlocBuilder<TextBookBloc, TextBookState>(
              builder: (context, state) {
                final bool selected = state is TextBookLoaded &&
                    state.selectedIndex == entry.index;
                return ListTile(
                  title: Text(showFullText ? entry.fullText : entry.text),
                  selected: selected,
                  selectedColor:
                      Theme.of(context).colorScheme.onSecondary,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .secondary
                      .withOpacity(0.2),
                  onTap: navigateToEntry,
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
            leading: const Icon(Icons.chevron_right_rounded),
            trailing: const SizedBox.shrink(),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            iconColor: Theme.of(context).colorScheme.primary,
            collapsedIconColor: Theme.of(context).colorScheme.primary,
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entry.children.length,
                itemBuilder: (context, index) {
                  return _buildTocItem(entry.children[index]);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<TextBookBloc, TextBookState>(
        bloc: context.read<TextBookBloc>(),
        builder: (context, state) {
          if (state is! TextBookLoaded) return const Center();
          _populateKeys(state.tableOfContents);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (state.selectedIndex != null && state.selectedIndex != _lastIndex) {
              _scrollToIndex(state.selectedIndex!);
              _lastIndex = state.selectedIndex;
            }
          });
          return Column(
            children: [
              TextField(
                controller: searchController,
                onChanged: (value) => setState(() {}),
                focusNode: widget.focusNode,
                autofocus: true,
                onSubmitted: (_) {
                  widget.focusNode.requestFocus();
                },
                decoration: InputDecoration(
                  hintText: 'איתור כותרת...',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            searchController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
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
            ],
          );
        });
  }
}
