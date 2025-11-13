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
import 'package:otzaria/settings/settings_state.dart';

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
      });
    }
  }

  int _getInitialTabIndex() {
    // קביעת הטאב הראשוני
    if (widget.initialTabIndex != null) {
      print('DEBUG: Using initialTabIndex: ${widget.initialTabIndex}');
      return widget.initialTabIndex!;
    } else if (widget.showSplitView) {
      // תצוגה מפוצלת - תמיד מפרשים (0)
      print('DEBUG: Split view - returning 0 (commentaries)');
      return 0;
    } else {
      // תצוגה משולבת - טוען שמור או ברירת מחדל קישורים (1)
      final saved = Settings.getValue<int>('key-sidebar-tab-index-combined');
      print('DEBUG: Combined view - saved: $saved, returning: ${saved ?? 1}');
      return saved ?? 1;
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
    setState(() {
      _paneOpen = !_paneOpen;
      _updateAreas();
    });
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
        return previous is TextBookLoaded &&
            current is TextBookLoaded &&
            previous.activeCommentators != current.activeCommentators;
      },
      listener: (context, state) {
        if (state is TextBookLoaded) {
          // פותח את החלונית רק בתצוגה מפוצלת
          if (widget.showSplitView) {
            _openPane();
          }
        }
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
          return BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              return Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: settingsState.paddingSize),
                    child: CombinedView(
                      data: widget.content,
                      textSize: state.fontSize,
                      openBookCallback: widget.openBookCallback,
                      openLeftPaneTab: widget.openLeftPaneTab,
                      showCommentaryAsExpansionTiles: !widget.showSplitView,
                      tab: widget.tab,
                    ),
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
                          FluentIcons.navigation_24_regular,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: _togglePane,
                      ),
                    ),
                  ),
                ],
              );
            },
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
                    print(
                        'DEBUG: Tab changed to $index, showSplitView: ${widget.showSplitView}');
                    setState(() {
                      _currentTabIndex = index;
                    });
                    // שומר את הטאב רק בתצוגה משולבת
                    if (!widget.showSplitView) {
                      print('DEBUG: Saving tab $index to combined settings');
                      Settings.setValue<int>(
                          'key-sidebar-tab-index-combined', index);
                    } else {
                      print('DEBUG: NOT saving tab (split view mode)');
                    }
                  },
                ),
              ),
            ),
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: settingsState.paddingSize),
                  child: CombinedView(
                    data: widget.content,
                    textSize: state.fontSize,
                    openBookCallback: widget.openBookCallback,
                    openLeftPaneTab: widget.openLeftPaneTab,
                    showCommentaryAsExpansionTiles: false,
                    tab: widget.tab,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
