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
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

/// Widget שמציג כרטיסיות עם מפרשים וקישורים בחלונית הצד
class TabbedCommentaryPanel extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final int? initialTabIndex; // אינדקס הכרטיסייה הראשונית
  final Function(int)? onTabChanged; // callback כשהטאב משתנה
  final bool showSplitView; // האם במצב מפוצל (true) או מפרשים למטה (false)
  final SelectionSyncController? selectionSyncController;

  const TabbedCommentaryPanel({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    required this.showSearch,
    this.onClosePane,
    this.initialTabIndex,
    this.onTabChanged,
    this.showSplitView = true,
    this.selectionSyncController,
  });

  @override
  State<TabbedCommentaryPanel> createState() => _TabbedCommentaryPanelState();
}

class _TabbedCommentaryPanelState extends State<TabbedCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // פונקציה ציבורית לעבור לכרטיסיית הקישורים
  void switchToLinksTab() {
    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  @override
  void initState() {
    super.initState();
    // וידוא שהאינדקס ההתחלתי תקף (בין 0 ל-2)
    final validInitialIndex = (widget.initialTabIndex ?? 0).clamp(0, 2);
    _tabController = TabController(
      length: 3, // 3 טאבים: מפרשים, קישורים והערות אישיות
      vsync: this,
      initialIndex: validInitialIndex, // כרטיסייה ראשונית
    );

    // מאזין לשינויים בטאב ושומר אותם
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging &&
          _tabController.index >= 0 &&
          _tabController.index < 3) {
        widget.onTabChanged?.call(_tabController.index);
      }
    });
  }

  @override
  void didUpdateWidget(TabbedCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _tabController.dispose();
    super.dispose();
  }

  Widget _tabLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      builder: (context, state) {
        return Column(
          children: [
            // שורת הכרטיסיות עם כפתור סגירה
            LayoutBuilder(
              builder: (context, constraints) {
                // מתחת לסף זה - הצג אייקונים בלבד (ללא טקסט)
                final isCompact = constraints.maxWidth < 270;
                final firstTabIcon = Icon(
                  widget.showSplitView
                      ? FluentIcons.book_24_regular
                      : FluentIcons.settings_24_regular,
                  size: 18,
                );
                return PanelTabHeader(
                  controller: _tabController,
                  onClose: widget.onClosePane,
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
                              widget.showSplitView ? 'מפרשים' : 'סינון מפרשים',
                            ),
                          ),
                          Tab(
                            icon: const Icon(FluentIcons.link_24_regular,
                                size: 18),
                            iconMargin: const EdgeInsets.only(bottom: 2),
                            child: _tabLabel('קישורים'),
                          ),
                          Tab(
                            icon: const Icon(FluentIcons.note_24_regular,
                                size: 18),
                            iconMargin: const EdgeInsets.only(bottom: 2),
                            child: _tabLabel('הערות'),
                          ),
                        ],
                );
              },
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
                      selectionSyncController: widget.selectionSyncController,
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
                    selectionSyncController: widget.selectionSyncController,
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
