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
import 'package:otzaria/widgets/adaptive_side_pane.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';

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
    this.commentaryPaneHeaderNotifier,
  });

  final List<String> content;
  final void Function(OpenedTab) openBookCallback;
  final TextEditingValue searchTextController;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final ValueChanged<String?>? onSelectedTextChanged;
  final TextBookTab tab;
  final int? initialTabIndex;
  final bool showSplitView;
  final ValueNotifier<(Widget?, double)>? commentaryPaneHeaderNotifier;

  @override
  State<SplitedViewScreen> createState() => _SplitedViewScreenState();
}

class _SplitedViewScreenState extends State<SplitedViewScreen>
    with SingleTickerProviderStateMixin {
  // קבועים לאינדקסים של הטאבים
  static const int _commentaryTabIndex = 0;
  static const int _linksTabIndex = 1;
  static const int _notesTabIndex = 2;

  late final MultiSplitViewController _controller;
  late final TabController _tabController;
  bool _paneOpen = false;
  int? _currentTabIndex;
  late double _leftPaneWidth;
  bool _isHovering = false; // מצב ריחוף על הטאב
  bool _publishedHeaderInToolbar = false;
  double? _publishedHeaderWidth;
  bool? _publishedHeaderSplitView;
  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null); // טקסט נבחר לתפריט הקשר

  @override
  void initState() {
    super.initState();
    _controller = MultiSplitViewController();
    _currentTabIndex = _getInitialTabIndex();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _currentTabIndex!.clamp(0, 2),
    );
    _tabController.addListener(_handleTabChanged);
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
        final validIndex = _currentTabIndex!.clamp(0, 2);
        if (_tabController.index != validIndex) {
          _tabController.animateTo(validIndex);
        }
      });
    }
  }

  int _getInitialTabIndex() {
    // קביעת הטאב הראשוני
    // הטאבים בטור השמאלי: 0=מפרשים, 1=קישורים, 2=הערות אישיות
    if (widget.initialTabIndex != null) {
      // וידוא שהאינדקס תקף (0-2)
      return widget.initialTabIndex!.clamp(0, 2);
    } else {
      // ברירת מחדל - מפרשים (0)
      final saved = Settings.getValue<int>('key-sidebar-tab-index-combined');
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
        _isHovering = false;
      });
      _clearToolbarHeader();
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
      _setCurrentTab(targetTab);
    });
  }

  void _openPane() {
    if (!_paneOpen) {
      setState(() {
        _paneOpen = true;
      });
    }
  }

  void _setCurrentTab(int index) {
    final validIndex = index.clamp(0, 2);
    _currentTabIndex = validIndex;
    if (_tabController.index != validIndex) {
      _tabController.animateTo(validIndex);
    }
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging ||
        _tabController.index < 0 ||
        _tabController.index >= 3) {
      return;
    }

    final index = _tabController.index;
    if (_currentTabIndex != index) {
      setState(() {
        _currentTabIndex = index;
      });
    }
    if (!widget.showSplitView) {
      Settings.setValue<int>('key-sidebar-tab-index-combined', index);
    }
  }

  bool _shouldShowHeaderInToolbar(BuildContext context) {
    const wideOuterSideGap = 10.0;
    const wideInnerSideGap = 12.0;
    const minMainContentWidth = 520.0;
    final wideOccupiedWidth =
        _leftPaneWidth + wideOuterSideGap + wideInnerSideGap;
    return _paneOpen &&
        MediaQuery.of(context).size.width >=
            (wideOccupiedWidth + minMainContentWidth);
  }

  void _scheduleToolbarHeaderSync(bool showHeaderInToolbar) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncToolbarHeader(showHeaderInToolbar);
    });
  }

  void _syncToolbarHeader(bool showHeaderInToolbar) {
    final notifier = widget.commentaryPaneHeaderNotifier;
    if (notifier == null) {
      return;
    }

    if (!showHeaderInToolbar) {
      _clearToolbarHeader();
      return;
    }

    if (_publishedHeaderInToolbar &&
        _publishedHeaderWidth == _leftPaneWidth &&
        _publishedHeaderSplitView == widget.showSplitView) {
      return;
    }

    notifier.value = (
      SizedBox(
        width: _leftPaneWidth,
        child: TabbedCommentaryPanelHeader(
          controller: _tabController,
          onClosePane: _togglePane,
          showSplitView: widget.showSplitView,
          height: kToolbarHeight,
        ),
      ),
      _leftPaneWidth,
    );
    _publishedHeaderInToolbar = true;
    _publishedHeaderWidth = _leftPaneWidth;
    _publishedHeaderSplitView = widget.showSplitView;
  }

  void _clearToolbarHeader() {
    final notifier = widget.commentaryPaneHeaderNotifier;
    if (notifier == null || !_publishedHeaderInToolbar) {
      return;
    }

    notifier.value = (null, 0.0);
    _publishedHeaderInToolbar = false;
    _publishedHeaderWidth = null;
    _publishedHeaderSplitView = null;
  }

  @override
  void dispose() {
    _clearToolbarHeader();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
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
          final showHeaderInToolbar = _shouldShowHeaderInToolbar(context);
          _scheduleToolbarHeaderSync(showHeaderInToolbar);

          return AdaptiveSidePane(
            isOpen: _paneOpen,
            alignment: AlignmentDirectional.centerStart,
            paneWidth: _leftPaneWidth,
            minMainContentWidth: 520,
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
                  controller: _tabController,
                  showHeader: !showHeaderInToolbar,
                  showSplitView: widget.showSplitView,
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
                      _setCurrentTab(2);
                    });
                  },
                  onOpenCommentatorsPane: () {
                    setState(() {
                      _paneOpen = true;
                      _setCurrentTab(0);
                    });
                  },
                  isPaneOpen: () => _paneOpen,
                ),
                if (!_paneOpen)
                  Positioned(
                    left: 0,
                    top: MediaQuery.of(context).size.height * 0.10,
                    child: CommentaryPaneTooltip(
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
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
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
            minPaneWidth: 200,
            maxPaneWidth: 800,
            onPaneWidthChanged: (nextWidth) {
              setState(() {
                _leftPaneWidth = nextWidth;
                _publishedHeaderWidth = null;
              });
            },
            onPaneResizeEnd: () {
              context
                  .read<SettingsBloc>()
                  .add(UpdateCommentaryPaneWidth(_leftPaneWidth));
            },
            autoHandleResponsiveVisibility: false,
          );
        },
      ),
    );
  }
}
