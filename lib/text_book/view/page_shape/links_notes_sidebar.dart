import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';

/// חלונית פנימית עבור צורת הדף שמציגה קישורים והערות אישיות.
class LinksNotesSidebar extends StatefulWidget {
  final String bookId;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final ValueChanged<int> onNavigateToLine;
  final VoidCallback onClosePane;
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  const LinksNotesSidebar({
    super.key,
    required this.bookId,
    required this.openBookCallback,
    required this.fontSize,
    required this.onNavigateToLine,
    required this.onClosePane,
    this.initialTabIndex = 0,
    this.onTabChanged,
  });

  @override
  State<LinksNotesSidebar> createState() => _LinksNotesSidebarState();
}

class _LinksNotesSidebarState extends State<LinksNotesSidebar>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged?.call(_tabController.index);
      }
    });
  }

  @override
  void didUpdateWidget(covariant LinksNotesSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetIndex = widget.initialTabIndex.clamp(0, 1);
    if (targetIndex != oldWidget.initialTabIndex &&
        _tabController.index != targetIndex) {
      _tabController.animateTo(targetIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Container(
              decoration: BoxDecoration(
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
                          icon: Icon(FluentIcons.link_24_regular, size: 18),
                          iconMargin: EdgeInsets.only(bottom: 2),
                          height: 48,
                          child: Text(
                            'קישורים',
                            style: TextStyle(fontSize: 12),
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                        Tab(
                          icon: Icon(FluentIcons.note_24_regular, size: 18),
                          iconMargin: EdgeInsets.only(bottom: 2),
                          height: 48,
                          child: Text(
                            'הערות',
                            style: TextStyle(fontSize: 12),
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      ],
                      labelColor: colorScheme.primary,
                      unselectedLabelColor:
                          colorScheme.onSurface.withValues(alpha: 0.6),
                      indicatorColor: colorScheme.primary,
                      dividerColor: Colors.transparent,
                    ),
                  ),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    onPressed: widget.onClosePane,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SelectedLineLinksView(
                  openBookCallback: widget.openBookCallback,
                  fontSize: widget.fontSize,
                  showVisibleLinksIfNoSelection: widget.initialTabIndex == 0,
                ),
                PersonalNotesSidebar(
                  bookId: widget.bookId,
                  onNavigateToLine: widget.onNavigateToLine,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
