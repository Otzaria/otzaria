// Responsive: חלוניות צד, פיצול, שורת כותרת וכרטיסיות בכל הרוחבים (320..1920),
// בצפיפות רגילה ומצומצמת, ובגובה 400. ראו שלב 1 ו-3 במשימת "השלמת מערכת
// העיצוב" (17.11.2026).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_navigation_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_tabs_bloc.dart';
import 'responsive_harness.dart';

/// כל הרוחבים בגובה 800, צפיפות מצומצמת בשלושה מהם, וגובה 400 ברוחב צר, בינוני
/// ורחב. מכסה את מה שהמשימה מבקשת מסרגל הכותרת והכרטיסיות (320..1920).
///
/// חלון מחשב אינו יורד מתחת ל-420 (`window_persistence.dart`): מתחת לזה זה
/// מכשיר מגע, בלי כפתורי חלון.
final List<ResponsiveViewport> _chromeViewports = [
  for (final w in responsiveWidths) ResponsiveViewport(w, 800, touch: w < 420),
  for (final w in const [320.0, 600.0, 1280.0])
    ResponsiveViewport(w, 800, compact: true, touch: w < 420),
  const ResponsiveViewport(320, 400, touch: true),
  const ResponsiveViewport(800, 400),
  const ResponsiveViewport(1920, 400),
  const ResponsiveViewport(320, 400, compact: true, touch: true),
];

PdfBookTab _tab(String title) => PdfBookTab(
  book: PdfBook(title: title, path: '/tmp/$title.pdf'),
  pageNumber: 1,
);

/// חלונית שאינה PDF, במקום טאב טקסט כבד (מנוע, מסד נתונים).
class _TextLikeTab extends OpenedTab {
  _TextLikeTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_TextLikeTab', 'title': title};
}

List<OpenedTab> _tabs(int count) => [
  for (var i = 0; i < count; i++) _tab('ספר מספר $i עם שם ארוך מאוד למדי'),
];

class _HistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<WorkspaceState> implements WorkspaceBloc {
  _WorkspaceBloc() : super(WorkspaceState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ה-providers של שורת הכותרת והעמודה, סביב האפליקציה.
Widget Function(Widget app) _tabsApp(
  List<OpenedTab> Function() makeTabs, {
  int current = 0,
  bool collapsed = false,
  double columnWidth = 220,
}) {
  return (app) {
    // הטאבים נוצרים בזמן ההרצה: היצירה קוראת ל-Settings, שמאותחל רק ב-setUpAll.
    final tabs = makeTabs();
    return AppWindowScope(
      controller: const WindowManagerAppWindowController(),
      geometry: const WindowManagerAppWindowController(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<WorkStatusCubit>(create: (_) => WorkStatusCubit()),
          BlocProvider<TabsBloc>.value(
            value: StubTabsBloc(
              TabsState(tabs: tabs, currentTabIndex: current),
            ),
          ),
          BlocProvider<NavigationBloc>.value(
            value: StubNavigationBloc(
              const NavigationState(currentScreen: Screen.reading),
            ),
          ),
          BlocProvider<SettingsBloc>.value(
            value: StubSettingsBloc(
              SettingsState.initial().copyWith(
                readingTabsPlacement:
                    SettingsRepository.readingTabsPlacementSide,
                readingTabsColumnCollapsed: collapsed,
                readingTabsColumnWidth: columnWidth,
              ),
            ),
          ),
          BlocProvider<WindowFullscreenCubit>(
            create: (_) =>
                WindowFullscreenCubit(initial: false, persist: (_) async {}),
          ),
          BlocProvider<HistoryBloc>.value(value: _HistoryBloc()),
          BlocProvider<WorkspaceBloc>.value(value: _WorkspaceBloc()),
        ],
        child: app,
      ),
    );
  };
}

/// תוכן ראשי שמסמן את גודלו, כדי לבדוק כמה מקום נשאר לו.
const _mainKey = ValueKey('main-content');

// autofocus: במסך אמיתי הפוקוס בתוכן הקריאה, ושם Esc מגיע לחלונית.
Widget _main() => const Focus(
  autofocus: true,
  child: SizedBox.expand(
    key: _mainKey,
    child: Center(child: Text('תוכן הספר')),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // ── שורת כותרת וכרטיסיות ──────────────────────────────────────────────────
  for (final count in const [3, 35]) {
    testResponsive(
      'שורת הכותרת עם $count כרטיסיות',
      viewports: _chromeViewports,
      scaffold: false,
      wrapApp: _tabsApp(() => _tabs(count), current: count > 5 ? 20 : 0),
      build: (_) => const Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: CustomTitleBar(),
        ),
      ),
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(CustomTitleBar),
          name: 'שורת הכותרת',
        );
      },
    );
  }

  for (final count in const [3, 35]) {
    for (final collapsed in const [false, true]) {
      testResponsive(
        'עמודת כרטיסיות בצד, $count כרטיסיות${collapsed ? ', מכווצת' : ''}',
        viewports: [
          for (final v in _chromeViewports)
            // העמודה מוצגת מ-600 (או בחלון נמוך).
            if (v.width >= 600 || v.height < 480) v,
        ],
        scaffold: false,
        wrapApp: _tabsApp(
          () => _tabs(count),
          collapsed: collapsed,
          // שמור גדול מכל חלון צר: העמודה חייבת להשאיר מקום לתוכן.
          columnWidth: 400,
        ),
        build: (context) => Scaffold(
          body: Row(
            children: [
              SizedBox(width: LayoutConstraints.navRailWidth),
              Expanded(
                child: ReadingTabsSidePanel(show: true, child: _main()),
              ),
            ],
          ),
        ),
        verify: (tester, run) async {
          final content = tester.getSize(find.byKey(_mainKey)).width;
          final area =
              tester.view.physicalSize.width - LayoutConstraints.navRailWidth;
          // התוכן שומר מקום מזערי, כשיש מקום בכלל.
          final expected = area > LayoutConstraints.minContentBesideTabsColumn
              ? LayoutConstraints.minContentBesideTabsColumn
              : 0.0;
          if (collapsed) return;
          if (content + 0.5 < expected) {
            run.add(
              ResponsiveIssue(
                'content-starved',
                'לתוכן נשארו $content, פחות מ-$expected',
              ),
            );
          }
        },
      );
    }
  }

  // ── חלונית צד נעוצה ───────────────────────────────────────────────────────
  for (final pinned in const [true, false]) {
    testResponsive(
      'NavSidePanel ${pinned ? 'נעוצה' : 'צפה'}, רוחב שמור 340',
      scaffold: false,
      viewports: _chromeViewports,
      build: (_) => Scaffold(
        body: NavSidePanel(
          isOpen: true,
          isPinned: pinned,
          paneWidth: 340,
          minMainContentWidth: 520,
          isResizable: true,
          minPaneWidth: 200,
          maxPaneWidth: 600,
          autoHandleResponsiveVisibility: false,
          onClose: () {},
          mainContent: _main(),
          paneContent: const Center(child: Text('תוכן החלונית')),
        ),
      ),
      verify: (tester, run) async {
        final width = tester.view.physicalSize.width;
        final main = tester.getRect(find.byKey(_mainKey));
        final pane = tester.getRect(find.text('תוכן החלונית'));
        expectInsideViewport(
          tester,
          run,
          find.text('תוכן החלונית'),
          name: 'תוכן החלונית',
        );
        // נעוצה בחלון שיש בו מקום: התוכן הראשי שומר את המזערי שלו.
        if (pinned && width >= 340 + 520 && main.width + 0.5 < 520) {
          run.add(
            ResponsiveIssue(
              'content-starved',
              'לתוכן הראשי נשארו ${main.width}',
            ),
          );
        }
        if (pane.width <= 0) {
          run.add(const ResponsiveIssue('pane', 'החלונית ללא רוחב'));
        }
      },
    );
  }

  // ── חלונית שנסגרת בכל רוחב: הצללה, Esc, או כפתור ──────────────────────────
  testResponsive(
    'חלונית נעוצה נסגרת ב-Esc כשהיא שכבה, ודוחקת כשיש מקום',
    scaffold: false,
    viewports: _chromeViewports,
    build: (_) => const _CloseableHarness(),
    verify: (tester, run) async {
      final state = tester.state<_CloseableHarnessState>(
        find.byType(_CloseableHarness),
      );
      final overlays = state.lastPushMode == false;
      if (overlays) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        if (state.isOpen) {
          run.add(
            const ResponsiveIssue('close', 'שכבה שלא נסגרת ב-Esc'),
          );
        }
      } else {
        // דחיקה: אין הצללה, והתוכן שומר את המזערי שלו.
        final main = tester.getRect(find.byKey(_mainKey));
        if (main.width + 0.5 < 520) {
          run.add(
            ResponsiveIssue('content-starved', 'לתוכן נשארו ${main.width}'),
          );
        }
      }
    },
  );

  // ── מצבי תוכן של החלונית: ריקה, טעינה, שגיאה ──────────────────────────────
  final paneStates = <String, Widget>{
    'ריקה': const SizedBox.shrink(),
    'טעינה': const Center(
      // ערך קבוע: אינדיקטור מסתובב אינסופי היה תוקע את pumpAndSettle.
      child: CircularProgressIndicator(value: 0.3),
    ),
    'שגיאה': Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'הטעינה נכשלה: הודעת שגיאה ארוכה מאוד שחוזרת על עצמה כדי לבדוק '
            'התנהגות בחלונית צרה',
            textAlign: TextAlign.center,
          ),
          TextButton(onPressed: () {}, child: const Text('נסה שוב')),
        ],
      ),
    ),
  };
  for (final entry in paneStates.entries) {
    testResponsive(
      'חלונית נעוצה במצב "${entry.key}"',
      scaffold: false,
      viewports: _chromeViewports,
      build: (_) => _CloseableHarness(paneContent: entry.value),
      verify: (tester, run) async {
        if (entry.key == 'שגיאה') {
          expectReachable(
            tester,
            run,
            find.text('נסה שוב'),
            name: 'כפתור "נסה שוב"',
          );
        }
      },
    );
  }

  // ── ContextOverlayPanel ───────────────────────────────────────────────────
  testResponsive(
    'ContextOverlayPanel נשארת בגבולות החלון',
    scaffold: false,
    viewports: _chromeViewports,
    build: (_) => Scaffold(
      body: Stack(
        children: [
          _main(),
          ContextOverlayPanel(
            isOpen: true,
            width: 400,
            onClose: () {},
            title: 'הגדרות',
            child: const Center(child: Text('תוכן הפאנל')),
          ),
        ],
      ),
    ),
    verify: (tester, run) async {
      expectInsideViewport(
        tester,
        run,
        find.text('תוכן הפאנל'),
        name: 'תוכן הפאנל',
      );
    },
  );

  // ── פיצול כרטיסיות ────────────────────────────────────────────────────────
  testResponsive(
    'SplitPaneView: שתי חלוניות עם סרגל פנימי',
    scaffold: false,
    // מתחת ל-420 שתי חלוניות נותנות לכל סרגל פחות מ-210, ושלושה כפתורי 48
    // גולשים: פיצול קיים בחלון צר הוא שאלה פתוחה (DESIGN_DECISIONS). הסרגל
    // לא נגלל: גלילה הייתה מסתירה את הפעולות מסרגלים שמסתגלים לרוחב
    // (סרגל הקורא) ושוברת את ההתאמה שלהם.
    viewports: [
      for (final v in _chromeViewports)
        if (v.width >= 420) v,
    ],
    build: (_) {
      final root = CombinedTab(
        rightTab: _tab('ימין'),
        // PDF לצד ספר טקסט: שני סוגי חלוניות באותו פיצול.
        leftTab: _TextLikeTab('שמאל'),
      );
      return Scaffold(
        body: SplitPaneView(
          root: root,
          onRatioChanged: (_) {},
          paneBuilder: (pane) => Column(
            children: [
              AppTopBar(
                leadingItems: [
                  AppTopBarItem(
                    widget: AppIconButton(
                      tooltip: 'תפריט',
                      icon: const Icon(FluentIcons.navigation_24_regular),
                      onPressed: () {},
                    ),
                  ),
                  AppTopBarItem(
                    widget: AppIconButton(
                      tooltip: 'חזרה',
                      icon: const Icon(FluentIcons.arrow_left_24_regular),
                      onPressed: () {},
                    ),
                  ),
                  AppTopBarItem(
                    widget: AppIconButton(
                      tooltip: 'נעיצה',
                      icon: const Icon(FluentIcons.pin_24_regular),
                      onPressed: () {},
                    ),
                  ),
                ],
                center: Text(pane.title, overflow: TextOverflow.ellipsis),
                trailingItems: const [],
              ),
              Expanded(child: Center(child: Text('תוכן ${pane.title}'))),
            ],
          ),
        ),
      );
    },
    verify: (tester, run) async {
      for (final title in const ['ימין', 'שמאל']) {
        final pane = find.text('תוכן $title');
        expectVisible(tester, run, pane, name: 'חלונית $title');
      }
      await expectReachable(
        tester,
        run,
        find.byTooltip('נעיצה').first,
        name: 'כפתור נעיצה בחלונית',
      );
    },
  );
}

/// חלונית נעוצה (NavSidePanel) שאפשר לסגור, ומדווחת באיזה מצב היא.
class _CloseableHarness extends StatefulWidget {
  const _CloseableHarness({this.paneContent});

  /// null: תוכן רגיל. אחרת מצב מיוחד של החלונית (ריקה, טעינה, שגיאה).
  final Widget? paneContent;

  @override
  State<_CloseableHarness> createState() => _CloseableHarnessState();
}

class _CloseableHarnessState extends State<_CloseableHarness> {
  bool isOpen = true;
  bool? lastPushMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NavSidePanel(
        isOpen: isOpen,
        isPinned: true,
        paneWidth: 340,
        minMainContentWidth: 520,
        isResizable: true,
        minPaneWidth: 200,
        maxPaneWidth: 600,
        autoHandleResponsiveVisibility: false,
        onClose: () => setState(() => isOpen = false),
        onLayoutModeChanged: (push) => lastPushMode = push,
        mainContent: _main(),
        paneContent:
            widget.paneContent ?? const Center(child: Text('תוכן החלונית')),
      ),
    );
  }
}
