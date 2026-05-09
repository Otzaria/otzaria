import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';

class SplitedViewScreen extends StatefulWidget {
  const SplitedViewScreen({
    super.key,
    required this.content,
    required this.openBookCallback,
    required this.searchTextController,
    required this.openLeftPaneTab,
    this.onSelectedTextChanged,
    required this.tab,
    this.initialTabIndex, // אינדקס הכרטיסייה הראשונית
    required this.showSplitView, // האם להציג בתצוגה מפוצלת
  });

  final List<String> content;
  final void Function(OpenedTab) openBookCallback;
  final TextEditingValue searchTextController;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final ValueChanged<String?>? onSelectedTextChanged;
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
  bool _paneOpen = false;
  int? _currentTabIndex;
  late double _leftPaneWidth;
  bool _isHovering = false; // מצב ריחוף על הטאב
  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null); // טקסט נבחר לתפריט הקשר

  @override
  void initState() {
    super.initState();
    _controller = MultiSplitViewController();
    _currentTabIndex = _getInitialTabIndex();
    if (widget.initialTabIndex != null) {
      _paneOpen = true;
    }
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

  ({double paneWidth, double minPaneWidth, double maxPaneWidth})
      _calculatePaneWidths(double availableWidth) {
    const minPaneWidth = 280.0;
    const minTextWidth = 300.0;
    final maxPaneWidth = (availableWidth * 0.75).clamp(minPaneWidth, double.infinity);
    // נדחס אם אין מספיק מקום לטקסט, אבל לא עולה על 75%
    final effectiveMax = ((availableWidth - minTextWidth).clamp(minPaneWidth, maxPaneWidth));
    final paneWidth = _leftPaneWidth.clamp(minPaneWidth, effectiveMax);

    return (
      paneWidth: paneWidth,
      minPaneWidth: minPaneWidth,
      maxPaneWidth: maxPaneWidth,
    );
  }

  void _togglePane() {
    if (!_paneOpen) {
      // פתיחת הטור - בחר את הטאב הנכון
      _openPaneWithSmartTab();
    } else {
      // סגירת הטור
      setState(() {
        _paneOpen = false;
        _isHovering = false;
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

    if (widget.showSplitView) {
      // מצב "מפרשים בצד" - תמיד פתח על מפרשים
      targetTab = _commentaryTabIndex;
    } else {
      // מצב "מפרשים מתחת הטקסט" - פתח קישורים (אם יש)
      final hasLinks = state.visibleLinks.isNotEmpty;
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
    _savedSelectedText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TextBookBloc, TextBookState>(
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
      child: TextBookStateBuilder(
        buildWhen: (previous, current) {
          if (previous is TextBookLoaded && current is TextBookLoaded) {
            return previous.fontSize != current.fontSize ||
                previous.showSplitView != current.showSplitView;
          }
          return true;
        },
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final paneWidths = _calculatePaneWidths(availableWidth);

              return AdaptiveSidePane(
                isOpen: _paneOpen,
                alignment: AlignmentDirectional.centerStart,
                paneWidth: paneWidths.paneWidth,
                minMainContentWidth: 200,
                onClose: () {
                  setState(() {
                    _paneOpen = false;
                    _isHovering = false;
                  });
                },
                paneContent: ValueListenableBuilder<String?>(
                  valueListenable: _savedSelectedText,
                  child: SelectionArea(
                    contextMenuBuilder: (context, selectableRegionState) {
                      return const SizedBox.shrink();
                    },
                    onSelectionChanged: (selection) {
                      if (selection != null && selection.plainText.isNotEmpty) {
                        _savedSelectedText.value = selection.plainText;
                      }
                    },
                    child: TabbedCommentaryPanel(
                      fontSize: state.fontSize,
                      openBookCallback: widget.openBookCallback,
                      showSearch: true,
                      onClosePane: _togglePane,
                      initialTabIndex: _currentTabIndex,
                      showSplitView: widget.showSplitView,
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
                          debugPrint('DEBUG: NOT saving tab (split view mode)');
                        }
                      },
                    ),
                  ),
                  builder: (context, selectedText, child) => child!,
                ),
                mainContent: Stack(
                  children: [
                    CombinedView(
                      data: widget.content,
                      textSize: state.fontSize,
                      openBookCallback: widget.openBookCallback,
                      openLeftPaneTab: widget.openLeftPaneTab,
                      onSelectedTextChanged: widget.onSelectedTextChanged,
                      showCommentaryAsExpansionTiles: !widget.showSplitView,
                      tab: widget.tab,
                      onOpenPersonalNotes: () {
                        setState(() {
                          _paneOpen = true;
                          _currentTabIndex = 2;
                        });
                      },
                      onOpenCommentatorsPane: () {
                        setState(() {
                          _paneOpen = true;
                          _currentTabIndex = 0;
                        });
                      },
                      onOpenLinksPane: () {
                        setState(() {
                          _paneOpen = true;
                          _currentTabIndex = _linksTabIndex;
                        });
                      },
                      isPaneOpen: () => _paneOpen,
                    ),
                    if (!_paneOpen)
                      Positioned(
                        left: 0,
                        top: MediaQuery.of(context).size.height * 0.10,
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _isHovering = true),
                          onExit: (_) => setState(() => _isHovering = false),
                          child: GestureDetector(
                            onTap: _togglePane,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
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
                  ],
                ),
                isResizable: true,
                minPaneWidth: paneWidths.minPaneWidth,
                maxPaneWidth: paneWidths.maxPaneWidth,
                onPaneWidthChanged: (nextWidth) {
                  _leftPaneWidth = nextWidth;
                },
                onPaneResizeEnd: () {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateCommentaryPaneWidth(_leftPaneWidth));
                },
                autoHandleResponsiveVisibility: false,
                scrollbarTopMargin: 0,
              );
            },
          );
        },
      ),
    );
  }
}
