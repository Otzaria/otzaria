import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';

class SplitedViewScreen extends StatefulWidget {
  const SplitedViewScreen({
    super.key,
    required this.content,
    required this.openBookCallback,
    required this.searchTextController,
    required this.openLeftPaneTab,
    required this.tab,
    this.initialTabIndex, // אינדקס הכרטיסייה הראשונית
    required this.showSplitView, // האם להציג בתצוגה מפוצלת
  });

  final List<String> content;
  final void Function(OpenedTab) openBookCallback;
  final TextEditingValue searchTextController;
  final void Function(int) openLeftPaneTab;
  final TextBookTab tab;
  final int? initialTabIndex;
  final bool showSplitView;

  @override
  State<SplitedViewScreen> createState() => _SplitedViewScreenState();
}

class _SplitedViewScreenState extends State<SplitedViewScreen> {
  late final MultiSplitViewController _controller;
  late final GlobalKey<SelectionAreaState> _selectionKey;
  bool _paneOpen = false;
  int? _currentTabIndex;

  @override
  void initState() {
    super.initState();
    _controller = MultiSplitViewController(areas: _openAreas());
    _selectionKey = GlobalKey<SelectionAreaState>();
    _currentTabIndex = _getInitialTabIndex();
  }

  @override
  void didUpdateWidget(SplitedViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם showSplitView השתנה, מאפס את הטאב
    if (oldWidget.showSplitView != widget.showSplitView) {
      setState(() {
        _currentTabIndex = _getInitialTabIndex();
        // אם עוברים למצב split view, פותחים את הטור השמאלי אוטומטית
        if (widget.showSplitView && !_paneOpen) {
          _paneOpen = true;
          _updateAreas();
        }
      });
    }
  }

  int _getInitialTabIndex() {
    // קביעת הטאב הראשוני
    // הטאבים בטור השמאלי: 0=מפרשים, 1=קישורים, 2=הערות אישיות
    if (widget.initialTabIndex != null) {
      debugPrint('DEBUG: Using initialTabIndex: ${widget.initialTabIndex}');
      // וידוא שהאינדקס תקף (0-2)
      return widget.initialTabIndex!.clamp(0, 2);
    } else {
      // ברירת מחדל - מפרשים (0)
      final saved = Settings.getValue<int>('key-sidebar-tab-index-combined');
      debugPrint('DEBUG: saved: $saved, returning: ${saved ?? 0}');
      // וידוא שהערך השמור תקף (0-2)
      return (saved ?? 0).clamp(0, 2);
    }
  }

  List<Area> _openAreas() => [
        Area(weight: 0.4, minimalSize: 200),
        Area(weight: 0.6, minimalSize: 200),
      ];

  List<Area> _closedAreas() => [
        Area(weight: 0, minimalSize: 0),
        Area(weight: 1, minimalSize: 200),
      ];

  void _updateAreas() {
    _controller.areas = _paneOpen ? _openAreas() : _closedAreas();
  }

  void _togglePane() {
    if (!_paneOpen) {
      // פתיחת הטור - בחר את הטאב הנכון
      _openPaneWithSmartTab();
    } else {
      // סגירת הטור
      setState(() {
        _paneOpen = false;
        _updateAreas();
      });
    }
  }

  // פונקציה ציבורית לפתיחה/סגירה מבחוץ
  void togglePane() {
    _togglePane();
  }

  void _openPaneWithSmartTab() {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      _openPane();
      return;
    }

    int targetTab;

    // הטאבים בטור השמאלי עכשיו הם: 0=מפרשים, 1=קישורים, 2=הערות אישיות

    if (state.visibleIndices.isNotEmpty) {
      // בדוק אם יש קישורים בשורה הנוכחית
      final hasLinks = _hasLinksInCurrentLine(state);
      if (hasLinks) {
        targetTab = 1; // קישורים
      } else {
        targetTab = 2; // הערות אישיות
      }
    } else {
      targetTab = 0; // ברירת מחדל - מפרשים
    }

    setState(() {
      _paneOpen = true;
      _currentTabIndex = targetTab;
      _updateAreas();
    });
  }

  bool _hasLinksInCurrentLine(TextBookLoaded state) {
    // בדיקה פשוטה - אם יש אינדקס נראה, נניח שיש קישורים
    // אפשר לשפר את זה בעתיד עם בדיקה מדויקת יותר
    return state.visibleIndices.isNotEmpty;
  }

  void _openPane() {
    if (!_paneOpen) {
      setState(() {
        _paneOpen = true;
        _updateAreas();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ContextMenu _buildContextMenu(TextBookLoaded state) {
    return ContextMenu(
      entries: [
        MenuItem(label: 'חיפוש', onSelected: () => widget.openLeftPaneTab(1)),
        const MenuDivider(),
        MenuItem(
          label: 'בחר את כל הטקסט',
          onSelected: () =>
              _selectionKey.currentState?.selectableRegion.selectAll(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TextBookBloc, TextBookState>(
      listenWhen: (previous, current) {
        // האזן רק אם הוספנו מפרשים (לא אם הסרנו)
        if (previous is TextBookLoaded && current is TextBookLoaded) {
          return current.activeCommentators.length >
              previous.activeCommentators.length;
        }
        return false;
      },
      listener: (context, state) {
        // מפרשים עברו לטור הימני, אז לא צריך לפתוח את הטור השמאלי
        // כשמוסיפים מפרשים
      },
      buildWhen: (previous, current) {
        if (previous is TextBookLoaded && current is TextBookLoaded) {
          return previous.fontSize != current.fontSize ||
              previous.showSplitView != current.showSplitView;
        }
        return true;
      },
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        // אם החלונית סגורה - מציגים combined view עם כפתור צף
        if (!_paneOpen) {
          return Stack(
            children: [
              CombinedView(
                data: widget.content,
                textSize: state.fontSize,
                openBookCallback: widget.openBookCallback,
                openLeftPaneTab: widget.openLeftPaneTab,
                showCommentaryAsExpansionTiles: !widget.showSplitView,
                tab: widget.tab,
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
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
                  child: IconButton(
                    iconSize: 18,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      FluentIcons.panel_left_contract_24_regular,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: _togglePane,
                  ),
                ),
              ),
            ],
          );
        }

        return MultiSplitView(
          controller: _controller,
          axis: Axis.horizontal,
          resizable: true,
          dividerBuilder:
              (axis, index, resizable, dragging, highlighted, themeData) {
            final color = dragging
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor;
            return MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 8,
                alignment: Alignment.center,
                child: Container(
                  width: 1.5,
                  color: color,
                ),
              ),
            );
          },
          children: [
            ContextMenuRegion(
              contextMenu: _buildContextMenu(state),
              child: SelectionArea(
                key: _selectionKey,
                child: TabbedCommentaryPanel(
                  fontSize: state.fontSize,
                  openBookCallback: widget.openBookCallback,
                  showSearch: true,
                  onClosePane: _togglePane,
                  initialTabIndex: _currentTabIndex,
                  onTabChanged: (index) {
                    debugPrint(
                        'DEBUG: Tab changed to $index, showSplitView: ${widget.showSplitView}');
                    setState(() {
                      _currentTabIndex = index;
                    });
                    // שומר את הטאב רק בתצוגה משולבת
                    if (!widget.showSplitView) {
                      debugPrint(
                          'DEBUG: Saving tab $index to combined settings');
                      Settings.setValue<int>(
                          'key-sidebar-tab-index-combined', index);
                    } else {
                      debugPrint('DEBUG: NOT saving tab (split view mode)');
                    }
                  },
                ),
              ),
            ),
            CombinedView(
              data: widget.content,
              textSize: state.fontSize,
              openBookCallback: widget.openBookCallback,
              openLeftPaneTab: widget.openLeftPaneTab,
              showCommentaryAsExpansionTiles: false,
              tab: widget.tab,
            ),
          ],
        );
      },
    );
  }
}
