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
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';
import 'package:otzaria/utils/context_menu_utils.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

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
  // קבועים לאינדקסים של הטאבים
  static const int _commentaryTabIndex = 0;
  static const int _linksTabIndex = 1;
  static const int _notesTabIndex = 2;

  late final MultiSplitViewController _controller;
  late final GlobalKey<SelectionAreaState> _selectionKey;
  bool _paneOpen = false;
  int? _currentTabIndex;
  late double _leftPaneWidth;
  bool _isResizing = false;
  bool _isHovering = false; // מצב ריחוף על הטאב
  String? _savedSelectedText; // טקסט נבחר לתפריט הקשר

  @override
  void initState() {
    super.initState();
    _controller = MultiSplitViewController();
    _selectionKey = GlobalKey<SelectionAreaState>();
    _currentTabIndex = _getInitialTabIndex();
    // טען את רוחב הפאנל מההגדרות
    _leftPaneWidth = context.read<SettingsBloc>().state.commentaryPaneWidth;
  }

  @override
  void didUpdateWidget(SplitedViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // אם showSplitView השתנה או initialTabIndex השתנה, מעדכן את הטאב
    if (oldWidget.showSplitView != widget.showSplitView ||
        oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() {
        _currentTabIndex = _getInitialTabIndex();
        // אם עוברים למצב split view או initialTabIndex השתנה, פותחים את הטור השמאלי אוטומטית
        if ((widget.showSplitView || widget.initialTabIndex != null) &&
            !_paneOpen) {
          _paneOpen = true;
        }
        // אם עוברים למצב של מפרשים מתחת הטקסט (showSplitView = false), סוגרים את הפאנל הימני
        if (!widget.showSplitView && _paneOpen) {
          _paneOpen = false;
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

  void _togglePane() {
    if (!_paneOpen) {
      // פתיחת הטור - בחר את הטאב הנכון
      _openPaneWithSmartTab();
    } else {
      // סגירת הטור
      setState(() {
        _paneOpen = false;
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

    // בדיקה אם יש מפרשים לקטע הנוכחי
    final hasCommentary = _hasCommentaryInCurrentLine(state);
    // בדיקה אם יש קישורים לקטע הנוכחי
    final hasLinks = state.visibleLinks.isNotEmpty;

    if (widget.showSplitView) {
      // מצב "מפרשים בצד" - פתח מפרשים (אם יש)
      if (hasCommentary) {
        targetTab = _commentaryTabIndex;
      } else if (hasLinks) {
        targetTab = _linksTabIndex;
      } else {
        targetTab = _notesTabIndex;
      }
    } else {
      // מצב "מפרשים מתחת הטקסט" - פתח קישורים (אם יש)
      if (hasLinks) {
        targetTab = _linksTabIndex;
      } else {
        targetTab = _notesTabIndex;
      }
    }

    setState(() {
      _paneOpen = true;
      _currentTabIndex = targetTab;
    });
  }

  bool _hasCommentaryInCurrentLine(TextBookLoaded state) {
    if (state.visibleIndices.isEmpty) return false;

    final visibleIndicesSet = state.visibleIndices.toSet();
    // בדיקה אם יש מפרשים פעילים לאינדקסים הנראים
    return state.links.any((link) =>
        visibleIndicesSet.contains(link.index1 - 1) &&
        (link.connectionType == "commentary" ||
            link.connectionType == "targum") &&
        state.activeCommentators.contains(utils.getTitleFromPath(link.path2)));
  }

  void _openPane() {
    if (!_paneOpen) {
      setState(() {
        _paneOpen = true;
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
        MenuItem(
          label: const Text('העתק'),
          icon: const Icon(FluentIcons.copy_24_regular),
          enabled: _savedSelectedText != null &&
              _savedSelectedText!.trim().isNotEmpty,
          onSelected: (_) => ContextMenuUtils.copyFormattedText(
            context: context,
            savedSelectedText: _savedSelectedText,
            fontSize: state.fontSize,
          ),
        ),
        MenuItem(
            label: const Text('חיפוש'),
            onSelected: (_) => widget.openLeftPaneTab(1)),
        const MenuDivider(),
        MenuItem(
          label: const Text('בחר את כל הטקסט'),
          onSelected: (_) =>
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

        return Stack(
          children: [
            Row(
              children: [
                // תוכן הספר
                Expanded(
                  child: CombinedView(
                    data: widget.content,
                    textSize: state.fontSize,
                    openBookCallback: widget.openBookCallback,
                    openLeftPaneTab: widget.openLeftPaneTab,
                    showCommentaryAsExpansionTiles: !widget.showSplitView,
                    tab: widget.tab,
                    onOpenPersonalNotes: () {
                      // פתיחת הפאנל הימני עם טאב ההערות האישיות
                      setState(() {
                        _paneOpen = true;
                        _currentTabIndex = 2; // אינדקס של הערות אישיות
                      });
                    },
                    onOpenCommentatorsPane: () {
                      // פתיחת הפאנל הימני עם טאב המפרשים
                      setState(() {
                        _paneOpen = true;
                        _currentTabIndex = 0; // אינדקס של מפרשים
                      });
                    },
                  ),
                ),
                // מפריד ניתן לגרירה
                if (_paneOpen)
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragStart: (_) {
                        setState(() => _isResizing = true);
                      },
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          // גרירה שמאלה מקטינה, ימינה מגדילה
                          _leftPaneWidth = (_leftPaneWidth + details.delta.dx)
                              .clamp(200.0, 800.0);
                        });
                      },
                      onHorizontalDragEnd: (_) {
                        setState(() => _isResizing = false);
                        // שמור את הרוחב ב-SettingsBloc
                        context
                            .read<SettingsBloc>()
                            .add(UpdateCommentaryPaneWidth(_leftPaneWidth));
                      },
                      child: Container(
                        width: _isResizing ? 4 : 8,
                        color: _isResizing
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        alignment: Alignment.center,
                        child: _isResizing
                            ? null
                            : Container(
                                width: 1.5,
                                color: Theme.of(context).dividerColor,
                              ),
                      ),
                    ),
                  ),
                // פאנל שמאלי (בצד ימין של המסך)
                if (_paneOpen)
                  SizedBox(
                    width: _leftPaneWidth,
                    child: ContextMenuRegion(
                      contextMenu: _buildContextMenu(state),
                      child: SelectionArea(
                        key: _selectionKey,
                        contextMenuBuilder: (context, selectableRegionState) {
                          // מבטל את התפריט הרגיל של Flutter כי יש ContextMenuRegion
                          return const SizedBox.shrink();
                        },
                        onSelectionChanged: (selection) {
                          if (selection != null &&
                              selection.plainText.isNotEmpty) {
                            setState(() {
                              _savedSelectedText = selection.plainText;
                            });
                          }
                        },
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
                            if (!widget.showSplitView) {
                              debugPrint(
                                  'DEBUG: Saving tab $index to combined settings');
                              Settings.setValue<int>(
                                  'key-sidebar-tab-index-combined', index);
                            } else {
                              debugPrint(
                                  'DEBUG: NOT saving tab (split view mode)');
                            }
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // טאב צף להצגה כאשר הפאנל סגור - עם 3 מצבים והדרכה
            if (!_paneOpen)
              Positioned(
                left: 0, // צמוד לקצה
                top: MediaQuery.of(context).size.height * 0.10, // למעלה במסך
                child: CommentaryPaneTooltip(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHovering = true),
                    onExit: (_) => setState(() => _isHovering = false),
                    child: GestureDetector(
                      onTap: _togglePane,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        // מצב 1: סגור - בליטה קטנה, מצב 2: ריחוף - נשלף יותר
                        width: _isHovering ? 48 : 20,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: _isHovering ? 0.95 : 0.8),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(40),
                            bottomRight: Radius.circular(40),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: _isHovering ? 8 : 4,
                              offset: const Offset(2, 0),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: _isHovering ? 1.0 : 0.6,
                            child: Icon(
                              FluentIcons.chevron_right_24_regular,
                              size: _isHovering ? 24 : 18,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
