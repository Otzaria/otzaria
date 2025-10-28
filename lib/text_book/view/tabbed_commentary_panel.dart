import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:otzaria/notes/widgets/notes_sidebar.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

/// Widget שמציג כרטיסיות עם מפרשים וקישורים בחלונית הצד
class TabbedCommentaryPanel extends StatefulWidget {
  final Function(OpenedTab) openBookCallback;
  final double fontSize;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final int? initialTabIndex; // אינדקס הכרטיסייה הראשונית

  const TabbedCommentaryPanel({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    required this.showSearch,
    this.onClosePane,
    this.initialTabIndex,
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
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex ?? 0, // כרטיסייה ראשונית
    );
  }

  @override
  void didUpdateWidget(TabbedCommentaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם יש אינדקס חדש, עובר אליו
    if (widget.initialTabIndex != null &&
        widget.initialTabIndex != oldWidget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex!);
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
            // שורת הכרטיסיות עם לחצן סגירה
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
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'מפרשים'),
                        Tab(text: 'קישורים'),
                        Tab(text: 'הערות אישיות'),
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
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClosePane,
                    ),
                  ),
                ],
              ),
            ),
            // תוכן הכרטיסיות
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // כרטיסיית המפרשים
                  CommentaryListBase(
                    openBookCallback: widget.openBookCallback,
                    fontSize: widget.fontSize,
                    showSearch: widget.showSearch,
                    onClosePane: null, // הסרת לחצן הסגירה מכאן
                  ),
                  // כרטיסיית הקישורים
                  SelectedLineLinksView(
                    openBookCallback: widget.openBookCallback,
                    fontSize: widget.fontSize,
                    showVisibleLinksIfNoSelection:
                        widget.initialTabIndex == 1, // אם נפתח ישירות לקישורים
                  ),
                  // כרטיסיית ההערות האישיות
                  NotesSidebar(
                    bookId: state.book.title,
                    onClose: null, // לא צריך כפתור סגירה - יש את הכפתור הכללי
                    onNavigateToPosition: (start, end) {
                      // ניווט למיקום ההערה בטקסט
                      UiSnack.show('ניווט למיקום $start-$end');
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
