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
            Container(
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
                  // כפתור סינון מפרשים - בהתחלה
                  IconButton(
                    icon: Icon(
                      FluentIcons.filter_24_regular,
                      color: _showFilterTab
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                    ),
                    tooltip: 'בחירת מפרשים',
                    onPressed: () {
                      setState(() {
                        _showFilterTab = !_showFilterTab;
                      });
                    },
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // חישוב גודל הטקסט לפי רוחב זמין
                        final availableWidth = constraints.maxWidth;
                        final fontSize = availableWidth < 200
                            ? 11.0
                            : (availableWidth < 300 ? 13.0 : 14.0);

                        return TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          padding: EdgeInsets.zero,
                          labelPadding: EdgeInsets.symmetric(
                              horizontal: availableWidth < 250 ? 8 : 16),
                          tabs: [
                            Tab(
                              child: Text(
                                'מפרשים',
                                style: TextStyle(fontSize: fontSize),
                              ),
                            ),
                            Tab(
                              child: Text(
                                'קישורים',
                                style: TextStyle(fontSize: fontSize),
                              ),
                            ),
                            Tab(
                              child: Text(
                                'הערות אישיות',
                                style: TextStyle(fontSize: fontSize),
                              ),
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
                        );
                      },
                    ),
                  ),
                  // לחצן סגירה
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    margin: const EdgeInsets.all(8.0),
                    child: IconButton(
                      iconSize: 18,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      onPressed: widget.onClosePane,
                    ),
                  ),
                ],
              ),
            ),
            // תוכן הכרטיסיות
            Expanded(
              child: _showFilterTab
                  ? const CommentatorsListView() // טאב הסינון
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // כרטיסיית המפרשים - מציגה את תוכן המפרשים הפעילים
                        CommentaryListBase(
                          openBookCallback: widget.openBookCallback,
                          fontSize: widget.fontSize,
                          showSearch: widget.showSearch,
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
