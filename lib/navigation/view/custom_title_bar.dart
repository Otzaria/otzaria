import 'dart:io';
import 'dart:math' as math;
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/navigation/view/tab_context_menu.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/update/my_update_widget.dart';

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

/// סמן ל-hit-test על רכיבי שורת הטאבים (טאבים וחיצי גלילה), לזיהוי לחיצה כפולה
/// עליהם כדי לדלג על maximize/restore (ראה [_CustomTitleBarState._hitTestTab]).
const String _kTabHitMarker = 'custom-title-bar-tab';

/// סמן ל-hit-test על כפתור הסגירה של טאב, כדי שלחיצה עליו לא תבחר את הטאב
/// ב-onPointerDown (ראה [_CustomTitleBarState._hitTestCloseButton]).
const String _kTabCloseButtonHitMarker = 'custom-title-bar-tab-close';

const double _kAppBarControlsWidth = 105.0;
const double _kWindowCaptionButtonsWidth = 138.0;
const double _kWindowCaptionButtonWidth = 46.0;

/// רוחב מרבי לטאב בודד: טאב לא נמתח מעבר לזה גם כשיש מעט טאבים ומלא מקום.
const double _kTabMaxWidth = 140.0;

/// מתחת לרוחב הזה כפתור ה-X מוסתר ומופיע רק ב-hover/בטאב הנבחר (כמו כרום).
const double _kTabCloseHideBelowWidth = 80.0;

/// רוחב כפתור ה-X בכרטיסיה. בכרטיסיה צרה הוא מצטמצם לרוחב שנותר בה.
const double _kTabCloseExtent = 25.0;

/// רוחב אייקון ה-X עצמו — מתחת לזה הוא נחתך, ולכן אינו מוצג גם בריחוף.
const double _kTabCloseMinExtent = 10.0;

/// מידות האייקונים שלצד הכותרת — הנעץ ואייקון סוג הכרטיסיה, כולל הרווח שאחריהם.
const double _kTabPinExtent = 18.0;
const double _kTabLeadingIconExtent = 18.0;

/// רוחב מזערי לטאב הנבחר: מבטיח שכפתור ה-X שלו תמיד נכנס (כמו כרום).
/// כשהחלוקה השווה יורדת מתחת לזה, שאר הטאבים מתחלקים ביתרה.
const double _kTabSelectedMinWidth = 60.0;

/// מתחת לרוחב הזה הריפודים בולעים את כל רוחב הכרטיסיה ולא נותר בה פיקסל
/// לכותרת, לאייקונים או ל-X — ולכן התוכן שלה אינו נבנה כלל.
const double _kTabContentMinWidth = 12.0;

/// גובה גוף הכרטיסיה, בלי המפריד שלצדה.
const double _kTabBodyHeight = 32.0;

/// רוחבי הטאבים בשורה: הנבחר עשוי להיות רחב מהשאר (ראה [_kTabSelectedMinWidth]).
typedef _TabWidths = ({double selected, double unselected});

/// סגנון משותף לכפתורי האייקון בשורת הכותרת
final ButtonStyle _kIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(32, 32),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: RoundedRectangleBorder(
    borderRadius: AppTokens.borderRadiusAll,
  ),
);

class _CustomTitleBarState extends State<CustomTitleBar> {
  // האם העכבר נמצא כרגע מעל שורת הטאבים. בעת סגירת טאב כשהעכבר בפנים מקפיאים
  // את רוחב הטאבים (ראה _pinnedTabWidths) כדי שכפתור ה-X של הטאב הבא יישאר תחת
  // הסמן וסגירות רצופות יפעלו.
  bool _pointerInsideTabStrip = false;

  // כשאינו null, כל הטאבים מצוירים ברוחבים הקפואים האלה במקום ברוחב המחושב.
  // מוגדר בסגירה (כשהעכבר בפנים) ומשוחרר ביציאת העכבר מהשורה (כמו כרום).
  _TabWidths? _pinnedTabWidths;

  // הרוחבים המחושבים האחרונים לטאב, לשימוש כערך הקפיאה בסגירה.
  _TabWidths? _lastComputedTabWidths;

  // הבחירה נדחית לשחרור כדי שתחילת גרירה לא תחליף את התצוגה.
  OpenedTab? _pendingTabSelection;

  // הטאב שהעכבר מעליו. שדה ולא משתנה מקומי ב-_buildTab: rebuild של ההורה היה
  // מאפס אותו, וה-X שמוצג רק בריחוף היה נמחק מתחת לסמן לפני שהלחיצה נורית.
  OpenedTab? _hoveredTab;

  /// המקש שמפעיל בחירה מרובה: Ctrl בכל הפלטפורמות, Command במק.
  bool get _isMultiSelectModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  // רוחב אזור הטאבים שנמדד בפריים הקודם (ע"י LayoutBuilder נפרד). הרשימה
  // נבנית עם הערך הזה ולא תחת ה-LayoutBuilder — אחרת Tooltip/OverlayPortal
  // שבטאב מופעל בזמן layout וזורק "_RenderLayoutBuilder was mutated".
  double? _tabsAreaWidth;

  /// בודק אם הנקודה הגלובלית פוגעת ברכיב של שורת הטאבים — טאב או חץ גלילה
  /// (מסומן ב-[_kTabHitMarker]). משמש כדי לדלג על maximize בלחיצה כפולה עליהם,
  /// בלי להסתמך על gesture arena.
  bool _hitTestTab(BuildContext context, Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData == _kTabHitMarker) {
        return true;
      }
    }
    return false;
  }

  /// בודק אם הנקודה הגלובלית פוגעת בכפתור הסגירה של טאב (מסומן ב-
  /// [_kTabCloseButtonHitMarker]). משמש כדי שלחיצה על ה-X לא תבחר את הטאב
  /// ב-onPointerDown — בחירה שם גורמת ל-rebuild שמשמיד את ה-IconButton
  /// לפני שה-onPressed שלו יורה, כך שהטאב מתחלף במקום להיסגר.
  bool _hitTestCloseButton(BuildContext context, Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      View.of(context).viewId,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData &&
          target.metaData == _kTabCloseButtonHitMarker) {
        return true;
      }
    }
    return false;
  }

  /// maximize/restore בלחיצה כפולה על האזור הריק שבשורת הטאבים (כמו DragToMoveArea).
  Future<void> _onTabsAreaDoubleTap() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  bool _isReadingScreen(NavigationState navState) =>
      navState.currentScreen == Screen.reading ||
      navState.currentScreen == Screen.search;

  bool _useStackedTabs(BuildContext context, NavigationState navState) {
    if (!_isReadingScreen(navState)) return false;
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  /// במצב "בצד" הכרטיסיות מוצגות בעמודה אנכית שבמסך הראשי, ולכן הרצועה
  /// שבכותרת אינה נבנית כלל. במסך לאורך נשמרת ההתנהגות הקיימת (שורה שנייה).
  bool _useSideTabs(
    BuildContext context,
    NavigationState navState,
    SettingsState settingsState,
  ) {
    if (!_isReadingScreen(navState) || !settingsState.readingTabsOnSide) {
      return false;
    }
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, navState) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final stackedTabs = _useStackedTabs(context, navState);
            // במסך עיון ללא טאבים פתוחים אין תוכן קריאה אמיתי, ולכן המסגרת
            // העליונה נצבעת כשאר מסכי הלוח (רקע לוח + גבול תחתון) במקום ברקע
            // מסך העיון. בחיפוש תמיד קיים טאב, לכן נשאר בסגנון הקריאה.
            final useReaderStyle =
                navState.currentScreen == Screen.search ||
                (navState.currentScreen == Screen.reading &&
                    context.select((TabsBloc bloc) => bloc.state.hasOpenTabs));
            final topBar = SizedBox(
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    clipBehavior: Clip.none,
                    decoration: BoxDecoration(
                      color: useReaderStyle
                          ? AppSurfaces.readerBackground(context)
                          : AppSurfaces.solidPanelBackground(context),
                      border: useReaderStyle
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
                          child: Center(
                            child: _buildActionButtons(context),
                          ),
                        ),

                        // תוכן הכותרת (טאבים או כותרת רגילה)
                        Expanded(
                          child: _buildContent(
                            context,
                            navState,
                            settingsState,
                          ),
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
                                const ManagedUpdateTitleBarIndicator(),
                                _buildFullscreenCaptionButton(
                                  context,
                                  settingsState,
                                ),
                                if (settingsState.isFullscreen)
                                  _CaptionActionButton(
                                    brightness: Theme.of(context).brightness,
                                    tooltip: 'מזער',
                                    icon: FluentIcons.subtract_24_regular,
                                    onPressed: () async {
                                      await FullscreenHelper.toggleFullscreen(
                                        context,
                                        false,
                                      );
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

            if (!stackedTabs) return topBar;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                topBar,
                _buildNarrowTabsRow(context),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final historyShortcut =
        Settings.getValue<String>('key-shortcut-open-history') ?? 'ctrl+h';
    final bookmarksShortcut =
        Settings.getValue<String>('key-shortcut-open-bookmarks') ??
        'ctrl+shift+b';
    final workspaceShortcut =
        Settings.getValue<String>('key-shortcut-switch-workspace') ?? 'ctrl+k';

    return SizedBox(
      width: _kAppBarControlsWidth,
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
                  tooltip:
                      'הצג היסטוריה (${ShortcutHelper.formatShortcutForDisplay(historyShortcut)})',
                  onPressed: () => _showHistoryDialog(context),
                  style: _kIconButtonStyle,
                ),
                IconButton(
                  key: tourTitleBarBookmarkButtonTargetKey,
                  icon: const Icon(FluentIcons.bookmark_24_regular, size: 18),
                  tooltip:
                      'הצג סימניות (${ShortcutHelper.formatShortcutForDisplay(bookmarksShortcut)})',
                  onPressed: () => _showBookmarksDialog(context),
                  style: _kIconButtonStyle,
                ),
                IconButton(
                  icon: const Icon(FluentIcons.add_square_24_regular, size: 18),
                  tooltip:
                      'החלף שולחן עבודה (${ShortcutHelper.formatShortcutForDisplay(workspaceShortcut)})',
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

  Widget _buildContent(
    BuildContext context,
    NavigationState navState,
    SettingsState settingsState,
  ) {
    if (_isReadingScreen(navState)) {
      final stacked = _useStackedTabs(context, navState);
      if (stacked || _useSideTabs(context, navState, settingsState)) {
        return Row(
          children: [
            const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
            // במצב "בצד" כפתור חיפוש הכרטיסיות יושב בראש העמודה עצמה.
            if (stacked) TabSearchButton(style: _kIconButtonStyle),
            _buildReadingSettingsButton(context),
          ],
        );
      }
      return _buildReadingTabs(context);
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
        final category = libraryState.currentCategory;
        // בתקייה הראשית (הספרייה עצמה) מוצג רק "ספריה" ללא שם קטגוריה;
        // בתקיות פנימיות מתווסף שם הקטגוריה ככותרת משנה.
        final isRoot =
            category == null || identical(category, libraryState.library);
        return _buildPanelTitle(
          context,
          // הקשר 'titleBar' — כאן זה שם המסך ("Library" כמו בסרגל), ולא
          // לשונית ההגדרות שמתורגמת "Seforim Library".
          context.settingsText('ספריה', context: 'titleBar'),
          subtitle: isRoot ? null : category.title,
        );
      },
    );
  }

  Widget _buildStandardTitle(BuildContext context, NavigationState navState) {
    final title = switch (navState.currentScreen) {
      Screen.settings => 'הגדרות',
      Screen.find => 'איתור',
      Screen.search => 'חיפוש',
      _ => 'אוצריא',
    };
    return _buildPanelTitle(context, context.settingsText(title));
  }

  Widget _buildPanelTitle(
    BuildContext context,
    String title, {
    String? subtitle,
  }) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final textStyle = TextStyle(
      color: color,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );
    return Row(
      children: [
        Expanded(
          child: DragToMoveArea(
            child: Center(
              child: Text(
                subtitle != null ? '$title: $subtitle' : title,
                style: textStyle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadingTabs(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        if (!state.hasOpenTabs) {
          return DragToMoveArea(
            child: Center(
              child: Text(
                context.settingsText('עיון'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }

        return Row(
          children: [
            Expanded(child: _buildScrollableTabsArea(state)),
            TabSearchButton(style: _kIconButtonStyle),
            const SizedBox(width: 8),
            _buildReadingSettingsButton(context),
          ],
        );
      },
    );
  }

  /// מחשב את רוחב הטאבים כך שכולם יתחלקו בשווה במקום הפנוי, עד תקרה של
  /// [_kTabMaxWidth]. אין רצפה לטאבים שאינם נבחרים: כשיש הרבה טאבים הם ממשיכים
  /// להצטמצם כך שכולם תמיד נכנסים — ללא גלילה וללא חיתוך. הטאב הנבחר לא יורד
  /// מ-[_kTabSelectedMinWidth] כדי שכפתור ה-X שלו יישאר תמיד (כמו כרום).
  _TabWidths _computeTabWidths(double available, int count) {
    if (count <= 0) return (selected: _kTabMaxWidth, unselected: _kTabMaxWidth);
    final ideal = available / count;
    final uniform = ideal < _kTabMaxWidth ? ideal : _kTabMaxWidth;
    if (count == 1 || uniform >= _kTabSelectedMinWidth) {
      return (selected: uniform, unselected: uniform);
    }
    // צפוף: הנבחר שומר רוחב מזערי (אך לא יותר מחצי השורה), השאר מתחלקים ביתרה.
    final selected = math.min(_kTabSelectedMinWidth, available / 2);
    final unselected = math.max(0.0, (available - selected) / (count - 1));
    return (selected: selected, unselected: unselected);
  }

  Widget _buildScrollableTabsArea(TabsState state) {
    // LayoutBuilder נפרד מודד רק את הרוחב (ילדו SizedBox ריק) ושומר אותו ב-state;
    // הרשימה — שמכילה Tooltip/OverlayPortal ומפתחות גלובליים — נבנית כאח שלו,
    // לא תחתיו. אחרת רינדור-מחדש של טאב בזמן layout מפעיל את ה-OverlayPortal
    // וזורק "_RenderLayoutBuilder was mutated".
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            if (_tabsAreaWidth == null || (_tabsAreaWidth! - w).abs() > 0.5) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _tabsAreaWidth = w);
              });
            }
            return const SizedBox.shrink();
          },
        ),
        _buildTabsContent(state),
      ],
    );
  }

  Widget _buildTabsContent(TabsState state) {
    // בפריים הראשון עוד אין מדידה; אומדן לפי רוחב המסך, מתוקן בפריים הבא.
    final available = _tabsAreaWidth ?? MediaQuery.sizeOf(context).width;
    _lastComputedTabWidths = _computeTabWidths(available, state.tabs.length);
    // בזמן סגירה רצופה (העכבר מעל השורה) הרוחב קפוא כדי שה-X של הטאב הבא יישאר
    // תחת הסמן; אחרת מתחלקים בשווה במקום הפנוי.
    final tabWidths = _pinnedTabWidths ?? _lastComputedTabWidths!;

    // בדסקטופ גרירת-עכבר על טאב מסדרת אותו מיד (כמו כרום); בנייד נדרשת לחיצה
    // ארוכה כדי שהחלקה/גלילה במגע לא תזיז טאב בטעות.
    final platform = Theme.of(context).platform;
    final isDesktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    // אותה גרירה מסדרת כרטיסיות ומוציאה אותן לחלונית קריאה.
    final tabStrip = ReadingTabStrip(
      tabs: state.tabs,
      widths: [
        for (var i = 0; i < state.tabs.length; i++)
          i == state.currentTabIndex
              ? tabWidths.selected
              : tabWidths.unselected,
      ],
      requireLongPressToDrag: !isDesktop,
      onReorder: (tab, newIndex) =>
          context.read<TabsBloc>().add(MoveTab(tab, newIndex)),
      // חלונית של טאב מפוצל שנגררת לרצועה חוזרת לכרטיסייה עצמאית.
      acceptsExternal: (tab) => context.read<TabsBloc>().state.tabs.any(
        (t) => t is CombinedTab && t.sibling(tab) != null,
      ),
      onExternalDrop: (tab, insertIndex) => context.read<TabsBloc>().add(
        DetachPane(tab, insertIndex: insertIndex),
      ),
      // תחילת גרירה אינה בוחרת כרטיסיה — בחירה מיידית הייתה מפצלת את הנגררת
      // עם עצמה בשחרור מעל אזור הקריאה; בסידור מחדש MoveTab בוחר את הנגררת.
      onDragStarted: () => _pendingTabSelection = null,
      onSpringOpen: (tab) {
        // ה-state שנתפס ב-build עלול להיות מיושן באמצע גרירה, ורק קריאה
        // ישירה מה-bloc משקפת מה מוצג עכשיו.
        final bloc = context.read<TabsBloc>();
        final index = bloc.state.tabs.indexOf(tab);
        if (index != -1 && index != bloc.state.currentTabIndex) {
          bloc.add(SetCurrentTab(index));
        }
      },
      // סימון שטח הטאב ל-hit-test, כדי שה-double-tap-to-maximize שבמסגרת
      // ידלג עליו (ראה _EmptyAreaDoubleTapRecognizer).
      tabBuilder: (tab, index, tabWidth) => MetaData(
        metaData: _kTabHitMarker,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: tabWidth,
          child: _buildTab(context, tab, index, state, tabWidth),
        ),
      ),
    );

    // מחליף את DragToMoveArea: גרירת חלון (onPanStart) ו-maximize/restore
    // (לחיצה כפולה) פעילים רק על האזור הריק שבשורת הטאבים. מזהה הלחיצה הכפולה
    // דוחה מצביעים שמעל טאב כבר ב-isPointerAllowed — אחרת הוא מחזיק את
    // ה-gesture arena ומעכב את כפתור ה-X של הטאב ב~300ms.
    // ה-MouseRegion משחרר את קפיאת הרוחב כשהעכבר עוזב את השורה.
    return MouseRegion(
      onEnter: (_) => _pointerInsideTabStrip = true,
      onExit: (_) {
        _pointerInsideTabStrip = false;
        if (_pinnedTabWidths != null) {
          setState(() => _pinnedTabWidths = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // גרירה על טאב מסדרת אותו (reorder); רק גרירה על האזור הריק גוררת חלון.
        onPanStart: (details) {
          if (_hitTestTab(context, details.globalPosition)) return;
          windowManager.startDragging();
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            _EmptyAreaDoubleTapRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  _EmptyAreaDoubleTapRecognizer
                >(
                  () => _EmptyAreaDoubleTapRecognizer(debugOwner: this),
                  (recognizer) {
                    recognizer.isPointerOnTab = (position) =>
                        _hitTestTab(context, position);
                    recognizer.onDoubleTap = _onTabsAreaDoubleTap;
                  },
                ),
          },
          child: KeyedSubtree(
            key: tourReadingTabsTargetKey,
            child: tabStrip,
          ),
        ),
      ),
    );
  }

  Widget _buildReadingSettingsButton(BuildContext context) {
    return DragToMoveArea(
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
          onPressed:
              widget.onReadingSettingsPressed ??
              () => showReadingSettingsDialog(context),
          style: _kIconButtonStyle,
        ),
      ),
    );
  }

  Widget _buildNarrowTabsRow(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      builder: (context, state) {
        if (!state.hasOpenTabs) return const SizedBox.shrink();
        return Container(
          color: AppSurfaces.readerBackground(context),
          height: 40,
          child: _buildScrollableTabsArea(state),
        );
      },
    );
  }

  // --- Helper Methods ---

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
    BuildContext context,
    SettingsState settingsState,
  ) {
    // הכפתור מוצג רק בהקשר שמתיר מסך מלא (עיון/כלים).
    if (!FullscreenHelper.isAllowedInContext(context)) {
      return const SizedBox.shrink();
    }
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

  /// מציג אייקון הצמדה רק כשהכרטיסיה מוצמדת
  Widget _buildPinIconInline(BuildContext context, OpenedTab tab) {
    if (!tab.isPinned) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => context.read<TabsBloc>().add(TogglePinTab(tab)),
      child: Padding(
        padding: const EdgeInsets.only(right: 4.0),
        child: Tooltip(
          message: 'בטל הצמדה',
          child: const Icon(FluentIcons.pin_24_filled, size: 14),
        ),
      ),
    );
  }

  void closeTab(OpenedTab tab, BuildContext context) {
    // סגירת טאב שנכלל בבחירה מרובה סוגרת את כל הקבוצה יחד.
    final selectedTabs = context.read<TabsBloc>().state.selectedTabs;
    if (selectedTabs.length > 1 && selectedTabs.contains(tab)) {
      closeSelectedTabs(context);
      return;
    }
    // קופאים את רוחב הטאבים כל עוד העכבר מעל השורה, כדי שכפתור ה-X של הטאב הבא
    // יישאר בדיוק תחת הסמן וסגירות רצופות יפעלו (כמו כרום). נועלים רק בסגירה
    // הראשונה (??=) — אחרת כל סגירה הייתה דורסת בערך הרחב יותר. השחרור ביציאת העכבר.
    if (_pointerInsideTabStrip && _lastComputedTabWidths != null) {
      _pinnedTabWidths ??= _lastComputedTabWidths;
    }
    closeTabWithHistory(context, tab);
  }

  /// סוגר חלונית אחת מלשונית מפוצלת; אחותה נשארת ככרטיסייה רגילה במקומה.
  void closePane(OpenedTab pane, BuildContext context) =>
      closePaneWithHistory(context, pane);

  /// החלונית שהחצי שלה בלשונית נמצא מתחת ל-[dx] (קואורדינטה מקומית, LTR).
  OpenedTab _paneAtDx(
    BuildContext context,
    CombinedTab tab,
    double dx,
    double tabWidth,
  ) {
    final inFirstHalf = Directionality.of(context) == TextDirection.rtl
        ? dx >= tabWidth / 2
        : dx < tabWidth / 2;
    return inFirstHalf ? tab.rightTab : tab.leftTab;
  }

  /// סוגר את כל הכרטיסיות שבבחירה המרובה בפעולה אחת.
  void closeSelectedTabs(BuildContext context) {
    if (_pointerInsideTabStrip && _lastComputedTabWidths != null) {
      _pinnedTabWidths ??= _lastComputedTabWidths;
    }
    closeSelectedTabsWithHistory(context);
  }

  /// רקע הכרטיסיה: סימון בחירה מרובה, ואחריו הכרטיסיה הפעילה.
  CustomPainter? _tabBackgroundPainter(
    BuildContext context,
    OpenedTab tab,
    TabsState state, {
    required bool isSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    if (state.selectedTabs.contains(tab)) {
      return _TabBackgroundPainter(colorScheme.secondaryContainer);
    }
    return isSelected
        ? _TabBackgroundPainter(AppSurfaces.topBarBackground(context))
        : null;
  }

  /// מפריד מוצג רק כשאין הבלטה משני צדיו: הכרטיסיה הפעילה והכרטיסיה שבריחוף
  /// נצבעות, ופס צמוד להן היה חוצה את ההבלטה.
  ///
  /// המפריד של הכרטיסיה הראשונה מפריד אותה מלחצני הפעולה שלפניה.
  bool _showLeadingDivider(TabsState state, int index) {
    bool emphasized(int i) =>
        i == state.currentTabIndex || identical(_hoveredTab, state.tabs[i]);
    if (index == 0) return !emphasized(0);
    return !emphasized(index) && !emphasized(index - 1);
  }

  /// הצללת הריחוף, שמצוירת מעל הרקע.
  CustomPainter? _tabHoverPainter(
    BuildContext context, {
    required bool isHovered,
    required bool isSelected,
  }) {
    if (!isHovered || isSelected) return null;
    return _TabBackgroundPainter(
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
    );
  }

  /// כרטיסיה שהצטמצמה מתחת ל-[_kTabContentMinWidth]. כל שכבות האינטראקציה
  /// נשמרות; רק התוכן — שאין לו כאן ולו פיקסל אחד — אינו נבנה.
  Widget _buildNarrowTab(
    BuildContext context,
    OpenedTab tab,
    int index,
    TabsState state,
    double tabWidth,
  ) {
    final isSelected = index == state.currentTabIndex;
    final showLeadingDivider = _showLeadingDivider(state, index);
    final isTabHovered = identical(_hoveredTab, tab);

    return _wrapWithTabPointer(
      context,
      tab,
      index,
      state,
      tabWidth: tabWidth,
      child: AppContextMenuRegion(
        menuBuilder: (menuCtx, _) =>
            _buildTabContextMenuEntries(menuCtx, tab, state),
        child: MouseRegion(
          onEnter: (_) => _setHoveredTab(tab),
          onExit: (_) => _clearHoveredTab(tab),
          // אין כאן כותרת כלל, ולכן ה-tooltip הוא הדרך היחידה לזהות את
          // הכרטיסיה — ומוצג בכל שטחה.
          child: Tooltip(
            message: tab.title,
            child: Row(
              children: [
                Container(
                  // ברוחב שברירי המפריד עצמו רחב מהכרטיסיה כולה, וקו קבוע
                  // של 1 היה גולש ממנה.
                  width: math.min(1.0, tabWidth),
                  height: 24,
                  margin: const EdgeInsets.only(top: 6, bottom: 6),
                  color: showLeadingDivider
                      ? Theme.of(context).colorScheme.outlineVariant
                      : null,
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxHeight: _kTabBodyHeight,
                    ),
                    padding: EdgeInsets.only(
                      left: 3,
                      right: index == 0 ? 0 : 3,
                    ),
                    // הגובה מפורש: ל-CustomPaint ללא ילד אין גודל טבעי, והוא
                    // היה מתכווץ לאפס — גם הציור וגם שטח הלחיצה.
                    child: CustomPaint(
                      size: const Size.fromHeight(_kTabBodyHeight),
                      painter: _tabBackgroundPainter(
                        context,
                        tab,
                        state,
                        isSelected: isSelected,
                      ),
                      foregroundPainter: _tabHoverPainter(
                        context,
                        isHovered: isTabHovered,
                        isSelected: isSelected,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// הכותרת שמתעדכנת תוך כדי קריאה (המיקום בספר, שאילתת החיפוש), או `null`
  /// לכרטיסיה שכותרתה סטטית.
  ValueListenable<String>? _liveTitleOf(OpenedTab tab) {
    if (tab is SearchingTab) return tab.titleNotifier;
    if (tab is PdfBookTab) return tab.currentTitle;
    if (tab is PdfCommentatorsTab) return tab.sourceTab.currentTitle;
    if (tab is TextBookTab) return tab.currentTitle;
    return null;
  }

  Widget _buildTab(
    BuildContext context,
    OpenedTab tab,
    int index,
    TabsState state,
    double tabWidth,
  ) {
    if (tabWidth < _kTabContentMinWidth) {
      return _buildNarrowTab(context, tab, index, state, tabWidth);
    }

    final isSelected = index == state.currentTabIndex;
    final closeTabShortcut =
        Settings.getValue<String>('key-shortcut-close-tab') ?? 'ctrl+w';

    final isTabHovered = identical(_hoveredTab, tab);

    Widget fadedTitle(String title) => buildFadedTabTitle(context, title);

    // X של חצי לשונית — סוגר רק את החלונית שלו, בסגנון ה-X של לשונית רגילה.
    Widget paneCloseButton(OpenedTab pane, double extent) {
      return Tooltip(
        preferBelow: false,
        message: 'סגור חלונית',
        child: MetaData(
          metaData: _kTabCloseButtonHitMarker,
          child: IconButton(
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            constraints: BoxConstraints.tightFor(
              width: extent,
              height: _kTabCloseExtent,
            ),
            onPressed: () => closePane(pane, context),
            icon: const Icon(FluentIcons.dismiss_24_regular, size: 10),
          ),
        ),
      );
    }

    Widget buildTabContent(
      String displayTitle, {
      required double paneCloseExtent,
      bool showPaneClose = false,
    }) {
      if (tab is CombinedTab) {
        // כל חלונית מפוצלת מציגה את תחילת שמה בחלק שווה מרוחב הטאב.
        // פסים מפרידים מוצגים רק כשיש להם מקום.
        final panes = leafPanes(tab);
        final showDividers = tabWidth >= 100 * (panes.length - 1);
        return Row(
          children: [
            for (var i = 0; i < panes.length; i++) ...[
              if (i > 0 && showDividers)
                Container(
                  width: 2,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: Theme.of(context).colorScheme.outline,
                ),
              Expanded(child: fadedTitle(panes[i].title)),
              if (showPaneClose) paneCloseButton(panes[i], paneCloseExtent),
            ],
          ],
        );
      }

      return fadedTitle(displayTitle);
    }

    Widget buildTabAppearance(String displayTitle, String tooltipMessage) {
      final showLeadingDivider = _showLeadingDivider(state, index);
      final colorScheme = Theme.of(context).colorScheme;

      // בטאב צר הריפודים האופקיים מתכווצים בהדרגה (8→3, 6→3) — אחרת ריפוד קבוע
      // של ~28px בולע את כל הרוחב והטאב (שאין לו רקע משלו) נעלם ויזואלית.
      final padScale = ((tabWidth - 40) / 40).clamp(0.0, 1.0);
      final outerPad = 3 + 3 * padScale;
      final innerPad = 3 + 5 * padScale;

      // הרוחב שנשאר לתוכן הכרטיסיה אחרי המפריד, ה-paddings ורווח הטאב הנבחר.
      // הכותרת תמיד ב-Expanded ומתכווצת לאפס בעת הצורך.
      final contentWidth =
          tabWidth -
          1 -
          outerPad -
          (index == 0 ? 0 : outerPad) -
          2 * innerPad -
          (isSelected ? 4 : 0);
      // בלשונית מפוצלת כל חצי מקבל X משלו במקום X יחיד ללשונית.
      final isCombined = tab is CombinedTab;
      final closeVisibleByState =
          tabWidth >= _kTabCloseHideBelowWidth || isSelected || isTabHovered;
      // ה-X מצטמצם לרוחב שנותר במקום להיעלם, כדי שבריחוף הוא יהיה שם תמיד.
      final closeExtent = math.min(_kTabCloseExtent, contentWidth);
      final paneCloseExtent = math.min(_kTabCloseExtent, contentWidth / 2);
      final showClose =
          !isCombined &&
          closeVisibleByState &&
          closeExtent >= _kTabCloseMinExtent;
      final showPaneClose =
          isCombined &&
          closeVisibleByState &&
          paneCloseExtent >= _kTabCloseMinExtent;
      final closeBudget = showClose
          ? closeExtent
          : (showPaneClose ? 2 * paneCloseExtent : 0);
      final showPin =
          tab.isPinned && (contentWidth - closeBudget) >= _kTabPinExtent;
      // אייקון ליד שם הטאב — רק כשהטאב רחב (אותו סף כמו מפריד ה-CombinedTab).
      final showPdfIcon = tab is PdfBookTab && tabWidth >= 100;
      final toolIcon = tab is ToolTab && tabWidth >= 100
          ? buildToolTabLeadingIcon(
              tab.toolId,
              color: colorScheme.onSurface,
              pluginState: context.read<PluginSystemBloc>().state,
            )
          : null;

      final titleStyle = TextStyle(
        color: colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 14,
      );
      // הרוחב שבו הכותרת מרונדרת בפועל — לפיו נקבע אם היא נחתכה, וה-tooltip
      // עוטף בזכותו את כל הכרטיסיה במקום את הכותרת בלבד.
      final titleWidth = math.max(
        0.0,
        contentWidth -
            closeBudget -
            (showPin ? _kTabPinExtent : 0) -
            (showPdfIcon || toolIcon != null ? _kTabLeadingIconExtent : 0),
      );

      final tabRow = Row(
        children: [
          // מקום המפריד שמור גם כשאינו נצבע: הסתרתו הייתה מזיזה את תוכן
          // הכרטיסיה בפיקסל בכל ריחוף.
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.only(top: 6, bottom: 6),
            color: showLeadingDivider ? colorScheme.outlineVariant : null,
          ),
          // הטאב ממלא את הרוחב הקבוע שמכתיב ה-SizedBox; הכותרת ב-Expanded כדי
          // שתתכווץ ותטושטש לקראת הסוף. ה-X/נעץ מוצגים רק אם נשאר להם מקום.
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: _kTabBodyHeight),
              padding: EdgeInsets.only(
                left: outerPad,
                right: index == 0 ? 0 : outerPad,
              ),
              child: CustomPaint(
                // טאב בבחירה מרובה נצבע ב-secondaryContainer כדי לסמן שהוא
                // חלק מהקבוצה שתיסגר יחד.
                painter: _tabBackgroundPainter(
                  context,
                  tab,
                  state,
                  isSelected: isSelected,
                ),
                foregroundPainter: _tabHoverPainter(
                  context,
                  isHovered: isTabHovered,
                  isSelected: isSelected,
                ),
                child: Tab(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: innerPad),
                    child: DefaultTextStyle(
                      style: titleStyle,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (isSelected) const SizedBox(width: 4),
                          if (showPin) _buildPinIconInline(context, tab),
                          if (showPdfIcon)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(
                                OtzariaIcons.book_pdf_24_regular,
                                size: 14,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          if (toolIcon != null)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: toolIcon,
                            ),
                          Expanded(
                            child: buildTabContent(
                              displayTitle,
                              paneCloseExtent: paneCloseExtent,
                              showPaneClose: showPaneClose,
                            ),
                          ),
                          if (showClose)
                            Tooltip(
                              preferBelow: false,
                              message: ShortcutHelper.formatShortcutForDisplay(
                                closeTabShortcut,
                              ),
                              child: MetaData(
                                metaData: _kTabCloseButtonHitMarker,
                                child: IconButton(
                                  // shrinkWrap + padding אפס: בלעדיהם שטח-המגע
                                  // ברירת-המחדל (48px) גולש בטאב צר.
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: EdgeInsets.zero,
                                  ),
                                  constraints: BoxConstraints.tightFor(
                                    width: closeExtent,
                                    height: _kTabCloseExtent,
                                  ),
                                  onPressed: () => closeTab(tab, context),
                                  icon: const Icon(
                                    FluentIcons.dismiss_24_regular,
                                    size: 10,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

      // ה-tooltip עוטף את הכרטיסיה כולה ולא את הכותרת בלבד, כדי שיופיע בריחוף
      // בכל שטחה — גם כשהכותרת מצטמצמת לאפס בכרטיסיה צרה.
      return TabTitleTooltip(
        message: tooltipMessage,
        title: displayTitle,
        titleWidth: titleWidth,
        titleStyle: titleStyle,
        alwaysShow: isCombined,
        child: tabRow,
      );
    }

    // בכרטיסיה עם כותרת חיה הזוג (כותרת מוצגת, הודעת tooltip) נגזר מהערך העדכני;
    // בכל השאר שניהם שם הכרטיסיה.
    final liveTitle = _liveTitleOf(tab);
    Widget buildLiveTabAppearance() {
      if (liveTitle == null) {
        return buildTabAppearance(tab.title, tab.title);
      }
      return ValueListenableBuilder<String>(
        valueListenable: liveTitle,
        builder: (context, value, child) {
          // בכרטיסיית חיפוש הערך הוא הכותרת עצמה; בשאר הוא המיקום שמתווסף לה.
          if (tab is SearchingTab) return buildTabAppearance(value, value);
          return buildTabAppearance(
            tab.title,
            value.isEmpty ? tab.title : '${tab.title}, $value',
          );
        },
      );
    }

    return _wrapWithTabPointer(
      context,
      tab,
      index,
      state,
      tabWidth: tabWidth,
      child: AppContextMenuRegion(
        menuBuilder: (menuCtx, _) =>
            _buildTabContextMenuEntries(menuCtx, tab, state),
        // הריחוף מרענן את השורה כולה ולא רק את הכרטיסיה: המפריד שנעלם בצדה
        // שייך לכרטיסיה השכנה.
        child: MouseRegion(
          onEnter: (_) => _setHoveredTab(tab),
          onExit: (_) => _clearHoveredTab(tab),
          child: buildLiveTabAppearance(),
        ),
      ),
    );
  }

  void _setHoveredTab(OpenedTab tab) {
    if (identical(_hoveredTab, tab)) return;
    setState(() => _hoveredTab = tab);
  }

  void _clearHoveredTab(OpenedTab tab) {
    if (!identical(_hoveredTab, tab)) return;
    setState(() => _hoveredTab = null);
  }

  /// עוטף כרטיסיה בטיפול הלחיצות שלה.
  ///
  /// בחירת הטאב על pointer-down: לחצן אמצעי סוגר (בלשונית מפוצלת — רק את
  /// החלונית שהחצי שלה נלחץ), לחצן ראשי (או תחילת גרירה)
  /// בוחר. לחצן ימני אינו בוחר — אחרת הבחירה גוררת rebuild שהורס את
  /// ה-AppContextMenuRegion לפני שתפריט ההקשר נפתח. משתמשים ב-Listener פסיבי
  /// כי הגרירה המיידית (ReorderableDragStartListener) זוכה ב-arena וחוסמת onTap.
  Widget _wrapWithTabPointer(
    BuildContext context,
    OpenedTab tab,
    int index,
    TabsState state, {
    required double tabWidth,
    required Widget child,
  }) {
    return Listener(
      onPointerUp: (_) {
        final pending = _pendingTabSelection;
        _pendingTabSelection = null;
        if (pending == null) return;
        // ה-state שנתפס ב-build עלול להיות מיושן עד השחרור.
        final bloc = context.read<TabsBloc>();
        final target = bloc.state.tabs.indexOf(pending);
        if (target != -1 && target != bloc.state.currentTabIndex) {
          bloc.add(SetCurrentTab(target));
        }
      },
      onPointerCancel: (_) => _pendingTabSelection = null,
      onPointerDown: (PointerDownEvent event) {
        // מונע מבחירה קודמת להשפיע על שחרור הלחיצה הנוכחי.
        _pendingTabSelection = null;
        if (event.buttons == 4) {
          // בלשונית מפוצלת נסגרת רק החלונית שהחצי שלה נלחץ.
          if (tab is CombinedTab) {
            closePane(
              _paneAtDx(context, tab, event.localPosition.dx, tabWidth),
              context,
            );
          } else {
            closeTab(tab, context);
          }
          return;
        }
        if (event.buttons != 1 ||
            _hitTestCloseButton(context, event.position)) {
          return;
        }
        // Ctrl/Cmd/Shift+לחיצה בונים בחירה מרובה לסגירה קבוצתית (כמו בדפדפן)
        // בלי להחליף את הטאב הפעיל.
        if (_isMultiSelectModifierPressed) {
          context.read<TabsBloc>().add(ToggleTabSelection(tab));
          return;
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          context.read<TabsBloc>().add(SelectTabRange(tab));
          return;
        }
        if (state.selectedTabs.isNotEmpty) {
          context.read<TabsBloc>().add(const ClearTabSelection());
        }
        if (index != state.currentTabIndex) {
          _pendingTabSelection = tab;
        }
      },
      child: AutoScrollBarrier(child: child),
    );
  }

  List<AppContextMenuEntry> _buildTabContextMenuEntries(
    BuildContext menuCtx,
    OpenedTab tab,
    TabsState state,
  ) {
    return buildTabContextMenuEntries(
      context,
      tab,
      state,
      onCloseTab: (target) => closeTab(target, context),
      onCloseSelectedTabs: () => closeSelectedTabs(context),
    );
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
    const topRadius = 8.0;
    const bottomRadius = 15.0;
    const bottomOffset = 5.0;

    path.moveTo(-bottomRadius, size.height + bottomOffset);

    path.arcToPoint(
      Offset(0, size.height + bottomOffset - bottomRadius),
      radius: const Radius.circular(bottomRadius),
      clockwise: false,
    );

    path.lineTo(0, topRadius);

    path.arcToPoint(
      const Offset(topRadius, 0),
      radius: const Radius.circular(topRadius),
    );

    path.lineTo(size.width - topRadius, 0);

    path.arcToPoint(
      Offset(size.width, topRadius),
      radius: const Radius.circular(topRadius),
    );

    path.lineTo(size.width, size.height + bottomOffset - bottomRadius);

    path.arcToPoint(
      Offset(size.width + bottomRadius, size.height + bottomOffset),
      radius: const Radius.circular(bottomRadius),
      clockwise: false,
    );

    path.lineTo(-bottomRadius, size.height + bottomOffset);

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TabBackgroundPainter oldDelegate) =>
      oldDelegate.color != color;
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
    Color iconColor = isDark
        ? Colors.white
        : Colors.black.withValues(alpha: 0.8956);

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

/// מזהה לחיצה כפולה לאזור הריק של שורת הטאבים בלבד. הדחייה חייבת להיות
/// ב-isPointerAllowed: מזהה שנכנס ל-arena מחזיק אותה עד timeout ומעכב את
/// הלחיצה על כפתור ה-X של הטאב.
class _EmptyAreaDoubleTapRecognizer extends DoubleTapGestureRecognizer {
  _EmptyAreaDoubleTapRecognizer({super.debugOwner});

  bool Function(Offset globalPosition)? isPointerOnTab;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (isPointerOnTab?.call(event.position) ?? false) return false;
    return super.isPointerAllowed(event);
  }
}
