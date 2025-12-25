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
import 'package:otzaria/widgets/scrollable_tab_bar.dart';
import 'package:otzaria/settings/reading_settings_dialog.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

const double _kAppBarControlsWidth = 125.0;
const double _kAppBarControlsWidthRightAligned = 105.0;
const int _kActionButtonsCount = 2; // fullscreen + settings
const double _kActionButtonWidth = 56.0;

/// סגנון משותף לכפתורי האייקון בשורת הכותרת
final ButtonStyle _kIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(32, 32),
  padding: EdgeInsets.zero,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
  ),
);

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
                // קריאת הגדרות כדי להציג את קיצורי המקלדת
                final historyShortcut =
                    Settings.getValue<String>('key-shortcut-open-history') ??
                        'ctrl+h';
                final bookmarksShortcut =
                    Settings.getValue<String>('key-shortcut-open-bookmarks') ??
                        'ctrl+shift+b';
                final workspaceShortcut = Settings.getValue<String>(
                        'key-shortcut-switch-workspace') ??
                    'ctrl+k';

                return Scaffold(
                  appBar: AppBar(
                    key: ValueKey(
                        'appbar_empty_${historyShortcut}_${bookmarksShortcut}_$workspaceShortcut'),
                    leadingWidth: _kAppBarControlsWidth,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // קבוצת היסטוריה וסימניות
                        IconButton(
                          icon: const Icon(FluentIcons.history_24_regular,
                              size: 18),
                          tooltip:
                              'הצג היסטוריה (${historyShortcut.toUpperCase()})',
                          onPressed: () => _showHistoryDialog(context),
                          style: _kIconButtonStyle,
                        ),
                        IconButton(
                          icon: const Icon(FluentIcons.bookmark_24_regular,
                              size: 18),
                          tooltip:
                              'הצג סימניות (${bookmarksShortcut.toUpperCase()})',
                          onPressed: () => _showBookmarksDialog(context),
                          style: _kIconButtonStyle,
                        ),
                        // קו מפריד
                        Container(
                          height: 20,
                          width: 1,
                          color: Colors.grey.shade400,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                        ),
                        // קבוצת שולחן עבודה
                        IconButton(
                          icon: const Icon(FluentIcons.add_square_24_regular,
                              size: 18),
                          tooltip:
                              'החלף שולחן עבודה (${workspaceShortcut.toUpperCase()})',
                          onPressed: () => _showSaveWorkspaceDialog(context),
                          style: _kIconButtonStyle,
                        ),
                      ],
                    ),
                    titleSpacing: 0,
                    centerTitle: true,
                    title: const Text('עיון'),
                    actions: [
                      // כפתור מסך מלא
                      BlocBuilder<SettingsBloc, SettingsState>(
                        builder: (context, settingsState) {
                          return IconButton(
                            icon: Icon(
                              settingsState.isFullscreen
                                  ? FluentIcons.full_screen_minimize_24_regular
                                  : FluentIcons.full_screen_maximize_24_regular,
                              size: 18,
                            ),
                            tooltip: settingsState.isFullscreen
                                ? 'צא ממסך מלא'
                                : 'מסך מלא',
                            onPressed: () async {
                              final newFullscreenState =
                                  !settingsState.isFullscreen;
                              await FullscreenHelper.toggleFullscreen(
                                  context, newFullscreenState);
                            },
                            style: _kIconButtonStyle,
                          );
                        },
                      ),
                      // כפתור הגדרות
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: IconButton(
                          icon: const Icon(FluentIcons.settings_24_regular,
                              size: 18),
                          tooltip: 'הגדרות תצוגת הספרים',
                          onPressed: () => showReadingSettingsDialog(context),
                          style: _kIconButtonStyle.copyWith(
                            foregroundColor: WidgetStatePropertyAll(
                                Theme.of(context).colorScheme.onSurfaceVariant),
                            backgroundColor: WidgetStatePropertyAll(
                                Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest),
                          ),
                        ),
                      ),
                    ],
                  ),
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

              // וידוא שהאינדקס תקף לפני יצירת ה-TabController
              final validIndex =
                  state.currentTabIndex.clamp(0, state.tabs.length - 1);
              final controller = TabController(
                length: state.tabs.length,
                vsync: this,
                initialIndex: validIndex,
              );

              controller.addListener(() {
                // בדיקה אם TabBarView קיים (לא במצב side-by-side)
                try {
                  if (controller.indexIsChanging &&
                      state.currentTabIndex < state.tabs.length) {
                    // שמירת המצב הנוכחי לפני המעבר לטאב אחר
                    debugPrint(
                        'DEBUG: מעבר בין טאבים - שמירת מצב טאב ${state.currentTabIndex}');
                    context.read<HistoryBloc>().add(CaptureStateForHistory(
                        state.tabs[state.currentTabIndex]));
                    // שמירת כל הטאבים לדיסק
                    context.read<TabsBloc>().add(const SaveTabs());
                  }
                  if (controller.index != state.currentTabIndex) {
                    debugPrint('DEBUG: עדכון טאב נוכחי ל-${controller.index}');
                    context
                        .read<TabsBloc>()
                        .add(SetCurrentTab(controller.index));
                  }
                } catch (e) {
                  // אם TabBarView לא קיים, מתעלמים
                  debugPrint(
                      'DEBUG: TabController listener error (expected in side-by-side mode): $e');
                }
              });

              // קריאת הגדרות כדי לגרום ל-rebuild כשהן משתנות
              final historyShortcut =
                  Settings.getValue<String>('key-shortcut-open-history') ??
                      'ctrl+h';
              final bookmarksShortcut =
                  Settings.getValue<String>('key-shortcut-open-bookmarks') ??
                      'ctrl+shift+b';
              final workspaceShortcut =
                  Settings.getValue<String>('key-shortcut-switch-workspace') ??
                      'ctrl+k';
              final closeTabShortcut =
                  Settings.getValue<String>('key-shortcut-close-tab') ??
                      'ctrl+w';

              return Scaffold(
                appBar: AppBar(
                  toolbarHeight: 36, // הקטנת גובה ה-AppBar
                  key: ValueKey(
                      'appbar_${historyShortcut}_${bookmarksShortcut}_${workspaceShortcut}_$closeTabShortcut'),
                  // רוחב מצומצם יותר כשהיישור לימין כדי להצמיד את הטאבים
                  leadingWidth: settingsState.alignTabsToRight
                      ? _kAppBarControlsWidthRightAligned
                      : _kAppBarControlsWidth,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // קבוצת היסטוריה וסימניות
                      IconButton(
                        icon: const Icon(FluentIcons.history_24_regular,
                            size: 18),
                        tooltip:
                            'הצג היסטוריה (${historyShortcut.toUpperCase()})',
                        onPressed: () => _showHistoryDialog(context),
                        style: _kIconButtonStyle,
                      ),
                      IconButton(
                        icon: const Icon(FluentIcons.bookmark_24_regular,
                            size: 18),
                        tooltip:
                            'הצג סימניות (${bookmarksShortcut.toUpperCase()})',
                        onPressed: () => _showBookmarksDialog(context),
                        style: _kIconButtonStyle,
                      ),
                      // קו מפריד
                      Container(
                        height: 20,
                        width: 1,
                        color: Colors.grey.shade400,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                      ),
                      // קבוצת שולחן עבודה עם אנימציה
                      IconButton(
                        icon: const Icon(FluentIcons.add_square_24_regular,
                            size: 18),
                        tooltip:
                            'החלף שולחן עבודה (${workspaceShortcut.toUpperCase()})',
                        onPressed: () => _showSaveWorkspaceDialog(context),
                        style: _kIconButtonStyle,
                      ),
                    ],
                  ),
                  titleSpacing: 0,
                  centerTitle: true,
                  title: Container(
                    // גובה מופחת של אזור הטאבים
                    constraints: const BoxConstraints(maxHeight: 32),
                    child: ScrollableTabBarWithArrows(
                      controller: controller,
                      // יישור הטאבים לפי הגדרת המשתמש
                      tabAlignment: settingsState.alignTabsToRight
                          ? TabAlignment.start
                          : TabAlignment.center,
                      // הסתרת החיצים כשאין גלילה ויישור לימין - למניעת רווחים מיותרים
                      hideArrowsWhenNotScrollable:
                          settingsState.alignTabsToRight,
                      onOverflowChanged: (overflow) {
                        if (mounted) {
                          setState(() => _tabsOverflow = overflow);
                        }
                      },
                      tabs: state.tabs
                          .map((tab) =>
                              _buildTab(context, tab, state, settingsState))
                          .toList(),
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
                          icon: Icon(
                            settingsState.isFullscreen
                                ? FluentIcons.full_screen_minimize_24_regular
                                : FluentIcons.full_screen_maximize_24_regular,
                            size: 18,
                          ),
                          tooltip: settingsState.isFullscreen
                              ? 'צא ממסך מלא'
                              : 'מסך מלא',
                          onPressed: () async {
                            final newFullscreenState =
                                !settingsState.isFullscreen;
                            await FullscreenHelper.toggleFullscreen(
                                context, newFullscreenState);
                          },
                          style: _kIconButtonStyle,
                        );
                      },
                    ),
                    // כפתור הגדרות בצד שמאל של שורת הטאבים
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: IconButton(
                        icon: const Icon(FluentIcons.settings_24_regular,
                            size: 18),
                        tooltip: 'הגדרות תצוגת הספרים',
                        onPressed: () => showReadingSettingsDialog(context),
                        style: _kIconButtonStyle.copyWith(
                          foregroundColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.onSurfaceVariant),
                          backgroundColor: WidgetStatePropertyAll(
                              Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest),
                        ),
                      ),
                    ),
                  ],
                ),
                body: SizedBox.fromSize(
                  size: MediaQuery.of(context).size,
                  child: TabBarView(
                    key: const ValueKey('normal_tab_view'),
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

  Widget _buildTab(BuildContext context, OpenedTab tab, TabsState state,
      SettingsState settingsState) {
    final index = state.tabs.indexOf(tab);
    final isSelected = index == state.currentTabIndex;
    final closeTabShortcut =
        Settings.getValue<String>('key-shortcut-close-tab') ?? 'ctrl+w';

    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == 4) {
          closeTab(tab, context);
        }
      },
      child: ContextMenuRegion(
        contextMenu: ContextMenu(
          maxHeight: 400,
          entries: <ContextMenuEntry>[
            MenuItem(
              label: Text(tab.isPinned ? 'בטל הצמדת כרטיסיה' : 'הצמד כרטיסיה'),
              onSelected: (_) =>
                  context.read<TabsBloc>().add(TogglePinTab(tab)),
            ),
            MenuItem(
                label: const Text('סגור'),
                onSelected: (_) => closeTab(tab, context)),
            MenuItem(
                label: const Text('סגור הכל'),
                onSelected: (_) => closeAllTabs(state, context)),
            MenuItem(
              label: const Text('סגור את האחרים'),
              onSelected: (_) => closeAllTabsButCurrent(state, context),
            ),
            MenuItem(
              label: const Text('שיכפול'),
              onSelected: (_) => context.read<TabsBloc>().add(CloneTab(tab)),
            ),
            const MenuDivider(),
            // אפשרות "הצג לצד" - תמיד מוצגת, אבל מושבתת אם אין מספיק טאבים
            if (tab is! CombinedTab)
              if (state.tabs.length > 1)
                MenuItem.submenu(
                  label: const Text('הצג לצד'),
                  items: state.tabs
                      .where((t) => t != tab && t is! CombinedTab)
                      .map((otherTab) => MenuItem(
                            label: Text(otherTab.title),
                            onSelected: (_) {
                              context.read<TabsBloc>().add(
                                    EnableSideBySideMode(
                                      rightTab: tab, // הטאב הנוכחי ימני
                                      leftTab: otherTab, // הטאב שנבחר שמאלי
                                    ),
                                  );
                            },
                          ))
                      .toList(),
                )
              else
                MenuItem(
                  label: const Text('הצג לצד'),
                  enabled: false,
                  onSelected: (_) {},
                ),
            // אפשרויות לטאב משולב
            if (tab is CombinedTab) ...[
              MenuItem(
                label: const Text('החלף צדדים'),
                onSelected: (_) =>
                    context.read<TabsBloc>().add(const SwapSideBySideTabs()),
              ),
              MenuItem(
                label: const Text('חזרה לתצוגה רגילה'),
                onSelected: (_) =>
                    context.read<TabsBloc>().add(const DisableSideBySideMode()),
              ),
            ],
            const MenuDivider(),
            // הוסרת אפשרות הצמדה לדף הבית לאחר הסרת דף הבית
            MenuItem.submenu(
              label: const Text('רשימת הכרטיסיות '),
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
            builder: (context, candidateData, rejectedData) {
              // קביעת אילו טאבים נחשבים "פעילים" לצורך פס ההפרדה
              bool isTabActive(int tabIndex) {
                return tabIndex == state.currentTabIndex;
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- לוגיקה חדשה ומאוחדת לפס הפרדה שמופיע מימין לטאב ---
                  // בסביבת RTL, הווידג'ט הראשון ברשימה מופיע הכי ימני במסך.
                  if (
                      // תנאי 1: הצגת פס הפרדה בקצה הימני של כל הטאבים.
                      // הפס נוצר על ידי הטאב הראשון (index 0) כשהוא אינו פעיל.
                      (index == 0 && !isTabActive(0)) ||
                          // תנאי 2: הצגת פס הפרדה בין שני טאבים.
                          // הפס נוצר על ידי הטאב הנוכחי (index) אם הוא וגם הטאב שלפניו (index - 1) אינם פעילים.
                          (index > 0 &&
                              !isTabActive(index) &&
                              !isTabActive(index - 1)))
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.only(top: 6, bottom: 6),
                      color: Colors.grey.shade400,
                    ),

                  // הווידג'ט המרכזי שמכיל את הטאב עצמו (ללא שינוי).
                  Container(
                    // גובה מופחת של הטאבים
                    constraints: const BoxConstraints(maxHeight: 32),
                    // הסרת padding ימני מהטאב הראשון כשהיישור לימין
                    padding: EdgeInsets.only(
                        left: 6,
                        right: (index == 0 && settingsState.alignTabsToRight)
                            ? 0
                            : 6,
                        top: 0,
                        bottom: 0),
                    child: CustomPaint(
                      painter: isSelected
                          ? _TabBackgroundPainter(
                              Theme.of(context).colorScheme.surfaceContainer)
                          : null,
                      child: Tab(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // אינדיקטור הצמדה
                                if (tab.isPinned)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4.0),
                                    child: Icon(
                                      FluentIcons.pin_24_filled,
                                      size: 14,
                                    ),
                                  ),
                                if (tab is CombinedTab)
                                  Tooltip(
                                    message: tab.title,
                                    child: Row(
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(
                                              FluentIcons
                                                  .panel_left_text_24_regular,
                                              size: 16),
                                        ),
                                        Text(truncate(tab.title, 20)),
                                      ],
                                    ),
                                  )
                                else if (tab is SearchingTab)
                                  ValueListenableBuilder(
                                    valueListenable: tab.queryController,
                                    builder: (context, value, child) => Tooltip(
                                      message: tab.title,
                                      child: Text(
                                        truncate(tab.title, 25),
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
                                          child: Icon(
                                              FluentIcons
                                                  .document_pdf_24_regular,
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
                                  message: closeTabShortcut.toUpperCase(),
                                  child: IconButton(
                                    constraints: const BoxConstraints(
                                      minWidth: 25,
                                      minHeight: 25,
                                      maxWidth: 25,
                                      maxHeight: 25,
                                    ),
                                    onPressed: () => closeTab(tab, context),
                                    icon: const Icon(
                                        FluentIcons.dismiss_24_regular,
                                        size: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // --- לוגיקה לפס הפרדה שמופיע משמאל לטאב ---
                  // משמש רק עבור הקצה השמאלי ביותר של כל הטאבים.
                  // הפס נוצר על ידי הטאב האחרון כשהוא אינו פעיל.
                  if (index == state.tabs.length - 1 && !isTabActive(index))
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.only(top: 6, bottom: 6),
                      color: Colors.grey.shade400,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<ContextMenuEntry> _getMenuItems(
      List<OpenedTab> tabs, BuildContext context) {
    List<MenuItem> items = tabs
        .map((tab) => MenuItem(
              label: Text(tab.title),
              onSelected: (_) {
                final index = tabs.indexOf(tab);
                context.read<TabsBloc>().add(SetCurrentTab(index));
              },
            ))
        .toList();

    items.sort((a, b) {
      final aText = (a.label as Text).data ?? '';
      final bText = (b.label as Text).data ?? '';
      return aText.compareTo(bText);
    });
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

  void pinTabToHomePage(OpenedTab tab, BuildContext context) {
    debugPrint('Pinning tab: ${tab.title}'); // debug

    // קבל את הרשימה הנוכחית של הספרים הנעוצים
    final currentBooksString =
        Settings.getValue<String>('key-pinned-books') ?? '';

    List<Map<String, dynamic>> currentPinnedBooksJson;
    try {
      currentPinnedBooksJson = currentBooksString.isEmpty
          ? <Map<String, dynamic>>[]
          : (jsonDecode(currentBooksString) as List)
              .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error parsing current pinned books, resetting: $e');
      currentPinnedBooksJson = <Map<String, dynamic>>[];
    }

    // בדוק אם הספר כבר נעוץ
    if (currentPinnedBooksJson.any((book) => book['title'] == tab.title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${tab.title}" כבר נעוץ בדף הבית'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // צור אובייקט עם כל המידע של הטאב
    final bookData = <String, dynamic>{
      'title': tab.title,
      'type': tab.runtimeType.toString(),
    };

    // הוסף מידע ספציפי לפי סוג הטאב
    if (tab is TextBookTab) {
      bookData['bookTitle'] = tab.book.title;
      bookData['index'] = tab.index;
    } else if (tab is PdfBookTab) {
      bookData['bookTitle'] = tab.book.title;
      bookData['bookPath'] = tab.book.path;
      bookData['pageNumber'] = tab.pageNumber;
    }

    // הוסף את הספר החדש
    final updatedBooks = [...currentPinnedBooksJson, bookData];

    // שמור את הרשימה המעודכנת כ-JSON
    final booksString = jsonEncode(updatedBooks);
    Settings.setValue<String>('key-pinned-books', booksString);

    debugPrint('Saved pinned books: $booksString'); // debug

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('הצמדת "${tab.title}" לדף הבית'),
        duration: const Duration(seconds: 2),
      ),
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
        final dividerWidth = _isResizing ? 4.0 : 8.0;

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
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) {
                      setState(() => _isResizing = true);
                    },
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        // תיקון: הפיכת הכיוון כי אנחנו ב-RTL
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

// CustomPainter לציור רקע של הטאב הפעיל
class _TabBackgroundPainter extends CustomPainter {
  final Color backgroundColor;

  _TabBackgroundPainter(this.backgroundColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final topRadius = 8.0;
    final bottomRadius = 12.0; // רדיוס לעיגול הפוך בפינות התחתונות
    final bottomOffset = 6.0;

    // מתחילים מהפינה השמאלית התחתונה עם עיגול הפוך
    path.moveTo(-bottomRadius, size.height + bottomOffset);

    // עיגול הפוך בפינה התחתונה השמאלית
    path.arcToPoint(
      Offset(0, size.height + bottomOffset - bottomRadius),
      radius: Radius.circular(bottomRadius),
      clockwise: false,
    );

    // קו שמאלי למעלה
    path.lineTo(0, topRadius);

    // פינה עליונה שמאלית מעוגלת
    path.arcToPoint(
      Offset(topRadius, 0),
      radius: Radius.circular(topRadius),
    );

    // קו עליון
    path.lineTo(size.width - topRadius, 0);

    // פינה עליונה ימנית מעוגלת
    path.arcToPoint(
      Offset(size.width, topRadius),
      radius: Radius.circular(topRadius),
    );

    // קו ימני למטה
    path.lineTo(size.width, size.height + bottomOffset - bottomRadius);

    // עיגול הפוך בפינה התחתונה הימנית
    path.arcToPoint(
      Offset(size.width + bottomRadius, size.height + bottomOffset),
      radius: Radius.circular(bottomRadius),
      clockwise: false,
    );

    // קו תחתון
    path.lineTo(-bottomRadius, size.height + bottomOffset);

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
