import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/panel_tab_header.dart';

/// Widget שמציג כרטיסיות עם מפרשים וקישורים בחלונית הצד
class TabbedCommentaryPanel extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final int? initialTabIndex; // אינדקס הכרטיסייה הראשונית
  final Function(int)? onTabChanged; // callback כשהטאב משתנה
  final bool showSplitView; // האם במצב מפוצל (true) או מפרשים למטה (false)
  final TabController? controller;
  final bool showHeader;

  const TabbedCommentaryPanel({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    required this.showSearch,
    this.onClosePane,
    this.initialTabIndex,
    this.onTabChanged,
    this.showSplitView = true,
    this.controller,
    this.showHeader = true,
  });

  @override
  State<TabbedCommentaryPanel> createState() => _TabbedCommentaryPanelState();
}

class _TabbedCommentaryPanelState extends State<TabbedCommentaryPanel>
    with SingleTickerProviderStateMixin {
  TabController? _ownedTabController;

  TabController get _tabController => widget.controller ?? _ownedTabController!;

  // פונקציה ציבורית לעבור לכרטיסיית הקישורים
  void switchToLinksTab() {
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedTabController = _createOwnedTabController();
    }
  }

  @override
  void didUpdateWidget(TabbedCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _ownedTabController?.dispose();
        _ownedTabController = null;
      }
      if (widget.controller == null) {
        _ownedTabController = _createOwnedTabController();
      }
    }

    // אם יש אינדקס חדש, עובר אליו (עם וידוא שהוא תקף)
    if (widget.initialTabIndex != null &&
        widget.initialTabIndex != oldWidget.initialTabIndex) {
      final validIndex = widget.initialTabIndex!.clamp(0, 2);
      // וודא שהאינדקס שונה מהנוכחי לפני שמנסים לעבור אליו
      if (_tabController.index != validIndex) {
        _tabController.animateTo(validIndex);
      }
    }
  }

  @override
  void dispose() {
    _ownedTabController?.dispose();
    super.dispose();
  }

  TabController _createOwnedTabController() {
    // וידוא שהאינדקס ההתחלתי תקף (בין 0 ל-2)
    final validInitialIndex = (widget.initialTabIndex ?? 0).clamp(0, 2);
    final controller = TabController(
      length: 3, // 3 טאבים: מפרשים, קישורים והערות אישיות
      vsync: this,
      initialIndex: validInitialIndex, // כרטיסייה ראשונית
    );

    // מאזין לשינויים בטאב ושומר אותם
    controller.addListener(() {
      if (!controller.indexIsChanging &&
          controller.index >= 0 &&
          controller.index < 3) {
        widget.onTabChanged?.call(controller.index);
      }
    });
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      builder: (context, state) {
        return Column(
          children: [
            // שורת הכרטיסיות עם כפתור סגירה
            if (widget.showHeader)
              TabbedCommentaryPanelHeader(
                controller: _tabController,
                onClosePane: widget.onClosePane,
                showSplitView: widget.showSplitView,
              ),
            // תוכן הכרטיסיות
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // כרטיסייה ראשונה: מפרשים (מצב מפוצל) או הגדרות מפרשים (מצב למטה)
                  if (widget.showSplitView)
                    CommentaryListBase(
                      key: const ValueKey('commentary_list_tabbed'),
                      openBookCallback: widget.openBookCallback,
                      fontSize: widget.fontSize,
                      showSearch: widget.showSearch,
                      selectedCommentatorsOverride: state.activeCommentators,
                      onSelectedCommentatorsOverrideChanged: (commentators) {
                        context
                            .read<TextBookBloc>()
                            .add(UpdateCommentators(commentators));
                      },
                    )
                  else
                    const CommentatorsListView(
                      key: ValueKey('commentators_settings_tabbed'),
                    ),
                  // כרטיסיית הקישורים
                  SelectedLineLinksView(
                    openBookCallback: widget.openBookCallback,
                    fontSize: widget.fontSize,
                    showVisibleLinksIfNoSelection:
                        widget.initialTabIndex == 1, // אם נפתח ישירות לקישורים
                  ),
                  // כרטיסיית ההערות האישיות
                  PersonalNotesSidebar(
                    bookId: state.book.title,
                    categoryId: state.book.categoryId,
                    onNavigateToLine: (line) =>
                        _handleNoteNavigation(context, state, line),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleNoteNavigation(
    BuildContext context,
    TextBookLoaded state,
    int lineNumber,
  ) async {
    if (lineNumber < 1 || state.content.isEmpty) {
      return;
    }

    final targetIndex = (lineNumber - 1).clamp(0, state.content.length - 1);

    await state.scrollController.scrollTo(
      index: targetIndex,
      alignment: 0.05,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    if (!mounted) return;
    if (!context.mounted) return;

    final bloc = context.read<TextBookBloc>();
    bloc.add(UpdateSelectedIndex(targetIndex));
    bloc.add(HighlightLine(targetIndex));
  }
}

class TabbedCommentaryPanelHeader extends StatelessWidget {
  final TabController controller;
  final VoidCallback? onClosePane;
  final bool showSplitView;
  final double height;

  const TabbedCommentaryPanelHeader({
    super.key,
    required this.controller,
    this.onClosePane,
    required this.showSplitView,
    this.height = 60,
  });

  Widget _tabLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // מתחת לסף זה - הצג אייקונים בלבד (ללא טקסט)
        final isCompact = constraints.maxWidth < 270;
        final firstTabIcon = Icon(
          showSplitView
              ? FluentIcons.book_24_regular
              : FluentIcons.settings_24_regular,
          size: 18,
        );
        return PanelTabHeader(
          controller: controller,
          height: height,
          onClose: onClosePane,
          tabs: isCompact
              ? [
                  Tab(icon: firstTabIcon),
                  const Tab(
                    icon: Icon(FluentIcons.link_24_regular, size: 18),
                  ),
                  const Tab(
                    icon: Icon(FluentIcons.note_24_regular, size: 18),
                  ),
                ]
              : [
                  Tab(
                    icon: firstTabIcon,
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    child: _tabLabel(
                      showSplitView ? 'מפרשים' : 'סינון מפרשים',
                    ),
                  ),
                  Tab(
                    icon: const Icon(FluentIcons.link_24_regular, size: 18),
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    child: _tabLabel('קישורים'),
                  ),
                  Tab(
                    icon: const Icon(FluentIcons.note_24_regular, size: 18),
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    child: _tabLabel('הערות'),
                  ),
                ],
        );
      },
    );
  }
}
