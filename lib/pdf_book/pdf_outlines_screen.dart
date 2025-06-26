import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class OutlineView extends StatefulWidget {
  const OutlineView({
    super.key,
    required this.outline,
    required this.controller,
    required this.focusNode,
  });

  final List<PdfOutlineNode>? outline;
  final PdfViewerController controller;
  final FocusNode focusNode;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _itemScrollController = ItemScrollController();
  List<({PdfOutlineNode node, int level})>? _flattenedOutline;
  final Map<PdfOutlineNode, PdfOutlineNode?> _parentMap = {};
  final Set<PdfOutlineNode> _expandedNodes = {};
  bool _isManuallyScrolling = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _flattenedOutline = _flattenOutline(widget.outline, 0);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _parentMap.clear();
      _expandedNodes.clear();
      _flattenedOutline = _flattenOutline(widget.outline, 0);
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (widget.outline != oldWidget.outline) {
      _parentMap.clear();
      _expandedNodes.clear();
      _flattenedOutline = _flattenOutline(widget.outline, 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    _scrollToCurrent();
  }

  void _scrollToCurrent() {
    if (!mounted ||
        !widget.controller.isReady ||
        _isManuallyScrolling ||
        _flattenedOutline == null ||
        !_itemScrollController.isAttached) return;

    final currentPage = widget.controller.pageNumber;
    if (currentPage == null) return;

    int targetIndex = -1;
    PdfOutlineNode? targetNode;
    for (int i = 0; i < _flattenedOutline!.length; i++) {
      final page = _flattenedOutline![i].node.dest?.pageNumber;
      if (page != null && page <= currentPage) {
        targetIndex = i;
        targetNode = _flattenedOutline![i].node;
      } else if (page != null && page > currentPage) {
        break;
      }
    }

    if (targetIndex != -1 && targetNode != null) {
      PdfOutlineNode? parent = _parentMap[targetNode];
      while (parent != null) {
        _expandedNodes.add(parent);
        parent = _parentMap[parent];
      }

      final visibleNodes = _searchController.text.isEmpty
          ? _visibleNodes()
          : _flattenedOutline!
              .where((item) => item.node.title
                  .toLowerCase()
                  .contains(_searchController.text.toLowerCase()))
              .toList();
      final visibleIndex =
          visibleNodes.indexWhere((item) => item.node == targetNode);

      if (visibleIndex != -1) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && _itemScrollController.isAttached) {
            _itemScrollController.scrollTo(
                index: visibleIndex,
                duration: const Duration(milliseconds: 300),
                alignment: 0.5,
                curve: Curves.ease);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final outline = widget.outline;
    if (outline == null || outline.isEmpty) {
      return const Center(
        child: Text('אין תוכן עניינים'),
      );
    }

    return Column(
      key: PageStorageKey(widget.key),
      children: [
        TextField(
          controller: _searchController,
          focusNode: widget.focusNode,
          autofocus: true,
          onChanged: (value) => setState(() {}),
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
                      _searchController.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (notification) {
              if (notification.dragDetails != null) {
                setState(() {
                  _isManuallyScrolling = true;
                });
              }
              return false;
            },
            child: _buildList(),
          ),
        ),
      ],
    );
  }

  List<({PdfOutlineNode node, int level})> _flattenOutline(
      List<PdfOutlineNode>? outline, int level,
      [PdfOutlineNode? parent]) {
    if (outline == null) return [];
    final List<({PdfOutlineNode node, int level})> list = [];
    for (final node in outline) {
      _parentMap[node] = parent;
      list.add((node: node, level: level));
      if (level == 0) {
        _expandedNodes.add(node); // root nodes expanded by default
      }
      if (node.children.isNotEmpty) {
        list.addAll(_flattenOutline(node.children, level + 1, node));
      }
    }
    return list;
  }

  Widget _buildList() {
    final items = _flattenedOutline;
    if (items == null) return const SizedBox.shrink();

    final visibleNodes = _searchController.text.isEmpty
        ? _visibleNodes()
        : items
            .where((item) => item.node.title
                .toLowerCase()
                .contains(_searchController.text.toLowerCase()))
            .toList();

    return ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemCount: visibleNodes.length,
        itemBuilder: (context, index) => _buildOutlineItem(
            visibleNodes[index].node,
            level: visibleNodes[index].level));
  }

  List<({PdfOutlineNode node, int level})> _visibleNodes() {
    final List<({PdfOutlineNode node, int level})> list = [];

    void addNodes(List<PdfOutlineNode>? nodes, int level) {
      if (nodes == null) return;
      for (final node in nodes) {
        list.add((node: node, level: level));
        if (_expandedNodes.contains(node)) {
          addNodes(node.children, level + 1);
        }
      }
    }

    addNodes(widget.outline, 0);
    return list;
  }

  Widget _buildOutlineItem(PdfOutlineNode node, {int level = 0}) {
    void navigateToEntry(bool isTap) {
      if (isTap) {
        setState(() {
          _isManuallyScrolling = false;
        });
      }
      if (node.dest != null) {
        // --- FIX IS HERE ---
        widget.controller.goToDest(node.dest!);
        // --- END OF FIX ---
      }
    }

    final tile = ListTile(
      title: Text(node.title, overflow: TextOverflow.ellipsis),
      selected: widget.controller.isReady &&
          node.dest?.pageNumber == widget.controller.pageNumber,
      selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      onTap: () => navigateToEntry(true),
    );

    if (node.children.isEmpty || _searchController.text.isNotEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(10 * level.toDouble(), 0, 0, 0),
        child: Material(color: Colors.transparent, child: tile),
      );
    }

    final expanded = _expandedNodes.contains(node);

    return Padding(
      padding: EdgeInsets.fromLTRB(10 * level.toDouble(), 0, 0, 0),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(node),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          trailing: const SizedBox.shrink(),
          leading: const Icon(Icons.chevron_right_rounded),
          onExpansionChanged: (value) {
            setState(() {
              if (value) {
                _expandedNodes.add(node);
              } else {
                _expandedNodes.remove(node);
              }
            });
          },
          initiallyExpanded: expanded,
          title: tile,
          children: const [],
        ),
      ),
    );
  }
}