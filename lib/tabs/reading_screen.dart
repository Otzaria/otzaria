import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:otzaria/search/view/full_text_search_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

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
      if (!mounted) return;
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
              // אין צורך לקרוא כאן ל-SaveTabs: כל פעולה שמשנה את הטאבים או את
              // הטאב הנוכחי (SetCurrentTab/AddTab/RemoveTab/MoveTab וכו') כבר
              // שומרת בעצמה ב-TabsBloc. קריאה נוספת כאן גרמה לשמירה כפולה
              // (encoding של כל הטאבים) בכל מעבר טאב.
              _syncPageController();
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
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return BlocBuilder<TabsBloc, TabsState>(
            builder: (context, state) {
              // Scaffold יחיד לשני המצבים — Theme מפיץ את scaffoldBackgroundColor
              // לכל Scaffold פנימי (TextBookScreen, PdfBookScreen וכד').
              final readerBg = AppSurfaces.readerBackground(context);
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
                                          const NavigateToScreen(
                                              Screen.library),
                                        );
                                  },
                                  icon: const Icon(
                                      FluentIcons.library_24_regular),
                                  label: const Text('דפדף בספרייה'),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Builder(builder: (context) {
                          final validIndex = state.currentTabIndex
                              .clamp(0, state.tabs.length - 1);
                          _ensurePageController(validIndex);
                          return KeyedSubtree(
                            key: tourReadingScreenTargetKey,
                            child: SizedBox.fromSize(
                              size: MediaQuery.of(context).size,
                              child: PageView(
                                key: const ValueKey('normal_tab_view'),
                                controller: _pageController,
                                // גלילה בין טאבים רק במובייל; בדסקטופ tab-bar הוא
                                // אמצעי הניווט, ו-PageScrollPhysics מתנגשת עם
                                // סימון טקסט אופקי ועם גלילה אופקית ב-PDF.
                                physics: Platform.isAndroid || Platform.isIOS
                                    ? const PageScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                // רק במובייל הגלילה ידנית ולכן onPageChanged משקף
                                // בחירת משתמש שצריך להזין חזרה ל-currentTabIndex.
                                // בדסקטופ (NeverScrollable) אי-אפשר לגלול ידנית,
                                // וה-callback היה יורה רק על קפיצות תוכנתיות —
                                // כולל ערך clamp שגוי רגעי בעת פתיחת טאב חדש —
                                // ודורס את האינדקס הנכון. לכן מנוטרל.
                                onPageChanged:
                                    Platform.isAndroid || Platform.isIOS
                                        ? (index) {
                                            if (index < state.tabs.length) {
                                              context
                                                  .read<TabsBloc>()
                                                  .add(SetCurrentTab(index));
                                            }
                                          }
                                        : null,
                                children: [
                                  for (var i = 0; i < state.tabs.length; i++)
                                    _buildTabView(
                                      state.tabs[i],
                                      enableTourTargets: i == validIndex,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                ),
              );
            },
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
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context
                  .read<TabsBloc>()
                  .add(OpenOrFocusTab(tab, insertAdjacent: true));
            },
            tab: tab,
            enableTourTargets: enableTourTargets,
          ));
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(key: ValueKey(tab), tab: tab);
    } else if (tab is CommentatorsTab) {
      return CommentatorsTabScreen(
        key: ValueKey(tab),
        tab: tab,
        openBookCallback: (t, {int index = 1}) {
          context.read<TabsBloc>().add(OpenOrFocusTab(t, insertAdjacent: true));
        },
      );
    } else if (tab is PdfCommentatorsTab) {
      return PdfCommentatorsTabScreen(
        key: ValueKey(tab),
        tab: tab,
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
        key: ValueKey(tab),
        tab: tab,
        isInCombinedView: isInCombinedView,
        enableTourTargets: false,
      );
    } else if (tab is TextBookTab) {
      return BlocProvider.value(
          value: tab.bloc,
          child: TextBookViewerBloc(
            openBookCallback: (tab, {int index = 1}) {
              context
                  .read<TabsBloc>()
                  .add(OpenOrFocusTab(tab, insertAdjacent: true));
            },
            tab: tab,
            isInCombinedView: isInCombinedView,
            enableTourTargets: false,
          ));
    } else if (tab is SearchingTab) {
      return FullTextSearchScreen(tab: tab);
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

        return Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ספר ימני (בגלל RTL, זה יופיע בצד ימין)
                SizedBox(
                  width: rightWidth,
                  child: ClipRect(child: widget.buildTabView(widget.rightTab)),
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
                              _splitRatio =
                                  (_splitRatio + ratioDelta).clamp(0.2, 0.8);
                            });
                          },
                          onPanEnd: (_) =>
                              widget.onSplitRatioChanged(_splitRatio),
                        ),
                      ),
                    ],
                  ),
                ),
                // ספר שמאלי - Expanded כדי למלא את שאר המקום ללא גלישה
                Expanded(
                  child: ClipRect(child: widget.buildTabView(widget.leftTab)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
