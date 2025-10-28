import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class OutlineView extends StatefulWidget {
  const OutlineView({
    super.key,
    required this.outline,
    required this.controller,
    required this.focusNode,
    this.document,
  });

  final List<PdfBookmark>? outline;
  final PdfViewerController controller;
  final FocusNode focusNode;
  final PdfDocument? document;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController searchController = TextEditingController();

  final ScrollController _tocScrollController = ScrollController();
  final Map<PdfBookmark, GlobalKey> _tocItemKeys = {};
  bool _isManuallyScrolling = false;
  int? _lastScrolledPage;
  final Map<PdfBookmark, bool> _expanded = {};
  final Map<PdfBookmark, ExpansibleController> _controllers = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
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
    _tocScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      _scrollToActiveItem();
    }
  }

  void _ensureParentsOpen(List<PdfBookmark> nodes, PdfBookmark targetNode) {
    final path = _findPath(nodes, targetNode);
    if (path.isEmpty) return;

    // מוצא את הרמה של הצומת היעד
    int targetLevel = _getNodeLevel(nodes, targetNode);

    // אם הצומת ברמה 2 ומעלה (שזה רמה 3 ומעלה בספירה רגילה), פתח את כל ההורים
    if (targetLevel >= 2) {
      for (final bookmark in path) {
        // Syncfusion: children -> bookmarks (count property)
        final hasChildren = bookmark.count > 0;
        if (hasChildren && _expanded[bookmark] != true) {
          _expanded[bookmark] = true;
          _controllers[bookmark]?.expand();
        }
      }
    }
  }

  int _getNodeLevel(List<PdfBookmark> nodes, PdfBookmark targetNode,
      [int currentLevel = 0]) {
    for (final bookmark in nodes) {
      if (bookmark == targetNode) {
        return currentLevel;
      }

      // Syncfusion: Get children bookmarks
      if (bookmark.count > 0) {
        final children = List<PdfBookmark>.generate(
          bookmark.count,
          (index) => bookmark[index],
        );
        final childLevel =
            _getNodeLevel(children, targetNode, currentLevel + 1);
        if (childLevel != -1) {
          return childLevel;
        }
      }
    }
    return -1;
  }

  List<PdfBookmark> _findPath(List<PdfBookmark> nodes, PdfBookmark targetNode) {
    for (final bookmark in nodes) {
      if (bookmark == targetNode) {
        return [bookmark];
      }

      // Syncfusion: Get children bookmarks
      if (bookmark.count > 0) {
        final children = List<PdfBookmark>.generate(
          bookmark.count,
          (index) => bookmark[index],
        );
        final subPath = _findPath(children, targetNode);
        if (subPath.isNotEmpty) {
          return [bookmark, ...subPath];
        }
      }
    }
    return [];
  }

  void _scrollToActiveItem() {
    // Syncfusion: Check if document is loaded via pageCount > 0
    if (_isManuallyScrolling ||
        widget.controller.pageCount == 0 ||
        widget.document == null) return;

    final currentPage = widget.controller.pageNumber;
    if (currentPage == _lastScrolledPage) return;

    PdfBookmark? activeNode;

    // Helper to get page number from bookmark
    int? getPageNumber(PdfBookmark bookmark) {
      try {
        // Try to access destination - this might throw if destination is invalid
        final dest = bookmark.destination;
        if (dest == null) return null;

        final pageIndex = widget.document!.pages.indexOf(dest.page);
        return pageIndex + 1;
      } catch (e) {
        // Bookmark has invalid or null destination
        return null;
      }
    }

    PdfBookmark? findClosestNode(List<PdfBookmark> nodes, int page) {
      PdfBookmark? bestMatch;
      for (final bookmark in nodes) {
        final bookmarkPage = getPageNumber(bookmark);
        if (bookmarkPage != null && bookmarkPage <= page) {
          bestMatch = bookmark;
          // Syncfusion: Get children bookmarks
          if (bookmark.count > 0) {
            final children = List<PdfBookmark>.generate(
              bookmark.count,
              (index) => bookmark[index],
            );
            final childMatch = findClosestNode(children, page);
            if (childMatch != null) {
              bestMatch = childMatch;
            }
          }
        } else if (bookmarkPage != null && bookmarkPage > page) {
          break;
        }
      }
      return bestMatch;
    }

    if (widget.outline != null) {
      activeNode = findClosestNode(widget.outline!, currentPage);
    }

    if (activeNode != null && widget.outline != null) {
      _ensureParentsOpen(widget.outline!, activeNode);
    }

    // קריאה ל-setState כדי לוודא שהפריט הנכון מודגש לפני הגלילה
    if (mounted) {
      setState(() {});
    }

    if (activeNode == null) {
      _lastScrolledPage = currentPage;
      return;
    }

    // נחכה פריים אחד כדי שה-setState יסיים וה-UI יתעדכן
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isManuallyScrolling) return;

      final key = _tocItemKeys[activeNode];
      final itemContext = key?.currentContext;
      if (itemContext == null) return;

      final itemRenderObject = itemContext.findRenderObject();
      if (itemRenderObject is! RenderBox) return;

      // --- התחלה: החישוב הנכון והבדוק ---
      // זהו החישוב מההצעה של ה-AI השני, מותאם לקוד שלנו.

      final scrollableBox = _tocScrollController.position.context.storageContext
          .findRenderObject() as RenderBox;

      // המיקום של הפריט ביחס ל-viewport של הגלילה
      final itemOffset = itemRenderObject
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;

      // גובה ה-viewport (האזור הנראה)
      final viewportHeight = scrollableBox.size.height;

      // גובה הפריט עצמו
      final itemHeight = itemRenderObject.size.height;

      // מיקום היעד המדויק למירוכז
      final target = _tocScrollController.offset +
          itemOffset -
          (viewportHeight / 2) +
          (itemHeight / 2);
      // --- סיום: החישוב הנכון והבדוק ---

      _tocScrollController.animateTo(
        target.clamp(
          0.0,
          _tocScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      _lastScrolledPage = currentPage;
    });
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
            child: searchController.text.isEmpty
                ? _buildOutlineList(outline)
                : _buildFilteredOutlineList(outline),
          ),
        ),
      ],
    );
  }

  Widget _buildOutlineList(List<PdfBookmark> outline) {
    return SingleChildScrollView(
      controller: _tocScrollController,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: outline.length,
        itemBuilder: (context, index) =>
            _buildOutlineItem(outline[index], level: 0),
      ),
    );
  }

  Widget _buildFilteredOutlineList(List<PdfBookmark>? outline) {
    List<({PdfBookmark node, int level})> allNodes = [];
    void getAllNodes(List<PdfBookmark>? outline, int level) {
      if (outline == null) return;
      for (var bookmark in outline) {
        allNodes.add((node: bookmark, level: level));
        // Syncfusion: Get children bookmarks
        if (bookmark.count > 0) {
          final children = List<PdfBookmark>.generate(
            bookmark.count,
            (index) => bookmark[index],
          );
          getAllNodes(children, level + 1);
        }
      }
    }

    getAllNodes(widget.outline, 0);

    final filteredNodes = allNodes
        .where((item) => item.node.title.contains(searchController.text))
        .toList();

    return SingleChildScrollView(
      controller: _tocScrollController,
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

  Widget _buildOutlineItem(PdfBookmark bookmark, {int level = 0}) {
    final itemKey = _tocItemKeys.putIfAbsent(bookmark, () => GlobalKey());

    // Get page number from PdfPage
    int? getPageNumber(PdfBookmark bookmark) {
      if (widget.document == null) return null;
      try {
        // Try to access destination - this might throw if destination is invalid
        final dest = bookmark.destination;
        if (dest == null) return null;

        final pageIndex = widget.document!.pages.indexOf(dest.page);
        return pageIndex + 1; // Page numbers start from 1
      } catch (e) {
        // Bookmark has invalid or null destination
        return null;
      }
    }

    final pageNumber = getPageNumber(bookmark);

    void navigateToEntry() {
      setState(() {
        _isManuallyScrolling = false;
        _lastScrolledPage = null;
      });
      // Syncfusion: dest -> destination, pageNumber -> page
      // Syncfusion: goTo + calcMatrixFitWidthForPage -> jumpToPage
      if (pageNumber != null) {
        widget.controller.jumpToPage(pageNumber);
      }
    }

    // Syncfusion: children -> count property
    final hasChildren = bookmark.count > 0;

    if (hasChildren) {
      final controller =
          _controllers.putIfAbsent(bookmark, () => ExpansibleController());
      final bool isExpanded = _expanded[bookmark] ?? (level == 0);

      if (controller.isExpanded != isExpanded) {
        if (isExpanded) {
          controller.expand();
        } else {
          controller.collapse();
        }
      }
    }

    return Padding(
      key: itemKey,
      padding: EdgeInsets.fromLTRB(0, 0, 10 * level.toDouble(), 0),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: !hasChildren
            ? Material(
                color: Colors.transparent,
                child: ListTile(
                  title: Text(bookmark.title),
                  // Syncfusion: isReady -> pageCount > 0
                  selected: widget.controller.pageCount > 0 &&
                      pageNumber == widget.controller.pageNumber,
                  selectedColor:
                      Theme.of(context).colorScheme.onSecondaryContainer,
                  selectedTileColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  onTap: navigateToEntry,
                  hoverColor: Theme.of(context).hoverColor,
                  mouseCursor: SystemMouseCursors.click,
                ),
              )
            : Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: PageStorageKey(bookmark),
                  controller: _controllers.putIfAbsent(
                      bookmark, () => ExpansibleController()),
                  initiallyExpanded: _expanded[bookmark] ?? (level == 0),
                  onExpansionChanged: (val) {
                    setState(() {
                      _expanded[bookmark] = val;
                    });
                  },
                  // גם לכותרת של הצומת המורחב נוסיף ListTile
                  title: ListTile(
                    title: Text(bookmark.title),
                    // Syncfusion: isReady -> pageCount > 0
                    selected: widget.controller.pageCount > 0 &&
                        pageNumber == widget.controller.pageNumber,
                    selectedColor: Theme.of(context).colorScheme.onSecondary,
                    selectedTileColor: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.2),
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
                  // Syncfusion: Get children bookmarks
                  children: List<PdfBookmark>.generate(
                    bookmark.count,
                    (index) => bookmark[index],
                  ).map((c) => _buildOutlineItem(c, level: level + 1)).toList(),
                ),
              ),
      ),
    );
  }
}
