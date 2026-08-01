import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';

import '../helpers/memory_settings_cache.dart';

/// בדיקת השרשרת המלאה של גרירת כרטיסיה לפיצול: הרצועה → מטען הגרירה →
/// יעד ההפלה → הגיאומטריה → אירוע ה-bloc → הטאב המפוצל → הרינדור.
///
/// כל חוליה נבדקת בנפרד בחבילות אחרות; כאן נבדק שהן מחוברות — באג שבו
/// הגרירה סימנה אזור אך השחרור לא פיצל בפועל נפל דווקא בין החוליות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  const tabWidth = 120.0;

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  List<String> titles(OpenedTab tab) =>
      leafPanes(tab).map((pane) => pane.title).toList();

  /// מסך קריאה מוקטן: אותה חיווט שב-`reading_screen`, בלי תוכן הספרים.
  Widget host(TabsBloc bloc, Map<String, int> initCounts) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocProvider<TabsBloc>.value(
          value: bloc,
          child: Scaffold(
            body: BlocBuilder<TabsBloc, TabsState>(
              builder: (context, state) {
                final current = state.currentTab;
                return Column(
                  children: [
                    SizedBox(
                      key: const Key('strip'),
                      height: 40,
                      child: ReadingTabStrip(
                        tabs: state.tabs,
                        widths: [for (final _ in state.tabs) tabWidth],
                        onReorder: (tab, index) =>
                            bloc.add(MoveTab(tab, index)),
                        tabBuilder: (tab, index, width) => SizedBox(
                          width: width,
                          child: ColoredBox(
                            color: const Color(0xFFDDDDDD),
                            child: Center(child: Text('טאב ${tab.title}')),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: current == null
                          ? const SizedBox.shrink()
                          : PaneDropTarget(
                              tab: current,
                              onDrop: (dragged, side) {
                                final incomingFirst =
                                    side == PaneDropSide.start;
                                bloc.add(
                                  EnableSideBySideMode(
                                    rightTab: incomingFirst ? dragged : current,
                                    leftTab: incomingFirst ? current : dragged,
                                  ),
                                );
                              },
                              child: SplitPaneView(
                                root: current,
                                onRatioChanged: (ratio) =>
                                    bloc.add(UpdateSplitRatio(ratio)),
                                paneBuilder: (pane) => _PaneBody(
                                  pane: pane,
                                  initCounts: initCounts,
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// מרימה מסך עם הכרטיסיות הנתונות ומחזירה את ה-bloc ומפת מוני ה-initState.
  Future<(TabsBloc, Map<String, int>)> pumpScreen(
    WidgetTester tester,
    List<OpenedTab> tabs,
  ) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    final initCounts = <String, int>{};
    addTearDown(() async => bloc.close());

    bloc.add(ReplaceAllTabs(tabs, 0));
    await tester.pumpWidget(host(bloc, initCounts));
    await tester.pumpAndSettle();
    return (bloc, initCounts);
  }

  Future<void> dragTab(
    WidgetTester tester,
    String title,
    Offset target,
  ) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('טאב $title')),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// מלבן החלונית עצמה ולא של הטקסט שבתוכה.
  Rect paneRect(WidgetTester tester, String title) => tester.getRect(
    find.ancestor(
      of: find.text('חלונית $title'),
      matching: find.byType(ClipRect),
    ),
  );

  Rect readingArea(WidgetTester tester) =>
      tester.getRect(find.byType(SplitPaneView));

  group('גרירה משורת הכרטיסיות אל אזור הקריאה', () {
    testWidgets('שחרור בחצי הימני ב-RTL מכניס את הנגררת מימין', (tester) async {
      final (bloc, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);

      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.right - 20, area.center.dy));

      expect(bloc.state.tabs, hasLength(1));
      final root = bloc.state.currentTab!;
      expect(root, isA<CombinedTab>());
      expect(titles(root), ['ב', 'א']);

      // שתי החלוניות מוצגות בפועל, והנגררת מימין.
      expect(find.text('חלונית א'), findsOneWidget);
      expect(find.text('חלונית ב'), findsOneWidget);
      expect(
        paneRect(tester, 'ב').center.dx,
        greaterThan(paneRect(tester, 'א').center.dx),
      );
      // הכרטיסיה יצאה מהרצועה — היא כבר חלונית.
      expect(find.text('טאב ב'), findsNothing);
    });

    testWidgets('שחרור בחצי השמאלי ב-RTL מכניס את הנגררת משמאל', (
      tester,
    ) async {
      final (bloc, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);

      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.left + 20, area.center.dy));

      final root = bloc.state.currentTab! as CombinedTab;
      expect(titles(root), ['א', 'ב']);
      expect(
        paneRect(tester, 'ב').center.dx,
        lessThan(paneRect(tester, 'א').center.dx),
      );
    });

    testWidgets('הגובה שבו משחררים אינו משנה', (tester) async {
      final (bloc, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);

      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.center.dx, area.bottom - 8));

      final root = bloc.state.currentTab!;
      expect(root, isA<CombinedTab>());
      expect(titles(root), ['ב', 'א']);
    });

    testWidgets('קו האמצע מפריד בין הצדדים גם בשחרור סמוך לו', (tester) async {
      // הצד נקבע לפי מיקום המצביע. הרצועה מסתמכת על
      // `pointerDragAnchorStrategy` כדי שיעד ההפלה יקבל אותו ולא את פינת
      // ה-feedback; בלעדיו שחרור סמוך לאמצע נופל לצד ההפוך.
      final (rightDrop, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);
      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.center.dx + 8, area.center.dy));
      expect(titles(rightDrop.state.currentTab!), ['ב', 'א']);

      final (leftDrop, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);
      await dragTab(tester, 'ב', Offset(area.center.dx - 8, area.center.dy));
      expect(titles(leftDrop.state.currentTab!), ['א', 'ב']);
    });

    testWidgets('טאב שכבר מפוצל אינו מקבל כרטיסייה שלישית', (tester) async {
      final (bloc, _) = await pumpScreen(tester, [
        leaf('א'),
        leaf('ב'),
        leaf('ג'),
      ]);

      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.right - 20, area.center.dy));
      // 'א' ו-'ב' התמזגו; 'ג' נשארה כרטיסייה בפני עצמה.
      expect(bloc.state.tabs, hasLength(2));

      // הפיצול השני נדחה: 'ג' נשארת בשורת הכרטיסיות.
      await dragTab(tester, 'ג', readingArea(tester).center);

      expect(bloc.state.tabs, hasLength(2));
      expect(leafPanes(bloc.state.currentTab!), hasLength(2));
      expect(find.text('טאב ג'), findsOneWidget);
      expect(find.text('חלונית ג'), findsNothing);
    });

    testWidgets('גרירת הכרטיסיה המוצגת על עצמה אינה משנה דבר', (tester) async {
      final (bloc, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);

      await dragTab(tester, 'א', readingArea(tester).center);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTab!.title, 'א');
      expect(bloc.state.currentTab, isNot(isA<CombinedTab>()));
    });
  });

  group('שימור מצב הקריאה', () {
    testWidgets('פיצול אינו בונה מחדש את החלונית שהייתה מוצגת', (tester) async {
      final (_, initCounts) = await pumpScreen(tester, [
        leaf('א'),
        leaf('ב'),
      ]);
      expect(initCounts['א'], 1);

      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.left + 20, area.center.dy));

      // המפתח היציב מעביר את ה-Element במקום להרוס אותו: בלי זה מיקום
      // הקריאה של הספר שהיה פתוח היה מתאפס בכל פיצול.
      expect(initCounts['א'], 1, reason: 'החלונית הקיימת לא נבנתה מחדש');
      expect(initCounts['ב'], 1);
    });

    testWidgets('סגירת חלונית אינה בונה מחדש את אחותה', (tester) async {
      final (bloc, initCounts) = await pumpScreen(tester, [
        leaf('א'),
        leaf('ב'),
      ]);
      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.left + 20, area.center.dy));

      final closing = (bloc.state.currentTab! as CombinedTab).leftTab;
      bloc.add(ClosePane(closing));
      await tester.pumpAndSettle();
      // חלון השחרור הדחוי של החלונית שנסגרה — בלי המתנה נשאר טיימר תלוי.
      await tester.pump(const Duration(milliseconds: 400));

      expect(bloc.state.currentTab!.title, 'א');
      expect(find.text('חלונית ב'), findsNothing);
      expect(initCounts['א'], 1, reason: 'האחות שנשארה לא נבנתה מחדש');
    });

    testWidgets('פירוק הפיצול אינו בונה מחדש את שתי החלוניות', (tester) async {
      final (bloc, initCounts) = await pumpScreen(tester, [
        leaf('א'),
        leaf('ב'),
      ]);
      final area = readingArea(tester);
      await dragTab(tester, 'ב', Offset(area.left + 20, area.center.dy));

      bloc.add(const DisableSideBySideMode(0));
      await tester.pumpAndSettle();

      expect(bloc.state.tabs, hasLength(2));
      expect(initCounts['א'], 1);
      expect(initCounts['ב'], 1);
    });
  });

  group('שחרור בתוך הרצועה', () {
    testWidgets('מסדר מחדש ואינו מפצל', (tester) async {
      final (bloc, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);

      final strip = tester.getRect(find.byKey(const Key('strip')));
      await dragTab(tester, 'ב', Offset(strip.right - 4, strip.center.dy));

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.tabs.map((t) => t.title), ['ב', 'א']);
      expect(bloc.state.currentTab, isNot(isA<CombinedTab>()));
    });

    testWidgets('שחרור באזור הריק של הרצועה אינו מפצל ואינו מסדר', (
      tester,
    ) async {
      final (bloc, _) = await pumpScreen(tester, [leaf('א'), leaf('ב')]);
      final before = bloc.state.tabs.map((t) => t.title).toList();

      final strip = tester.getRect(find.byKey(const Key('strip')));
      await dragTab(tester, 'ב', Offset(strip.left + 20, strip.center.dy));

      // מיקום ההכנסה בקצה הזורם הוא סוף הרשימה — כלומר המקום שממנו יצאה.
      expect(bloc.state.tabs.map((t) => t.title), before);
      expect(bloc.state.currentTab, isNot(isA<CombinedTab>()));
    });
  });
}

/// תוכן חלונית שמונה כמה פעמים נבנה ה-State שלו — כך נמדד שימור המצב.
class _PaneBody extends StatefulWidget {
  final OpenedTab pane;
  final Map<String, int> initCounts;

  const _PaneBody({required this.pane, required this.initCounts});

  @override
  State<_PaneBody> createState() => _PaneBodyState();
}

class _PaneBodyState extends State<_PaneBody> {
  @override
  void initState() {
    super.initState();
    widget.initCounts.update(
      widget.pane.title,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEEEEEE),
      child: Center(child: Text('חלונית ${widget.pane.title}')),
    );
  }
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs() => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  SideBySideMode? loadSideBySideMode() => null;

  @override
  Future<void> saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}
