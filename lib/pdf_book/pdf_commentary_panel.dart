import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/widgets/commentators_filter_button.dart';
import 'package:otzaria/widgets/commentators_filter_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/pdf_book/pdf_commentators_selector.dart';
import 'package:otzaria/pdf_book/pdf_commentary_content.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/utils/context_menu_utils.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:async'; // Added for Timer
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// מייצג קבוצת קטעי פירוש רצופים מאותו ספר
class CommentaryGroup {
  final String bookTitle;
  final List<Link> links;

  CommentaryGroup({required this.bookTitle, required this.links});
}

/// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
List<CommentaryGroup> _groupConsecutiveLinks(List<Link> links) {
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    final title = utils.getTitleFromPath(link.path2);

    if (currentTitle == null || currentTitle != title) {
      // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
      if (currentGroup.isNotEmpty) {
        groups.add(CommentaryGroup(
          bookTitle: currentTitle!,
          links: List.from(currentGroup),
        ));
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      // אותו ספר - מוסיף לקבוצה הנוכחית
      currentGroup.add(link);
    }
  }

  // מוסיף את הקבוצה האחרונה
  if (currentGroup.isNotEmpty) {
    groups.add(CommentaryGroup(
      bookTitle: currentTitle!,
      links: List.from(currentGroup),
    ));
  }

  return groups;
}

/// Widget שמציג מפרשים וקישורים עבור PDF
class PdfCommentaryPanel extends StatefulWidget {
  final PdfBookTab tab;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final VoidCallback? onClose;
  final int? initialTabIndex;

  const PdfCommentaryPanel({
    super.key,
    required this.tab,
    required this.openBookCallback,
    required this.fontSize,
    this.onClose,
    this.initialTabIndex,
  });

  @override
  State<PdfCommentaryPanel> createState() => _PdfCommentaryPanelState();
}

class _PdfCommentaryPanelState extends State<PdfCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showFilterTab = false;
  String? _savedSelectedText;
  late final GlobalKey<SelectionAreaState> _selectionKey;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _currentSearchIndex = 0;
  int _totalSearchResults = 0;
  bool _allExpanded = true;
  final Map<String, bool> _expansionStates = {};

  // Anti-jitter search stats
  final Map<String, int> _searchResultsPerLink = {};
  Timer? _searchUpdateDebounce;
  final Map<String, int> _pendingCounts = {};

  // Scroll support
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  final Map<String, GlobalKey> _itemKeys = {};
  List<Link> _orderedLinks = [];
  List<CommentaryGroup> _orderedGroups = [];

  String _getLinkKey(Link link) => '${link.path2}_${link.index2}';

  // Helper to determine relative index for highlighting
  int _getItemSearchIndex(Link link) {
    if (_searchResultsPerLink.isEmpty) return -1;

    int cumulativeIndex = 0;
    final linkKey = _getLinkKey(link);

    for (final orderedLink in _orderedLinks) {
      final currentKey = _getLinkKey(orderedLink);

      // Found the link
      if (currentKey == linkKey) {
        final itemResults = _searchResultsPerLink[linkKey] ?? 0;
        if (itemResults == 0) return -1;

        final relativeIndex = _currentSearchIndex - cumulativeIndex;
        // Check if the current global index falls within this item's range
        return (relativeIndex >= 0 && relativeIndex < itemResults)
            ? relativeIndex
            : -1;
      }

      cumulativeIndex += _searchResultsPerLink[currentKey] ?? 0;
    }

    return -1;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3, // מפרשים, קישורים, הערות
      vsync: this,
      initialIndex: widget.initialTabIndex ?? 0,
    );
    _selectionKey = GlobalKey<SelectionAreaState>();
  }

  @override
  void didUpdateWidget(PdfCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם initialTabIndex השתנה, מעדכן את הטאב
    if (oldWidget.initialTabIndex != widget.initialTabIndex &&
        widget.initialTabIndex != null) {
      _tabController.animateTo(widget.initialTabIndex!);
    }
  }

  @override
  void dispose() {
    _searchUpdateDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _updateSearchResultsCount(Link link, int count) {
    if (!mounted) return;

    final key = '${link.path2}_${link.index2}';
    _pendingCounts[key] = count;

    if (_searchUpdateDebounce?.isActive ?? false) return;

    _searchUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _searchResultsPerLink.addAll(_pendingCounts);
        _pendingCounts.clear();
        _totalSearchResults =
            _searchResultsPerLink.values.fold(0, (sum, count) => sum + count);

        // Reset current index if out of bounds
        if (_currentSearchIndex >= _totalSearchResults &&
            _totalSearchResults > 0) {
          _currentSearchIndex = 0;
        }
      });
    });
  }

  /// העתקת טקסט מעוצב (HTML) ללוח
  Future<void> _copyFormattedText() async {
    await ContextMenuUtils.copyFormattedText(
      context: context,
      savedSelectedText: _savedSelectedText,
      fontSize: widget.fontSize,
    );
  }

  /// העתקת כל הטקסט הנראה בפאנל
  Future<void> _copyAllVisibleText() async {
    final selection = _selectionKey.currentState?.selectableRegion;
    if (selection == null) return;

    // בחירת כל הטקסט
    selection.selectAll();

    // המתנה קצרה לעדכון הבחירה
    await Future.delayed(const Duration(milliseconds: 50));

    // העתקה
    await _copyFormattedText();
  }

  /// בניית תפריט הקשר כללי
  ctx.ContextMenu _buildContextMenu() {
    return ctx.ContextMenu(
      entries: [
        ctx.MenuItem(
          label: const Text('העתק'),
          icon: const Icon(FluentIcons.copy_24_regular),
          enabled: _savedSelectedText != null &&
              _savedSelectedText!.trim().isNotEmpty,
          onSelected: (_) => _copyFormattedText(),
        ),
        ctx.MenuItem(
          label: const Text('העתק את כל הטקסט'),
          icon: const Icon(FluentIcons.document_copy_24_regular),
          onSelected: (_) => _copyAllVisibleText(),
        ),
        ctx.MenuItem(
          label: const Text('בחר את כל הטקסט'),
          icon: const Icon(FluentIcons.select_all_on_24_regular),
          onSelected: (_) =>
              _selectionKey.currentState?.selectableRegion.selectAll(),
        ),
      ],
    );
  }

  /// בניית תפריט הקשר למפרש ספציפי
  ctx.ContextMenu _buildCommentaryContextMenu(Link link) {
    return ContextMenuUtils.buildCommentaryContextMenu(
      context: context,
      link: link,
      openBookCallback: widget.openBookCallback,
      fontSize: widget.fontSize,
      savedSelectedText: _savedSelectedText,
      onCopySelected: _copyFormattedText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // שורת הכרטיסיות
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(
                      icon: Icon(FluentIcons.book_24_regular, size: 18),
                      iconMargin: EdgeInsets.only(bottom: 2),
                      height: 48,
                      child: Text('מפרשים', style: TextStyle(fontSize: 12)),
                    ),
                    Tab(
                      icon: Icon(FluentIcons.link_24_regular, size: 18),
                      iconMargin: EdgeInsets.only(bottom: 2),
                      height: 48,
                      child: Text('קישורים', style: TextStyle(fontSize: 12)),
                    ),
                    Tab(
                      icon: Icon(FluentIcons.note_24_regular, size: 18),
                      iconMargin: EdgeInsets.only(bottom: 2),
                      height: 48,
                      child: Text('הערות', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  dividerColor: Colors.transparent,
                  onTap: (index) {
                    // אם לוחצים על טאב מפרשים (0) ואנחנו בכפתור סינון, סוגרים אותו
                    if (index == 0 && _showFilterTab) {
                      setState(() {
                        _showFilterTab = false;
                      });
                    }
                  },
                ),
              ),
              // לחצן סגירה
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: widget.onClose ?? () {},
              ),
            ],
          ),
        ),
        // תוכן הכרטיסיות - עטוף ב-SelectionArea כדי לאפשר בחירת טקסט
        Expanded(
          child: ctx.ContextMenuRegion(
            contextMenu: _buildContextMenu(),
            child: SelectionArea(
              key: _selectionKey,
              contextMenuBuilder: (context, selectableRegionState) {
                // מבטל את התפריט הרגיל של Flutter כי יש ContextMenuRegion
                return const SizedBox.shrink();
              },
              onSelectionChanged: (selection) {
                if (selection != null && selection.plainText.isNotEmpty) {
                  setState(() {
                    _savedSelectedText = selection.plainText;
                  });
                }
              },
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCommentariesView(),
                  _buildLinksView(),
                  _buildNotesView(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentatorsFilter() {
    return CommentatorsFilterScreen(
      onBack: () {
        setState(() {
          _showFilterTab = false;
        });
      },
      child: PdfCommentatorsSelector(
        tab: widget.tab,
        onChanged: () {
          setState(() {
            // עדכון התצוגה כשמשנים מפרשים
          });
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          CommentatorsFilterButton(
            isActive: false,
            onPressed: () {
              setState(() {
                _showFilterTab = true;
              });
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            iconSize: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RtlTextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'חפש בתוך המפרשים המוצגים...',
                prefixIcon: const Icon(FluentIcons.search_24_regular),
                suffixIcon: _searchQuery.isNotEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_totalSearchResults > 0) ...[
                            Text(
                              '${_currentSearchIndex + 1}/$_totalSearchResults',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon:
                                  const Icon(FluentIcons.chevron_up_24_regular),
                              iconSize: 20,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              onPressed: _currentSearchIndex > 0
                                  ? () {
                                      setState(() {
                                        _currentSearchIndex--;
                                      });
                                      _scrollToSearchResult();
                                    }
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(
                                  FluentIcons.chevron_down_24_regular),
                              iconSize: 20,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              onPressed:
                                  _currentSearchIndex < _totalSearchResults - 1
                                      ? () {
                                          setState(() {
                                            _currentSearchIndex++;
                                          });
                                          _scrollToSearchResult();
                                        }
                                      : null,
                            ),
                          ],
                          IconButton(
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _currentSearchIndex = 0;
                                _totalSearchResults = 0;
                                _searchResultsPerLink.clear();
                              });
                            },
                          ),
                        ],
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentSearchIndex = 0;
                  if (value.isEmpty) {
                    _searchResultsPerLink.clear();
                    _totalSearchResults = 0;
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          if (widget.tab.activeCommentators.isNotEmpty)
            IconButton(
              icon: Icon(
                _allExpanded
                    ? FluentIcons.arrow_collapse_all_24_regular
                    : FluentIcons.arrow_expand_all_24_regular,
              ),
              tooltip:
                  _allExpanded ? 'סגור את כל המפרשים' : 'פתח את כל המפרשים',
              onPressed: () {
                setState(() {
                  _allExpanded = !_allExpanded;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCommentariesView() {
    if (_showFilterTab) {
      return _buildCommentatorsFilter();
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _buildCommentariesListContent(),
        ),
      ],
    );
  }

  Widget _buildCommentariesListContent() {
    debugPrint('=== PDF Commentary Debug ===');
    debugPrint('currentTextLineNumber: ${widget.tab.currentTextLineNumber}');
    debugPrint('total links: ${widget.tab.links.length}');
    debugPrint('activeCommentators: ${widget.tab.activeCommentators}');

    // בדיקה אם יש מספר שורה נוכחי
    if (widget.tab.currentTextLineNumber == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'לא נמצאו מפרשים לדף זה',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Debug: currentTextLineNumber is null',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.7,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // סינון מפרשים לפי טווח השורות של העמוד הנוכחי
    final currentLine = widget.tab.currentTextLineNumber!;

    // מציאת טווח השורות של העמוד הנוכחי
    int startLine = currentLine;
    int endLine = startLine;

    if (widget.tab.pdfHeadings != null) {
      final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();
      final currentIndex =
          sortedHeadings.indexWhere((e) => e.value == currentLine);

      if (currentIndex != -1 && currentIndex < sortedHeadings.length - 1) {
        endLine = sortedHeadings[currentIndex + 1].value - 1;
      } else {
        // אם זה העמוד האחרון, נניח טווח של 50 שורות
        endLine = startLine + 50;
      }
    } else {
      // אם אין headings, נניח טווח של 50 שורות
      endLine = startLine + 50;
    }

    debugPrint('Looking for links in range: $startLine-$endLine');
    debugPrint('Active commentators: ${widget.tab.activeCommentators.length}');

    final relevantLinks = widget.tab.links
        .where((link) =>
            link.index1 >= startLine &&
            link.index1 <= endLine &&
            (link.connectionType == "commentary" ||
                link.connectionType == "targum") &&
            widget.tab.activeCommentators
                .contains(utils.getTitleFromPath(link.path2)))
        .toList();

    // מיון הקישורים קודם לפי שם הספר ואז לפי מספר השורה
    // כך כל הקישורים של אותו מפרש יהיו ביחד ויקובצו נכון
    relevantLinks.sort((a, b) {
      // קודם לפי שם הספר
      final titleA = utils.getTitleFromPath(a.path2);
      final titleB = utils.getTitleFromPath(b.path2);
      final titleCompare = titleA.compareTo(titleB);
      if (titleCompare != 0) return titleCompare;

      // אם אותו ספר, לפי מספר השורה
      return a.index1.compareTo(b.index1);
    });

    debugPrint('Found ${relevantLinks.length} relevant links');

    if (relevantLinks.isEmpty) {
      // בדיקה מפורטת למה אין קישורים
      final allLinksInRange = widget.tab.links
          .where((link) => link.index1 >= startLine && link.index1 <= endLine)
          .toList();

      final hasCommentaryLinks = allLinksInRange.any((link) =>
          link.connectionType == "commentary" ||
          link.connectionType == "targum");

      // אם יש מפרשים זמינים אבל לא נבחרו בכלל - פתח אוטומטית את מסך הבחירה
      if (hasCommentaryLinks && widget.tab.activeCommentators.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showFilterTab) {
            setState(() {
              _showFilterTab = true;
            });
          }
        });
        return const Center(child: CircularProgressIndicator());
      }

      // אין מפרשים בכלל לקטע הזה, או שיש מפרשים נבחרים אבל הם לא רלוונטיים לדף
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                hasCommentaryLinks
                    ? 'לא נמצאו מפרשים מהנבחרים לדף זה'
                    : 'לא נמצאו מפרשים לקטע הנבחר',
                style: TextStyle(
                  fontSize: widget.fontSize * 0.9,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasCommentaryLinks) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showFilterTab = true;
                    });
                  },
                  icon: const Icon(FluentIcons.apps_list_24_regular),
                  label: const Text('בחר מפרשים'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // קיבוץ המפרשים לפי ספר
    final groups = _groupConsecutiveLinks(relevantLinks);

    // מיון הקבוצות לפי סדר הדורות
    return FutureBuilder<List<CommentaryGroup>>(
      future: _sortGroupsByEra(groups),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sortedGroups = snapshot.data!;
        _orderedGroups = sortedGroups;

        // Rebuild _orderedLinks based on groups
        _orderedLinks = [];
        for (final group in sortedGroups) {
          // We need to verify link order inside group.
          // In _buildCommentariesView, relevantLinks are sorted by title then index.
          // _groupConsecutiveLinks groups them.
          // So the links inside group.links should already be in order.
          _orderedLinks.addAll(group.links);
        }

        // Initialize keys
        final currentLinkKeys =
            _orderedLinks.map((l) => _getLinkKey(l)).toSet();
        _itemKeys.removeWhere((key, value) => !currentLinkKeys.contains(key));
        for (final key in currentLinkKeys) {
          if (!_itemKeys.containsKey(key)) {
            _itemKeys[key] = GlobalKey();
          }
        }

        return ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ScrollablePositionedList.builder(
              key: PageStorageKey(
                  'commentary_${widget.tab.currentTextLineNumber}_${widget.tab.activeCommentators.hashCode}_$_allExpanded'),
              itemCount: sortedGroups.length,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              scrollOffsetController: _scrollOffsetController,
              itemBuilder: (context, index) {
                final group = sortedGroups[index];
                return _buildCommentaryGroupTile(group);
              },
            ));
      },
    );
  }

  void _scrollToSearchResult() {
    if (_totalSearchResults == 0 ||
        _orderedLinks.isEmpty ||
        !_itemScrollController.isAttached) {
      return;
    }

    int cumulativeIndex = 0;
    Link? targetLink;

    // 1. מוצא את ה-link שמכיל את תוצאת החיפוש הנוכחית
    for (final link in _orderedLinks) {
      final linkKey = _getLinkKey(link);
      final itemResults = _searchResultsPerLink[linkKey] ?? 0;
      if (_currentSearchIndex < cumulativeIndex + itemResults) {
        targetLink = link;
        break;
      }
      cumulativeIndex += itemResults;
    }

    if (targetLink == null) return;

    // 2. מוצא את ה-group שמכיל את ה-link
    // Since we have _orderedGroups
    int targetGroupIndex = -1;
    CommentaryGroup? targetGroup;

    for (int i = 0; i < _orderedGroups.length; i++) {
      final group = _orderedGroups[i];
      // Check if link is in group. Note: link instances might differ if rebuilt, so compare by key
      final targetLinkKey = _getLinkKey(targetLink);
      if (group.links.any((l) => _getLinkKey(l) == targetLinkKey)) {
        targetGroupIndex = i;
        targetGroup = group;
        break;
      }
    }

    if (targetGroupIndex == -1 || targetGroup == null) return;

    // 3. מבטיח שה-ExpansionTile של הקבוצה פתוח
    final groupKey = targetGroup.bookTitle;
    final bool isCurrentlyExpanded = _expansionStates[groupKey] ?? _allExpanded;

    if (!isCurrentlyExpanded) {
      setState(() {
        _expansionStates[groupKey] = true;
      });
    }

    // 4. ביצוע הגלילה
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (!isCurrentlyExpanded) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }

      // Check if group is already visible
      bool groupVisible = false;
      if (_itemPositionsListener.itemPositions.value.isNotEmpty) {
        final positions = _itemPositionsListener.itemPositions.value;
        if (positions.any((p) => p.index == targetGroupIndex)) {
          groupVisible = true;
        }
      }

      if (_itemScrollController.isAttached && !groupVisible) {
        _itemScrollController.scrollTo(
          index: targetGroupIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.05,
        );
        // Wait for group scroll
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
      }

      // Micro-scrolling to specific link
      final linkKey = _getLinkKey(targetLink!);
      final itemKey = _itemKeys[linkKey];
      final BuildContext? itemContext = itemKey?.currentContext;

      if (itemContext != null && itemContext.mounted) {
        try {
          final scrollable = Scrollable.of(itemContext);
          scrollable.position.ensureVisible(
            itemContext.findRenderObject()!,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: 0.1,
          );
        } catch (e) {
          debugPrint('Error scrolling to item: $e');
        }
      } else if (groupVisible) {
        // Group is visible but item context is not found (perhaps off screen in the large column?)
        // In this case, maybe we SHOULD scroll the group to top to be safe, or just scroll to group?
        // If we are here, it means we thought group is visible so we didn't scroll the group.
        // But we can't find the item context.
        // Let's force scroll the group if item context is missing even if group is technically visible.
        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: targetGroupIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.05,
          );
          await Future.delayed(const Duration(milliseconds: 350));
          if (!mounted) return;

          // Retry finding context
          final retryContext = itemKey?.currentContext;
          if (retryContext != null && retryContext.mounted) {
            final scrollable = Scrollable.of(retryContext);
            scrollable.position.ensureVisible(
              retryContext.findRenderObject()!,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        }
      }
    });
  }

  /// ממיין קבוצות מפרשים לפי סדר הדורות
  Future<List<CommentaryGroup>> _sortGroupsByEra(
      List<CommentaryGroup> groups) async {
    // יצירת מפה של כל שם ספר לדור שלו
    final Map<String, int> eraOrder = {};

    for (final group in groups) {
      final title = group.bookTitle;

      // בדיקה לאיזה דור שייך הספר
      if (await utils.hasTopic(title, 'תורה שבכתב')) {
        eraOrder[title] = 0;
      } else if (await utils.hasTopic(title, 'חז"ל')) {
        eraOrder[title] = 1;
      } else if (await utils.hasTopic(title, 'ראשונים')) {
        eraOrder[title] = 2;
      } else if (await utils.hasTopic(title, 'אחרונים')) {
        eraOrder[title] = 3;
      } else if (await utils.hasTopic(title, 'מחברי זמננו')) {
        eraOrder[title] = 4;
      } else {
        eraOrder[title] = 5; // שאר מפרשים
      }
    }

    // מיון הקבוצות לפי הדור
    final sortedGroups = List<CommentaryGroup>.from(groups);
    sortedGroups.sort((a, b) {
      final orderA = eraOrder[a.bookTitle] ?? 5;
      final orderB = eraOrder[b.bookTitle] ?? 5;

      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      // אם שני הספרים באותו דור, ממיינים לפי שם
      return a.bookTitle.compareTo(b.bookTitle);
    });

    return sortedGroups;
  }

  Widget _buildCommentaryGroupTile(CommentaryGroup group) {
    final groupKey = group.bookTitle;
    if (!_expansionStates.containsKey(groupKey)) {
      _expansionStates[groupKey] = _allExpanded;
    }
    final isExpanded = _expansionStates[groupKey] ?? _allExpanded;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return _CollapsibleCommentaryGroup(
          key: PageStorageKey(
              '${group.bookTitle}_${widget.tab.currentTextLineNumber}'),
          group: group,
          settingsState: settingsState,
          tab: widget.tab,
          fontSize: widget.fontSize,
          openBookCallback: widget.openBookCallback,
          buildContextMenu: _buildCommentaryContextMenu,
          isExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _expansionStates[groupKey] = expanded;
            });
          },
          searchQuery: _searchQuery,
          onSearchResultsCountUpdate: _updateSearchResultsCount,
          getKeyForLink: _getLinkKeyObject,
          getItemSearchIndex: _getItemSearchIndex, // Pass the function
        );
      },
    );
  }

  // Helper method used in _scrollToSearchResult to inject keys
  Key? _getLinkKeyObject(Link link) {
    return _itemKeys[_getLinkKey(link)];
  }

  Widget _buildLinksView() {
    if (widget.tab.currentTextLineNumber == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    // סינון קישורים (לא מפרשים) לפי טווח השורות של העמוד
    final currentLine = widget.tab.currentTextLineNumber!;

    // מציאת טווח השורות של העמוד הנוכחי
    int startLine = currentLine;
    int endLine = startLine;

    if (widget.tab.pdfHeadings != null) {
      final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();
      final currentIndex =
          sortedHeadings.indexWhere((e) => e.value == currentLine);

      if (currentIndex != -1 && currentIndex < sortedHeadings.length - 1) {
        endLine = sortedHeadings[currentIndex + 1].value - 1;
      } else {
        endLine = startLine + 50;
      }
    } else {
      endLine = startLine + 50;
    }

    final relevantLinks = widget.tab.links
        .where((link) =>
            link.index1 >= startLine &&
            link.index1 <= endLine &&
            link.connectionType != "commentary" &&
            link.connectionType != "targum" &&
            link.start == null &&
            link.end == null)
        .toList();

    // מיון הקישורים לפי מספר השורה
    relevantLinks.sort((a, b) => a.index1.compareTo(b.index1));

    if (relevantLinks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'לא נמצאו קישורים לדף זה',
            style: TextStyle(
              fontSize: widget.fontSize * 0.9,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: relevantLinks.length,
      itemBuilder: (context, index) {
        final link = relevantLinks[index];
        return _buildLinkTile(link);
      },
    );
  }

  Widget _buildLinkTile(Link link) {
    final keyStr = '${link.path2}_${link.index2}';
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return ctx.ContextMenuRegion(
          contextMenu: _buildCommentaryContextMenu(link),
          child: ExpansionTile(
            key: PageStorageKey(keyStr),
            maintainState: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            collapsedBackgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(
              utils.getTitleFromPath(link.path2),
              style: TextStyle(
                fontSize: settingsState.commentatorsFontSize - 2,
                fontWeight: FontWeight.bold,
                fontFamily: settingsState.commentatorsFontFamily,
              ),
            ),
            subtitle: Text(
              link.heRef,
              style: TextStyle(
                fontSize: settingsState.commentatorsFontSize - 4,
                fontWeight: FontWeight.normal,
                fontFamily: settingsState.commentatorsFontFamily,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
            children: [
              GestureDetector(
                onTap: () {
                  // פתיחת הספר בלחיצה על הקישור
                  widget.openBookCallback(
                    TextBookTab(
                      book: TextBook(
                        title: utils.getTitleFromPath(link.path2),
                      ),
                      index: link.index2 - 1,
                      openLeftPane:
                          (Settings.getValue<bool>('key-pin-sidebar') ??
                                  false) ||
                              (Settings.getValue<bool>(
                                      'key-default-sidebar-open') ??
                                  false),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: FutureBuilder<String>(
                    future: link.content,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        debugPrint(
                            'Error loading link content: ${snapshot.error}');
                        debugPrint('Stack trace: ${snapshot.stackTrace}');
                        return Text('שגיאה: ${snapshot.error}');
                      }
                      return BlocBuilder<SettingsBloc, SettingsState>(
                        builder: (context, settingsState) {
                          return Text(
                            utils.stripHtmlIfNeeded(snapshot.data ?? ''),
                            style: TextStyle(
                              fontSize: settingsState.commentatorsFontSize,
                              fontFamily: settingsState.commentatorsFontFamily,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotesView() {
    // נשתמש בספר הטקסט המקורי תמיד - כך ההערות יהיו משותפות
    return FutureBuilder(
      future: DataRepository.instance.library.then(
        (library) => library.findBookByTitle(widget.tab.book.title, TextBook),
      ),
      builder: (context, snapshot) {
        final bookId = widget.tab.book.title; // תמיד נשתמש בשם הספר המקורי

        debugPrint('Building notes view for bookId: $bookId');

        return PersonalNotesSidebar(
          key: ValueKey(bookId),
          bookId: bookId,
          onNavigateToLine: (lineNumber) {
            // מנסים למצוא את העמוד המתאים למספר השורה
            if (widget.tab.pdfHeadings != null) {
              final sortedHeadings =
                  widget.tab.pdfHeadings!.getSortedHeadings();

              // מציאת הכותרת הקרובה ביותר למספר השורה
              for (int i = sortedHeadings.length - 1; i >= 0; i--) {
                if (sortedHeadings[i].value <= lineNumber) {
                  // מצאנו את הכותרת - צריך למצוא את העמוד שלה
                  final headingTitle = sortedHeadings[i].key;
                  final targetPage = _findPageForHeading(headingTitle);

                  if (targetPage != null) {
                    debugPrint(
                        'Navigating from line $lineNumber to page: $targetPage');
                    if (widget.tab.pdfViewerController.isReady) {
                      widget.tab.pdfViewerController
                          .goToPage(pageNumber: targetPage);
                    }
                    return;
                  }
                  break;
                }
              }
            }

            // אם לא הצלחנו למצוא, נניח שזה מספר עמוד
            debugPrint('Navigating to page: $lineNumber');
            if (widget.tab.pdfViewerController.isReady) {
              widget.tab.pdfViewerController.goToPage(pageNumber: lineNumber);
            }
          },
        );
      },
    );
  }

  // מוצא את העמוד של כותרת מסוימת
  int? _findPageForHeading(String heading) {
    final outline = widget.tab.outline.value;
    if (outline == null) return null;

    int? findInNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        if (node.title == heading) {
          return node.dest?.pageNumber;
        }
        final childResult = findInNodes(node.children);
        if (childResult != null) return childResult;
      }
      return null;
    }

    return findInNodes(outline);
  }
}

/// Widget מותאם אישית להצגת קבוצת מפרשים עם אפשרות כיווץ/הרחבה
/// שלא מפריע לבחירת טקסט והעתקה (במקום ExpansionTile)
class _CollapsibleCommentaryGroup extends StatefulWidget {
  final CommentaryGroup group;
  final SettingsState settingsState;
  final PdfBookTab tab;
  final double fontSize;
  final Function(OpenedTab) openBookCallback;
  final ctx.ContextMenu Function(Link) buildContextMenu;
  final bool isExpanded;
  final Function(bool) onExpansionChanged;
  final String searchQuery;
  final Function(Link, int)? onSearchResultsCountUpdate;
  final Key? Function(Link)? getKeyForLink; // Support linking keys
  final int Function(Link)? getItemSearchIndex; // Support highlighting

  const _CollapsibleCommentaryGroup({
    super.key,
    required this.group,
    required this.settingsState,
    required this.tab,
    required this.fontSize,
    required this.openBookCallback,
    required this.buildContextMenu,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.searchQuery,
    this.onSearchResultsCountUpdate,
    this.getKeyForLink,
    this.getItemSearchIndex,
  });

  @override
  State<_CollapsibleCommentaryGroup> createState() =>
      _CollapsibleCommentaryGroupState();
}

class _CollapsibleCommentaryGroupState
    extends State<_CollapsibleCommentaryGroup> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת הקבוצה - ניתנת ללחיצה להרחבה/כיווץ
        InkWell(
          onTap: () {
            widget.onExpansionChanged(!widget.isExpanded);
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Icon(
                  widget.isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_left,
                  size: 20,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.group.bookTitle,
                    style: TextStyle(
                      fontSize: widget.settingsState.commentatorsFontSize - 2,
                      fontWeight: FontWeight.bold,
                      fontFamily: widget.settingsState.commentatorsFontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // תוכן המפרשים - מוצג רק כשמורחב
        if (widget.isExpanded)
          ...widget.group.links.map((link) {
            return ctx.ContextMenuRegion(
              key: widget.getKeyForLink
                  ?.call(link), // Attach the key here for scrolling
              contextMenu: widget.buildContextMenu(link),
              child: Padding(
                padding: const EdgeInsets.only(
                    right: 32.0, left: 16.0, top: 8.0, bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.heRef,
                      style: TextStyle(
                        fontSize: widget.settingsState.commentatorsFontSize - 4,
                        fontWeight: FontWeight.normal,
                        fontFamily: widget.settingsState.commentatorsFontFamily,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    PdfCommentaryContent(
                      key: ValueKey(
                          '${link.path2}_${link.index2}_${widget.tab.currentTextLineNumber}'),
                      link: link,
                      fontSize: widget.fontSize,
                      openBookCallback: widget.openBookCallback,
                      searchQuery: widget.searchQuery,
                      onSearchResultsCountChanged: (count) {
                        widget.onSearchResultsCountUpdate?.call(link, count);
                      },
                      currentSearchIndex:
                          widget.getItemSearchIndex?.call(link) ?? -1,
                    ),
                  ],
                ),
              ),
            );
          }),
        const Divider(height: 1),
      ],
    );
  }
}
