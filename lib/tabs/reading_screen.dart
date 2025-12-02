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
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/search/view/full_text_search_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'dart:convert';
import 'package:otzaria/settings/reading_settings_dialog.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

const double _kTabBarHeight = 36.0;

class _ReadingScreenState extends State<ReadingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (mounted) {
      try {
        context.read<HistoryBloc>().add(FlushHistory());
      } catch (e) {}
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
    return MultiBlocListener(
      listeners: [
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            if (state.hasOpenTabs) {
              context.read<HistoryBloc>().add(CaptureStateForHistory(state.currentTab!));
            }
          },
          listenWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex,
        ),
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            if (!state.hasOpenTabs) {
              context.read<NavigationBloc>().add(const NavigateToScreen(Screen.library));
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
                return _buildEmptyState(context, settingsState);
              }
              return _buildTabView(context, state, settingsState);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, SettingsState settingsState) {
    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(context, settingsState, null),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('לא נבחרו ספרים', style: TextStyle(fontSize: 18)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.read<NavigationBloc>().add(const NavigateToScreen(Screen.library));
                      },
                      icon: const Icon(FluentIcons.library_24_regular),
                      label: const Text('דפדף בספרייה'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabView(BuildContext context, TabsState state, SettingsState settingsState) {
    final validIndex = state.currentTabIndex.clamp(0, state.tabs.length - 1);

    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(context, settingsState, state),
          Expanded(child: _buildTabContent(state.tabs[validIndex])),
        ],
      ),
    );
  }

  /// שורת כלים משולבת עם כפתורים וטאבים
  Widget _buildToolbar(BuildContext context, SettingsState settingsState, TabsState? tabsState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Theme.of(context).colorScheme.surface;
    
    final historyShortcut = Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h';
    final bookmarksShortcut = Settings.getValue<String>('key-shortcut-open-bookmarks') ?? 'ctrl+shift+b';
    final workspaceShortcut = Settings.getValue<String>('key-shortcut-switch-workspace') ?? 'ctrl+k';

    return Container(
      height: _kTabBarHeight,
      color: backgroundColor,
      child: Row(
        children: [
          // כפתורים בצד ימין
          _buildToolbarButton(
            icon: FluentIcons.history_20_regular,
            tooltip: 'היסטוריה (${historyShortcut.toUpperCase()})',
            onPressed: () => _showHistoryDialog(context),
          ),
          _buildToolbarButton(
            icon: FluentIcons.bookmark_20_regular,
            tooltip: 'סימניות (${bookmarksShortcut.toUpperCase()})',
            onPressed: () => _showBookmarksDialog(context),
          ),
          _buildToolbarDivider(),
          _buildToolbarButton(
            icon: FluentIcons.add_square_20_regular,
            tooltip: 'שולחן עבודה (${workspaceShortcut.toUpperCase()})',
            onPressed: () => _showSaveWorkspaceDialog(context),
          ),
          _buildToolbarDivider(),
          
          // טאבים באמצע
          if (tabsState != null && tabsState.hasOpenTabs)
            Expanded(
              child: _FluentTabBar(
                tabs: tabsState.tabs,
                currentIndex: tabsState.currentTabIndex.clamp(0, tabsState.tabs.length - 1),
                onTabSelected: (index) => context.read<TabsBloc>().add(SetCurrentTab(index)),
                onTabClosed: (tab) => closeTab(tab, context),
                onTabReorder: (tab, newIndex) => context.read<TabsBloc>().add(MoveTab(tab, newIndex)),
                buildContextMenu: (tab) => _buildTabContextMenu(context, tab, tabsState),
              ),
            )
          else
            const Expanded(child: SizedBox()),
          
          // כפתורים בצד שמאל
          _buildToolbarDivider(),
          BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, state) {
              return _buildToolbarButton(
                icon: state.isFullscreen
                    ? FluentIcons.full_screen_minimize_20_regular
                    : FluentIcons.full_screen_maximize_20_regular,
                tooltip: state.isFullscreen ? 'צא ממסך מלא' : 'מסך מלא',
                onPressed: () async {
                  await FullscreenHelper.toggleFullscreen(context, !state.isFullscreen);
                },
              );
            },
          ),
          _buildToolbarButton(
            icon: FluentIcons.settings_20_regular,
            tooltip: 'הגדרות',
            onPressed: () => showReadingSettingsDialog(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 18, color: iconColor),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Widget _buildToolbarDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.withValues(alpha: 0.3),
    );
  }


  ContextMenu _buildTabContextMenu(BuildContext context, OpenedTab tab, TabsState state) {
    return ContextMenu(
      maxHeight: 400,
      entries: <ContextMenuEntry>[
        MenuItem(
          label: tab.isPinned ? 'בטל הצמדת כרטיסיה' : 'הצמד כרטיסיה',
          onSelected: () => context.read<TabsBloc>().add(TogglePinTab(tab)),
        ),
        MenuItem(label: 'סגור', onSelected: () => closeTab(tab, context)),
        MenuItem(label: 'סגור הכל', onSelected: () => closeAllTabs(state, context)),
        MenuItem(label: 'סגור את האחרים', onSelected: () => closeAllTabsButCurrent(state, context)),
        MenuItem(label: 'שיכפול', onSelected: () => context.read<TabsBloc>().add(CloneTab(tab))),
        const MenuDivider(),
        if (tab is! CombinedTab)
          if (state.tabs.length > 1)
            MenuItem.submenu(
              label: 'הצג לצד',
              items: state.tabs
                  .where((t) => t != tab && t is! CombinedTab)
                  .map((otherTab) => MenuItem(
                        label: otherTab.title,
                        onSelected: () => context.read<TabsBloc>().add(
                              EnableSideBySideMode(rightTab: tab, leftTab: otherTab),
                            ),
                      ))
                  .toList(),
            )
          else
            MenuItem(label: 'שלב עם', enabled: false, onSelected: () {}),
        if (tab is CombinedTab) ...[
          MenuItem(
            label: 'החלף צדדים',
            onSelected: () => context.read<TabsBloc>().add(const SwapSideBySideTabs()),
          ),
          MenuItem(
            label: 'חזרה לתצוגה רגילה',
            onSelected: () => context.read<TabsBloc>().add(const DisableSideBySideMode()),
          ),
        ],
        const MenuDivider(),
        MenuItem.submenu(label: 'רשימת הכרטיסיות', items: _getMenuItems(state.tabs, context)),
      ],
    );
  }

  Widget _buildTabContent(OpenedTab tab) {
    if (tab is CombinedTab) {
      return _buildCombinedTabView(tab);
    } else if (tab is PdfBookTab) {
      return PdfBookScreen(key: PageStorageKey(tab), tab: tab);
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
        value: tab.bloc,
        child: TextBookViewerBloc(
          openBookCallback: (tab, {int index = 1}) => context.read<TabsBloc>().add(AddTab(tab)),
          tab: tab,
        ),
      );
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(
        tab: tab,
        openBookCallback: (tab, {int index = 1}) => context.read<TabsBloc>().add(AddTab(tab)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCombinedTabView(CombinedTab combinedTab) {
    return _SideBySideViewWidget(
      key: ValueKey('combined_${combinedTab.rightTab.title}_${combinedTab.leftTab.title}'),
      rightTab: combinedTab.rightTab,
      leftTab: combinedTab.leftTab,
      initialSplitRatio: combinedTab.splitRatio,
      onSplitRatioChanged: (ratio) => context.read<TabsBloc>().add(UpdateSplitRatio(ratio)),
      buildTabView: (tab) => _buildSingleTabContent(tab, isInCombinedView: true),
    );
  }

  Widget _buildSingleTabContent(OpenedTab tab, {bool isInCombinedView = false}) {
    if (tab is PdfBookTab) {
      return PdfBookScreen(key: PageStorageKey(tab), tab: tab, isInCombinedView: isInCombinedView);
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
        value: tab.bloc,
        child: TextBookViewerBloc(
          openBookCallback: (tab, {int index = 1}) => context.read<TabsBloc>().add(AddTab(tab)),
          tab: tab,
          isInCombinedView: isInCombinedView,
        ),
      );
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(
        tab: tab,
        openBookCallback: (tab, {int index = 1}) => context.read<TabsBloc>().add(AddTab(tab)),
      );
    }
    return const SizedBox.shrink();
  }

  List<ContextMenuEntry> _getMenuItems(List<OpenedTab> tabs, BuildContext context) {
    List<MenuItem> items = tabs
        .map((tab) => MenuItem(
              label: tab.title,
              onSelected: () => context.read<TabsBloc>().add(SetCurrentTab(tabs.indexOf(tab))),
            ))
        .toList();
    items.sort((a, b) => a.label.compareTo(b.label));
    return items;
  }

  void _showSaveWorkspaceDialog(BuildContext context) {
    context.read<HistoryBloc>().add(FlushHistory());
    showDialog(context: context, builder: (context) => const WorkspaceSwitcherDialog());
  }

  void closeTab(OpenedTab tab, BuildContext context) {
    context.read<HistoryBloc>().add(AddHistory(tab));
    context.read<TabsBloc>().add(RemoveTab(tab));
  }

  void pinTabToHomePage(OpenedTab tab, BuildContext context) {
    final currentBooksString = Settings.getValue<String>('key-pinned-books') ?? '';
    List<Map<String, dynamic>> currentPinnedBooksJson;
    try {
      currentPinnedBooksJson = currentBooksString.isEmpty
          ? <Map<String, dynamic>>[]
          : (jsonDecode(currentBooksString) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      currentPinnedBooksJson = <Map<String, dynamic>>[];
    }

    if (currentPinnedBooksJson.any((book) => book['title'] == tab.title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${tab.title}" כבר נעוץ בדף הבית'), duration: const Duration(seconds: 2)),
      );
      return;
    }

    final bookData = <String, dynamic>{'title': tab.title, 'type': tab.runtimeType.toString()};
    if (tab is TextBookTab) {
      bookData['bookTitle'] = tab.book.title;
      bookData['index'] = tab.index;
    } else if (tab is PdfBookTab) {
      bookData['bookTitle'] = tab.book.title;
      bookData['bookPath'] = tab.book.path;
      bookData['pageNumber'] = tab.pageNumber;
    }

    final updatedBooks = [...currentPinnedBooksJson, bookData];
    Settings.setValue<String>('key-pinned-books', jsonEncode(updatedBooks));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('הצמדת "${tab.title}" לדף הבית'), duration: const Duration(seconds: 2)),
    );
  }

  void closeAllTabs(TabsState state, BuildContext context) {
    for (final tab in state.tabs) {
      context.read<HistoryBloc>().add(AddHistory(tab));
    }
    context.read<TabsBloc>().add(CloseAllTabs());
  }

  void closeAllTabsButCurrent(TabsState state, BuildContext context) {
    final current = state.tabs[state.currentTabIndex];
    for (final tab in state.tabs.where((t) => t != current)) {
      context.read<HistoryBloc>().add(AddHistory(tab));
    }
    context.read<TabsBloc>().add(CloseOtherTabs(current));
  }

  void _showHistoryDialog(BuildContext context) {
    context.read<HistoryBloc>().add(FlushHistory());
    showDialog(context: context, builder: (context) => const HistoryDialog());
  }

  void _showBookmarksDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const BookmarksDialog());
  }
}


/// Fluent-style TabBar widget with scroll arrows
class _FluentTabBar extends StatefulWidget {
  final List<OpenedTab> tabs;
  final int currentIndex;
  final Function(int) onTabSelected;
  final Function(OpenedTab) onTabClosed;
  final Function(OpenedTab, int) onTabReorder;
  final ContextMenu Function(OpenedTab) buildContextMenu;

  const _FluentTabBar({
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onTabReorder,
    required this.buildContextMenu,
  });

  @override
  State<_FluentTabBar> createState() => _FluentTabBarState();
}

class _FluentTabBarState extends State<_FluentTabBar> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    setState(() {
      _canScrollLeft = pos.pixels > pos.minScrollExtent + 1;
      _canScrollRight = pos.pixels < pos.maxScrollExtent - 1;
    });
  }

  void _scrollBy(double delta) {
    final pos = _scrollController.position;
    final target = (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scrollController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kTabBarHeight,
      child: Row(
        children: [
          // חץ גלילה שמאלה (בגלל RTL - חץ שמאלה מגלגל ימינה)
          if (_canScrollLeft)
            _buildScrollArrow(FluentIcons.chevron_left_20_regular, () => _scrollBy(-120)),
          // רשימת הטאבים
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scrollController,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: widget.tabs.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                widget.onTabReorder(widget.tabs[oldIndex], newIndex);
              },
              proxyDecorator: (child, index, animation) {
                return Material(elevation: 4, color: Colors.transparent, child: child);
              },
              itemBuilder: (context, index) {
                final tab = widget.tabs[index];
                final isSelected = index == widget.currentIndex;
                return ReorderableDragStartListener(
                  key: ValueKey(tab),
                  index: index,
                  child: _FluentTab(
                    tab: tab,
                    isSelected: isSelected,
                    showDivider: !isSelected && index > 0 && index - 1 != widget.currentIndex,
                    onTap: () => widget.onTabSelected(index),
                    onClose: () => widget.onTabClosed(tab),
                    contextMenu: widget.buildContextMenu(tab),
                  ),
                );
              },
            ),
          ),
          // חץ גלילה ימינה (בגלל RTL - חץ ימינה מגלגל שמאלה)
          if (_canScrollRight)
            _buildScrollArrow(FluentIcons.chevron_right_20_regular, () => _scrollBy(120)),
        ],
      ),
    );
  }

  Widget _buildScrollArrow(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 24,
        height: _kTabBarHeight,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }
}

/// Single Fluent-style tab
class _FluentTab extends StatefulWidget {
  final OpenedTab tab;
  final bool isSelected;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ContextMenu contextMenu;

  const _FluentTab({
    required this.tab,
    required this.isSelected,
    this.showDivider = false,
    required this.onTap,
    required this.onClose,
    required this.contextMenu,
  });

  @override
  State<_FluentTab> createState() => _FluentTabState();
}

class _FluentTabState extends State<_FluentTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    // צבע הרקע של התוכן (הספר) - זה יהיה צבע הטאב הפעיל והאפבר
    final contentBg = isDark ? const Color(0xFF2D2D2D) : colorScheme.primaryContainer;
    // צבע רקע לטאבים לא פעילים (כמו ה-toolbar)
    final inactiveBg = isDark ? const Color(0xFF1E1E1E) : colorScheme.surfaceContainerLow;
    final hoverBg = isDark ? const Color(0xFF252525) : colorScheme.surfaceContainerHighest;

    final backgroundColor = widget.isSelected ? contentBg : (_isHovered ? hoverBg : inactiveBg);
    final textColor = isDark ? Colors.white : Colors.black;

    Widget icon;
    String displayTitle;

    // אייקונים לפי סוג הטאב - document_text לספרי טקסט
    if (widget.tab is CombinedTab) {
      icon = Icon(FluentIcons.panel_left_text_20_regular, size: 14, color: textColor);
      displayTitle = truncate(widget.tab.title, 16);
    } else if (widget.tab is SearchingTab) {
      icon = Icon(FluentIcons.search_20_regular, size: 14, color: textColor);
      displayTitle = truncate(widget.tab.title, 18);
    } else if (widget.tab is PdfBookTab) {
      icon = Icon(FluentIcons.document_pdf_20_regular, size: 14, color: textColor);
      displayTitle = truncate(widget.tab.title, 12);
    } else {
      // ספרי טקסט - אותו אייקון כמו בספרייה
      icon = Icon(FluentIcons.document_text_20_regular, size: 14, color: textColor);
      displayTitle = truncate(widget.tab.title, 12);
    }

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 4) widget.onClose();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: ContextMenuRegion(
          contextMenu: widget.contextMenu,
          child: GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              height: _kTabBarHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // קו מפריד בין טאבים לא פעילים
                  if (widget.showDivider && !_isHovered)
                    Container(
                      width: 1,
                      height: 20,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // פינה עגולה הפוכה שמאלית - רק לטאב פעיל
                      if (widget.isSelected)
                        Positioned(
                          bottom: 0,
                          left: 1 - 6, // מתחשב ב-margin של 1
                          child: CustomPaint(
                            size: const Size(6, 6),
                            painter: _InvertedCornerPainter(
                              color: backgroundColor,
                              isLeft: true,
                            ),
                          ),
                        ),
                      // פינה עגולה הפוכה ימנית - רק לטאב פעיל
                      if (widget.isSelected)
                        Positioned(
                          bottom: 0,
                          right: 1 - 6, // מתחשב ב-margin של 1
                          child: CustomPaint(
                            size: const Size(6, 6),
                            painter: _InvertedCornerPainter(
                              color: backgroundColor,
                              isLeft: false,
                            ),
                          ),
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        height: _kTabBarHeight - (widget.isSelected ? 4 : 8),
                        margin: EdgeInsets.only(top: 4, bottom: widget.isSelected ? 0 : 4, left: 1, right: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: widget.isSelected
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  topRight: Radius.circular(6),
                                )
                              : BorderRadius.circular(6),
                        ),
                        child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.tab.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 2.0),
                            child: Icon(FluentIcons.pin_16_filled, size: 10, color: textColor),
                          ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: icon),
                        Tooltip(
                          message: widget.tab.title,
                          child: Text(
                            displayTitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor,
                              fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 100),
                          opacity: (_isHovered || widget.isSelected) ? 1.0 : 0.0,
                          child: InkWell(
                            onTap: widget.onClose,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(FluentIcons.dismiss_12_regular, size: 12, color: textColor.withOpacity(0.7)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for inverted corner effect (like Chrome tabs)
class _InvertedCornerPainter extends CustomPainter {
  final Color color;
  final bool isLeft;

  _InvertedCornerPainter({required this.color, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.arcToPoint(
        Offset(size.width, 0),
        radius: Radius.circular(size.width),
        clockwise: false,
      );
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.arcToPoint(
        const Offset(0, 0),
        radius: Radius.circular(size.width),
        clockwise: true,
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InvertedCornerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isLeft != isLeft;
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
  bool _isResizing = false;

  @override
  void initState() {
    super.initState();
    _splitRatio = widget.initialSplitRatio;
  }

  @override
  void didUpdateWidget(_SideBySideViewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSplitRatio != oldWidget.initialSplitRatio) {
      setState(() => _splitRatio = widget.initialSplitRatio);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final rightWidth = totalWidth * _splitRatio;
        final leftWidth = totalWidth * (1.0 - _splitRatio);
        final dividerWidth = _isResizing ? 4.0 : 8.0;

        return Row(
          children: [
            SizedBox(width: rightWidth, child: widget.buildTabView(widget.rightTab)),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragStart: (_) => setState(() => _isResizing = true),
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    final delta = -details.delta.dx / totalWidth;
                    _splitRatio = (_splitRatio + delta).clamp(0.2, 0.8);
                  });
                },
                onHorizontalDragEnd: (_) {
                  setState(() => _isResizing = false);
                  widget.onSplitRatioChanged(_splitRatio);
                },
                child: Container(
                  width: dividerWidth,
                  color: _isResizing ? Theme.of(context).colorScheme.primary : Colors.transparent,
                  alignment: Alignment.center,
                  child: _isResizing ? null : Container(width: 1.5, color: Theme.of(context).dividerColor),
                ),
              ),
            ),
            SizedBox(width: leftWidth - dividerWidth, child: widget.buildTabView(widget.leftTab)),
          ],
        );
      },
    );
  }
}
