import 'dart:io';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart' show Screen;
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/resolving_tab_screen.dart';
import 'package:otzaria/tabs/utils/tab_swipe_direction.dart';
import 'package:otzaria/search/view/full_text_search_screen.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/widgets/layout/split_pane_content_inset.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with WidgetsBindingObserver {
  // PageController מנוהל ישירות במקום TabBarView: TabBarView עוטף ילדים
  // ב-Semantics ללא key, וה-KeyedSubtree.wrap הפנימי שלו מקבע מפתח לפי
  // אינדקס. בהזזת/סגירת טאב סמוך ה-reconciliation מצליח בחוץ אך נכשל
  // ב-type-mismatch בילד הפנימי — מה שהורס את ה-State של ה-PDF
  // (PdfViewerController + Bloc נוצרים מחדש → טעינה מחודשת של המסמך).
  // PageView לא עוטף ב-Semantics, וה-SliverChildListDelegate משתמש ב-key
  // של הילד עצמו, כך שהזזה שומרת על ה-State.
  PageController? _pageController;

  /// סף ההפעלה (בפיקסלים לוגיים) של החלקה אופקית למעבר טאב בדסקטופ.
  static const double _kTabSwipeThreshold = 80.0;

  /// הצטברות ה-dx מתחילת מחוות ההחלקה הנוכחית.
  double _swipeAccum = 0;

  /// האם המחווה הנוכחית כבר הפעילה מעבר טאב (מעבר אחד לכל מחווה).
  bool _swipeFired = false;

  /// מדכא את [_syncPageController] בזמן אנימציית מעבר מהחלקה, כדי
  /// ש-jumpToPage של הסנכרון לא יקטע את האנימציה באמצע.
  bool _suppressPageSync = false;

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

  void _ensurePageController(int initialIndex) {
    _pageController ??= PageController(initialPage: initialIndex);
  }

  void _syncPageController() {
    // הקפיצה נדחית לפוסט-פריים בכוונה: ה-BlocListener שמפעיל את הסנכרון רץ
    // *לפני* שה-BlocBuilder בונה מחדש את ה-PageView, כך שברגע הקריאה ל-PageView
    // עדיין יש את מספר הילדים הישן. כשנפתח טאב חדש בסוף, jumpToPage לאינדקס
    // החדש על תצוגה ישנה חורג מהתחום ונצמד (clamp) רגעית לאינדקס הקודם, מה
    // שיורה onPageChanged עם אינדקס שגוי → SetCurrentTab שגוי → ההדגשה בשורת
    // הטאבים קופצת לטאב הקודם במקום לחדש. דחייה לפוסט-פריים מבטיחה שהקפיצה
    // תתבצע אחרי שהילד החדש כבר בעץ, על תצוגה תקינה.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _suppressPageSync) return;
      final controller = _pageController;
      if (controller == null || !controller.hasClients) return;
      final state = context.read<TabsBloc>().state;
      if (!state.hasOpenTabs) return;
      final targetIndex = state.currentTabIndex.clamp(0, state.tabs.length - 1);
      final currentPage = controller.page?.round();
      if (currentPage != null && currentPage != targetIndex) {
        controller.jumpToPage(targetIndex);
      }
    });
  }

  /// עוטפת את ה-PageView בזיהוי החלקה אופקית למעבר טאב בדסקטופ.
  ///
  /// ה-physics של ה-PageView נשאר NeverScrollable בדסקטופ (ראו הערה שם),
  /// והמחווה ממומשת ב-recognizer ייעודי המוגבל לטאצ'פד ולמסך מגע בלבד:
  /// - גרירות עכבר (kind: mouse) מסוננות לגמרי, כך שסימון טקסט אופקי
  ///   ב-SelectionArea וב-PDF לא נפגע.
  /// - ה-recognizer משתתף ב-gesture arena כצומת חיצוני, ולכן מפסיד
  ///   לכל רכיב פנימי שתובע את המחווה: גלילה אנכית בספרי טקסט,
  ///   pan/zoom של pdfrx (כולל גלילה אופקית ב-PDF), וסרגלי טאבים
  ///   פנימיים הנגללים אופקית.
  /// - אירועי גלגלת (pointer signals) לא מטופלים כלל — אין מצב של
  ///   טאב "תקוע" באמצע גלילה ואין טיפול כפול מול ה-Listener של ה-PDF.
  Widget _wrapWithDesktopTabSwipe(Widget child) {
    if (Platform.isAndroid || Platform.isIOS) return child;
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(
                supportedDevices: const {
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.touch,
                },
              ),
              (recognizer) {
                recognizer
                  ..onStart = (_) {
                    _swipeAccum = 0;
                    _swipeFired = false;
                  }
                  ..onUpdate = (details) {
                    if (_swipeFired) return;
                    _swipeAccum += details.delta.dx;
                    if (_swipeAccum.abs() >= _kTabSwipeThreshold) {
                      _swipeFired = true;
                      _switchTabBySwipe(
                        tabSwipeDirection(
                          accumulatedDx: _swipeAccum,
                          textDirection: Directionality.of(context),
                        ),
                      );
                    }
                  }
                  ..onEnd = (_) {
                    _swipeFired = false;
                  }
                  ..onCancel = () {
                    _swipeFired = false;
                  };
              },
            ),
      },
      child: child,
    );
  }

  /// מעבר לטאב סמוך בעקבות מחוות החלקה. [direction] הוא `1` לטאב הבא
  /// או `-1` לטאב הקודם (כפי שחושב ב-[tabSwipeDirection]).
  Future<void> _switchTabBySwipe(int direction) async {
    final state = context.read<TabsBloc>().state;
    if (!state.hasOpenTabs) return;
    final target = state.currentTabIndex + direction;
    if (target < 0 || target >= state.tabs.length) return;
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    // עדכון ה-bloc קודם כדי שההדגשה בשורת הטאבים תגיב מיד; הסנכרון
    // (jumpToPage) מדוכא בינתיים כדי שהאנימציה תושלם בלי קטיעה.
    context.read<TabsBloc>().add(SetCurrentTab(target));
    _suppressPageSync = true;
    try {
      await controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
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
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            if (state.hasOpenTabs) {
              context.read<HistoryBloc>().add(
                CaptureStateForHistory(state.currentTab!),
              );
              // אין צורך לקרוא כאן ל-SaveTabs: כל פעולה שמשנה את הטאבים או את
              // הטאב הנוכחי (SetCurrentTab/AddTab/RemoveTab/MoveTab וכו') כבר
              // שומרת בעצמה ב-TabsBloc. קריאה נוספת כאן גרמה לשמירה כפולה
              // (encoding של כל הטאבים) בכל מעבר טאב.
              _syncPageController();
              // ממקד את אזור הקריאה של הטאב הפעיל כדי שגלילה עם החיצים תעבוד
              // מיד במעבר טאב — הטאבים נשמרים חיים ולכן initState לא רץ שוב.
              final activeTab = state.currentTab;
              if (activeTab != null) {
                final focusRepo = context.read<FocusRepository>();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  focusRepo.requestTabContentFocus(activeTab);
                });
              }
            }
          },
          listenWhen: (previous, current) =>
              previous.currentTabIndex != current.currentTabIndex ||
              previous.tabs.length != current.tabs.length,
        ),
        BlocListener<TabsBloc, TabsState>(
          listener: (context, state) {
            // כשסוגרים את הטאב האחרון, עוברים למסך הספרייה.
            // משחררים גם את ה-PageController כדי שכשייפתחו טאבים חדשים
            // ייווצר controller חדש עם initialPage תקין; אחרת ה-page
            // הפנימי הישן נשאר ו-_syncPageController נכשל ב-hasClients.
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
        builder: (context, state) {
          // Scaffold יחיד לשני המצבים — Theme מפיץ את scaffoldBackgroundColor
          // לכל Scaffold פנימי (TextBookScreen, PdfBookScreen וכד').
          final readerBg = AppSurfaces.readerBackground(context);
          final validIndex = state.hasOpenTabs
              ? state.currentTabIndex.clamp(0, state.tabs.length - 1)
              : 0;
          if (state.hasOpenTabs) {
            _ensurePageController(validIndex);
          }
          return Theme(
            data: Theme.of(context).copyWith(
              scaffoldBackgroundColor: readerBg,
            ),
            child: Scaffold(
              body: !state.hasOpenTabs
                  ? Center(
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
                    )
                  : KeyedSubtree(
                      key: tourReadingScreenTargetKey,
                      child: SizedBox.fromSize(
                        size: MediaQuery.of(context).size,
                        child: _wrapWithDesktopTabSwipe(
                          PageView(
                            key: const ValueKey('normal_tab_view'),
                            controller: _pageController,
                            // גלילת PageView רק במובייל; בדסקטופ
                            // PageScrollPhysics מתנגשת עם סימון טקסט אופקי,
                            // עם גלילה אופקית ב-PDF ועם אירועי גלגלת.
                            // החלקת טאצ'פד/מגע בדסקטופ ממומשת בנפרד
                            // ב-_wrapWithDesktopTabSwipe.
                            physics: Platform.isAndroid || Platform.isIOS
                                ? const PageScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                            // רק במובייל הגלילה ידנית ולכן onPageChanged משקף
                            // בחירת משתמש שצריך להזין חזרה ל-currentTabIndex.
                            // בדסקטופ (NeverScrollable) אי-אפשר לגלול ידנית,
                            // וה-callback היה יורה רק על קפיצות תוכנתיות —
                            // כולל ערך clamp שגוי רגעי בעת פתיחת טאב חדש —
                            // ודורס את האינדקס הנכון. לכן מנוטרל.
                            onPageChanged: Platform.isAndroid || Platform.isIOS
                                ? (index) {
                                    if (index < state.tabs.length) {
                                      context.read<TabsBloc>().add(
                                        SetCurrentTab(index),
                                      );
                                    }
                                  }
                                : null,
                            children: [
                              for (var i = 0; i < state.tabs.length; i++)
                                // בלי key על הילד הישיר, גרירת טאב משייכת
                                // Elementים לפי אינדקס וההזזה הורסת State
                                // (ב-PDF: סגירת המסמך וטעינה מחדש מהדיסק).
                                // TickerMode מכבה אנימציות של טאבי רקע.
                                KeyedSubtree(
                                  key: ObjectKey(state.tabs[i]),
                                  child: TickerMode(
                                    enabled: i == validIndex,
                                    child: _buildTabView(
                                      state.tabs[i],
                                      enableTourTargets: i == validIndex,
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

  Widget _buildTabView(
    OpenedTab tab, {
    required bool enableTourTargets,
  }) {
    if (tab is CombinedTab) {
      // הצגת שני הספרים זה לצד זה
      return _buildCombinedTabView(tab);
    } else if (tab is PdfBookTab) {
      return PdfBookScreen(
        key: ValueKey(tab),
        tab: tab,
        enableTourTargets: enableTourTargets,
      );
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
        key: ValueKey(tab),
        value: tab.bloc,
        child: _TabVisibilityBridge(
          bloc: tab.bloc,
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context.read<TabsBloc>().add(
                OpenOrFocusTab(tab, insertAdjacent: true),
              );
            },
            tab: tab,
            enableTourTargets: enableTourTargets,
          ),
        ),
      );
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(key: ValueKey(tab), tab: tab);
    } else if (tab is CommentatorsTab) {
      return _TabVisibilityBridge(
        key: ValueKey(tab),
        bloc: tab.bloc,
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
    }
    return const SizedBox.shrink();
  }

  Widget _buildCombinedTabView(CombinedTab combinedTab) {
    return _SideBySideViewWidget(
      key: ValueKey(
        'combined_${combinedTab.rightTab.title}_${combinedTab.leftTab.title}',
      ),
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

  Widget _buildSingleTabContent(
    OpenedTab tab, {
    bool isInCombinedView = false,
  }) {
    if (tab is PdfBookTab) {
      return PdfBookScreen(
        key: ValueKey(tab),
        tab: tab,
        isInCombinedView: isInCombinedView,
        enableTourTargets: false,
      );
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
        value: tab.bloc,
        child: _TabVisibilityBridge(
          bloc: tab.bloc,
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context.read<TabsBloc>().add(
                OpenOrFocusTab(tab, insertAdjacent: true),
              );
            },
            tab: tab,
            isInCombinedView: isInCombinedView,
            enableTourTargets: false,
          ),
        ),
      );
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(tab: tab);
    } else if (tab is CommentatorsTab) {
      return _TabVisibilityBridge(
        key: ValueKey(tab),
        bloc: tab.bloc,
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
    }
    return const SizedBox.shrink();
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
  static const double _combinedDividerWidth = 12;
  late double _splitRatio;

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
        final colorScheme = Theme.of(context).colorScheme;

        // כל חלונית נצמדת לדופן החלון (הידית יושבת על הדופן), והשוליים מוזרקים
        // פנימה סביב תוכן הקריאה בלבד — בצד הדופן החיצוני של אותה חלונית.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ספר ימני (בגלל RTL, זה יופיע בצד ימין)
            SizedBox(
              width: rightWidth,
              child: ClipRect(
                child: SplitPaneContentInset(
                  // ספר זה יושב בקצה ההתחלתי של השורה (ימין ב-RTL) — השוליים
                  // מוזרקים בצד הדופן החיצוני שלו.
                  contentInset: const EdgeInsetsDirectional.only(
                    start: _combinedDividerWidth,
                  ),
                  child: widget.buildTabView(widget.rightTab),
                ),
              ),
            ),
            // מפריד ניתן לגרירה
            SizedBox(
              width: _combinedDividerWidth,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  ColoredBox(color: colorScheme.surfaceContainer),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        setState(() {
                          // תיקון: הפיכת הכיוון כי אנחנו ב-RTL
                          final ratioDelta = -details.delta.dx / totalWidth;
                          _splitRatio = (_splitRatio + ratioDelta).clamp(
                            0.2,
                            0.8,
                          );
                        });
                      },
                      onPanEnd: (_) => widget.onSplitRatioChanged(_splitRatio),
                    ),
                  ),
                ],
              ),
            ),
            // ספר שמאלי - Expanded כדי למלא את שאר המקום ללא גלישה
            Expanded(
              child: ClipRect(
                child: SplitPaneContentInset(
                  // ספר זה יושב בקצה הסופי של השורה (שמאל ב-RTL) — השוליים
                  // מוזרקים בצד הדופן החיצוני שלו.
                  contentInset: const EdgeInsetsDirectional.only(
                    end: _combinedDividerWidth,
                  ),
                  child: widget.buildTabView(widget.leftTab),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// מדווח ל-bloc של טאב טקסט על שינויי נראות דרך [TickerMode] (שכבר משקף
/// "האם זה הטאב הפעיל") — טאב רקע משחרר תוכן ומשהה חימום.
class _TabVisibilityBridge extends StatefulWidget {
  final TextBookBloc bloc;
  final Widget child;

  const _TabVisibilityBridge({
    super.key,
    required this.bloc,
    required this.child,
  });

  @override
  State<_TabVisibilityBridge> createState() => _TabVisibilityBridgeState();
}

class _TabVisibilityBridgeState extends State<_TabVisibilityBridge> {
  ValueListenable<TickerModeData>? _tickerModeNotifier;
  bool? _lastReported;

  void _report() {
    final visible = _tickerModeNotifier?.value.enabled ?? true;
    if (_lastReported == visible || widget.bloc.isClosed) {
      return;
    }
    _lastReported = visible;
    widget.bloc.add(SetTabVisibility(visible));
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
      _report();
    }
  }

  @override
  void dispose() {
    _tickerModeNotifier?.removeListener(_report);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
