import 'dart:io';
import 'package:flutter/foundation.dart';
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
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/core/ui_snack.dart';
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

/// סגנון משותף לכפתורי האייקון בשורת הכותרת
final ButtonStyle _kIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(32, 32),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
  ),
);

class _CustomTitleBarState extends State<CustomTitleBar> {
  // ScrollController לשורת הטאבים הראשית (ReorderableListView). הבחירה מנוהלת
  // דרך TabsBloc (currentTabIndex) + onTap, ולא דרך TabController — האינדיקטור
  // מצויר ידנית (CustomPaint) ולא ע"י ה-indicator של TabBar.
  final ScrollController _tabsScrollController = ScrollController();

  // GlobalKey לטאב הנבחר, לשם גלילה אוטומטית שלו לתצוגה (ראה
  // _ensureSelectedTabVisible). עובר בין הטאבים כשהבחירה משתנה — בטוח כי רק
  // טאב אחד נבחר בכל רגע, ורק מבנה אחד (רחב/צר) מרנדר טאבים בו-זמנית.
  final GlobalKey _selectedTabKey = GlobalKey();

  // חתימת המצב שאליו גללנו לאחרונה. כוללת זהות הטאב הנבחר, אינדקסו, מספר
  // הטאבים, רוחב המסך והאוריינטציה — כך שגלילה-מחדש מתרחשת לא רק בבחירת טאב
  // אחר אלא גם בשחזור workspace/ReplaceAllTabs (אותו אינדקס, טאב אחר), resize
  // ומעבר portrait/landscape — בכולם הטאב הנבחר עלול לצאת מהתצוגה.
  Object? _lastScrollSignature;
  // הטאב שאליו גללנו לאחרונה, להבחנה בין שינוי-בחירה (מנפישים) לבין שינוי
  // גודל/מבנה בלבד (גלילה מיידית, ללא אנימציה מיותרת).
  OpenedTab? _lastScrolledTab;

  // נקבע ב-onDoubleTapDown (לפני onDoubleTap): האם הלחיצה הכפולה האחרונה באזור
  // הטאבים הייתה על טאב בפועל. אם כן — מדלגים על maximize/restore.
  bool _doubleTapOnTab = false;

  @override
  void dispose() {
    _tabsScrollController.dispose();
    super.dispose();
  }

  /// בודק אם הנקודה הגלובלית פוגעת ברכיב של שורת הטאבים — טאב או חץ גלילה
  /// (מסומן ב-[_kTabHitMarker]). משמש כדי לדלג על maximize בלחיצה כפולה עליהם,
  /// בלי להסתמך על gesture arena.
  bool _hitTestTab(BuildContext context, Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance
        .hitTestInView(result, globalPosition, View.of(context).viewId);
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
    WidgetsBinding.instance
        .hitTestInView(result, globalPosition, View.of(context).viewId);
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
  /// אם הלחיצה הייתה על טאב (נקבע ב-onDoubleTapDown) — אין שינוי גודל.
  Future<void> _onTabsAreaDoubleTap() async {
    if (_doubleTapOnTab) return;
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  /// גולל את שורת הטאבים כך שהטאב הנבחר ייראה במלואו.
  ///
  /// נדרש כי שורת הטאבים בנויה על [ReorderableListView] (lazy, עם אינדיקטור
  /// ידני) וללא [TabController] — ולכן אין גלילה אוטומטית לטאב הנבחר. בלעדי
  /// פונקציה זו, בטעינה ראשונית עם הרבה טאבים ה-ScrollController נשאר ב-offset 0
  /// והטאב הפעיל עלול להישאר גלול מחוץ לתצוגה.
  ///
  /// [animate] - האם להנפיש את הגלילה (false בטעינה ראשונית כדי למקם מיידית).
  ///
  /// [prevMax] - ה-maxScrollExtent מהניסיון הקודם. כל עוד הוא ממשיך לגדול
  /// (ה-ListView ה-lazy מודד רוחבי טאבים נוספים ו-overflow מתגלה בהדרגה),
  /// ממשיכים לנסות גם כשהטאב נראה כרגע — אחרת הוא נדחק החוצה אחרי שהחץ מופיע.
  void _ensureSelectedTabVisible(
      {required bool animate, int attempt = 0, double? prevMax}) {
    if (attempt >= 12) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabsScrollController.hasClients) {
        _ensureSelectedTabVisible(
            animate: animate, attempt: attempt + 1, prevMax: prevMax);
        return;
      }
      final pos = _tabsScrollController.position;
      if (!pos.hasContentDimensions) {
        // המידות עדיין לא נמדדו — ננסה שוב בפריים הבא.
        _ensureSelectedTabVisible(
            animate: animate, attempt: attempt + 1, prevMax: prevMax);
        return;
      }
      final currentMax = pos.maxScrollExtent;
      final maxGrew = prevMax == null || currentMax > prevMax + 0.5;
      final ctx = _selectedTabKey.currentContext;
      if (ctx == null) {
        // הטאב הנבחר מחוץ לתחום הרינדור (ReorderableListView הוא lazy). קפיצה
        // להערכה לינארית לפי האינדקס מכניסה אותו לתחום, ופריים נוסף מדייק.
        final state = context.read<TabsBloc>().state;
        if (state.tabs.length <= 1 || currentMax <= 0) return;
        final estimate =
            (currentMax * state.currentTabIndex / (state.tabs.length - 1))
                .clamp(pos.minScrollExtent, currentMax);
        if ((estimate - pos.pixels).abs() < 1.0) return; // כבר שם — מניעת לולאה
        _tabsScrollController.jumpTo(estimate);
        _ensureSelectedTabVisible(
            animate: animate, attempt: attempt + 1, prevMax: currentMax);
        return;
      }
      final renderObject = ctx.findRenderObject();
      if (renderObject == null) return;
      final viewport = RenderAbstractViewport.of(renderObject);
      // ה-offsets שיביאו את הטאב לקצה ההתחלתי/הסופי של ה-viewport.
      final leadingEdge = viewport.getOffsetToReveal(renderObject, 0.0).offset;
      final trailingEdge = viewport.getOffsetToReveal(renderObject, 1.0).offset;
      // גלילה מינימלית: רק אם הטאב חתוך, ולכיוון הקרוב. אם נראה במלואו — כלום.
      final double? target = pos.pixels > leadingEdge
          ? leadingEdge
          : (pos.pixels < trailingEdge ? trailingEdge : null);
      if (target == null) {
        // הטאב נראה. אם המידות עדיין גדלות (overflow מתגלה), נמשיך לוודא בפריים
        // הבא — אך רק במצב מיידי, כדי לא לקטוע אנימציית בחירה.
        if (!animate && maxGrew) {
          _ensureSelectedTabVisible(
              animate: animate, attempt: attempt + 1, prevMax: currentMax);
        }
        return;
      }
      final clamped = target.clamp(pos.minScrollExtent, currentMax);
      if (animate) {
        _tabsScrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      } else {
        _tabsScrollController.jumpTo(clamped);
        // ייתכן ש-overflow נוסף יתגלה אחרי הקפיצה; נמשיך לוודא עד התייצבות.
        if (maxGrew) {
          _ensureSelectedTabVisible(
              animate: animate, attempt: attempt + 1, prevMax: currentMax);
        }
      }
    });
  }

  bool _useStackedTabs(BuildContext context, NavigationState navState) {
    final isReading = navState.currentScreen == Screen.reading ||
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
            final useReaderStyle = navState.currentScreen == Screen.search ||
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

  Widget _buildPanelTitle(BuildContext context, String title,
      {String? subtitle}) {
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

  Widget _buildScrollableTabsArea(TabsState state) {
    // גלילה אוטומטית לטאב הנבחר כשמשהו שעלול להוציאו מהתצוגה משתנה: בחירת טאב,
    // החלפת רשימת הטאבים (workspace/ReplaceAllTabs), resize או שינוי אוריינטציה.
    // ה-MediaQuery נקרא רק לשם זיהוי השינוי; ערכו אינו חייב להיות מדויק.
    final mq = MediaQuery.of(context);
    final signature = (
      state.currentTab,
      state.currentTabIndex,
      state.tabs.length,
      mq.size.width.round(),
      mq.orientation,
    );
    // כניסה-מחדש של השורה לעץ (חזרה למסך עיון ממסך אחר) מאתחלת את ה-offset ל-0
    // והטאב הנבחר נעלם, אך ה-signature זהה לזה שלפני היציאה — לכן בודקים גם
    // hasClients: בפריים הראשון של הכניסה ה-ScrollController עדיין מנותק.
    final reentering = !_tabsScrollController.hasClients;
    if (reentering || signature != _lastScrollSignature) {
      final isFirstScroll = _lastScrollSignature == null;
      // מנפישים רק כשהבחירה עצמה השתנתה; שינוי גודל/מבנה/כניסה — גלילה מיידית.
      final selectionChanged = !identical(state.currentTab, _lastScrolledTab);
      _lastScrollSignature = signature;
      _lastScrolledTab = state.currentTab;
      _ensureSelectedTabVisible(
          animate: selectionChanged && !isFirstScroll && !reentering);
    }
    // ReorderableListView מטפל במלוא הגרירה-לסידור: הרמת הטאב, ה-placeholder
    // היחיד שזז, סידור שאר הטאבים לתצוגת התוצאה, והאנימציה — ללא לולאת ה-shift
    // של hit-test ידני. הבחירה היא ב-onPointerDown (ב-_buildTab), כך שכל
    // אינטראקציה בוחרת את הטאב; הגרירה היא מיידית דרך ReorderableDragStartListener.
    final reorderList = ReorderableListView.builder(
      scrollController: _tabsScrollController,
      scrollDirection: Axis.horizontal,
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
        return ReorderableDragStartListener(
          key: ObjectKey(tab),
          index: index,
          // סימון שטח הטאב ל-hit-test, כדי שה-double-tap-to-maximize שבמסגרת
          // (ראה _buildScrollableTabsArea) ידלג עליו. בליעה דרך GestureDetector
          // מקונן אינה אמינה מול ה-DoubleTapGestureRecognizer של ה-DragToMoveArea
          // (שני הזיהויים מתקיימים במקביל), ולכן מזהים "לחיצה על טאב" בבדיקת
          // hit-test מפורשת ב-onDoubleTapDown.
          child: MetaData(
            metaData: _kTabHitMarker,
            behavior: HitTestBehavior.opaque,
            child: _buildTab(context, tab, state),
          ),
        );
      },
    );

    // מחליף את DragToMoveArea בגרסה ששולטת ב-onDoubleTap: גרירת חלון (onPanStart)
    // ו-maximize/restore (onDoubleTap) פעילים על האזור הריק שבשורת הטאבים, אך
    // לחיצה כפולה *על טאב* מדלגת על ה-maximize. הזיהוי הוא ע"י hit-test מפורש
    // (onDoubleTapDown) ולא ע"י arena/בליעה — שאינם אמינים ל-double-tap מקונן.
    // זהו ה-מקבילה לאופן שבו ReorderableDragStartListener בולע את הגרירה על טאב:
    // אזור ריק → גרירה/maximize של החלון; טאב → לא.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTapDown: (details) =>
          _doubleTapOnTab = _hitTestTab(context, details.globalPosition),
      onDoubleTap: _onTabsAreaDoubleTap,
      child: KeyedSubtree(
        key: tourReadingTabsTargetKey,
        // חיצי גלילה מוצגים רק כשהטאבים גולשים מעבר לרוחב הזמין.
        // ה-AnimatedBuilder מאזין ל-ScrollController לעדכון בזמן גלילה (offset),
        // וה-NotificationListener תופס שינויי מידות התוכן (maxScrollExtent) —
        // למשל בטעינה ראשונית או בהוספת/הסרת טאבים — שאינם מפעילים את ה-controller,
        // ומאלץ הערכה מחדש של זמינות החיצים בפריים הבא.
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
            return false;
          },
          child: AnimatedBuilder(
            animation: _tabsScrollController,
            builder: (context, _) {
              final position = _tabsScrollController.hasClients &&
                      _tabsScrollController.position.hasContentDimensions
                  ? _tabsScrollController.position
                  : null;
              final canLeft = position != null &&
                  position.pixels > position.minScrollExtent + 0.5;
              final canRight = position != null &&
                  position.pixels < position.maxScrollExtent - 0.5;
              final hasOverflow = canLeft || canRight;

              if (!hasOverflow) return reorderList;

              return Row(
                children: [
                  _buildTabsScrollArrow(
                      FluentIcons.chevron_left_24_regular, canLeft, -150),
                  Expanded(child: reorderList),
                  _buildTabsScrollArrow(
                      FluentIcons.chevron_right_24_regular, canRight, 150),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTabsScrollArrow(IconData icon, bool enabled, double delta) {
    // סימון כרכיב של שורת הטאבים כדי שלחיצה כפולה על החץ תיבלע ולא תפעיל
    // maximize/restore של החלון (ראה _hitTestTab).
    return MetaData(
      metaData: _kTabHitMarker,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          onPressed: enabled ? () => _scrollTabsBy(delta) : null,
          icon: Icon(icon),
        ),
      ),
    );
  }

  void _scrollTabsBy(double delta) {
    if (!_tabsScrollController.hasClients) return;
    final pos = _tabsScrollController.position;
    final target = (_tabsScrollController.offset + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _tabsScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
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
          onPressed: widget.onReadingSettingsPressed ??
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
      BuildContext context, SettingsState settingsState) {
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

  Widget _buildTab(BuildContext context, OpenedTab tab, TabsState state) {
    final index = state.tabs.indexOf(tab);
    final isSelected = index == state.currentTabIndex;
    final closeTabShortcut =
        Settings.getValue<String>('key-shortcut-close-tab') ?? 'ctrl+w';

    bool isTabActive(int tabIndex) => tabIndex == state.currentTabIndex;
    bool isTabHovered = false;

    Widget buildTabContent() {
      if (tab is CombinedTab) {
        return Tooltip(
          message: tab.title,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(FluentIcons.panel_left_text_24_regular, size: 16),
              ),
              Text(truncate(tab.title, 20)),
            ],
          ),
        );
      }

      if (tab is SearchingTab) {
        return ValueListenableBuilder<String>(
          valueListenable: tab.titleNotifier,
          builder: (context, title, child) => Tooltip(
            message: title,
            child: Text(truncate(title, 25)),
          ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(FluentIcons.document_pdf_24_regular, size: 16),
                  ),
                  Text(truncate(tab.title, 12)),
                ],
              ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(FluentIcons.document_pdf_24_regular, size: 16),
                  ),
                  Text(truncate(tab.title, 12)),
                ],
              ),
            );
          },
        );
      }

      if (tab is CommentatorsTab) {
        return Tooltip(
          message: tab.title,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(FluentIcons.book_24_regular, size: 16),
              ),
              Text(truncate(tab.title, 20)),
            ],
          ),
        );
      }

      final textTab = tab as TextBookTab;
      return ValueListenableBuilder<String>(
        valueListenable: textTab.currentTitle,
        builder: (context, currentTitleValue, child) {
          final tooltipMessage = currentTitleValue.isNotEmpty
              ? '${tab.title}, $currentTitleValue'
              : tab.title;
          return Tooltip(
            message: tooltipMessage,
            child: Text(truncate(tab.title, 12)),
          );
        },
      );
    }

    Widget buildTabAppearance(StateSetter? setState) {
      final showLeadingDivider =
          index > 0 && !isTabActive(index) && !isTabActive(index - 1);
      final colorScheme = Theme.of(context).colorScheme;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLeadingDivider)
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              color: colorScheme.outlineVariant,
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 32),
            padding: EdgeInsets.only(
              left: 6,
              right: index == 0 ? 0 : 6,
            ),
            child: CustomPaint(
              painter: isSelected
                  ? _TabBackgroundPainter(AppSurfaces.topBarBackground(context))
                  : null,
              foregroundPainter: isTabHovered && !isSelected
                  ? _TabBackgroundPainter(
                      colorScheme.onSurface.withValues(alpha: 0.08))
                  : null,
              child: Tab(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isSelected) const SizedBox(width: 4),
                        _buildPinIconInline(context, tab),
                        buildTabContent(),
                        Tooltip(
                          preferBelow: false,
                          message: closeTabShortcut.toUpperCase(),
                          child: MetaData(
                            metaData: _kTabCloseButtonHitMarker,
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
        ],
      );
    }

    return KeyedSubtree(
      // ה-key על הטאב הנבחר בלבד, כדי שגלילה אוטומטית תוכל לאתר אותו (ראה
      // _ensureSelectedTabVisible). הטאבים האחרים ללא key (null).
      key: isSelected ? _selectedTabKey : null,
      child: Listener(
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
          key: isSelected ? tourTabContextMenuTargetKey : null,
          menuBuilder: (menuCtx, _) =>
              _buildTabContextMenuEntries(menuCtx, tab, state),
          menuItemKeysByLabel: isSelected
              ? {'הצג לצד': tourTabSideBySideMenuItemTargetKey}
              : null,
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
      ),
    );
  }

  /// בונה פריט תפריט להעברת טאב לשולחן עבודה אחר
  AppContextMenuEntry _buildMoveToWorkspaceMenuEntry(
      BuildContext context, OpenedTab tab) {
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
      BuildContext context, OpenedTab tab, String targetWorkspaceId) {
    final tabsBloc = context.read<TabsBloc>();
    final workspaceBloc = context.read<WorkspaceBloc>();
    final tabsState = tabsBloc.state;
    final workspaceState = workspaceBloc.state;

    final targetWorkspace =
        workspaceState.workspaces.firstWhere((w) => w.id == targetWorkspaceId);

    tabsBloc.add(RemoveTab(tab));

    final currentTabs = tabsState.tabs.where((t) => t != tab).toList();
    final newActiveIndex = currentTabs.isEmpty
        ? 0
        : tabsState.currentTabIndex.clamp(0, currentTabs.length - 1);

    workspaceBloc.add(MoveTabToWorkspace(
      tab: tab,
      targetWorkspaceId: targetWorkspaceId,
      currentTabs: currentTabs,
      currentTabIndex: newActiveIndex,
    ));

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

    if (tab is! CombinedTab) {
      if (state.tabs.length > 1) {
        final otherTabsList =
            state.tabs.where((t) => t != tab && t is! CombinedTab).toList();
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
