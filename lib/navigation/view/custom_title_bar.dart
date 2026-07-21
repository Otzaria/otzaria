import 'dart:io';
import 'dart:math' as math;
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
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
import 'package:otzaria/core/messages/library_messages.dart';
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

/// רוחב מזערי לטאב הנבחר: מבטיח שכפתור ה-X שלו תמיד נכנס (כמו כרום).
/// כשהחלוקה השווה יורדת מתחת לזה, שאר הטאבים מתחלקים ביתרה.
const double _kTabSelectedMinWidth = 60.0;

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

  bool _useStackedTabs(BuildContext context, NavigationState navState) {
    final isReading =
        navState.currentScreen == Screen.reading ||
        navState.currentScreen == Screen.search;
    if (!isReading) return false;
    return MediaQuery.of(context).orientation == Orientation.portrait;
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
                          child: Stack(
                            children: [
                              Center(
                                child: _buildActionButtons(context),
                              ),
                              if (useReaderStyle)
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
                          child: _buildContent(context, navState),
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

  Widget _buildContent(BuildContext context, NavigationState navState) {
    if (navState.currentScreen == Screen.reading ||
        navState.currentScreen == Screen.search) {
      if (_useStackedTabs(context, navState)) {
        return Row(
          children: [
            const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
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
          'ספריה',
          subtitle: isRoot ? null : category.title,
        );
      },
    );
  }

  Widget _buildStandardTitle(BuildContext context, NavigationState navState) {
    final title = switch (navState.currentScreen) {
      Screen.settings => 'הגדרות',
      Screen.more => 'כלים',
      Screen.find => 'איתור',
      Screen.search => 'חיפוש',
      _ => 'אוצריא',
    };
    return _buildPanelTitle(context, title);
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
                'עיון',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }

        return Row(
          children: [
            Expanded(child: _buildScrollableTabsArea(state)),
            const SizedBox(width: 36),
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

    // ReorderableListView מטפל בגרירה-לסידור. כל טאב ברוחב קבוע מחושב; אין גלילה
    // (physics=Never) — גרירה על האזור הריק נופלת לגרירת החלון שב-GestureDetector.
    final reorderList = ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: state.tabs.length,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.85, child: child),
      ),
      onReorderItem: (oldIndex, newIndex) {
        // onReorderItem כבר מתאים את newIndex להסרת הפריט (remove-then-insert),
        // בדיוק ה-convention ש-_onMoveTab מצפה לו — אין צורך בתיקון ידני.
        if (oldIndex == newIndex) return;
        final tab = state.tabs[oldIndex];
        context.read<TabsBloc>().add(MoveTab(tab, newIndex));
      },
      itemBuilder: (context, index) {
        final tab = state.tabs[index];
        final tabWidth = index == state.currentTabIndex
            ? tabWidths.selected
            : tabWidths.unselected;
        // סימון שטח הטאב ל-hit-test, כדי שה-double-tap-to-maximize שבמסגרת
        // ידלג עליו (ראה _EmptyAreaDoubleTapRecognizer).
        final tabChild = MetaData(
          metaData: _kTabHitMarker,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: tabWidth,
            child: _buildTab(context, tab, state, tabWidth),
          ),
        );
        return isDesktop
            ? ReorderableDragStartListener(
                key: ObjectKey(tab),
                index: index,
                child: tabChild,
              )
            : ReorderableDelayedDragStartListener(
                key: ObjectKey(tab),
                index: index,
                child: tabChild,
              );
      },
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
            child: reorderList,
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
    // קופאים את רוחב הטאבים כל עוד העכבר מעל השורה, כדי שכפתור ה-X של הטאב הבא
    // יישאר בדיוק תחת הסמן וסגירות רצופות יפעלו (כמו כרום). נועלים רק בסגירה
    // הראשונה (??=) — אחרת כל סגירה הייתה דורסת בערך הרחב יותר. השחרור ביציאת העכבר.
    if (_pointerInsideTabStrip && _lastComputedTabWidths != null) {
      _pinnedTabWidths ??= _lastComputedTabWidths;
    }
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

  Widget _buildTab(
    BuildContext context,
    OpenedTab tab,
    TabsState state,
    double tabWidth,
  ) {
    final index = state.tabs.indexOf(tab);
    final isSelected = index == state.currentTabIndex;
    final closeTabShortcut =
        Settings.getValue<String>('key-shortcut-close-tab') ?? 'ctrl+w';

    bool isTabActive(int tabIndex) => tabIndex == state.currentTabIndex;
    bool isTabHovered = false;

    // כותרת בשורה אחת שמוצגת מההתחלה (RTL: מימין) ונדהית רק בקצה הסוף, כמו
    // כרום. TextOverflow.fade/clip של פלאטר מציג בעברית את *סוף* הכותרת
    // (הפוך מהרצוי), לכן מצמידים את הטקסט בעצמנו: OverflowBox ברוחב טבעי מיושר
    // ל-start (ימין ב-RTL) → ההתחלה גלויה, הסוף גולש; ClipRect חותך אותו;
    // ו-ShaderMask מדהה רק את קצה הסוף. בכותרת קצרה הקצה ריק והדהייה נעלמת.
    Widget fadedTitle(String title) {
      final isLtr = Directionality.of(context) == TextDirection.ltr;
      return ClipRect(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: isLtr ? Alignment.centerLeft : Alignment.centerRight,
            end: isLtr ? Alignment.centerRight : Alignment.centerLeft,
            stops: const [0.0, 0.82, 1.0],
            colors: const [Colors.white, Colors.white, Colors.transparent],
          ).createShader(rect),
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            minWidth: 0,
            maxWidth: double.infinity,
            child: Text(title, maxLines: 1, softWrap: false),
          ),
        ),
      );
    }

    Widget buildTabContent() {
      if (tab is CombinedTab) {
        // תצוגה מפוצלת: כל ספר בחצי מרוחב הטאב, מציג את ההתחלה שלו עם דהייה
        // בקצה. הימני (rightTab) ראשון ב-Row → מימין ב-RTL, כמו בתצוגה עצמה.
        // פס מפריד דק בין השניים, אך רק כשהטאב רחב מספיק — אחרת רוחבו הקבוע
        // היה גולש כשהטאב מצטמצם והחצאים מתאפסים.
        return Tooltip(
          message: tab.title,
          child: Row(
            children: [
              Expanded(child: fadedTitle(tab.rightTab.title)),
              if (tabWidth >= 100)
                Container(
                  width: 2,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: Theme.of(context).colorScheme.outline,
                ),
              Expanded(child: fadedTitle(tab.leftTab.title)),
            ],
          ),
        );
      }

      if (tab is SearchingTab) {
        return ValueListenableBuilder<String>(
          valueListenable: tab.titleNotifier,
          builder: (context, title, child) =>
              Tooltip(message: title, child: fadedTitle(title)),
        );
      }

      if (tab is PdfBookTab) {
        return ValueListenableBuilder<String>(
          valueListenable: tab.currentTitle,
          builder: (context, currentTitleValue, child) {
            final tooltipMessage = currentTitleValue.isNotEmpty
                ? '${tab.title}, $currentTitleValue'
                : tab.title;
            return Tooltip(
              message: tooltipMessage,
              child: fadedTitle(tab.title),
            );
          },
        );
      }

      if (tab is PdfCommentatorsTab) {
        return ValueListenableBuilder<String>(
          valueListenable: tab.sourceTab.currentTitle,
          builder: (context, currentTitleValue, child) {
            final tooltipMessage = currentTitleValue.isNotEmpty
                ? '${tab.title}, $currentTitleValue'
                : tab.title;
            return Tooltip(
              message: tooltipMessage,
              child: fadedTitle(tab.title),
            );
          },
        );
      }

      if (tab is CommentatorsTab || tab is ResolvingTab) {
        return Tooltip(message: tab.title, child: fadedTitle(tab.title));
      }

      final textTab = tab as TextBookTab;
      return ValueListenableBuilder<String>(
        valueListenable: textTab.currentTitle,
        builder: (context, currentTitleValue, child) {
          final tooltipMessage = currentTitleValue.isNotEmpty
              ? '${tab.title}, $currentTitleValue'
              : tab.title;
          return Tooltip(message: tooltipMessage, child: fadedTitle(tab.title));
        },
      );
    }

    Widget buildTabAppearance(StateSetter? setState) {
      // הטאב הראשון מקבל מפריד מול לחצני הפעולה שלפניו; שאר הטאבים מול הקודם.
      final showLeadingDivider = index == 0
          ? !isTabActive(index)
          : !isTabActive(index) && !isTabActive(index - 1);
      final colorScheme = Theme.of(context).colorScheme;

      // בטאב צר הריפודים האופקיים מתכווצים בהדרגה (8→3, 6→3) — אחרת ריפוד קבוע
      // של ~28px בולע את כל הרוחב והטאב (שאין לו רקע משלו) נעלם ויזואלית.
      final padScale = ((tabWidth - 40) / 40).clamp(0.0, 1.0);
      final outerPad = 3 + 3 * padScale;
      final innerPad = 3 + 5 * padScale;

      // תקציב הרוחב לאלמנטים שאינם הכותרת (X/נעץ), אחרי ה-paddings ורווח הטאב
      // הנבחר. מציגים X/נעץ רק אם נשאר מקום פיזי — אחרת הם היו גולשים בטאב צר.
      // הכותרת תמיד ב-Expanded ומתכווצת לאפס בעת הצורך.
      final extrasBudget =
          tabWidth - 2 * (outerPad + innerPad) - (isSelected ? 4 : 0);
      final showClose =
          extrasBudget >= 25 &&
          (tabWidth >= _kTabCloseHideBelowWidth || isSelected || isTabHovered);
      final showPin =
          tab.isPinned && (extrasBudget - (showClose ? 25 : 0)) >= 20;
      // אייקון PDF ליד שם הספר — רק כשהטאב רחב (אותו סף כמו מפריד ה-CombinedTab).
      final showPdfIcon = tab is PdfBookTab && tabWidth >= 100;

      return Row(
        children: [
          if (showLeadingDivider)
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              color: colorScheme.outlineVariant,
            ),
          // הטאב ממלא את הרוחב הקבוע שמכתיב ה-SizedBox; הכותרת ב-Expanded כדי
          // שתתכווץ ותטושטש לקראת הסוף. ה-X/נעץ מוצגים רק אם נשאר להם מקום.
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 32),
              padding: EdgeInsets.only(
                left: outerPad,
                right: index == 0 ? 0 : outerPad,
              ),
              child: CustomPaint(
                painter: isSelected
                    ? _TabBackgroundPainter(
                        AppSurfaces.topBarBackground(context),
                      )
                    : null,
                foregroundPainter: isTabHovered && !isSelected
                    ? _TabBackgroundPainter(
                        colorScheme.onSurface.withValues(alpha: 0.08),
                      )
                    : null,
                child: Tab(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: innerPad),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (isSelected) const SizedBox(width: 4),
                          if (showPin) _buildPinIconInline(context, tab),
                          if (showPdfIcon)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(
                                FluentIcons.document_pdf_16_regular,
                                size: 14,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          Expanded(child: buildTabContent()),
                          if (showClose)
                            Tooltip(
                              preferBelow: false,
                              message: closeTabShortcut.toUpperCase(),
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
                                  constraints: const BoxConstraints(
                                    minWidth: 25,
                                    minHeight: 25,
                                    maxWidth: 25,
                                    maxHeight: 25,
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
    }

    return Listener(
      // בחירת הטאב על pointer-down: לחצן אמצעי סוגר, לחצן ראשי (או תחילת
      // גרירה) בוחר. לחצן ימני אינו בוחר — אחרת הבחירה גוררת rebuild שהורס את
      // ה-AppContextMenuRegion לפני שתפריט ההקשר נפתח. משתמשים ב-Listener
      // פסיבי כי הגרירה המיידית (ReorderableDragStartListener) זוכה ב-arena
      // וחוסמת onTap.
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == 4) {
          closeTab(tab, context);
        } else if (event.buttons == 1 &&
            index != state.currentTabIndex &&
            !_hitTestCloseButton(context, event.position)) {
          context.read<TabsBloc>().add(SetCurrentTab(index));
        }
      },
      child: AppContextMenuRegion(
        menuBuilder: (menuCtx, _) =>
            _buildTabContextMenuEntries(menuCtx, tab, state),
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            return MouseRegion(
              onEnter: (_) => setLocalState(() => isTabHovered = true),
              onExit: (_) => setLocalState(() => isTabHovered = false),
              child: buildTabAppearance(setLocalState),
            );
          },
        ),
      ),
    );
  }

  /// בונה פריט תפריט להעברת טאב לשולחן עבודה אחר
  AppContextMenuEntry _buildMoveToWorkspaceMenuEntry(
    BuildContext context,
    OpenedTab tab,
  ) {
    final workspaceState = context.read<WorkspaceBloc>().state;

    final otherWorkspaces = workspaceState.workspaces
        .where((w) => w.id != workspaceState.activeWorkspaceId)
        .toList();

    if (otherWorkspaces.isEmpty) {
      return AppContextMenuEntry(
        label: 'העבר לשולחן עבודה',
        enabled: false,
      );
    }

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
    BuildContext context,
    OpenedTab tab,
    String targetWorkspaceId,
  ) {
    final tabsBloc = context.read<TabsBloc>();
    final workspaceBloc = context.read<WorkspaceBloc>();
    final tabsState = tabsBloc.state;
    final workspaceState = workspaceBloc.state;

    final targetWorkspace = workspaceState.workspaces.firstWhere(
      (w) => w.id == targetWorkspaceId,
    );

    tabsBloc.add(RemoveTab(tab));

    final currentTabs = tabsState.tabs.where((t) => t != tab).toList();
    final newActiveIndex = currentTabs.isEmpty
        ? 0
        : tabsState.currentTabIndex.clamp(0, currentTabs.length - 1);

    workspaceBloc.add(
      MoveTabToWorkspace(
        tab: tab,
        targetWorkspaceId: targetWorkspaceId,
        currentTabs: currentTabs,
        currentTabIndex: newActiveIndex,
      ),
    );

    UiSnack.show(LibraryMessages.tabMovedToWorkspace(targetWorkspace.name));
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

    if (tab is! CombinedTab) {
      if (state.tabs.length > 1) {
        final otherTabsList = state.tabs
            .where((t) => t != tab && t is! CombinedTab)
            .toList();
        final otherTabs = otherTabsList.asMap().entries.map((mapEntry) {
          final otherTab = mapEntry.value;
          return AppContextMenuEntry(
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
        entries.add(
          AppContextMenuEntry(
            label: 'הצג לצד',
            children: otherTabs,
          ),
        );
      } else {
        entries.add(
          AppContextMenuEntry(
            label: 'הצג לצד',
            enabled: false,
          ),
        );
      }
    }

    if (tab is CombinedTab) {
      entries.addAll([
        AppContextMenuEntry(
          label: 'החלף צדדים',
          onTap: () => context.read<TabsBloc>().add(const SwapSideBySideTabs()),
        ),
        AppContextMenuEntry(
          label: 'חזרה לתצוגה רגילה',
          onTap: () => context.read<TabsBloc>().add(
            DisableSideBySideMode(state.tabs.indexOf(tab)),
          ),
        ),
      ]);
    }

    entries.addAll([
      const AppContextMenuEntry.divider(),
      AppContextMenuEntry(
        label: 'כרטיסיות פתוחות',
        // childrenBuilder + stream: הרשימה נבנית מחדש בכל שינוי במצב הכרטיסיות,
        // כך שסגירת כרטיסייה דרך ה-X מסירה את שורתה והתפריט נשאר פתוח.
        childrenBuilder: () =>
            _getOpenTabsMenuEntries(context.read<TabsBloc>().state.tabs),
        childrenRefreshStream: context.read<TabsBloc>().stream,
      ),
      _buildMoveToWorkspaceMenuEntry(context, tab),
    ]);

    return entries;
  }

  List<AppContextMenuEntry> _getOpenTabsMenuEntries(List<OpenedTab> tabs) {
    // ללא מיון — הרשימה משקפת את סדר הכרטיסיות בשורת הכרטיסיות.
    return tabs.map((tab) {
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
            // סגירת הכרטיסייה מעדכנת את ה-TabsBloc; ה-childrenRefreshStream
            // יבנה מחדש את הרשימה ושורת הכרטיסייה תיעלם.
            onPressed: () => closeTab(tab, context),
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
