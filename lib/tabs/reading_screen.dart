import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
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
import 'package:otzaria/search/view/full_text_search_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/widgets/scrollable_tab_bar.dart';
import 'package:otzaria/settings/reading_settings_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/settings/settings_event.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

const double _kAppBarControlsWidth = 125.0;
const int _kActionButtonsCount = 2; // fullscreen + settings
const double _kActionButtonWidth = 56.0;

class _ReadingScreenState extends State<ReadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // האם יש אוברפלואו בטאבים (גלילה)? משמש לקביעת placeholder לדינמיות מרכוז/התפרשות
  bool _tabsOverflow = false;
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    return BlocListener<TabsBloc, TabsState>(
      listener: (context, state) {
        if (state.hasOpenTabs) {
          context
              .read<HistoryBloc>()
              .add(CaptureStateForHistory(state.currentTab!));
        }
      },
      listenWhen: (previous, current) =>
          previous.currentTabIndex != current.currentTabIndex,
      child: BlocBuilder<TabsBloc, TabsState>(
        builder: (context, state) {
          if (!state.hasOpenTabs) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('לא נבחרו ספרים'),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton(
                      onPressed: () {
                        context.read<NavigationBloc>().add(
                              const NavigateToScreen(Screen.library),
                            );
                      },
                      child: const Text('דפדף בספרייה'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton(
                      onPressed: () {
                        _showSaveWorkspaceDialog(context);
                      },
                      child: const Text('החלף שולחן עבודה'),
                    ),
                  ),
                  // קו מפריד
                  Container(
                    height: 1,
                    width: 200,
                    color: Colors.grey.shade400,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton(
                      onPressed: () {
                        _showHistoryDialog(context);
                      },
                      child: const Text('הצג היסטוריה'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton(
                      onPressed: () {
                        _showBookmarksDialog(context);
                      },
                      child: const Text('הצג סימניות'),
                    ),
                  )
                ],
              ),
            );
          }

          return Builder(
            builder: (context) {
              final controller = TabController(
                length: state.tabs.length,
                vsync: this,
                initialIndex: state.currentTabIndex,
              );

              controller.addListener(() {
                if (controller.indexIsChanging &&
                    state.currentTabIndex < state.tabs.length) {
                  // שמירת המצב הנוכחי לפני המעבר לטאב אחר
                  debugPrint(
                      'DEBUG: מעבר בין טאבים - שמירת מצב טאב ${state.currentTabIndex}');
                  context.read<HistoryBloc>().add(CaptureStateForHistory(
                      state.tabs[state.currentTabIndex]));
                }
                if (controller.index != state.currentTabIndex) {
                  debugPrint('DEBUG: עדכון טאב נוכחי ל-${controller.index}');
                  context.read<TabsBloc>().add(SetCurrentTab(controller.index));
                }
              });

              return Scaffold(
                appBar: AppBar(
                  // 1. משתמשים בקבוע שהגדרנו עבור הרוחב
                  leadingWidth: _kAppBarControlsWidth,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // קבוצת היסטוריה וסימניות
                      IconButton(
                        icon: const Icon(FluentIcons.history_24_regular),
                        tooltip: 'הצג היסטוריה',
                        onPressed: () => _showHistoryDialog(context),
                      ),
                      IconButton(
                        icon: const Icon(FluentIcons.bookmark_24_regular),
                        tooltip: 'הצג סימניות',
                        onPressed: () => _showBookmarksDialog(context),
                      ),
                      // קו מפריד
                      Container(
                        height: 24,
                        width: 1,
                        color: Colors.grey.shade400,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                      ),
                      // קבוצת שולחן עבודה עם אנימציה
                      IconButton(
                        icon: const Icon(FluentIcons.add_square_24_regular),
                        tooltip: 'החלף שולחן עבודה',
                        onPressed: () => _showSaveWorkspaceDialog(context),
                      ),
                    ],
                  ),
                  titleSpacing: 0,
                  centerTitle: true,
                  title: Container(
                    constraints: const BoxConstraints(maxHeight: 50),
                    child: ScrollableTabBarWithArrows(
                      controller: controller,
                      tabAlignment: TabAlignment.center,
                      onOverflowChanged: (overflow) {
                        if (mounted) {
                          setState(() => _tabsOverflow = overflow);
                        }
                      },
                      tabs: state.tabs
                          .map((tab) => _buildTab(context, tab, state))
                          .toList(),
                    ),
                  ),
                  flexibleSpace: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  // שומרים תמיד מקום קבוע לימין כדי למנוע שינויי רוחב פתאומיים
                  actions: [
                    // רווח למרכוז - חישוב דינמי
                    // מפחיתים את רוחב הכפתורים מהרוחב הכולל
                    if (!_tabsOverflow)
                      const SizedBox(
                          width: _kAppBarControlsWidth -
                              (_kActionButtonsCount * _kActionButtonWidth)),
                    // כפתור מסך מלא - פעיל תמיד
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settingsState) {
                        return IconButton(
                          icon: Icon(settingsState.isFullscreen
                              ? FluentIcons.full_screen_minimize_24_regular
                              : FluentIcons.full_screen_maximize_24_regular),
                          tooltip: settingsState.isFullscreen
                              ? 'צא ממסך מלא'
                              : 'מסך מלא',
                          onPressed: () async {
                            final newFullscreenState =
                                !settingsState.isFullscreen;
                            context
                                .read<SettingsBloc>()
                                .add(UpdateIsFullscreen(newFullscreenState));
                            await windowManager
                                .setFullScreen(newFullscreenState);
                          },
                        );
                      },
                    ),
                    // כפתור הגדרות בצד שמאל של שורת הטאבים
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: IconButton(
                        icon: const Icon(FluentIcons.settings_24_regular),
                        tooltip: 'הגדרות תצוגת הספרים',
                        onPressed: () => showReadingSettingsDialog(context),
                        style: IconButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                body: SizedBox.fromSize(
                  size: MediaQuery.of(context).size,
                  child: TabBarView(
                    controller: controller,
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
    if (tab is PdfBookTab) {
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

  Widget _buildTab(BuildContext context, OpenedTab tab, TabsState state) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == 4) {
          closeTab(tab, context);
        }
      },
      child: ContextMenuRegion(
        contextMenu: ContextMenu(
          entries: [
            MenuItem(label: 'סגור', onSelected: () => closeTab(tab, context)),
            MenuItem(
                label: 'סגור הכל',
                onSelected: () => closeAllTabs(state, context)),
            MenuItem(
              label: 'סגור את האחרים',
              onSelected: () => closeAllTabsButCurrent(state, context),
            ),
            MenuItem(
              label: 'שיכפול',
              onSelected: () => context.read<TabsBloc>().add(CloneTab(tab)),
            ),
            MenuItem.submenu(
              label: 'רשימת הכרטיסיות ',
              items: _getMenuItems(state.tabs, context),
            )
          ],
        ),
        child: Draggable<OpenedTab>(
          axis: Axis.horizontal,
          data: tab,
          childWhenDragging: const SizedBox.shrink(),
          feedback: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
              child: Text(
                tab.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
          ),
          child: DragTarget<OpenedTab>(
            onAcceptWithDetails: (draggedTab) {
              if (draggedTab.data == tab) return;
              final newIndex = state.tabs.indexOf(tab);
              context.read<TabsBloc>().add(MoveTab(draggedTab.data, newIndex));
            },
            builder: (context, candidateData, rejectedData) => Tab(
              child: Row(
                children: [
                  if (tab is SearchingTab)
                    ValueListenableBuilder(
                      valueListenable: tab.queryController,
                      builder: (context, value, child) => Tooltip(
                        message: tab.title,
                        child: Text(
                          truncate(tab.title, 12),
                        ),
                      ),
                    )
                  else if (tab is PdfBookTab)
                    Tooltip(
                      message: tab.title,
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(FluentIcons.document_pdf_24_regular,
                                size: 16),
                          ),
                          Text(truncate(tab.title, 12)),
                        ],
                      ),
                    )
                  else
                    Tooltip(
                        message: tab.title,
                        child: Text(truncate(tab.title, 12))),
                  Tooltip(
                    preferBelow: false,
                    message:
                        (Settings.getValue<String>('key-shortcut-close-tab') ??
                                'ctrl+w')
                            .toUpperCase(),
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 25,
                        minHeight: 25,
                        maxWidth: 25,
                        maxHeight: 25,
                      ),
                      onPressed: () => closeTab(tab, context),
                      icon:
                          const Icon(FluentIcons.dismiss_24_regular, size: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<ContextMenuEntry> _getMenuItems(
      List<OpenedTab> tabs, BuildContext context) {
    List<MenuItem> items = tabs
        .map((tab) => MenuItem(
              label: tab.title,
              onSelected: () {
                final index = tabs.indexOf(tab);
                context.read<TabsBloc>().add(SetCurrentTab(index));
              },
            ))
        .toList();

    items.sort((a, b) => a.label.compareTo(b.label));
    return items;
  }

  void _showSaveWorkspaceDialog(BuildContext context) {
    context.read<HistoryBloc>().add(FlushHistory());
    showDialog(
      context: context,
      builder: (context) => const WorkspaceSwitcherDialog(),
    );
  }

  void closeTab(OpenedTab tab, BuildContext context) {
    context.read<HistoryBloc>().add(AddHistory(tab));
    context.read<TabsBloc>().add(RemoveTab(tab));
  }

  void closeAllTabs(TabsState state, BuildContext context) {
    for (final tab in state.tabs) {
      context.read<HistoryBloc>().add(AddHistory(tab));
    }
    context.read<TabsBloc>().add(CloseAllTabs());
  }

  void closeAllTabsButCurrent(TabsState state, BuildContext context) {
    final current = state.tabs[state.currentTabIndex];
    final toClose = state.tabs.where((t) => t != current).toList();
    for (final tab in toClose) {
      context.read<HistoryBloc>().add(AddHistory(tab));
    }
    context.read<TabsBloc>().add(CloseOtherTabs(current));
  }

  void _showHistoryDialog(BuildContext context) {
    context.read<HistoryBloc>().add(FlushHistory());
    showDialog(
      context: context,
      builder: (context) => const HistoryDialog(),
    );
  }

  void _showBookmarksDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const BookmarksDialog(),
    );
  }
}
