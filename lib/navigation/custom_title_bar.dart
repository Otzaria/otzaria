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
import 'package:otzaria/utils/fullscreen_helper.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/utils/text_manipulation.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
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

class _CustomTitleBarState extends State<CustomTitleBar>
    with TickerProviderStateMixin {
  bool _tabsOverflow = false;
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, navState) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            return Container(
              height: 40, // גובה הכותרת
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  // כפתורי פעולה (היסטוריה וכו') - תמיד מוצגים
                  _buildActionButtons(context, settingsState),

                  // תוכן הכותרת (טאבים או כותרת רגילה)
                  Expanded(
                    child: _buildContent(context, navState, settingsState),
                  ),

                  // כפתורי חלון (רק בדסקטופ)
                  if (!kIsWeb &&
                      (Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS))
                    const SizedBox(
                      width: 138,
                      height: 50,
                      child: WindowCaption(
                        brightness: Brightness.light,
                        backgroundColor: Colors.transparent,
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
          Container(
            height: 20,
            width: 1,
            color: Colors.grey.shade400,
            margin: const EdgeInsets.symmetric(horizontal: 2),
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
    if (navState.currentScreen == Screen.reading) {
      return _buildReadingTabs(context, settingsState);
    } else {
      return _buildStandardTitle(context, navState);
    }
  }

  Widget _buildStandardTitle(BuildContext context, NavigationState navState) {
    String title = 'אוצריא';
    switch (navState.currentScreen) {
      case Screen.library:
        title = 'ספרייה';
        break;
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

        // ניהול ה-TabController
        final validIndex =
            state.currentTabIndex.clamp(0, state.tabs.length - 1);

        // יצירה מחדש של הקונטרולר אם צריך (כמו ב-ReadingScreen)
        if (_tabController == null ||
            _tabController!.length != state.tabs.length) {
          _tabController?.dispose();
          _tabController = TabController(
            length: state.tabs.length,
            vsync: this,
            initialIndex: validIndex,
          );
          _tabController!.addListener(() {
            if (_tabController!.indexIsChanging) {
              // עדכון ה-Bloc כשהמשתמש לוחץ על טאב
              if (_tabController!.index != state.currentTabIndex) {
                context
                    .read<TabsBloc>()
                    .add(SetCurrentTab(_tabController!.index));
              }
            }
          });
        } else if (_tabController!.index != validIndex &&
            !_tabController!.indexIsChanging) {
          // סנכרון הקונטרולר אם ה-Bloc השתנה ממקור אחר (למשל סגירת טאב)
          _tabController!.animateTo(validIndex);
        }

        // חישוב מרווחים למרכוז
        double leftSpacerWidth = 0;
        double rightSpacerWidth = 0;

        if (!settingsState.alignTabsToRight) {
          bool showWindowControls = !kIsWeb &&
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
          double windowControlsWidth = showWindowControls ? 138.0 : 0.0;
          double actionButtonsWidth = _kAppBarControlsWidth;
          double extraButtonsWidth =
              _kActionButtonsCount * _kActionButtonWidth;

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
            // אזור הטאבים
            Expanded(
              child: DragToMoveArea(
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
              ),
            ),

            // כפתורים נוספים (מסך מלא, הגדרות)
            IconButton(
              icon: Icon(
                settingsState.isFullscreen
                    ? FluentIcons.full_screen_minimize_24_regular
                    : FluentIcons.full_screen_maximize_24_regular,
                size: 18,
              ),
              tooltip: settingsState.isFullscreen ? 'צא ממסך מלא' : 'מסך מלא',
              onPressed: () async {
                final newFullscreenState = !settingsState.isFullscreen;
                await FullscreenHelper.toggleFullscreen(
                    context, newFullscreenState);
              },
              style: _kIconButtonStyle,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: IconButton(
                icon: const Icon(FluentIcons.settings_24_regular, size: 18),
                tooltip: 'הגדרות תצוגת הספרים',
                onPressed: () => showReadingSettingsDialog(context),
                style: _kIconButtonStyle.copyWith(
                  foregroundColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.onSurfaceVariant),
                  backgroundColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerHighest),
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
              bool isTabActive(int tabIndex) {
                return tabIndex == state.currentTabIndex;
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((index == 0 && !isTabActive(0)) ||
                      (index > 0 &&
                          !isTabActive(index) &&
                          !isTabActive(index - 1)))
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
    final bottomRadius = 12.0;
    final bottomOffset = 6.0;

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
