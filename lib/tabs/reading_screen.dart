import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart' show Screen;
import 'package:otzaria/pdf_book/pdf_book_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/search/view/full_text_search_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_state.dart';
import 'package:otzaria/widgets/resizable_drag_handle.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Check if widget is still mounted before accessing context
    if (mounted) {
      try {
        context.read<HistoryBloc>().add(FlushHistory());
      } catch (e) {
        // Ignore errors during disposal
      }
    }
    _tabController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleTabControllerChange() {
    final controller = _tabController;
    if (controller == null) return;
    final tabsState = context.read<TabsBloc>().state;
    if (!tabsState.hasOpenTabs) return;

    if (controller.indexIsChanging &&
        tabsState.currentTabIndex < tabsState.tabs.length) {
      context.read<HistoryBloc>().add(
          CaptureStateForHistory(tabsState.tabs[tabsState.currentTabIndex]));
      context.read<TabsBloc>().add(const SaveTabs());
    }

    if (controller.index != tabsState.currentTabIndex) {
      context.read<TabsBloc>().add(SetCurrentTab(controller.index));
    }
  }

  void _ensureTabController(TabsState state) {
    if (!state.hasOpenTabs) return;

    final validIndex = state.currentTabIndex.clamp(0, state.tabs.length - 1);
    if (_tabController == null || _tabController!.length != state.tabs.length) {
      _tabController?.dispose();
      _tabController = TabController(
        length: state.tabs.length,
        vsync: this,
        initialIndex: validIndex,
      )..addListener(_handleTabControllerChange);
      return;
    }

    if (_tabController!.index != validIndex &&
        !_tabController!.indexIsChanging) {
      _tabController!.animateTo(validIndex);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      context.read<HistoryBloc>().add(FlushHistory());
      context.read<TabsBloc>().add(const SaveTabs());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            if (state.hasOpenTabs) {
              context
                  .read<HistoryBloc>()
                  .add(CaptureStateForHistory(state.currentTab!));
            }
          },
          listenWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex,
        ),
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            // כשסוגרים את הטאב האחרון, עוברים למסך הספרייה
            if (!state.hasOpenTabs) {
              context.read<NavigationBloc>().add(
                    const NavigateToScreen(Screen.library),
                  );
            }
          },
          listenWhen: (previous, current) =>
              previous.hasOpenTabs && !current.hasOpenTabs,
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return BlocBuilder<TabsBloc, TabsState>(
            builder: (context, state) {
              if (!state.hasOpenTabs) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'לא נבחרו ספרים',
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<NavigationBloc>().add(
                                    const NavigateToScreen(Screen.library),
                                  );
                            },
                            icon: const Icon(FluentIcons.library_24_regular),
                            label: const Text('דפדף בספרייה'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              _ensureTabController(state);

              return Scaffold(
                body: SizedBox.fromSize(
                  size: MediaQuery.of(context).size,
                  child: TabBarView(
                    key: const ValueKey('normal_tab_view'),
                    controller: _tabController,
                    children:
                        state.tabs.map((tab) => _buildTabView(tab)).toList(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTabView(OpenedTab tab) {
    if (tab is CombinedTab) {
      // הצגת שני הספרים זה לצד זה
      return _buildCombinedTabView(tab);
    } else if (tab is PdfBookTab) {
      return PdfBookScreen(
        key: PageStorageKey(tab),
        tab: tab,
      );
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
          value: tab.bloc,
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context.read<TabsBloc>().add(AddTab(tab));
            },
            tab: tab,
          ));
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(
        tab: tab,
        openBookCallback: (tab, {int index = 1}) {
          context.read<TabsBloc>().add(AddTab(tab));
        },
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCombinedTabView(CombinedTab combinedTab) {
    return _SideBySideViewWidget(
      key: ValueKey(
          'combined_${combinedTab.rightTab.title}_${combinedTab.leftTab.title}'),
      rightTab: combinedTab.rightTab,
      leftTab: combinedTab.leftTab,
      initialSplitRatio: combinedTab.splitRatio,
      onSplitRatioChanged: (ratio) {
        context.read<TabsBloc>().add(UpdateSplitRatio(ratio));
      },
      buildTabView: (tab) =>
          _buildSingleTabContent(tab, isInCombinedView: true),
    );
  }

  Widget _buildSingleTabContent(OpenedTab tab,
      {bool isInCombinedView = false}) {
    if (tab is PdfBookTab) {
      return PdfBookScreen(
        key: PageStorageKey(tab),
        tab: tab,
        isInCombinedView: isInCombinedView,
      );
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
          value: tab.bloc,
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context.read<TabsBloc>().add(AddTab(tab));
            },
            tab: tab,
            isInCombinedView: isInCombinedView,
          ));
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(
        tab: tab,
        openBookCallback: (tab, {int index = 1}) {
          context.read<TabsBloc>().add(AddTab(tab));
        },
      );
    }
    return const SizedBox.shrink();
  }
}

// Widget להצגת 2 ספרים זה לצד זה
class _SideBySideViewWidget extends StatefulWidget {
  final OpenedTab rightTab;
  final OpenedTab leftTab;
  final double initialSplitRatio;
  final Function(double) onSplitRatioChanged;
  final Widget Function(OpenedTab) buildTabView;

  const _SideBySideViewWidget({
    super.key,
    required this.rightTab,
    required this.leftTab,
    required this.initialSplitRatio,
    required this.onSplitRatioChanged,
    required this.buildTabView,
  });

  @override
  State<_SideBySideViewWidget> createState() => _SideBySideViewWidgetState();
}

class _SideBySideViewWidgetState extends State<_SideBySideViewWidget> {
  late double _splitRatio;

  @override
  void initState() {
    super.initState();
    _splitRatio = widget.initialSplitRatio;
  }

  @override
  void didUpdateWidget(_SideBySideViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון היחס אם השתנה (למשל, אחרי החלפת צדדים)
    if (widget.initialSplitRatio != oldWidget.initialSplitRatio) {
      setState(() {
        _splitRatio = widget.initialSplitRatio;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final rightWidth = totalWidth * _splitRatio;
        final leftWidth = totalWidth * (1.0 - _splitRatio);
        const dividerWidth = 8.0;

        return Stack(
          children: [
            Row(
              children: [
                // ספר ימני (בגלל RTL, זה יופיע בצד ימין)
                SizedBox(
                  width: rightWidth,
                  child: widget.buildTabView(widget.rightTab),
                ),
                // מפריד ניתן לגרירה
                ResizableDragHandle(
                  isVertical: true,
                  onDragDelta: (delta) {
                    setState(() {
                      // תיקון: הפיכת הכיוון כי אנחנו ב-RTL
                      final ratioDelta = -delta / totalWidth;
                      _splitRatio = (_splitRatio + ratioDelta).clamp(0.2, 0.8);
                    });
                  },
                  onDragEnd: () => widget.onSplitRatioChanged(_splitRatio),
                ),
                // ספר שמאלי (בגלל RTL, זה יופיע בצד שמאל)
                SizedBox(
                  width: leftWidth - dividerWidth,
                  child: widget.buildTabView(widget.leftTab),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
