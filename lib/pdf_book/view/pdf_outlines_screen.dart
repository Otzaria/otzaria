import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:positioned_sliver_list/positioned_sliver_list.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_tokens.dart';

typedef PdfOutlineSearchEntry = ({
  PdfOutlineNode node,
  int level,
  String normalizedTitle,
});

typedef _OutlineRow = ({PdfOutlineNode node, int level, bool isExpanded});

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
  static const _headerKey = ValueKey('pdf-outline-header');

  // גובה שורה טיפוסי; משמש רק להערכת פס הגלילה לשורות שטרם נמדדו.
  static const double _estimatedRowExtent = 44;

  final TextEditingController searchController = TextEditingController();

  final ScrollController _tocScrollController = ScrollController();
  final ListController _listController = ListController();
  final FocusNode _entryFocusNode = FocusNode(debugLabel: 'PDF outline entry');
  late final _OutlineFocusPolicy _focusPolicy = _OutlineFocusPolicy(
    _entryFocusNode,
    () => widget.isPaneOpen && _rowIndices.containsKey(_activeNode),
  );
  bool _isManuallyScrolling = false;
  int? _lastScrolledPage;

  /// הסעיף שהעמוד הנוכחי נמצא בו — גם כשהעמוד אינו תחילת סעיף.
  PdfOutlineNode? _activeNode;

  // מעבר עמוד מחליף רק את הסימון; דגל לכל צומת בונה מחדש שתי שורות ולא את כל העץ.
  final Map<PdfOutlineNode, ValueNotifier<bool>> _selected = {};
  final Map<PdfOutlineNode, bool> _expanded = {};
  int _expandedRevision = 0;

  // הסינון רץ בכל הקשה ובכל מעבר עמוד, ולכן הכותרות מנורמלות פעם אחת לעץ.
  List<PdfOutlineNode>? _searchEntriesSource;
  List<PdfOutlineSearchEntry> _searchEntries = const [];

  // השורות הגלויות משתנות רק עם העץ, השאילתה או מצב ההרחבה.
  List<PdfOutlineNode>? _rowsSource;
  String? _rowsQuery;
  int _rowsRevision = -1;
  List<_OutlineRow> _rows = const [];
  Map<PdfOutlineNode, int> _rowIndices = Map.identity();

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
    _entryFocusNode.dispose();
    _listController.dispose();
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

    // רמת הצומת היעד היא מספר אבותיו בנתיב.
    final targetLevel = path.length - 1;

    // אם הצומת ברמה 2 ומעלה (שזה רמה 3 ומעלה בספירה רגילה), פתח את כל ההורים
    if (targetLevel >= 2) {
      for (final node in path) {
        if (node.children.isNotEmpty && _expanded[node] != true) {
          setState(() {
            _expanded[node] = true;
            _expandedRevision++;
          });
        }
      }
    }
  }

  // רץ בכל מעבר עמוד על כל העץ: בלי איטרטור ובלי רשימה לכל צומת.
  List<PdfOutlineNode> _findPath(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode,
  ) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node == targetNode) {
        return [node];
      }

      final subPath = _findPath(node.children, targetNode);
      if (subPath.isNotEmpty) {
        return [node, ...subPath];
      }
    }
    return const [];
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

    // נחכה פריים אחד כדי שהשורות שנפתחו ייכנסו לרשימה.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isManuallyScrolling || !_listController.isAttached) {
        return;
      }
      int? targetIndex() {
        if (!mounted ||
            !widget.isPaneOpen ||
            _isManuallyScrolling ||
            !identical(widget.outline, outline) ||
            !identical(_activeNode, activeNode)) {
          return null;
        }
        final rowIndex = _rowIndices[activeNode];
        // +1: פריט 0 ברשימה הוא הכותרת.
        return rowIndex == null ? null : rowIndex + 1;
      }

      final index = targetIndex();
      if (index == null) return;
      AppMotion.scroll(
        context,
        AppTokens.animPanelSlide,
        animate: (duration) => _listController.animateToItem(
          index: targetIndex,
          scrollController: _tocScrollController,
          alignment: 0.5,
          duration: (_) => duration,
          curve: (_) => Curves.easeInOut,
        ),
        jump: () => _listController.jumpToItem(
          index: index,
          scrollController: _tocScrollController,
          alignment: 0.5,
        ),
      );
    });
  }

  /// השורות הגלויות לפי [_expanded]. בהיעדר הכרעה פתוחים צמתי השורש ושרשרת
  /// הילד הראשון; בסינון כל התאמה מוצגת עם צאצאיה הפתוחים.
  List<_OutlineRow> _visibleRows(List<PdfOutlineNode> outline, String query) {
    if (identical(_rowsSource, outline) &&
        _rowsQuery == query &&
        _rowsRevision == _expandedRevision) {
      return _rows;
    }
    final rows = <_OutlineRow>[];
    void add(PdfOutlineNode node, int level, bool isFirstChild) {
      final isExpanded = _expanded[node] ?? (level == 0 || isFirstChild);
      rows.add((node: node, level: level, isExpanded: isExpanded));
      if (!isExpanded) return;
      final children = node.children;
      for (var i = 0; i < children.length; i++) {
        add(children[i], level + 1, isFirstChild && i == 0);
      }
    }

    if (query.isEmpty) {
      for (var i = 0; i < outline.length; i++) {
        add(outline[i], 0, i == 0);
      }
    } else {
      if (!identical(_searchEntriesSource, outline)) {
        _searchEntriesSource = outline;
        _searchEntries = flattenPdfOutlineForSearch(outline);
      }
      for (final entry in filterPdfOutline(_searchEntries, query)) {
        add(entry.node, entry.level, false);
      }
    }

    final indices = Map<PdfOutlineNode, int>.identity();
    for (var i = 0; i < rows.length; i++) {
      indices.putIfAbsent(rows[i].node, () => i);
    }
    _rowsSource = outline;
    _rowsQuery = query;
    _rowsRevision = _expandedRevision;
    _rows = rows;
    _rowIndices = indices;
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final outline = widget.outline;
    if (outline == null || outline.isEmpty) {
      return const OtzariaEmptyState(
        isCompact: true,
        icon: OtzariaIcons.text_bullet_list_tree_24_regular,
        title: 'אין תוכן עניינים',
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
      presentation: NavPanelSearchPresentation.persistent,
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
        child: _buildOutlineList(outline, searchController.text),
      ),
    );
  }

  Widget _buildOutlineList(List<PdfOutlineNode> outline, String query) {
    final rows = _visibleRows(outline, query);
    // בסינון צומת עשוי להופיע פעמיים (כהתאמה וכצאצא של התאמה), ולכן בלי מפתח.
    final keyRows = query.isEmpty;
    return NavTreeFocusGroup(
      child: FocusTraversalGroup(
        policy: _focusPolicy,
        child: Stack(
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(-2),
              child: Focus(
                focusNode: _entryFocusNode,
                includeSemantics: false,
                onFocusChange: _revealFocusedEntry,
                child: const SizedBox.shrink(),
              ),
            ),
            SuperListView.builder(
              controller: _tocScrollController,
              listController: _listController,
              extentEstimation: (_, _) => _estimatedRowExtent,
              padding: kNavTreeListPadding,
              itemCount: rows.length + 1,
              findChildIndexCallback: (key) {
                if (key == _headerKey) return 0;
                if (!keyRows || key is! ObjectKey) return null;
                final index = _rowIndices[key.value];
                return index == null ? null : index + 1;
              },
              itemBuilder: (context, index) {
                if (index == 0) {
                  return KeyedSubtree(
                    key: _headerKey,
                    child: NavTreeHeader(
                      title: widget.title ?? '',
                      trailing: const NavPanelSearchToggle(),
                    ),
                  );
                }
                final row = _buildOutlineRow(
                  rows[index - 1],
                  isGroupStart: index == 1,
                  isGroupEnd: index == rows.length,
                );
                return keyRows
                    ? KeyedSubtree(
                        key: ObjectKey(rows[index - 1].node),
                        child: row,
                      )
                    : row;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _revealFocusedEntry(bool hasFocus) {
    if (!hasFocus) return;
    final node = _activeNode;
    final outline = widget.outline;
    final index = _rowIndices[node];
    if (!widget.isPaneOpen || index == null || !_listController.isAttached) {
      _entryFocusNode.nextFocus();
      return;
    }
    _listController.jumpToItem(
      index: index + 1,
      scrollController: _tocScrollController,
      alignment: 0.5,
    );
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_entryFocusNode.hasFocus) return;
      if (!widget.isPaneOpen || !identical(widget.outline, outline)) {
        _entryFocusNode.unfocus();
        return;
      }
      if (!identical(_activeNode, node) || _rowIndices[node] != index) {
        _revealFocusedEntry(true);
        return;
      }
      final target = _focusPolicy.selectedTarget;
      if (target == null) {
        _entryFocusNode.nextFocus();
      } else {
        target.requestFocus();
      }
    });
  }

  Widget _buildOutlineRow(
    _OutlineRow row, {
    required bool isGroupStart,
    required bool isGroupEnd,
  }) {
    final node = row.node;
    Future<void> navigateToEntry() async {
      _entryFocusNode.unfocus();
      _isManuallyScrolling = false;
      _lastScrolledPage = null;
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
    final isExpanded = row.isExpanded;

    return NavTreeGroupCard(
      isGroupStart: isGroupStart,
      isGroupEnd: isGroupEnd,
      child: ValueListenableBuilder<bool>(
        valueListenable: selected,
        builder: (context, isSelected, _) => NavTreeTile.heading(
          title: node.title,
          level: row.level,
          isSelected: isSelected,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          onTap: navigateToEntry,
          onToggleExpand: hasChildren
              ? () {
                  _entryFocusNode.unfocus();
                  setState(() {
                    _expanded[node] = !isExpanded;
                    _expandedRevision++;
                  });
                }
              : null,
        ),
      ),
    );
  }
}

bool _isSelectedOutlineFocus(FocusNode node) =>
    node.context?.findAncestorWidgetOfExactType<NavTreeTile>()?.isSelected ==
    true;

class _OutlineFocusPolicy extends OrderedTraversalPolicy {
  _OutlineFocusPolicy(this.entryNode, this.hasActiveRow);

  final FocusNode entryNode;
  final bool Function() hasActiveRow;

  FocusNode? get selectedTarget {
    final targets = super.sortDescendants(
      entryNode.parent!.traversalDescendants.where(_isSelectedOutlineFocus),
      entryNode,
    );
    return targets.isEmpty ? null : targets.first;
  }

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final nodes = descendants.toList();
    final needsEntry = hasActiveRow() && !nodes.any(_isSelectedOutlineFocus);
    return super.sortDescendants(
      nodes.where(
        (node) => node != entryNode || needsEntry || node == currentNode,
      ),
      currentNode,
    );
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // נקודת הכניסה היא יעד Tab בלבד; החיצים ממשיכים בין השורות הגלויות.
    entryNode.skipTraversal = true;
    try {
      return super.inDirection(currentNode, direction);
    } finally {
      entryNode.skipTraversal = false;
    }
  }
}
