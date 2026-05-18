import 'dart:async';
import 'dart:io';
import 'dart:math' show max;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/navigation/scrollable_tab_bar.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

class CustomTitleBar extends StatefulWidget {
  final VoidCallback? onReadingSettingsPressed;
  final bool isReadingSettingsPanelOpen;

  const CustomTitleBar({
    super.key,
    this.onReadingSettingsPressed,
    this.isReadingSettingsPanelOpen = false,
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

const double _kAppBarControlsWidth = 125.0;
const double _kAppBarControlsWidthRightAligned = 105.0;
const int _kActionButtonsCount = 1; // settings בלבד
const double _kActionButtonWidth = 56.0;
const double _kWindowCaptionButtonsWidth = 138.0;
const double _kWindowCaptionButtonWidth = 46.0;

// קבועים לחישוב רוחב טאבים בסגנון Chrome
const double _kMaxTabWidth = 200.0;
// מינימום: padding (4) + tab padding (8) + pin icon (15) + X (25) + 2 אותיות עברית (20)
const double _kMinTabWidth = 72.0;

/// סגנון משותף לכפתורי האייקון בשורת הכותרת
final ButtonStyle _kIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(32, 32),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
  ),
);

class _CustomTitleBarState extends State<CustomTitleBar>
    with TickerProviderStateMixin {
  bool _tabsOverflow = false;
  TabController? _tabController;

  // ניהול רוחב טאבים בסגנון Chrome
  int _displayedTabCount = 0;
  List<OpenedTab>? _previousTabs;
  Timer? _tabCloseDebounce;

  @override
  void dispose() {
    _tabCloseDebounce?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  /// מעדכן את _displayedTabCount לפי הלוגיקה:
  /// - פתיחת טאב: מיידי
  /// - סגירת הטאב האחרון ברשימה: מיידי
  /// - סגירת טאב אחר: עיכוב 2 שניות
  void _updateTabsDisplay(TabsState state) {
    final newTabs = state.tabs;
    final newCount = newTabs.length;
    final prevTabs = _previousTabs;
    _previousTabs = List.unmodifiable(newTabs);

    if (prevTabs == null) return; // אתחול ראשוני מטופל בבנאי

    final prevCount = prevTabs.length;
    if (newCount == prevCount) return;

    if (newCount > prevCount) {
      // נפתח טאב חדש — מיידי
      _tabCloseDebounce?.cancel();
      setState(() => _displayedTabCount = newCount);
      return;
    }

    // נסגר טאב — בדוק אם היה הטאב האחרון
    final bool lastTabRemoved = prevTabs.isNotEmpty &&
        newCount == prevCount - 1 &&
        (newCount == 0 || !newTabs.contains(prevTabs.last));

    if (lastTabRemoved) {
      // הטאב האחרון נסגר — מיידי (כפתור ה-X נשאר באותו מקום)
      _tabCloseDebounce?.cancel();
      setState(() => _displayedTabCount = newCount);
    } else {
      // טאב פנימי נסגר — עיכוב 2 שניות למניעת קפיצות
      _tabCloseDebounce?.cancel();
      _tabCloseDebounce = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(
              () => _displayedTabCount = context.read<TabsBloc>().state.tabs.length);
        }
      });
    }
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
                      color: (navState.currentScreen == Screen.reading ||
                              navState.currentScreen == Screen.search)
                          ? Theme.of(context).colorScheme.surface
                          : AppSurfaces.solidPanelBackground(context),
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
                                if (settingsState.isFullscreen)
                                  _CaptionActionButton(
                                    brightness: Theme.of(context).brightness,
                                    tooltip: 'מזער',
                                    icon: FluentIcons.subtract_24_regular,
                                    onPressed: () async {
                                      await FullscreenHelper.toggleFullscreen(
                                          context, false);
                                      await windowManager.minimize();
                                    },
                                  ),
                                if (settingsState.isFullscreen)
                                  _CaptionActionButton(
                                    brightness: Theme.of(context).brightness,
                                    tooltip: 'סגור',
                                    icon: FluentIcons.dismiss_24_regular,
                                    onPressed: () => windowManager.close(),
                                  ),
                                if (!settingsState.isFullscreen)
                                  SizedBox(
                                    width: _kWindowCaptionButtonsWidth,
                                    height: 50,
                                    child: WindowCaption(
                                      brightness: Theme.of(context).brightness,
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
      child: Stack(
        children: [
          const DragToMoveArea(
            child: SizedBox.expand(),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: tourTitleBarHistoryButtonTargetKey,
                  icon: const Icon(FluentIcons.history_24_regular, size: 18),
                  tooltip: 'הצג היסטוריה (${historyShortcut.toUpperCase()})',
                  onPressed: () => _showHistoryDialog(context),
                  style: _kIconButtonStyle,
                ),
                IconButton(
                  key: tourTitleBarBookmarkButtonTargetKey,
                  icon: const Icon(FluentIcons.bookmark_24_regular, size: 18),
                  tooltip: 'הצג סימניות (${bookmarksShortcut.toUpperCase()})',
                  onPressed: () => _showBookmarksDialog(context),
                  style: _kIconButtonStyle,
                ),
                IconButton(
                  icon: const Icon(FluentIcons.add_square_24_regular, size: 18),
                  tooltip:
                      'החלף שולחן עבודה (${workspaceShortcut.toUpperCase()})',
                  onPressed: () => _showSaveWorkspaceDialog(context),
                  style: _kIconButtonStyle,
                ),
              ],
            ),
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
    return BlocConsumer<TabsBloc, TabsState>(
      listener: (context, state) => _updateTabsDisplay(state),
      builder: (context, state) {
        // אתחול ראשוני של המספר המוצג
        if (_previousTabs == null) {
          _displayedTabCount = state.tabs.length;
          _previousTabs = List.unmodifiable(state.tabs);
        }

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
            if (leftSpacerWidth > 0)
              DragToMoveArea(
                child: SizedBox(width: leftSpacerWidth),
              ),
            // אזור הטאבים המעודכן
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // חישוב רוחב טאב בסגנון Chrome
                  // שימוש ב-max כדי שבפתיחת טאב חדש (לפני שה-setState מתעדכן)
                  // לא יהיו יותר טאבים ממה שמחושב — ימנע overflow וחיצי גלילה מיותרים
                  final int displayCount =
                      max(_displayedTabCount, state.tabs.length).clamp(1, 9999);
                  double tabWidth =
                      constraints.maxWidth / displayCount;
                  tabWidth = tabWidth.clamp(_kMinTabWidth, _kMaxTabWidth);

                  return DragTarget<OpenedTab>(
                    onWillAcceptWithDetails: (details) => state.tabs.length > 1,
                    onAcceptWithDetails: (details) {
                      // מקבלים את רוחב המסך הכולל ואת מיקום העכבר בעת העזיבה
                      final RenderBox renderBox =
                          context.findRenderObject() as RenderBox;
                      final localOffset =
                          renderBox.globalToLocal(details.offset);
                      final isLeftHalf =
                          localOffset.dx < (renderBox.size.width / 2);

                      // בודקים אם כיוון האפליקציה הוא מימין לשמאל (RTL)
                      final isRtl =
                          Directionality.of(context) == TextDirection.rtl;

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
                        context
                            .read<TabsBloc>()
                            .add(MoveTab(draggedTab, newIndex));
                      }
                    },
                    builder: (context, candidateData, rejectedData) {
                      return DragToMoveArea(
                        child: KeyedSubtree(
                          key: tourReadingTabsTargetKey,
                          child: ScrollableTabBarWithArrows(
                            controller: _tabController!,
                            tabAlignment: settingsState.alignTabsToRight
                                ? TabAlignment.start
                                : TabAlignment.center,
                            hideArrowsWhenNotScrollable:
                                settingsState.alignTabsToRight,
                            onOverflowChanged: (overflow) {
                              if (mounted && _tabsOverflow != overflow) {
                                setState(() => _tabsOverflow = overflow);
                              }
                            },
                            tabWidth: tabWidth,
                            tabs: state.tabs
                                .map((tab) => _buildTab(
                                    context, tab, state, settingsState))
                                .toList(),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // רווח קבוע בין הכרטסיה האחרונה לבין סמל ההגדרות (~חצי טאב)
            // רלוונטי רק במצב צמוד-לימין; במצב ממורכז אין צורך ברווח זה
            if (settingsState.alignTabsToRight) const SizedBox(width: 36),

            // כפתורים נוספים (הגדרות)
            DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: IconButton(
                  key: tourReadingSettingsButtonTargetKey,
                  icon: Icon(
                    widget.isReadingSettingsPanelOpen
                        ? FluentIcons.settings_24_filled
                        : FluentIcons.settings_24_regular,
                    size: 18,
                  ),
                  tooltip: 'הגדרות תצוגת הספרים',
                  onPressed: widget.onReadingSettingsPressed ??
                      () => showReadingSettingsDialog(context),
                  style: _kIconButtonStyle.copyWith(
                    foregroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            if (rightSpacerWidth > 0)
              DragToMoveArea(
                child: SizedBox(width: rightSpacerWidth),
              ),
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
      brightness: Theme.of(context).brightness,
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

  /// בונה אייקון הצמדה inline עם hover state מהטאב
  Widget _buildPinIconInline(
      BuildContext context, OpenedTab tab, bool isHovered) {
    final show = tab.isPinned || isHovered;
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      child: show
          ? GestureDetector(
              onTap: () => context.read<TabsBloc>().add(TogglePinTab(tab)),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 1.0, end: 4.0),
                child: Tooltip(
                  message: tab.isPinned ? 'בטל הצמדה' : 'הצמד כרטיסיה',
                  child: Icon(
                    tab.isPinned
                        ? FluentIcons.pin_24_filled
                        : FluentIcons.pin_24_regular,
                    size: 14,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
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

    // State לניהול hover על הטאב
    bool isTabHovered = false;

    // פונקציה פנימית לבניית המראה של הטאב כדי למנוע כפילות קוד באנימציות
    Widget buildTabAppearance(StateSetter? setState) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 32),
        padding: EdgeInsetsDirectional.only(
            start: 2,
            end: (index == 0 && settingsState.alignTabsToRight) ? 0 : 2,
            top: 0,
            bottom: 0),
        child: CustomPaint(
          painter: isSelected
              ? _TabBackgroundPainter(
                  Theme.of(context).colorScheme.surfaceContainer)
              : null,
          child: Tab(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
                  child: Transform.translate(
                    offset: const Offset(0, -2),
                    child: Row(
                      children: [
                        if (isSelected) const SizedBox(width: 4),
                        _buildPinIconInline(context, tab, isTabHovered),
                    if (tab is CombinedTab)
                      Expanded(
                        child: Tooltip(
                          message: tab.title,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(
                                  FluentIcons.panel_left_text_24_regular,
                                  size: 14),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  tab.title,
                                  overflow: TextOverflow.clip,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (tab is SearchingTab)
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: tab.titleNotifier,
                          builder: (context, title, child) => Tooltip(
                            message: title,
                            child: Text(
                              title,
                              overflow: TextOverflow.clip,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      )
                    else if (tab is PdfBookTab)
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: tab.currentTitle,
                          builder: (context, currentTitleValue, child) {
                            final tooltipMessage =
                                currentTitleValue.isNotEmpty
                                    ? '${tab.title}, $currentTitleValue'
                                    : tab.title;
                            return Tooltip(
                              message: tooltipMessage,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                      FluentIcons.document_pdf_24_regular,
                                      size: 14),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      tab.title,
                                      overflow: TextOverflow.clip,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: (tab as TextBookTab).currentTitle,
                          builder: (context, currentTitleValue, child) {
                            final tooltipMessage =
                                currentTitleValue.isNotEmpty
                                    ? '${tab.title}, $currentTitleValue'
                                    : tab.title;
                            return Tooltip(
                              message: tooltipMessage,
                              child: Text(
                                tab.title,
                                overflow: TextOverflow.clip,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            );
                          },
                        ),
                      ),
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
                    if (!isSelected && index != state.currentTabIndex - 1)
                      Container(
                        width: 1,
                        height: 16,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      ],
                    ),
                  ),
              ),
            ),
          ),
        ),
      );
    }

    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == 4) {
          closeTab(tab, context);
        }
      },
      child: AppContextMenuRegion(
        key: isSelected ? tourTabContextMenuTargetKey : null,
        menuBuilder: (menuCtx, _) =>
            _buildTabContextMenuEntries(menuCtx, tab, state),
        menuItemKeysByLabel:
            isSelected ? {'הצג לצד': tourTabSideBySideMenuItemTargetKey} : null,
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
            child: buildTabAppearance(null),
          ),
          // עטיפה ב-Material כדי למנוע את הקווים הצהובים בטקסט בזמן גרירה
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: buildTabAppearance(null),
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
              final isHovered =
                  candidateData.isNotEmpty && candidateData.first != tab;

              return StatefulBuilder(
                builder: (context, setState) {
                  return MouseRegion(
                    onEnter: (_) => setState(() => isTabHovered = true),
                    onExit: (_) => setState(() => isTabHovered = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      // פותחים רווח באמצעות שוליים כדי לדמות תזוזה של הטאבים הצידה
                      margin: EdgeInsets.only(
                        right: isHovered && isRtl ? 120.0 : 0.0,
                        left: isHovered && !isRtl ? 120.0 : 0.0,
                      ),
                      child: buildTabAppearance(setState),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// בונה פריט תפריט להעברת טאב לשולחן עבודה אחר
  AppContextMenuEntry _buildMoveToWorkspaceMenuEntry(
      BuildContext context, OpenedTab tab) {
    final workspaceState = context.read<WorkspaceBloc>().state;

    // מסנן את שולחנות העבודה - מציג רק את אלו שאינם שולחן העבודה הנוכחי
    final otherWorkspaces = workspaceState.workspaces
        .where((w) => w.id != workspaceState.activeWorkspaceId)
        .toList();

    // אם אין שולחנות עבודה אחרים, מציג פריט מושבת
    if (otherWorkspaces.isEmpty) {
      return AppContextMenuEntry(
        label: 'העבר לשולחן עבודה',
        enabled: false,
      );
    }

    // בונה תת-תפריט עם כל שולחנות העבודה האחרים
    return AppContextMenuEntry(
      label: 'העבר לשולחן עבודה',
      children: otherWorkspaces.map((workspace) {
        return AppContextMenuEntry(
          label: workspace.name,
          onTap: () {
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

  List<AppContextMenuEntry> _buildTabContextMenuEntries(
    BuildContext menuCtx,
    OpenedTab tab,
    TabsState state,
  ) {
    final entries = <AppContextMenuEntry>[
      AppContextMenuEntry(
        label: tab.isPinned ? 'בטל הצמדת כרטיסיה' : 'הצמד כרטיסיה',
        onTap: () => context.read<TabsBloc>().add(TogglePinTab(tab)),
      ),
      AppContextMenuEntry(
        label: 'סגור',
        onTap: () => closeTab(tab, context),
      ),
      AppContextMenuEntry(
        label: 'סגור הכל',
        onTap: () => closeAllTabs(state, context),
      ),
      AppContextMenuEntry(
        label: 'סגור את האחרים',
        onTap: () => closeAllTabsButCurrent(state, context),
      ),
      AppContextMenuEntry(
        label: 'שיכפול',
        onTap: () => context.read<TabsBloc>().add(CloneTab(tab)),
      ),
      const AppContextMenuEntry.divider(),
    ];

    // הצג לצד
    if (tab is! CombinedTab) {
      if (state.tabs.length > 1) {
        final otherTabsList = state.tabs
            .where((t) => t != tab && t is! CombinedTab)
            .toList();
        final otherTabs = otherTabsList.asMap().entries.map((mapEntry) {
          final isFirst = mapEntry.key == 0;
          final otherTab = mapEntry.value;
          return AppContextMenuEntry(
            key: isFirst ? tourTabSideBySideFirstItemTargetKey : null,
            label: otherTab.title,
            onTap: () {
              context.read<TabsBloc>().add(
                    EnableSideBySideMode(
                      rightTab: tab,
                      leftTab: otherTab,
                    ),
                  );
            },
          );
        }).toList();
        entries.add(AppContextMenuEntry(
          label: 'הצג לצד',
          children: otherTabs,
        ));
      } else {
        entries.add(AppContextMenuEntry(
          label: 'הצג לצד',
          enabled: false,
        ));
      }
    }

    // אפשרויות CombinedTab
    if (tab is CombinedTab) {
      entries.addAll([
        AppContextMenuEntry(
          label: 'החלף צדדים',
          onTap: () => context.read<TabsBloc>().add(const SwapSideBySideTabs()),
        ),
        AppContextMenuEntry(
          label: 'חזרה לתצוגה רגילה',
          onTap: () => context
              .read<TabsBloc>()
              .add(DisableSideBySideMode(state.tabs.indexOf(tab))),
        ),
      ]);
    }

    entries.addAll([
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'כרטיסיות פתוחות',
        children: _getOpenTabsMenuEntries(state.tabs),
      ),
      _buildMoveToWorkspaceMenuEntry(context, tab),
    ]);

    return entries;
  }

  List<AppContextMenuEntry> _getOpenTabsMenuEntries(List<OpenedTab> tabs) {
    final sortedTabs = [...tabs]..sort((a, b) => a.title.compareTo(b.title));

    return sortedTabs.map((tab) {
      return AppContextMenuEntry(
        label: tab.title,
        onTap: () {
          final index = tabs.indexOf(tab);
          context.read<TabsBloc>().add(SetCurrentTab(index));
        },
        trailing: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            tooltip: 'סגור',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(FluentIcons.dismiss_24_regular, size: 14),
            onPressed: () {
              Navigator.of(context).maybePop();
              closeTab(tab, context);
            },
            splashRadius: 16,
          ),
        ),
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
