import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';

class LinksNotesSidebar extends StatefulWidget {
  final String bookId;
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final ValueChanged<int> onNavigateToLine;
  final VoidCallback? onClosePane;
  final int? initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  const LinksNotesSidebar({
    super.key,
    required this.bookId,
    required this.openBookCallback,
    required this.fontSize,
    required this.onNavigateToLine,
    this.onClosePane,
    this.initialTabIndex,
    this.onTabChanged,
  });

  @override
  State<LinksNotesSidebar> createState() => LinksNotesSidebarState();
}

class LinksNotesSidebarState extends State<LinksNotesSidebar>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  void switchToTab(int index) {
    final validIndex = index.clamp(0, 1);
    if (_tabController.index != validIndex) {
      _tabController.animateTo(validIndex);
    }
  }

  @override
  void initState() {
    super.initState();
    final validInitialIndex = (widget.initialTabIndex ?? 0).clamp(0, 1);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: validInitialIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging &&
          _tabController.index >= 0 &&
          _tabController.index < 2) {
        widget.onTabChanged?.call(_tabController.index);
      }
    });
  }

  @override
  void didUpdateWidget(covariant LinksNotesSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != null &&
        widget.initialTabIndex != oldWidget.initialTabIndex) {
      final validIndex = widget.initialTabIndex!.clamp(0, 1);
      if (_tabController.index != validIndex) {
        _tabController.animateTo(validIndex);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  ),
                ),
                if (widget.onClosePane != null)
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
                showVisibleLinksIfNoSelection: true,
              ),
              PersonalNotesSidebar(
                bookId: widget.bookId,
                onNavigateToLine: widget.onNavigateToLine,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
