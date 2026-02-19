import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/widgets/scrollable_tab_bar.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/settings/reading_settings_dialog.dart';
import 'package:otzaria/settings/library_settings_dialog.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

const double _kAppBarControlsWidth = 125.0;
const double _kAppBarControlsWidthRightAligned = 105.0;
const int _kActionButtonsCount = 1; // settings בלבד
const double _kActionButtonWidth = 56.0;
const double _kWindowCaptionButtonsWidth = 138.0;
const double _kWindowCaptionButtonWidth = 46.0;

/// סגנון משותף לכפתורי האייקון בשורת הכותרת
final ButtonStyle _kIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(32, 32),
  padding: EdgeInsets.zero,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
  ),
);

class _CustomTitleBarState extends State<CustomTitleBar>
    with TickerProviderStateMixin {
  bool _tabsOverflow = false;
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _handleReadingTabControllerChange() {
    final controller = _tabController;
    if (controller == null) return;
    final tabsState = context.read<TabsBloc>().state;
    if (!tabsState.hasOpenTabs) return;

    if (controller.indexIsChanging &&
        controller.index != tabsState.currentTabIndex) {
      context.read<TabsBloc>().add(SetCurrentTab(controller.index));
    }
  }

  void _ensureReadingTabController(TabsState state) {
    if (!state.hasOpenTabs) return;

    final validIndex = state.currentTabIndex.clamp(0, state.tabs.length - 1);
    if (_tabController == null || _tabController!.length != state.tabs.length) {
      _tabController?.dispose();
      _tabController = TabController(
        length: state.tabs.length,
        vsync: this,
        initialIndex: validIndex,
      )..addListener(_handleReadingTabControllerChange);
      return;
    }

    if (_tabController!.index != validIndex &&
        !_tabController!.indexIsChanging) {
      _tabController!.animateTo(validIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, navState) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            return SizedBox(
              height: 40, // גובה הכותרת
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    clipBehavior: Clip.none,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: (navState.currentScreen == Screen.reading ||
                              navState.currentScreen == Screen.search)
                          ? null
                          : Border(
                              bottom: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                    ),
                    child: Row(
                      children: [
                        // כפתורי פעולה (היסטוריה וכו') - תמיד מוצגים
                        SizedBox(
                          height: 40,
                          child: Stack(
                            children: [
                              Center(
                                child:
                                    _buildActionButtons(context, settingsState),
                              ),
                              if (navState.currentScreen == Screen.reading ||
                                  navState.currentScreen == Screen.search)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Align(
                                    alignment: AlignmentDirectional.bottomStart,
                                    child: Container(
                                      width: 74,
                                      height: 1,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // תוכן הכותרת (טאבים או כותרת רגילה)
                        Expanded(
                          child:
                              _buildContent(context, navState, settingsState),
                        ),

                        // כפתורי חלון (רק בדסקטופ)
                        if (!kIsWeb &&
                            (Platform.isWindows ||
                                Platform.isLinux ||
                                Platform.isMacOS))
                          SizedBox(
                            height: 50,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildFullscreenCaptionButton(
                                    context, settingsState),
                                const SizedBox(
                                  width: _kWindowCaptionButtonsWidth,
                                  height: 50,
                                  child: WindowCaption(
                                    brightness: Brightness.light,
                                    backgroundColor: Colors.transparent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButtons(
      BuildContext context, SettingsState settingsState) {
    final historyShortcut =
        Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h';
    final bookmarksShortcut =
        Settings.getValue<String>('key-shortcut-open-bookmarks') ??
            'ctrl+shift+b';
    final workspaceShortcut =
        Settings.getValue<String>('key-shortcut-switch-workspace') ?? 'ctrl+k';

    return SizedBox(
      width: settingsState.alignTabsToRight
          ? _kAppBarControlsWidthRightAligned
          : _kAppBarControlsWidth,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(FluentIcons.history_24_regular, size: 18),
            tooltip: 'הצג היסטוריה (${historyShortcut.toUpperCase()})',
            onPressed: () => _showHistoryDialog(context),
            style: _kIconButtonStyle,
          ),
          IconButton(
            icon: const Icon(FluentIcons.bookmark_24_regular, size: 18),
            tooltip: 'הצג סימניות (${bookmarksShortcut.toUpperCase()})',
            onPressed: () => _showBookmarksDialog(context),
            style: _kIconButtonStyle,
          ),
          IconButton(
            icon: const Icon(FluentIcons.add_square_24_regular, size: 18),
            tooltip: 'החלף שולחן עבודה (${workspaceShortcut.toUpperCase()})',
            onPressed: () => _showSaveWorkspaceDialog(context),
            style: _kIconButtonStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, NavigationState navState,
      SettingsState settingsState) {
    if (navState.currentScreen == Screen.reading ||
        navState.currentScreen == Screen.search) {
      return _buildReadingTabs(context, settingsState);
    } else if (navState.currentScreen == Screen.library) {
      return _buildLibraryTitle(context);
    } else {
      return _buildStandardTitle(context, navState);
    }
  }

  Widget _buildLibraryTitle(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) =>
          previous.currentCategory != current.currentCategory,
      builder: (context, libraryState) {
        final title = libraryState.currentCategory?.title ?? '';
        return Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Center(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: const Icon(FluentIcons.settings_24_regular, size: 18),
                tooltip: 'הגדרות ספרייה',
                onPressed: () => showLibrarySettingsDialog(context),
                style: _kIconButtonStyle.copyWith(
                  foregroundColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStandardTitle(BuildContext context, NavigationState navState) {
    String title = 'אוצריא';
    switch (navState.currentScreen) {
      case Screen.find:
        title = 'איתור';
        break;
      case Screen.search:
        title = 'חיפוש';
        break;
      case Screen.settings:
        title = 'הגדרות';
        break;
      default:
        break;
    }

    return DragToMoveArea(
      child: Center(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  Widget _buildReadingTabs(BuildContext context, SettingsState settingsState) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        if (!state.hasOpenTabs) {
          return DragToMoveArea(
            child: Center(
              child: Text(
                'עיון',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }

        _ensureReadingTabController(state);

        // חישוב מרווחים למרכוז
        double leftSpacerWidth = 0;
        double rightSpacerWidth = 0;

        if (!settingsState.alignTabsToRight) {
          bool showWindowControls = !kIsWeb &&
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
          double windowControlsWidth = showWindowControls
              ? _kWindowCaptionButtonsWidth + _kWindowCaptionButtonWidth
              : 0.0;
          double actionButtonsWidth = _kAppBarControlsWidth;
          double extraButtonsWidth = _kActionButtonsCount * _kActionButtonWidth;

          double totalLeft = actionButtonsWidth;
          double totalRight = extraButtonsWidth + windowControlsWidth;

          if (totalRight > totalLeft) {
            leftSpacerWidth = totalRight - totalLeft;
          } else {
            rightSpacerWidth = totalLeft - totalRight;
          }
        }

        return Row(
          children: [
            if (leftSpacerWidth > 0) SizedBox(width: leftSpacerWidth),
            // אזור הטאבים המעודכן
            Expanded(
              child: DragTarget<OpenedTab>(
                onWillAcceptWithDetails: (details) => state.tabs.length > 1,
                onAcceptWithDetails: (details) {
                  // מקבלים את רוחב המסך הכולל ואת מיקום העכבר בעת העזיבה
                  final screenWidth = MediaQuery.of(context).size.width;
                  final dropPosition = details.offset.dx;
                  final isLeftHalf = dropPosition < (screenWidth / 2);
                  
                  // בודקים אם כיוון האפליקציה הוא מימין לשמאל (RTL) - אוצריא בעברית
                  final isRtl = Directionality.of(context) == TextDirection.rtl;
                  
                  // חישוב האינדקס החדש
                  int newIndex;
                  if (isRtl) {
                    newIndex = isLeftHalf ? state.tabs.length - 1 : 0;
                  } else {
                    newIndex = isLeftHalf ? 0 : state.tabs.length - 1;
                  }

                  final draggedTab = details.data;
                  final currentIndex = state.tabs.indexOf(draggedTab);
                  
                  // מבצעים את ההעברה רק אם הטאב באמת שינה מיקום
                  if (currentIndex != -1 && currentIndex != newIndex) {
                    context.read<TabsBloc>().add(MoveTab(draggedTab, newIndex));
                  }
                },
                builder: (context, candidateData, rejectedData) {
                  return DragToMoveArea(
                    child: ScrollableTabBarWithArrows(
                      controller: _tabController!,
                      tabAlignment: settingsState.alignTabsToRight
                          ? TabAlignment.start
                          : TabAlignment.center,
                      hideArrowsWhenNotScrollable: settingsState.alignTabsToRight,
                      onOverflowChanged: (overflow) {
                        if (mounted && _tabsOverflow != overflow) {
                          setState(() => _tabsOverflow = overflow);
                        }
                      },
                      tabs: state.tabs
                          .map((tab) =>
                              _buildTab(context, tab, state, settingsState))
                          .toList(),
                    ),
                  );
                },
              ),
            ),

            // כפתורים נוספים (הגדרות)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: const Icon(FluentIcons.settings_24_regular, size: 18),
                tooltip: 'הגדרות תצוגת הספרים',
                onPressed: () => showReadingSettingsDialog(context),
                style: _kIconButtonStyle.copyWith(
                  foregroundColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            if (rightSpacerWidth > 0) SizedBox(width: rightSpacerWidth),
          ],
        );
      },
    );
  }

  // --- Helper Methods copied from ReadingScreen ---

  void _showHistoryDialog(BuildContext context) {
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

  void _showSaveWorkspaceDialog(BuildContext context) {
    context.read<HistoryBloc>().add(FlushHistory());
    showDialog(
      context: context,
      builder: (context) => const WorkspaceSwitcherDialog(),
    );
  }

  Widget _buildFullscreenCaptionButton(
      BuildContext context, SettingsState settingsState) {
    return _CaptionActionButton(
      brightness: Brightness.light,
      tooltip: settingsState.isFullscreen ? 'צא ממסך מלא' : 'מסך מלא',
      icon: settingsState.isFullscreen
          ? FluentIcons.full_screen_minimize_24_regular
          : FluentIcons.full_screen_maximize_24_regular,
      onPressed: () async {
        final newFullscreenState = !settingsState.isFullscreen;
        await FullscreenHelper.toggleFullscreen(context, newFullscreenState);
      },
    );
  }

  void closeTab(OpenedTab tab, BuildContext context) {
    context.read<HistoryBloc>().add(AddHistory(tab));
    context.read<TabsBloc>().add(RemoveTab(tab));
  }

  void closeAllTabs(TabsState state, BuildContext context) {
    context.read<TabsBloc>().add(CloseAllTabs());
  }

  void closeAllTabsButCurrent(TabsState state, BuildContext context) {
    if (state.currentTab != null) {
      context.read<TabsBloc>().add(CloseOtherTabs(state.currentTab!));
    }
  }

  Widget _buildTab(BuildContext context, OpenedTab tab, TabsState state,
      SettingsState settingsState) {
    final index = state.tabs.indexOf(tab);
    final isSelected = index == state.currentTabIndex;
    final closeTabShortcut =
        Settings.getValue<String>('key-shortcut-close-tab') ?? 'ctrl+w';
    
    // מזהים את כיוון השפה כדי לדעת מאיזה צד לפתוח את הרווח
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    bool isTabActive(int tabIndex) {
      return tabIndex == state.currentTabIndex;
    }

    // פונקציה פנימית לבניית המראה של הטאב כדי למנוע כפילות קוד באנימציות
    Widget buildTabAppearance() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((index == 0 && !isTabActive(0)) ||
              (index > 0 && !isTabActive(index) && !isTabActive(index - 1)))
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              color: Colors.grey.shade400,
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 32),
            padding: EdgeInsets.only(
                left: 6,
                right: (index == 0 && settingsState.alignTabsToRight) ? 0 : 6,
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
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                                      FluentIcons.panel_left_text_24_regular,
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
                                      FluentIcons.document_pdf_24_regular,
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
                            icon: const Icon(FluentIcons.dismiss_24_regular,
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
          if (index == state.tabs.length - 1 && !isTabActive(index))
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              color: Colors.grey.shade400,
            ),
        ],
      );
    }

    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == 4) {
          closeTab(tab, context);
        }
      },
      child: ContextMenuRegion(
        contextMenu: ContextMenu(
          // ... תפריט ההקשר נשאר בדיוק כפי שהיה ...
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
                                      rightTab: tab,
                                      leftTab: otherTab,
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
            MenuItem.submenu(
              label: const Text('כרטיסיות פתוחות '),
              items: _getMenuItems(state.tabs, context),
            ),
            _buildMoveToWorkspaceMenuItem(context, tab)
          ],
        ),
        child: Draggable<OpenedTab>(
          axis: Axis.horizontal,
          data: tab,
          // כאן מתבצעת אנימציית הסגירה החלקה במקום "היעלמות" פתאומית
          childWhenDragging: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 1.0, end: 0.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Align(
                alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: value,
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: buildTabAppearance(),
          ),
          // עטיפה ב-Material כדי למנוע את הקווים הצהובים בטקסט בזמן גרירה
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: buildTabAppearance(),
            ),
          ),
          child: DragTarget<OpenedTab>(
            onAcceptWithDetails: (draggedTab) {
              if (draggedTab.data == tab) return;
              final newIndex = state.tabs.indexOf(tab);
              context.read<TabsBloc>().add(MoveTab(draggedTab.data, newIndex));
            },
            builder: (context, candidateData, rejectedData) {
              // בודקים אם יש טאב אחר שמרחף מעלינו כרגע
              final isHovered = candidateData.isNotEmpty && candidateData.first != tab;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                // פותחים רווח באמצעות שוליים כדי לדמות תזוזה של הטאבים הצידה
                margin: EdgeInsets.only(
                  right: isHovered && isRtl ? 120.0 : 0.0,
                  left: isHovered && !isRtl ? 120.0 : 0.0,
                ),
                child: buildTabAppearance(),
              );
            },
          ),
        ),
      ),
    );
  }

  /// בונה פריט תפריט להעברת טאב לשולחן עבודה אחר
  ContextMenuEntry _buildMoveToWorkspaceMenuItem(
      BuildContext context, OpenedTab tab) {
    final workspaceState = context.read<WorkspaceBloc>().state;

    // מסנן את שולחנות העבודה - מציג רק את אלו שאינם שולחן העבודה הנוכחי
    final otherWorkspaces = workspaceState.workspaces
        .where((w) => w.id != workspaceState.activeWorkspaceId)
        .toList();

    // אם אין שולחנות עבודה אחרים, מציג פריט מושבת
    if (otherWorkspaces.isEmpty) {
      return MenuItem(
        label: const Text('העבר לשולחן עבודה'),
        enabled: false,
        onSelected: (_) {},
      );
    }

    // בונה תת-תפריט עם כל שולחנות העבודה האחרים
    return MenuItem.submenu(
      label: const Text('העבר לשולחן עבודה'),
      items: otherWorkspaces.map((workspace) {
        return MenuItem(
          label: Text(workspace.name),
          onSelected: (_) {
            _moveTabToWorkspace(context, tab, workspace.id);
          },
        );
      }).toList(),
    );
  }

  /// מעביר טאב לשולחן עבודה אחר
  void _moveTabToWorkspace(
      BuildContext context, OpenedTab tab, String targetWorkspaceId) {
    final tabsBloc = context.read<TabsBloc>();
    final workspaceBloc = context.read<WorkspaceBloc>();
    final tabsState = tabsBloc.state;
    final workspaceState = workspaceBloc.state;

    // מוצא את שולחן העבודה היעד
    final targetWorkspace =
        workspaceState.workspaces.firstWhere((w) => w.id == targetWorkspaceId);

    // מסיר את הטאב מה-UI
    tabsBloc.add(RemoveTab(tab));

    // מחשב את הטאבים והאינדקס החדשים
    final currentTabs = tabsState.tabs.where((t) => t != tab).toList();
    final newActiveIndex = currentTabs.isEmpty
        ? 0
        : tabsState.currentTabIndex.clamp(0, currentTabs.length - 1);

    // שולח event להעברת הטאב
    workspaceBloc.add(MoveTabToWorkspace(
      tab: tab,
      targetWorkspaceId: targetWorkspaceId,
      currentTabs: currentTabs,
      currentTabIndex: newActiveIndex,
    ));

    // מציג הודעה למשתמש
    UiSnack.show('הכרטיסיה הועברה לשולחן העבודה "${targetWorkspace.name}"');
  }

  List<ContextMenuEntry> _getMenuItems(
    List<OpenedTab> tabs,
    BuildContext context,
  ) {
    final sortedTabs = [...tabs]..sort((a, b) => a.title.compareTo(b.title));

    return sortedTabs.map((tab) {
      return MenuItem(
        // חשוב: נותן רוחב מינימלי כדי שהשורה לא תהיה "חבילה" ממורכזת
        constraints: const BoxConstraints(minWidth: 280, minHeight: 32),

        // חשוב: label פשוט, בלי Row
        label: Text(
          tab.title,
          overflow: TextOverflow.ellipsis,
        ),

        // חשוב: ה-X מגיע כ-trailing, ואז החבילה ממקמת אותו בקצה
        trailing: IconButton(
          tooltip: 'סגור',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
          onPressed: () {
            Navigator.of(context).maybePop(); // סוגר את התפריט
            closeTab(tab, context);
          },
        ),

        onSelected: (_) {
          final index = tabs.indexOf(tab); // אינדקס לפי הרשימה המקורית
          context.read<TabsBloc>().add(SetCurrentTab(index));
        },
      );
    }).toList();
  }
}

class _TabBackgroundPainter extends CustomPainter {
  final Color color;

  _TabBackgroundPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final topRadius = 8.0;
    final bottomRadius = 15.0;
    final bottomOffset = 5.0;

    path.moveTo(-bottomRadius, size.height + bottomOffset);

    path.arcToPoint(
      Offset(0, size.height + bottomOffset - bottomRadius),
      radius: Radius.circular(bottomRadius),
      clockwise: false,
    );

    path.lineTo(0, topRadius);

    path.arcToPoint(
      Offset(topRadius, 0),
      radius: Radius.circular(topRadius),
    );

    path.lineTo(size.width - topRadius, 0);

    path.arcToPoint(
      Offset(size.width, topRadius),
      radius: Radius.circular(topRadius),
    );

    path.lineTo(size.width, size.height + bottomOffset - bottomRadius);

    path.arcToPoint(
      Offset(size.width + bottomRadius, size.height + bottomOffset),
      radius: Radius.circular(bottomRadius),
      clockwise: false,
    );

    path.lineTo(-bottomRadius, size.height + bottomOffset);

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CaptionActionButton extends StatefulWidget {
  const _CaptionActionButton({
    required this.onPressed,
    required this.icon,
    required this.brightness,
    this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final Brightness brightness;
  final String? tooltip;

  @override
  State<_CaptionActionButton> createState() => _CaptionActionButtonState();
}

class _CaptionActionButtonState extends State<_CaptionActionButton> {
  bool _isHovering = false;
  bool _isPressed = false;

  void _onHover(bool hovered) {
    if (_isHovering != hovered) {
      setState(() => _isHovering = hovered);
    }
  }

  void _onPressedState(bool pressed) {
    if (_isPressed != pressed) {
      setState(() => _isPressed = pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.brightness == Brightness.dark;

    Color bgColor = Colors.transparent;
    Color iconColor =
        isDark ? Colors.white : Colors.black.withValues(alpha: 0.8956);

    if (_isHovering) {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.0605)
          : Colors.black.withValues(alpha: 0.0373);
    }
    if (_isPressed) {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.0419)
          : Colors.black.withValues(alpha: 0.0241);
      iconColor = isDark
          ? Colors.white.withValues(alpha: 0.786)
          : Colors.black.withValues(alpha: 0.6063);
    }

    final button = MouseRegion(
      onExit: (_) => _onHover(false),
      onHover: (_) => _onHover(true),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _onPressedState(true),
        onTapCancel: () => _onPressedState(false),
        onTapUp: (_) => _onPressedState(false),
        onTap: widget.onPressed,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: _kWindowCaptionButtonWidth,
            minHeight: 32,
          ),
          decoration: BoxDecoration(color: bgColor),
          child: Center(
            child: Icon(
              widget.icon,
              size: 16,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip == null) {
      return button;
    }

    return Tooltip(message: widget.tooltip!, child: button);
  }
}