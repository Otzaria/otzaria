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

/// Widget שמציג כרטיסיות עם מפרשים וקישורים בחלונית הצד
class TabbedCommentaryPanel extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final int? initialTabIndex; // אינדקס הכרטיסייה הראשונית
  final Function(int)? onTabChanged; // callback כשהטאב משתנה

  const TabbedCommentaryPanel({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    required this.showSearch,
    this.onClosePane,
    this.initialTabIndex,
    this.onTabChanged,
  });

  @override
  State<TabbedCommentaryPanel> createState() => _TabbedCommentaryPanelState();
}

class _TabbedCommentaryPanelState extends State<TabbedCommentaryPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showFilterTab = false; // האם להציג את טאב הסינון

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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // שורת הכרטיסיות עם כפתור סגירה
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
                    // כפתור סינון מפרשים - בהתחלה
                    IconButton(
                      icon: Icon(
                        FluentIcons.apps_list_24_regular,
                        color: _showFilterTab
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                        size: 20,
                      ),
                      tooltip: 'בחירת מפרשים',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed: () {
                        setState(() {
                          _showFilterTab = !_showFilterTab;
                        });
                      },
                    ),
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(
                            icon: Icon(FluentIcons.book_24_regular, size: 18),
                            iconMargin: EdgeInsets.only(bottom: 2),
                            height: 48,
                            child:
                                Text('מפרשים', style: TextStyle(fontSize: 12)),
                          ),
                          Tab(
                            icon: Icon(FluentIcons.link_24_regular, size: 18),
                            iconMargin: EdgeInsets.only(bottom: 2),
                            height: 48,
                            child:
                                Text('קישורים', style: TextStyle(fontSize: 12)),
                          ),
                          Tab(
                            icon: Icon(FluentIcons.note_24_regular, size: 18),
                            iconMargin: EdgeInsets.only(bottom: 2),
                            height: 48,
                            child:
                                Text('הערות', style: TextStyle(fontSize: 12)),
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
                      onPressed: widget.onClosePane,
                    ),
                  ],
                ),
              ),
            ),
            // תוכן הכרטיסיות
            Expanded(
              child: _showFilterTab
                  ? CommentatorsListView(
                      onCommentatorSelected: () {
                        // סגירת מסך בחירת המפרשים וחזרה לטאב המפרשים
                        setState(() {
                          _showFilterTab = false;
                        });
                      },
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // כרטיסיית המפרשים - מציגה את תוכן המפרשים הפעילים
                        CommentaryListBase(
                          openBookCallback: widget.openBookCallback,
                          fontSize: widget.fontSize,
                          showSearch: widget.showSearch,
                          onOpenCommentatorsFilter: () {
                            setState(() {
                              _showFilterTab = true;
                            });
                          },
                        ),
                        // כרטיסיית הקישורים
                        SelectedLineLinksView(
                          openBookCallback: widget.openBookCallback,
                          fontSize: widget.fontSize,
                          showVisibleLinksIfNoSelection:
                              widget.initialTabIndex ==
                                  1, // אם נפתח ישירות לקישורים
                        ),
                        // כרטיסיית ההערות האישיות
                        PersonalNotesSidebar(
                          bookId: state.book.title,
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
