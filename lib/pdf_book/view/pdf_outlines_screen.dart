import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';

typedef PdfOutlineSearchEntry = ({
  PdfOutlineNode node,
  int level,
  String normalizedTitle,
});

/// כל צמתי העץ בסדר התצוגה, עם הכותרת מנורמלת כמו באיתור (בלי ניקוד וגרשיים).
@visibleForTesting
List<PdfOutlineSearchEntry> flattenPdfOutlineForSearch(
  List<PdfOutlineNode> outline,
) {
  final entries = <PdfOutlineSearchEntry>[];
  void walk(List<PdfOutlineNode> nodes, int level) {
    for (final node in nodes) {
      final title = normalizeFindText(node.title);
      entries.add((node: node, level: level, normalizedTitle: title));
      walk(node.children, level + 1);
    }
  }

  walk(outline, 0);
  return entries;
}

@visibleForTesting
List<PdfOutlineSearchEntry> filterPdfOutline(
  List<PdfOutlineSearchEntry> entries,
  String rawQuery,
) {
  final normalizedQuery = normalizeFindText(rawQuery);
  if (normalizedQuery.isEmpty) return entries;
  return entries
      .where(
        (e) => findNormalizedTextMatches(
          normalizedQuery: normalizedQuery,
          normalizedPrimaryText: e.normalizedTitle,
        ),
      )
      .toList();
}

class OutlineView extends StatefulWidget {
  const OutlineView({
    super.key,
    required this.outline,
    required this.controller,
    required this.focusNode,
    this.title,
    this.isPaneOpen = true,
    this.onNavigateToPage,
  });

  final List<PdfOutlineNode>? outline;
  final PdfViewerController controller;
  final FocusNode focusNode;

  /// כותרת ראשית מעל הרשימה (שם הספר).
  final String? title;

  /// האם הפאנל הצדדי פתוח. כשהוא סגור אין לגלול (הגלילה נכשלת ומשבשת
  /// את ה-guard), וברגע הפתיחה יש לגלול למיקום הנוכחי.
  final bool isPaneOpen;
  final Future<void> Function(int pageNumber)? onNavigateToPage;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

/// הסעיף העמוק ביותר שמתחיל בעמוד [page] או לפניו. סעיף בלי יעד מדולג, ולא עוצר
/// את הסריקה של אחיו.
@visibleForTesting
PdfOutlineNode? pdfOutlineActiveNode(List<PdfOutlineNode> nodes, int page) {
  PdfOutlineNode? bestMatch;
  for (final node in nodes) {
    final nodePage = node.dest?.pageNumber;
    if (nodePage == null) continue;
    if (nodePage > page) break;
    bestMatch = pdfOutlineActiveNode(node.children, page) ?? node;
  }
  return bestMatch;
}

class _OutlineViewState extends State<OutlineView>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController searchController = TextEditingController();

  final ScrollController _tocScrollController = ScrollController();
  final Map<PdfOutlineNode, GlobalKey> _tocItemKeys = {};
  bool _isManuallyScrolling = false;
  int? _lastScrolledPage;

  /// הסעיף שהעמוד הנוכחי נמצא בו — גם כשהעמוד אינו תחילת סעיף.
  PdfOutlineNode? _activeNode;

  // מעבר עמוד מחליף רק את הסימון; דגל לכל צומת בונה מחדש שתי שורות ולא את כל העץ.
  final Map<PdfOutlineNode, ValueNotifier<bool>> _selected = {};
  final Map<PdfOutlineNode, bool> _expanded = {};
  final Map<PdfOutlineNode, ExpansibleController> _controllers = {};

  // הסינון רץ בכל הקשה ובכל מעבר עמוד, ולכן הכותרות מנורמלות פעם אחת לעץ.
  List<PdfOutlineNode>? _searchEntriesSource;
  List<PdfOutlineSearchEntry> _searchEntries = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // ה-listener נורה רק על שינוי ב-controller; אם הוא כבר מוכן בעת
    // פתיחת הפאנל, יש לגלול ראשונית למיקום הנוכחי.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActiveItem();
    });
  }

  @override
  void didUpdateWidget(covariant OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (!identical(oldWidget.outline, widget.outline) ||
        (!oldWidget.isPaneOpen && widget.isPaneOpen)) {
      _lastScrolledPage = null;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActiveItem();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final notifier in _selected.values) {
      notifier.dispose();
    }
    _tocScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      _scrollToActiveItem();
    }
  }

  void _setActiveNode(PdfOutlineNode? node) {
    if (identical(node, _activeNode)) return;
    _selected[_activeNode]?.value = false;
    _activeNode = node;
    _selected[node]?.value = true;
  }

  void _ensureParentsOpen(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode,
  ) {
    final path = _findPath(nodes, targetNode);
    if (path.isEmpty) return;

    // מוצא את הרמה של הצומת היעד
    int targetLevel = _getNodeLevel(nodes, targetNode);

    // אם הצומת ברמה 2 ומעלה (שזה רמה 3 ומעלה בספירה רגילה), פתח את כל ההורים
    if (targetLevel >= 2) {
      for (final node in path) {
        if (node.children.isNotEmpty && _expanded[node] != true) {
          setState(() => _expanded[node] = true);
          _controllers[node]?.expand();
        }
      }
    }
  }

  int _getNodeLevel(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode, [
    int currentLevel = 0,
  ]) {
    for (final node in nodes) {
      if (node == targetNode) {
        return currentLevel;
      }

      final childLevel = _getNodeLevel(
        node.children,
        targetNode,
        currentLevel + 1,
      );
      if (childLevel != -1) {
        return childLevel;
      }
    }
    return -1;
  }

  List<PdfOutlineNode> _findPath(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode,
  ) {
    for (final node in nodes) {
      if (node == targetNode) {
        return [node];
      }

      final subPath = _findPath(node.children, targetNode);
      if (subPath.isNotEmpty) {
        return [node, ...subPath];
      }
    }
    return [];
  }

  void _scrollToActiveItem() {
    if (!widget.isPaneOpen || !widget.controller.isReady) return;

    final currentPage = widget.controller.pageNumber;
    if (currentPage == _lastScrolledPage) return;

    final outline = widget.outline;
    final activeNode = outline != null && currentPage != null
        ? pdfOutlineActiveNode(outline, currentPage)
        : null;

    // בגלילה ידנית רק ההדגשה מתעדכנת; הגלילה האוטומטית תחכה לסיומה.
    if (_isManuallyScrolling) {
      _setActiveNode(activeNode);
      return;
    }

    // מסומן מיד — אחרת כל עדכון של הקונטרולר חוזר על סריקת העץ וה-setState.
    _lastScrolledPage = currentPage;
    if (activeNode != null && outline != null) {
      _ensureParentsOpen(outline, activeNode);
    }
    _setActiveNode(activeNode);
    // בלי setState ייתכן שאין פריים מתוזמן, והגלילה שלמטה הייתה ממתינה לו.
    SchedulerBinding.instance.ensureVisualUpdate();
    if (activeNode == null) return;

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

      final scrollableBox =
          _tocScrollController.position.context.storageContext
                  .findRenderObject()
              as RenderBox;

      // המיקום של הפריט ביחס ל-viewport של הגלילה
      final itemOffset = itemRenderObject
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;

      // גובה ה-viewport (האזור הנראה)
      final viewportHeight = scrollableBox.size.height;

      // גובה הפריט עצמו
      final itemHeight = itemRenderObject.size.height;

      // מיקום היעד המדויק למירוכז
      final target =
          _tocScrollController.offset +
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

    final delegate = NavPanelSearchDelegate(
      controller: searchController,
      hintText: 'חיפוש סימניה...',
      focusNode: widget.focusNode,
      onChanged: (value) => setState(() {}),
      onSubmitted: (_) => widget.focusNode.requestFocus(),
      onClear: () => setState(() {}),
    );

    return NavPanelCollapsibleSearch(
      delegate: delegate,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _isManuallyScrolling = true;
          } else if (notification is ScrollEndNotification) {
            _isManuallyScrolling = false;
          }
          return false;
        },
        child: searchController.text.isEmpty
            ? _buildOutlineList(outline)
            : _buildFilteredOutlineList(outline),
      ),
    );
  }

  Widget _buildOutlineList(List<PdfOutlineNode> outline) {
    return NavTreeFocusGroup(
      child: SingleChildScrollView(
        controller: _tocScrollController,
        padding: kNavTreeListPadding,
        child: Column(
          children: [
            NavTreeHeader(
              title: widget.title ?? '',
              trailing: const NavPanelSearchToggle(),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: outline.length,
              itemBuilder: (context, index) => _buildOutlineItem(
                outline[index],
                level: 0,
                isFirstChild: index == 0,
                isGroupStart: index == 0,
                isGroupEnd: index == outline.length - 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredOutlineList(List<PdfOutlineNode> outline) {
    if (!identical(_searchEntriesSource, outline)) {
      _searchEntriesSource = outline;
      _searchEntries = flattenPdfOutlineForSearch(outline);
    }
    final filteredNodes = filterPdfOutline(
      _searchEntries,
      searchController.text,
    );

    return NavTreeFocusGroup(
      child: SingleChildScrollView(
        controller: _tocScrollController,
        padding: kNavTreeListPadding,
        child: Column(
          children: [
            NavTreeHeader(
              title: widget.title ?? '',
              trailing: const NavPanelSearchToggle(),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredNodes.length,
              itemBuilder: (context, index) => _buildOutlineItem(
                filteredNodes[index].node,
                level: filteredNodes[index].level,
                isGroupStart: index == 0,
                isGroupEnd: index == filteredNodes.length - 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlineItem(
    PdfOutlineNode node, {
    int level = 0,
    bool isFirstChild = false,
    bool isGroupStart = false,
    bool isGroupEnd = false,
  }) {
    final itemKey = _tocItemKeys.putIfAbsent(node, () => GlobalKey());
    Future<void> navigateToEntry() async {
      setState(() {
        _isManuallyScrolling = false;
        _lastScrolledPage = null;
      });
      final targetPage = node.dest?.pageNumber;
      if (targetPage == null) {
        return;
      }

      final onNavigateToPage = widget.onNavigateToPage;
      if (onNavigateToPage != null) {
        await onNavigateToPage(targetPage);
        return;
      }

      await widget.controller.goToPage(pageNumber: targetPage);
    }

    final selected = _selected.putIfAbsent(
      node,
      () => ValueNotifier(identical(node, _activeNode)),
    );
    final hasChildren = node.children.isNotEmpty;
    final bool isExpanded = _expanded[node] ?? (level == 0 || isFirstChild);

    final tile = ValueListenableBuilder<bool>(
      valueListenable: selected,
      builder: (context, isSelected, _) => NavTreeTile.heading(
        title: node.title,
        level: level,
        isSelected: isSelected,
        isExpanded: isExpanded,
        hasChildren: hasChildren,
        onTap: navigateToEntry,
        onToggleExpand: hasChildren
            ? () => setState(() {
                _expanded[node] = !isExpanded;
              })
            : null,
      ),
    );

    if (!hasChildren) {
      return NavTreeGroupCard(
        isGroupStart: isGroupStart,
        isGroupEnd: isGroupEnd,
        child: KeyedSubtree(
          key: itemKey,
          child: tile,
        ),
      );
    }

    return Column(
      key: itemKey,
      children: [
        NavTreeGroupCard(
          isGroupStart: isGroupStart,
          isGroupEnd: isGroupEnd && !isExpanded,
          child: tile,
        ),
        if (isExpanded)
          ...node.children.asMap().entries.map(
            (e) => _buildOutlineItem(
              e.value,
              level: level + 1,
              isFirstChild: isFirstChild && e.key == 0,
              isGroupEnd: isGroupEnd && e.key == node.children.length - 1,
            ),
          ),
      ],
    );
  }
}
