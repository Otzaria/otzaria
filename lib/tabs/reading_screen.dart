import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/cupertino.dart' show InheritedCupertinoTheme;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart' show Screen;
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/semantic_search/view/semantic_search_results_screen.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/resolving_tab_screen.dart';
import 'package:otzaria/tools/view/tool_tab_screen.dart';
import 'package:otzaria/tabs/utils/tab_swipe_direction.dart';
import 'package:otzaria/tabs/utils/tab_content_vertical_drag_recognizer.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';
import 'package:otzaria/tabs/view/active_pane_marker.dart';
import 'package:otzaria/tabs/view/pane_drag_handle.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/companion/companion_book_sync.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, this.onFindRefRequested});

  /// פותח את חלונית איתור הספר דרך מעטפת החלון הראשי.
  final VoidCallback? onFindRefRequested;

  /// עקיפה לבדיקות של זיהוי פלטפורמת מגע (physics ו-onPageChanged של מובייל).
  @visibleForTesting
  static bool? debugForceTouchTabs;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with WidgetsBindingObserver {
  // PageView ולא TabBarView: TabBarView מקבע לילדים מפתח לפי אינדקס, והזזת או
  // סגירת טאב סמוך הורסת את ה-State של ה-PDF (המסמך נטען מחדש).
  PageController? _pageController;
  bool _routeWasCurrent = true;
  OpenedTab? _paneBeforeModal;

  /// מהירות שחרור (פיקסלים לוגיים/שנייה) שמעליה ההחלקה נחשבת הנפה
  /// ומעבירה טאב גם לפני מחצית הדרך.
  static const double _kTabSwipeFlingVelocity = 250.0;

  /// העמוד (השבור) שבו הייתה התצוגה בתחילת מחוות ההחלקה הנוכחית.
  double _swipeStartPage = 0;

  /// האם מחוות החלקה גוררת כעת את ה-PageView.
  bool _swipeDragging = false;

  /// מדכא את [_syncPageController] בזמן אנימציית מעבר מהחלקה, כדי
  /// ש-jumpToPage של הסנכרון לא יקטע את האנימציה באמצע.
  bool _suppressPageSync = false;

  bool get _isTouchPlatform =>
      ReadingScreen.debugForceTouchTabs ??
      (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PluginTextReaderRegistry.instance.addListener(_onTextReaderChanged);
  }

  /// התצוגה (החלון) שהמסך יושב בה; הנראות של התוספים נשמרת לפיה.
  int? _viewId;
  bool _viewResolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final activePane = context.read<TabsBloc>().state.activePane;
    if (_routeWasCurrent && !routeIsCurrent) {
      _paneBeforeModal = activePane;
    } else if (!_routeWasCurrent && routeIsCurrent) {
      // היעד שהיה ממוקד לפני החלונית עשוי להיסגר או להפוך לטאב רקע.
      if (activePane != null && !identical(activePane, _paneBeforeModal)) {
        _requestTabContentFocus(activePane);
      }
      _paneBeforeModal = null;
    }
    _routeWasCurrent = routeIsCurrent;

    final viewId = View.maybeOf(context)?.viewId;
    if (_viewResolved && viewId == _viewId) return;
    _viewResolved = true;
    _viewId = viewId;
    // זריעה מיידית ולא רק מה-listener: בעלייה עם טאב תוסף משוחזר, קבוצה ריקה
    // הייתה גורמת ל-onForegroundInstanceReady להשהות מיד את התוסף שעל המסך.
    _syncVisiblePluginTabs(context.read<TabsBloc>().state);
  }

  void _requestTabContentFocus(OpenedTab pane) {
    final focusRepository = context.read<FocusRepository>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ModalRoute.isCurrentOf(context) == false ||
          !identical(context.read<TabsBloc>().state.activePane, pane)) {
        return;
      }
      focusRepository.requestTabContentFocus(pane);
    });
  }

  void _onTextReaderChanged() {
    if (mounted) _syncVisiblePluginTabs(context.read<TabsBloc>().state);
  }

  void _syncVisiblePluginTabs(TabsState state) {
    final registry = PluginTextReaderRegistry.instance;
    PluginRuntimeDispatcher.instance.setVisiblePluginInstances(
      {
        ...ToolTab.visiblePluginInstancesOf(state.currentTab),
        if (registry.activePlugin case final plugin?)
          if (state.currentTab case final currentTab?)
            for (final tab in leafPanes(currentTab).whereType<TextBookTab>())
              if (registry.usesPlugin(tab))
                (
                  pluginId: plugin.pluginId,
                  instanceId: registry.instanceIdFor(tab),
                ),
      },
      viewId: _viewId,
    );
  }

  @override
  void dispose() {
    PluginTextReaderRegistry.instance.removeListener(_onTextReaderChanged);
    // Check if widget is still mounted before accessing context
    if (mounted) {
      try {
        context.read<TabsBloc>().add(const SaveTabs());
      } catch (e) {
        // Ignore errors during disposal
      }
      try {
        context.read<HistoryBloc>().add(FlushHistory());
      } catch (e) {
        // Ignore errors during disposal
      }
    }
    _pageController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Handing Flutter the same widget instance skips rebuilding that subtree, so
  /// a tab switch only rebuilds the tabs whose content actually changed.
  final Map<OpenedTab, ({Widget view, String titles})> _tabViewCache =
      Map.identity();
  int? _tabViewCacheCounter;

  static String _paneTitles(OpenedTab tab) =>
      leafPanes(tab).map((pane) => pane.title).join('\n');

  Widget _cachedTabView(OpenedTab tab) => (_tabViewCache[tab] ??= (
    view: _buildTabView(tab),
    titles: _paneTitles(tab),
  )).view;

  void _pruneTabViewCache(TabsState state) {
    // updateCounter marks tabs mutated in place; of those mutations only a
    // rename reaches tab content, so a pin keeps every cached view.
    final mutated = _tabViewCacheCounter != state.updateCounter;
    _tabViewCacheCounter = state.updateCounter;
    final open = Set<OpenedTab>.identity()..addAll(state.tabs);
    _tabViewCache.removeWhere(
      (tab, entry) =>
          !open.contains(tab) || (mutated && entry.titles != _paneTitles(tab)),
    );
  }

  void _ensurePageController(int initialIndex) {
    _pageController ??= PageController(initialPage: initialIndex);
  }

  /// קפיצת סנכרון תוכנתית מתבצעת כעת — הדיווח שלה ב-onPageChanged אינו
  /// בחירת משתמש ואסור להזין אותו חזרה כ-SetCurrentTab.
  bool _inProgrammaticJump = false;

  void _syncPageController() {
    // בפוסט-פריים: ה-listener רץ לפני שה-PageView נבנה מחדש, ו-jumpToPage לטאב
    // חדש על התצוגה הישנה נצמד לאינדקס הקודם ומקפיץ אליו את ההדגשה.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _suppressPageSync) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      final state = context.read<TabsBloc>().state;
      if (!state.hasOpenTabs) return;
      final targetIndex = state.currentTabIndex.clamp(0, state.tabs.length - 1);
      final currentPage = controller.page?.round();
      if (currentPage != null && currentPage != targetIndex) {
        // במסך מנותק (keepAlive מחוץ למסך) הקפיצה מדווחת ל-onPageChanged ערך
        // clamp שגוי, שבמובייל מהפך את הבחירה לטאב הקודם. הדגל חוסם את המשוב.
        _inProgrammaticJump = true;
        try {
          controller.jumpToPage(targetIndex);
        } finally {
          _inProgrammaticJump = false;
        }
      }
    });
  }

  /// מזהה החלקה בין טאבים בדסקטופ, בלוח מגע ובמסך מגע.
  /// הגרירה מזיזה את ה-PageView באופן הדרגתי, ובשחרור מתיישבים על
  /// הטאב הקרוב (או הסמוך, בהנפה מהירה) — כמו PageScrollPhysics במובייל.
  Widget _wrapWithDesktopTabSwipe(Widget child) {
    if (_isTouchPlatform) return child;
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        // מעל WebView אין מזהה גלילה פנימי שימנע מעבר טאב בגלילה אנכית.
        TabContentVerticalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
              TabContentVerticalDragRecognizer
            >(
              TabContentVerticalDragRecognizer.new,
              (recognizer) => recognizer.onStart = (_) {},
            ),
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(
                supportedDevices: const {PointerDeviceKind.trackpad},
              ),
              _configureTabSwipe,
            ),
        TouchTabSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<TouchTabSwipeRecognizer>(
              () => TouchTabSwipeRecognizer(
                singleFingerPansContent: () {
                  final tab = context.read<TabsBloc>().state.currentTab;
                  return tab is PdfBookTab && tab.canPanHorizontally;
                },
              ),
              _configureTabSwipe,
            ),
      },
      child: child,
    );
  }

  void _configureTabSwipe(HorizontalDragGestureRecognizer recognizer) {
    recognizer
      // הזכייה בזירה מגיעה רק אחרי סף — down מוסר את הדלתא
      // שנצברה עד אז במקום לבלוע אותה (רציפות הגרירה).
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = (_) {
        final controller = _pageController;
        if (controller == null || !controller.hasClients) return;
        _swipeDragging = true;
        _swipeStartPage = controller.page ?? 0;
      }
      ..onUpdate = (details) {
        final controller = _pageController;
        if (!_swipeDragging || controller == null || !controller.hasClients) {
          return;
        }
        final position = controller.position;
        final offsetDelta =
            details.delta.dx.abs() *
            tabSwipeDirection(
              accumulatedDx: details.delta.dx,
              textDirection: Directionality.of(context),
            );
        position.jumpTo(
          (position.pixels + offsetDelta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
      ..onEnd = (details) {
        _settleSwipe(details.velocity.pixelsPerSecond.dx);
      }
      ..onCancel = () {
        _settleSwipe(0);
      };
  }

  /// משלים מחוות החלקה: מתיישב על הטאב הקרוב למיקום הנוכחי, או על
  /// הסמוך כשהשחרור היה בהנפה מהירה, ומעדכן את ה-bloc בהתאם.
  Future<void> _settleSwipe(double velocityDx) async {
    if (!_swipeDragging) return;
    _swipeDragging = false;
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final state = context.read<TabsBloc>().state;
    if (!state.hasOpenTabs) return;
    final page = controller.page ?? _swipeStartPage;
    // המרת מהירות ה-dx למרחב העמודים (אותה המרה כמו לדלתא של הגרירה).
    final pageVelocity =
        velocityDx.abs() *
        tabSwipeDirection(
          accumulatedDx: velocityDx,
          textDirection: Directionality.of(context),
        );
    int target;
    if (velocityDx != 0 && pageVelocity.abs() >= _kTabSwipeFlingVelocity) {
      target = pageVelocity > 0 ? page.floor() + 1 : page.ceil() - 1;
    } else {
      target = page.round();
    }
    target = target.clamp(0, state.tabs.length - 1);
    // עדכון ה-bloc קודם כדי שההדגשה בשורת הטאבים תגיב מיד; הסנכרון
    // (jumpToPage) מדוכא בינתיים כדי שהאנימציה תושלם בלי קטיעה.
    if (target != state.currentTabIndex) {
      context.read<TabsBloc>().add(SetCurrentTab(target));
    }
    final duration = AppMotion.duration(
      context,
      const Duration(milliseconds: 220),
    );
    _suppressPageSync = true;
    try {
      if (duration == Duration.zero) {
        controller.jumpToPage(target);
      } else {
        await controller.animateToPage(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _suppressPageSync = false;
      // השלמת סנכרון לכל שינוי טאב שקרה בזמן האנימציה (למשל לחיצה
      // בשורת הטאבים) ושנבלע על-ידי הדיכוי.
      if (mounted) _syncPageController();
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
        // תוספים שמוצגים בטאב הפעיל ממשיכים לרוץ; השאר מושהים. כולל טאב
        // מפוצל, שבו יכולים להיות כמה תוספים בו-זמנית.
        BlocListener<TabsBloc, TabsState>(
          listenWhen: (previous, current) =>
              !identical(previous.currentTab, current.currentTab) ||
              previous.updateCounter != current.updateCounter,
          listener: (context, state) => _syncVisiblePluginTabs(state),
        ),
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            if (state.hasOpenTabs) {
              context.read<HistoryBloc>().add(
                CaptureStateForHistory(state.currentTab!),
              );
              // בלי SaveTabs: כל פעולה שמשנה את הטאבים כבר שומרת ב-TabsBloc,
              // וקריאה נוספת מקודדת שוב את כל הטאבים בכל מעבר טאב.
              _syncPageController();
              // הטאבים חיים (initState לא רץ שוב), ולכן ממקדים כאן את החלונית
              // הפעילה כדי שהחיצים יגללו מיד; המסכים נרשמים לפוקוס לפי חלונית.
              final focusTarget = state.activePane;
              if (focusTarget != null) {
                _requestTabContentFocus(focusTarget);
              }
            }
          },
          listenWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex ||
              previous.tabs.length != current.tabs.length,
        ),
        BlocListener<TabsBloc, TabsState>(
          // שינוי מבנה בתוך אותו טאב (סגירת חלונית, החלפת צדדים, פיצול) מותיר
          // את פוקוס המקלדת על חלונית שנעלמה או זזה. לחיצה בתוך חלונית אינה
          // נכנסת לכאן — שם הפוקוס שייך למה שנלחץ.
          listenWhen: (previous, current) =>
              previous.currentTabIndex == current.currentTabIndex &&
              previous.tabs.length == current.tabs.length &&
              !identical(previous.currentTab, current.currentTab),
          listener: (context, state) {
            final pane = state.activePane;
            if (pane == null) return;
            _requestTabContentFocus(pane);
          },
        ),
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            // בסגירת הטאב האחרון — למסך הספרייה. ה-PageController משוחרר, כי
            // ב-controller הישן _syncPageController נכשל ב-hasClients.
            if (!state.hasOpenTabs) {
              _pageController?.dispose();
              _pageController = null;
              context.read<NavigationBloc>().add(
                const NavigateToScreen(Screen.library),
              );
            }
          },
          listenWhen: (previous, current) =>
              previous.hasOpenTabs && !current.hasOpenTabs,
        ),
      ],
      child: BlocBuilder<TabsBloc, TabsState>(
        // סימון החלונית הפעילה אינו משנה את מה שמצויר כאן — הוא מכוון פוקוס
        // והקשר. בלי הסינון כל לחיצה בחלונית בנתה מחדש את כל הטאבים הפתוחים
        // (כולם מותקנים בעץ בגלל KeepAlive).
        buildWhen: TabsState.changedBesidesActivePane,
        builder: (context, state) {
          final validIndex = state.hasOpenTabs
              ? state.currentTabIndex.clamp(0, state.tabs.length - 1)
              : 0;
          if (state.hasOpenTabs) {
            _ensurePageController(validIndex);
          }
          // שינוי כרטיסיות באותו אורך אינו מגיע ל-BlocListener.
          TabContentBoundaries.instance.retainOnly(state.tabs);
          _pruneTabViewCache(state);
          // Scaffold יחיד לשני המצבים; גם Scaffold-ים פנימיים מקבלים את רקע הקריאה.
          return ReaderSurfaceScope(
            child: Scaffold(
              body: !state.hasOpenTabs
                  ? OtzariaEmptyState(
                      icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
                      title: 'לא נבחרו ספרים',
                      message: 'פתחו ספר מהספרייה או מהאיתור כדי להתחיל בקריאה',
                      actions: [
                        ActionButton.recommended(
                          text: 'דפדף בספרייה',
                          icon: FluentIcons.library_24_regular,
                          onPressed: () {
                            context.read<NavigationBloc>().add(
                              const NavigateToScreen(Screen.library),
                            );
                          },
                        ),
                        ActionButton.neutral(
                          text: 'איתור ספר',
                          icon: FluentIcons.search_24_regular,
                          onPressed: widget.onFindRefRequested,
                        ),
                      ],
                    )
                  : KeyedSubtree(
                      key: TourTargetKeys.of(context).readingScreen,
                      child: SizedBox.fromSize(
                        size: MediaQuery.of(context).size,
                        child: _wrapWithDesktopTabSwipe(
                          PageView(
                            key: const ValueKey('normal_tab_view'),
                            controller: _pageController,
                            // בדסקטופ הגלילה מתנגשת בסימון טקסט, ב-PDF
                            // ובגלגלת; החלקה שם: _wrapWithDesktopTabSwipe.
                            physics: _isTouchPlatform
                                ? const PageScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            // בדסקטופ הוא היה יורה רק בקפיצות תוכנתיות (גם
                            // clamp שגוי בפתיחת טאב) ודורס את האינדקס הנכון.
                            onPageChanged: _isTouchPlatform
                                ? (index) {
                                    if (_inProgrammaticJump) return;
                                    if (index < state.tabs.length) {
                                      context.read<TabsBloc>().add(
                                        SetCurrentTab(index),
                                      );
                                    }
                                  }
                                : null,
                            children: [
                              for (var i = 0; i < state.tabs.length; i++)
                                // מפתח על הילד הישיר שומר State כשהטאבים מחליפים מיקום.
                                // TickerMode מכבה את האנימציות של טאבי רקע.
                                // ExcludeFocus: מעבר Tab שנחת בטאב רקע גלל אליו.
                                ExcludeFocus(
                                  key: ObjectKey(state.tabs[i]),
                                  excluding: i != validIndex,
                                  child: TickerMode(
                                    enabled: i == validIndex,
                                    // המפתח מאפשר לצלם את הכרטיסיה הנגררת,
                                    // גם כשהיא אינה הפעילה.
                                    child: RepaintBoundary(
                                      key: TabContentBoundaries.instance.keyFor(
                                        state.tabs[i],
                                      ),
                                      child: TourTargetsScope(
                                        enabled:
                                            i == validIndex &&
                                            state.tabs[i] is! CombinedTab,
                                        child: _BackgroundTabMediaQuery(
                                          frozen: i != validIndex,
                                          controller: _pageController!,
                                          index: i,
                                          child: _cachedTabView(state.tabs[i]),
                                        ),
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
          );
        },
      ),
    );
  }

  /// בונה את הטאב דרך עץ החלוניות שלו.
  ///
  /// גם טאב שאינו מפוצל עובר דרך [SplitPaneView], כדי שהמפתח היציב של כל
  /// חלונית יהיה זהה בשני המצבים: כך מיזוג טאבים לתצוגה מפוצלת (ופירוקה
  /// בחזרה) מעביר את החלונית הקיימת במקום לבנות אותה מחדש, ואין רגע שבו
  /// שני מסכים מחוברים לאותו `scrollController`.
  Widget _buildTabView(OpenedTab tab) {
    final isSplit = tab is CombinedTab;
    // רק חלוניות PDF מתחלקות בתקציב מטמון התמונות.
    final pdfPanes = leafPanes(tab).whereType<PdfBookTab>().length;
    return CompanionBookSyncScope(
      tab: tab,
      child: _buildPaneTree(tab, isSplit: isSplit, pdfPanes: pdfPanes),
    );
  }

  Widget _buildPaneTree(
    OpenedTab tab, {
    required bool isSplit,
    required int pdfPanes,
  }) {
    return PaneDropTarget(
      tab: tab,
      onDrop: (dragged, side) {
        // הצד שאליו נגררה הכרטיסייה קובע את סדר החלוניות.
        final incomingFirst = side == PaneDropSide.start;
        context.read<TabsBloc>().add(
          CreateCombinedTab(
            rightTab: incomingFirst ? dragged : tab,
            leftTab: incomingFirst ? tab : dragged,
          ),
        );
      },
      child: SplitPaneView(
        root: tab,
        onRatioChanged: (ratio) {
          context.read<TabsBloc>().add(UpdateSplitRatio(ratio));
        },
        paneBuilder: (pane) {
          // ה-scope קיים תמיד ורק enabled מתחלף — שינוי צורת העץ בפיצול
          // ובפירוק היה בונה מחדש את הספר.
          final content = PaneDragHandleScope(
            pane: pane,
            enabled: isSplit,
            child: ActivePaneMarker(
              pane: pane,
              enabled: isSplit,
              // bloc הערות פר-חלונית: bloc משותף בין טאבים הציג בחלונית ההערות
              // את הערות הספר שנטען אחרון בטאב אחר (issue #870).
              child: BlocProvider<PersonalNotesBloc>(
                create: (_) => PersonalNotesBloc(),
                child: _buildPaneContent(
                  pane,
                  isInCombinedView: isSplit,
                  // החימום טוען את הספר כולו; בטאב מפוצל שתי החלוניות היו
                  // מחממות ספרים גדולים במקביל ומכפילות את צריכת הזיכרון.
                  allowBackgroundWarming: !isSplit,
                  pdfPaneCount: pdfPanes,
                ),
              ),
            ),
          );

          // רק המסגרת מגיבה לשינוי החלונית הפעילה; התוכן נבנה פעם אחת ונלכד
          // ב-closure, אחרת כל לחיצה בחלונית הייתה בונה מחדש את שני הספרים.
          return BlocSelector<TabsBloc, TabsState, bool>(
            selector: (state) => identical(state.activePane, pane),
            builder: (context, isActive) =>
                PaneCard(isActive: isActive, isSplit: isSplit, child: content),
          );
        },
      ),
    );
  }

  Widget _buildPaneContent(
    OpenedTab tab, {
    required bool isInCombinedView,
    bool allowBackgroundWarming = true,
    int pdfPaneCount = 1,
  }) {
    if (tab is PdfBookTab) {
      return PdfBookScreen(
        key: ValueKey(tab),
        tab: tab,
        isInCombinedView: isInCombinedView,
        pdfPaneCount: pdfPaneCount,
      );
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
        key: ValueKey(tab),
        value: tab.bloc,
        child: _TabVisibilityBridge(
          bloc: tab.bloc,
          allowBackgroundWarming: allowBackgroundWarming,
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context.read<TabsBloc>().add(
                OpenOrFocusTab(tab, insertAdjacent: true),
              );
            },
            tab: tab,
            isInCombinedView: isInCombinedView,
          ),
        ),
      );
    } else if (tab is SemanticSearchTab) {
      return SemanticSearchResultsScreen(key: ValueKey(tab), tab: tab);
    } else if (tab is SearchingTab) {
      return BlocProvider.value(
        key: ValueKey(tab),
        value: tab.searchBloc,
        child: TantivyFullTextSearch(tab: tab),
      );
    } else if (tab is CommentatorsTab) {
      return _TabVisibilityBridge(
        key: ValueKey(tab),
        bloc: tab.bloc,
        allowBackgroundWarming: allowBackgroundWarming,
        child: CommentatorsTabScreen(
          tab: tab,
          openBookCallback: (t, {int index = 1}) {
            context.read<TabsBloc>().add(
              OpenOrFocusTab(t, insertAdjacent: true),
            );
          },
        ),
      );
    } else if (tab is PdfCommentatorsTab) {
      return PdfCommentatorsTabScreen(
        key: ValueKey(tab),
        tab: tab,
      );
    } else if (tab is ResolvingTab) {
      return ResolvingTabScreen(key: ValueKey(tab), tab: tab);
    } else if (tab is ToolTab) {
      return ToolTabScreen(key: ValueKey(tab), tab: tab);
    }
    return const SizedBox.shrink();
  }
}

/// מקפיא את מדדי החלון וערכת הצבע רק בטאבים מוסתרים לגמרי; בזמן החלקה שני
/// הטאבים הנראים חייבים לקבל ערכים עדכניים גם לפני שהטאב הנבחר מתחלף.
class _BackgroundTabMediaQuery extends StatefulWidget {
  final bool frozen;
  final PageController controller;
  final int index;
  final Widget child;

  const _BackgroundTabMediaQuery({
    required this.frozen,
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  State<_BackgroundTabMediaQuery> createState() =>
      _BackgroundTabMediaQueryState();
}

class _BackgroundTabMediaQueryState extends State<_BackgroundTabMediaQuery> {
  MediaQueryData? _data;
  late Widget Function(Widget child) _theme;

  @override
  Widget build(BuildContext context) {
    final live = MediaQuery.of(context);
    // Theme.of תלוי גם ב-CupertinoTheme, ו-MaterialApp מגדיר גם את צבע הבחירה;
    // בלי להקפיא את שלושתם אנימציית ערכת הצבע בונה את טאבי הרקע בכל פריים.
    final theme = Theme.of(context);
    final cupertino = context
        .dependOnInheritedWidgetOfExactType<InheritedCupertinoTheme>()
        ?.theme;
    final selection = DefaultSelectionStyle.of(context);
    Widget liveTheme(Widget child) {
      child = DefaultSelectionStyle(
        selectionColor: selection.selectionColor,
        cursorColor: selection.cursorColor,
        mouseCursor: selection.mouseCursor,
        child: Theme(data: theme, child: child),
      );
      return cupertino == null
          ? child
          : InheritedCupertinoTheme(theme: cupertino, child: child);
    }

    return AnimatedBuilder(
      animation: widget.controller,
      child: widget.child,
      builder: (context, child) {
        final controller = widget.controller;
        final page =
            controller.hasClients && controller.position.hasContentDimensions
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        if (!widget.frozen ||
            (page - widget.index).abs() < 1 ||
            _data == null) {
          _data = live;
          _theme = liveTheme;
        }
        return MediaQuery(data: _data!, child: _theme(child!));
      },
    );
  }
}

/// מדווח ל-bloc של טאב טקסט על שינויי נראות דרך [TickerMode] (שכבר משקף
/// "האם זה הטאב הפעיל") — טאב רקע משחרר תוכן ומשהה חימום.
class _TabVisibilityBridge extends StatefulWidget {
  final TextBookBloc bloc;
  final Widget child;

  /// מועבר ל-[SetTabVisibility]; מכובה כשהחלונית חולקת טאב עם אחרות.
  final bool allowBackgroundWarming;

  const _TabVisibilityBridge({
    super.key,
    required this.bloc,
    required this.child,
    this.allowBackgroundWarming = true,
  });

  @override
  State<_TabVisibilityBridge> createState() => _TabVisibilityBridgeState();
}

class _TabVisibilityBridgeState extends State<_TabVisibilityBridge> {
  ValueListenable<TickerModeData>? _tickerModeNotifier;
  ({bool visible, bool warming})? _lastReported;

  void _report() {
    final visible = _tickerModeNotifier?.value.enabled ?? true;
    final next = (visible: visible, warming: widget.allowBackgroundWarming);
    if (_lastReported == next || widget.bloc.isClosed) {
      return;
    }
    _lastReported = next;
    widget.bloc.add(
      SetTabVisibility(
        visible,
        allowBackgroundWarming: widget.allowBackgroundWarming,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerModeNotifier)) {
      _tickerModeNotifier?.removeListener(_report);
      _tickerModeNotifier = notifier;
      notifier.addListener(_report);
    }
    _report();
  }

  @override
  void didUpdateWidget(_TabVisibilityBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bloc, widget.bloc)) {
      _lastReported = null;
    }
    // מדווח גם על שינוי בחימום: פיצול הטאב מכבה אותו וסגירת חלונית מחזירה.
    _report();
  }

  @override
  void dispose() {
    _tickerModeNotifier?.removeListener(_report);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
