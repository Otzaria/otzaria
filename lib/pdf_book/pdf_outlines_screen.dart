import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdfrx/pdfrx.dart';

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
  TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Map<PdfOutlineNode, GlobalKey> _nodeKeys = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initNodeKeys();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentPage();
    });
  }

  @override
  void didUpdateWidget(covariant OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.outline != widget.outline) {
      _initNodeKeys();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentPage();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    _scrollToCurrentPage();
  }

  void _scrollToKey(GlobalKey key) {
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

  void _initNodeKeys() {
    _nodeKeys.clear();
    void traverse(List<PdfOutlineNode>? nodes) {
      if (nodes == null) return;
      for (final node in nodes) {
        _nodeKeys[node] = GlobalKey();
        traverse(node.children);
      }
    }

    traverse(widget.outline);
  }

  PdfOutlineNode? _findBestNode(List<PdfOutlineNode>? nodes, int page) {
    PdfOutlineNode? best;
    void search(List<PdfOutlineNode>? nodes) {
      if (nodes == null) return;
      for (final node in nodes) {
        final destPage = node.dest?.pageNumber;
        if (destPage != null && destPage <= page) {
          if (best == null || destPage >= (best!.dest?.pageNumber ?? 0)) {
            best = node;
          }
        }
        search(node.children);
      }
    }

    search(nodes);
    return best;
  }

  void _scrollToCurrentPage() {
    final node =
        _findBestNode(widget.outline, widget.controller.pageNumber ?? 1);
    final key = node != null ? _nodeKeys[node] : null;
    if (key != null) {
      _scrollToKey(key);
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
      children: [
        TextField(
          controller: searchController,
          focusNode: widget.focusNode,
          autofocus: true,
          onChanged: (value) => setState(() {}),
          onSubmitted: (_) {
            widget.focusNode.requestFocus();
          },
          decoration: InputDecoration(
            hintText: 'חיפוש סימניה...',
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
          child: searchController.text.isEmpty
              ? _buildOutlineList(outline)
              : _buildFilteredOutlineList(outline),
        ),
      ],
    );
  }

  Widget _buildOutlineList(List<PdfOutlineNode> outline) {
    return SingleChildScrollView(
      controller: scrollController,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: outline.length,
        itemBuilder: (context, index) =>
            _buildOutlineItem(outline[index], level: 0),
      ),
    );
  }

  Widget _buildFilteredOutlineList(List<PdfOutlineNode>? outline) {
    List<({PdfOutlineNode node, int level})> allNodes = [];
    void getAllNodes(List<PdfOutlineNode>? outline, int level) {
      if (outline == null) return;
      for (var node in outline) {
        allNodes.add((node: node, level: level));
        getAllNodes(node.children, level + 1);
      }
    }

    getAllNodes(widget.outline, 0);

    final filteredNodes = allNodes
        .where((item) => item.node.title.contains(searchController.text))
        .toList();

    return SingleChildScrollView(
      controller: scrollController,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filteredNodes.length,
        itemBuilder: (context, index) => _buildOutlineItem(
            filteredNodes[index].node,
            level: filteredNodes[index].level),
      ),
    );
  }

  Widget _buildOutlineItem(PdfOutlineNode node, {int level = 0}) {
    void navigateToEntry() {
      if (node.dest != null) {
        widget.controller.goTo(widget.controller
            .calcMatrixFitWidthForPage(pageNumber: node.dest?.pageNumber ?? 1));
      }
    }

    final key = _nodeKeys[node];

    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(0, 0, 10 * level.toDouble(), 0),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: node.children.isEmpty
            ? Material(
                color: Colors.transparent,
                child: ListTile(
                  title: Text(node.title),
                  selected: widget.controller.isReady &&
                      node.dest?.pageNumber ==
                          widget.controller.pageNumber,
                  selectedColor: Theme.of(context).colorScheme.onSecondary,
                  selectedTileColor:
                      Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                  onTap: navigateToEntry,
                  hoverColor: Theme.of(context).hoverColor,
                  mouseCursor: SystemMouseCursors.click,
                ),
              )
            : Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: PageStorageKey(node),
                  initiallyExpanded: level == 0,
                  // גם לכותרת של הצומת המורחב נוסיף ListTile
                  title: ListTile(
                    title: Text(node.title),
                    selected: widget.controller.isReady &&
                        node.dest?.pageNumber ==
                            widget.controller.pageNumber,
                    selectedColor:
                        Theme.of(context).colorScheme.onSecondary,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withOpacity(0.2),
                    onTap: navigateToEntry,
                    hoverColor: Theme.of(context).hoverColor,
                    mouseCursor: SystemMouseCursors.click,
                    contentPadding: EdgeInsets.zero, // שלא יזיז ימינה
                  ),
                  leading: const Icon(Icons.chevron_right_rounded),
                  trailing: const SizedBox.shrink(),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  iconColor: Theme.of(context).colorScheme.primary,
                  collapsedIconColor: Theme.of(context).colorScheme.primary,
                  children: node.children
                      .map((c) => _buildOutlineItem(c, level: level + 1))
                      .toList(),
                ),
              ),
      ),
    );
  }
}
