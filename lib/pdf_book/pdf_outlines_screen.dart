import 'package:flutter/material.dart';
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
  PdfOutlineNode? _currentNode;
  final Map<PdfOutlineNode, GlobalKey> _itemKeys = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _scrollToCurrentPage();
  }

  @override
  void didUpdateWidget(covariant OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
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
    if (mounted) {
      _scrollToCurrentPage();
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

  PdfOutlineNode? _findBestNode(List<PdfOutlineNode>? nodes, int page) {
    PdfOutlineNode? best;
    void search(List<PdfOutlineNode>? entries) {
      if (entries == null) return;
      for (final n in entries) {
        final p = n.dest?.pageNumber;
        if (p != null && p <= page) {
          if (best == null || p > (best!.dest?.pageNumber ?? -1)) {
            best = n;
          }
        }
        search(n.children);
      }
    }

    search(nodes);
    return best;
  }

  void _scrollToKey(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
      );
    }
  }

  void _scrollToCurrentPage() {
    if (!widget.controller.isReady) return;
    final page = widget.controller.pageNumber ?? 1;
    final node = _findBestNode(widget.outline, page);
    if (node == null) return;
    if (node != _currentNode) {
      setState(() {
        _currentNode = node;
      });
    }
    final key = _itemKeys[node];
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToKey(key));
    }
  }

  Widget _buildOutlineItem(PdfOutlineNode node, {int level = 0}) {
    final key = _itemKeys.putIfAbsent(node, () => GlobalObjectKey(node));
    void navigateToEntry() {
      if (node.dest != null) {
        widget.controller.goTo(widget.controller
            .calcMatrixFitWidthForPage(pageNumber: node.dest?.pageNumber ?? 1));
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 10 * level.toDouble(), 0),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: node.children.isEmpty
            ? Material(
                color: Colors.transparent,
                child: ListTile(
                  key: key,
                  title: Text(node.title),
                  selected: node == _currentNode,
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
                    key: key,
                    title: Text(node.title),
                    selected: node == _currentNode,
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
