import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/view/selected_line_links_view.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
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
  final ValueListenable<int>? openFilterRequest;
  final ValueNotifier<int>? openCommentatorsFilterNotifier;
  final ValueNotifier<int>? closeCommentatorsFilterNotifier;
  final TextBookTab? tab; // עבור פתיחת כרטסיית מפרשים

  /// מדגיש מונח חיפוש בטאב המפרשים בלי להציג ממשק חיפוש — מונח התוצאה
  /// שנחתה בהערה, כדי שיודגש כשהחלונית נפתחת אוטומטית.
  final ValueListenable<String>? highlightQueryListenable;

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
    this.openFilterRequest,
    this.openCommentatorsFilterNotifier,
    this.closeCommentatorsFilterNotifier,
    this.tab,
    this.highlightQueryListenable,
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
                final firstTabIconData = widget.showSplitView
                    ? FluentIcons.book_24_regular
                    : FluentIcons.settings_24_regular;
                return PanelTabHeader(
                  controller: _tabController,
                  onClose: widget.onClosePane,
                  // במצב "מפרשים למטה" שורת הלחצנים החדשה לא קיימת (הטאב הראשון
                  // מציג הגדרות מפרשים), לכן משאירים כאן את לחצן הפתיחה בכרטיסייה
                  // חדשה כפי שהיה במקור.
                  extraActions: widget.showSplitView
                      ? const []
                      : [
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 40),
                            tooltip: 'פתח כרטסיית מפרשים',
                            icon: const Icon(FluentIcons.open_24_regular),
                            onPressed: widget.tab == null
                                ? null
                                : () => context.read<TabsBloc>().add(
                                      AddTab(
                                        CommentatorsTab(
                                          sourceTab: widget.tab!,
                                        ),
                                        insertAdjacent: true,
                                      ),
                                    ),
                          ),
                        ],
                  tabs: isCompact
                      ? [
                          PanelTab(icon: firstTabIconData),
                          const PanelTab(icon: FluentIcons.link_24_regular),
                          const PanelTab(icon: FluentIcons.note_24_regular),
                        ]
                      : [
                          PanelTab(
                            icon: firstTabIconData,
                            label: widget.showSplitView
                                ? 'מפרשים'
                                : 'סינון מפרשים',
                          ),
                          const PanelTab(
                            icon: FluentIcons.link_24_regular,
                            label: 'קישורים',
                          ),
                          const PanelTab(
                            icon: FluentIcons.note_24_regular,
                            label: 'הערות',
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
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) => CommentaryListBase(
                        key: const ValueKey('commentary_list_tabbed'),
                        openBookCallback: widget.openBookCallback,
                        fontSize: settingsState.commentatorsFontSize,
                        showSearch: widget.showSearch,
                        selectionSyncController: widget.selectionSyncController,
                        openFilterRequest: widget.openFilterRequest,
                        highlightQueryListenable:
                            widget.highlightQueryListenable,
                        selectedCommentatorsOverride: state.activeCommentators,
                        openFilterNotifier:
                            widget.openCommentatorsFilterNotifier,
                        closeFilterNotifier:
                            widget.closeCommentatorsFilterNotifier,
                        onSelectedCommentatorsOverrideChanged: (commentators) {
                          context
                              .read<TextBookBloc>()
                              .add(UpdateCommentators(commentators));
                        },
                        onOpenInNewTab: widget.tab == null
                            ? null
                            : () => context.read<TabsBloc>().add(
                                  AddTab(
                                    CommentatorsTab(
                                      sourceTab: widget.tab!,
                                    ),
                                    insertAdjacent: true,
                                  ),
                                ),
                      ),
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
