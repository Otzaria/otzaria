import 'package:flutter/gestures.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';
import 'package:otzaria/tabs/utils/tab_content_vertical_drag_recognizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// אימות התנהגותי של `MoveTab` על ה-`ReadingScreen` האמיתי: אחרי הזזה,
/// ה-`State` של מסך הטאב חייב להיות *אותו מופע*. ב-PDF זה ההבדל בין
/// "המסמך נשאר פתוח" לבין "dispose סוגר אותו ו-initState טוען מהדיסק".
///
/// `PdfBookScreen` דורש pdfrx נייטיב ולכן אינו ניתן להרכבה כאן;
/// `PdfCommentatorsTab` עובר באותו `_buildTabView` עם אותו פרופיל keepAlive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<TabsBloc> pumpReadingScreen(
    WidgetTester tester,
    List<OpenedTab> tabs, {
    int currentTabIndex = 0,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(bloc.close);
    bloc.emit(
      TabsState(
        tabs: tabs,
        currentTabIndex: currentTabIndex,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: _FakeSettingsBloc()),
            BlocProvider<PersonalNotesBloc>.value(
              value: _FakePersonalNotesBloc(),
            ),
            BlocProvider<TabsBloc>.value(value: bloc),
            BlocProvider<HistoryBloc>.value(value: _FakeHistoryBloc()),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: const ReadingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return bloc;
  }

  State? tabScreenState(WidgetTester tester, String title) {
    final finder = find.byWidgetPredicate(
      (w) => w is PdfCommentatorsTabScreen && w.tab.title.contains(title),
      skipOffstage: false,
    );
    if (finder.evaluate().isEmpty) return null;
    return tester.state(finder);
  }

  /// מבקר בכל טאב כדי שכל ה-Stateים ייבנו וישמרו חיים (keepAlive) —
  /// טאב שמעולם לא הוצג פשוט אינו בעץ ואין מה לשמר.
  Future<void> visitAllTabs(
    WidgetTester tester,
    TabsBloc bloc,
    int backTo,
  ) async {
    for (var i = 0; i < bloc.state.tabs.length; i++) {
      bloc.add(SetCurrentTab(i));
      await tester.pumpAndSettle();
    }
    bloc.add(SetCurrentTab(backTo));
    await tester.pumpAndSettle();
  }

  testWidgets('מחוות מעבר טאבים בדסקטופ: trackpad, ומגע במזהה נפרד', (
    tester,
  ) async {
    final tabs = [_tab('א')];
    addTearDown(tabs.single.dispose);
    await pumpReadingScreen(tester, tabs);

    final detectorFinder = find.byWidgetPredicate(
      (widget) => widget is RawGestureDetector && widget.child is PageView,
    );
    expect(detectorFinder, findsOneWidget);

    final detector = tester.widget<RawGestureDetector>(detectorFinder);
    final factory = detector.gestures[HorizontalDragGestureRecognizer];
    expect(factory, isNotNull);

    final recognizer =
        factory!.constructor() as HorizontalDragGestureRecognizer;
    addTearDown(recognizer.dispose);
    expect(recognizer.supportedDevices, const {PointerDeviceKind.trackpad});

    final touchFactory = detector.gestures[TouchTabSwipeRecognizer];
    expect(touchFactory, isNotNull);
    final touch = touchFactory!.constructor() as TouchTabSwipeRecognizer;
    addTearDown(touch.dispose);
    expect(touch.supportedDevices, const {PointerDeviceKind.touch});

    // ה"בולען" האנכי — המתחרה שמונע מהאופקי לזכות מיד כחבר יחיד בזירה
    // מעל תוכן ללא Scrollable (WebView של תוסף).
    final verticalFactory = detector.gestures[TabContentVerticalDragRecognizer];
    expect(verticalFactory, isNotNull);
    final vertical =
        verticalFactory!.constructor() as VerticalDragGestureRecognizer;
    addTearDown(vertical.dispose);
    expect(vertical.supportedDevices, const {
      PointerDeviceKind.trackpad,
      PointerDeviceKind.touch,
    });
  });

  testWidgets('הבולען האנכי לא גובר על גלילת ה-PDF במגע (#1982)', (
    tester,
  ) async {
    final tabs = [_tab('א')];
    addTearDown(tabs.single.dispose);
    await pumpReadingScreen(tester, tabs);
    final detector = tester.widget<RawGestureDetector>(
      find.byWidgetPredicate(
        (widget) => widget is RawGestureDetector && widget.child is PageView,
      ),
    );

    var contentPanUpdates = 0;
    await tester.pumpWidget(
      RawGestureDetector(
        gestures: {
          TabContentVerticalDragRecognizer:
              detector.gestures[TabContentVerticalDragRecognizer]!,
        },
        // מדמה את ה-InteractiveViewer של pdfrx (ScaleGestureRecognizer).
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleUpdate: (_) => contentPanUpdates++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      const Offset(300, 300),
      kind: PointerDeviceKind.touch,
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
    }
    await gesture.up();
    await tester.pump();

    expect(contentPanUpdates, greaterThan(0));
  });

  testWidgets('גלילה אנכית ב-trackpad אינה גוררת את ה-PageView', (
    tester,
  ) async {
    // טאב אמצעי — בקצה ה-clamp על minScrollExtent היה מסתיר את הרעד.
    final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
    addTearDown(() {
      for (final t in tabs) {
        t.dispose();
      }
    });
    final bloc = await pumpReadingScreen(tester, tabs, currentTabIndex: 1);

    final center = tester.getCenter(find.byType(PageView));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    // גלילה אנכית מהירה עם ג'יטר אופקי קל — הפרופיל של גלילת תוכן אמיתית.
    for (var i = 1; i <= 6; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(i.isEven ? 3.0 : -3.0, -80.0 * i),
        timeStamp: Duration(milliseconds: 10 * i),
      );
      await tester.pump();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
        reason: 'מחווה אנכית אסור שתזיז את התצוגה — גם לא רעד רגעי',
      );
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 70));
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.page, 1);
    expect(bloc.state.currentTabIndex, 1);
  });

  testWidgets('גלילה אלכסונית בעיקר אנכית ב-WebView אינה מעבירה טאב', (
    tester,
  ) async {
    final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
    addTearDown(() {
      for (final tab in tabs) {
        tab.dispose();
      }
    });
    final bloc = await pumpReadingScreen(tester, tabs, currentTabIndex: 1);
    final detector = tester.widget<RawGestureDetector>(
      find.byWidgetPredicate(
        (widget) => widget is RawGestureDetector && widget.child is PageView,
      ),
    );
    // WebView נייטיבי לא מוסיף מזהה גלילה לזירת המחוות של Flutter.
    final overlay = Overlay.of(tester.element(find.byType(PageView)));
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: RawGestureDetector(
          gestures: detector.gestures,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );
    overlay.insert(entry);
    addTearDown(() {
      entry.remove();
      entry.dispose();
    });
    await tester.pump();
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(400, 400);
    await gesture.panZoomStart(center);
    const pans = [Offset(5, -20), Offset(20, -60), Offset(35, -110)];
    for (var i = 0; i < pans.length; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: pans[i],
        timeStamp: Duration(milliseconds: 10 * (i + 1)),
      );
      await tester.pump();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        1,
      );
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(bloc.state.currentTabIndex, 1);
  });

  group('החלקת trackpad — גרירה הדרגתית והתיישבות', () {
    PageController pageControllerOf(WidgetTester tester) =>
        tester.widget<PageView>(find.byType(PageView)).controller!;

    testWidgets('גרירה קצרה מזיזה את התצוגה בהדרגה וחוזרת לטאב הנוכחי', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);

      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(center, timeStamp: Duration.zero);
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(-200, 0),
        timeStamp: const Duration(milliseconds: 50),
      );
      await tester.pump();

      final midDragPage = pageControllerOf(tester).page!;
      expect(
        midDragPage,
        greaterThan(0.05),
        reason: 'הגרירה חייבת להזיז את התצוגה בהדרגה, לא לחכות לסף',
      );
      expect(midDragPage, lessThan(0.5));
      expect(bloc.state.currentTabIndex, 0);

      // עצירה לפני השחרור — מאפסת את מהירות ההנפה.
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(-200, 0),
        timeStamp: const Duration(milliseconds: 300),
      );
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(-200, 0),
        timeStamp: const Duration(milliseconds: 350),
      );
      await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(pageControllerOf(tester).page, 0);
      expect(bloc.state.currentTabIndex, 0);
    });

    testWidgets('גרירה מעבר למחצית הדרך מתיישבת על הטאב הסמוך', (tester) async {
      final tabs = [_tab('א'), _tab('ב')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);

      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(center, timeStamp: Duration.zero);
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(-900, 0),
        timeStamp: const Duration(milliseconds: 100),
      );
      await tester.pump();
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(-900, 0),
        timeStamp: const Duration(milliseconds: 350),
      );
      await gesture.panZoomUpdate(
        center,
        pan: const Offset(-900, 0),
        timeStamp: const Duration(milliseconds: 400),
      );
      await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(bloc.state.currentTabIndex, 1);
      expect(pageControllerOf(tester).page, 1);
    });

    testWidgets('הנפה מהירה מעבירה טאב גם לפני מחצית הדרך', (tester) async {
      final tabs = [_tab('א'), _tab('ב')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);

      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(center, timeStamp: Duration.zero);
      for (var i = 1; i <= 5; i++) {
        await gesture.panZoomUpdate(
          center,
          pan: Offset(-30.0 * i, 0),
          timeStamp: Duration(milliseconds: 10 * i),
        );
      }
      await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(bloc.state.currentTabIndex, 1);
      expect(pageControllerOf(tester).page, 1);
    });
  });

  group('ReadingScreen + MoveTab — שימור State', () {
    testWidgets('גרירת הטאב הראשון לסוף: כל הטאבים שומרים State', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      final before = {
        for (final t in ['א', 'ב', 'ג']) t: tabScreenState(tester, t),
      };
      expect(before.values, everyElement(isNotNull));

      bloc.add(MoveTab(tabs[0], 2));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['ב', 'ג', 'א']);
      for (final t in ['א', 'ב', 'ג']) {
        expect(
          identical(tabScreenState(tester, t), before[t]),
          isTrue,
          reason: 'ה-State של "$t" הוחלף — ב-PDF זה dispose וטעינה מחדש',
        );
      }
      // הטאב שנגרר היה הפעיל — ההדגשה עוקבת אחריו למיקום החדש.
      expect(bloc.state.currentTabIndex, 2);
      expect(_short(bloc.state.currentTab!.title), 'א');
    });

    testWidgets('הזזה אחורה: הטאב האחרון לראש, כל ה-Stateים נשמרים', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 2);

      final before = {
        for (final t in ['א', 'ב', 'ג']) t: tabScreenState(tester, t),
      };

      bloc.add(MoveTab(tabs[2], 0));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['ג', 'א', 'ב']);
      for (final t in ['א', 'ב', 'ג']) {
        expect(identical(tabScreenState(tester, t), before[t]), isTrue);
      }
    });
  });

  group('ReadingScreen - unchanged tabs are not rebuilt', () {
    Widget tabScreenWidget(WidgetTester tester, String title) => tester.widget(
      find.byWidgetPredicate(
        (w) => w is PdfCommentatorsTabScreen && w.tab.title.contains(title),
        skipOffstage: false,
      ),
    );

    testWidgets('switching tabs reuses the content of the other tabs', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      final before = tabScreenWidget(tester, 'ג');
      bloc.add(const SetCurrentTab(1));
      await tester.pumpAndSettle();

      expect(
        identical(tabScreenWidget(tester, 'ג'), before),
        isTrue,
        reason: 'a background tab that did not change must not be rebuilt',
      );
    });

    testWidgets('an in-place tab update still rebuilds the tab content', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      final before = tabScreenWidget(tester, 'ב');
      bloc.add(TogglePinTab(tabs[1]));
      await tester.pumpAndSettle();

      expect(identical(tabScreenWidget(tester, 'ב'), before), isFalse);
    });

    testWidgets('replacing a tab does not rebuild the other tabs', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      final replacement = _tab('ד');
      addTearDown(() {
        for (final t in [tabs[0], tabs[1], replacement]) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      final before = {
        for (final t in ['א', 'ב']) t: tabScreenWidget(tester, t),
      };
      bloc.add(ReplaceTab(oldTab: tabs[2], newTab: replacement));
      await tester.pumpAndSettle();
      // ההחלפה משחררת את הטאב הישן בהשהיה.
      await tester.pump(const Duration(milliseconds: 400));

      expect(_titles(bloc), ['א', 'ב', 'ד']);
      for (final t in ['א', 'ב']) {
        expect(
          identical(tabScreenWidget(tester, t), before[t]),
          isTrue,
          reason: 'only the replaced tab changed; "$t" must not be rebuilt',
        );
      }
    });

    testWidgets('splitting and unsplitting do not rebuild unrelated tabs', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 1);

      final before = tabScreenWidget(tester, 'א');
      Future<void> expectUnrelatedTabKept(TabsEvent event) async {
        bloc.add(event);
        await tester.pumpAndSettle();
        expect(
          identical(tabScreenWidget(tester, 'א'), before),
          isTrue,
          reason: '${event.runtimeType} must not rebuild an unrelated tab',
        );
      }

      await expectUnrelatedTabKept(
        CreateCombinedTab(rightTab: tabs[1], leftTab: tabs[2]),
      );
      await expectUnrelatedTabKept(const SwapSideBySideTabs());
      await expectUnrelatedTabKept(const ExpandCombinedTab(1));
      await expectUnrelatedTabKept(
        CreateCombinedTab(rightTab: tabs[1], leftTab: tabs[2]),
      );
      await expectUnrelatedTabKept(DetachPane(tabs[2], insertIndex: 2));
      final extra = _tab('ה');
      await expectUnrelatedTabKept(OpenTabInSidePane(extra));
      // הבלוק משחרר את החלונית שנסגרה בהשהיה.
      await expectUnrelatedTabKept(ClosePane(extra));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_titles(bloc), ['א', 'ב', 'ג']);
    });

    testWidgets('committing a split ratio does not rebuild any tab content', (
      tester,
    ) async {
      final background = [_tab('א'), _tab('ב'), _tab('ג')];
      final split = CombinedTab(rightTab: _tab('ד'), leftTab: _tab('ה'));
      final tabs = <OpenedTab>[...background, split];
      addTearDown(() {
        for (final t in [...background, split.rightTab, split.leftTab]) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 3);

      const titles = ['א', 'ב', 'ג', 'ד', 'ה'];
      final before = {for (final t in titles) t: tabScreenWidget(tester, t)};
      split.splitRatio = 0.7;
      bloc.add(const UpdateSplitRatio(0.7));
      await tester.pumpAndSettle();

      expect(split.splitRatio, 0.7);
      for (final t in titles) {
        expect(
          identical(tabScreenWidget(tester, t), before[t]),
          isTrue,
          reason: 'the ratio is already on screen; "$t" must not be rebuilt',
        );
      }
    });
  });

  group('ReadingScreen — ה-PageView עוקב אחרי הטאב הפעיל', () {
    double displayedPage(WidgetTester tester) {
      final pageView = tester.widget<PageView>(find.byType(PageView));
      return pageView.controller!.page!;
    }

    testWidgets('הזזת הטאב הפעיל — התצוגה קופצת למיקום החדש', (tester) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      bloc.add(MoveTab(tabs[0], 2));
      await tester.pumpAndSettle();

      expect(bloc.state.currentTabIndex, 2);
      expect(displayedPage(tester), 2);
    });

    testWidgets('הזזת טאב רקע — הנגרר נבחר והתצוגה עוברת אליו', (
      tester,
    ) async {
      final tabs = [_tab('א'), _tab('ב'), _tab('ג'), _tab('ד')];
      addTearDown(() {
        for (final t in tabs) {
          t.dispose();
        }
      });
      final bloc = await pumpReadingScreen(tester, tabs);
      await visitAllTabs(tester, bloc, 0);

      // "ד" מהסוף למקום 1 — כמו בדפדפן, הנגרר הופך לטאב המוצג (issue #1104).
      bloc.add(MoveTab(tabs[3], 1));
      await tester.pumpAndSettle();

      expect(_titles(bloc), ['א', 'ד', 'ב', 'ג']);
      expect(bloc.state.currentTabIndex, 1);
      expect(
        displayedPage(tester),
        1,
        reason: 'הטאב שנגרר נבחר — התצוגה חייבת לעבור אליו',
      );
    });
  });
}

/// כותרות הטאבים ללא הקידומת "מפרשים | " שמוסיף [PdfCommentatorsTab].
List<String> _titles(TabsBloc bloc) =>
    bloc.state.tabs.map((t) => _short(t.title)).toList();

String _short(String title) => title.replaceFirst('מפרשים | ', '');

/// כרטסיית מפרשים קלה שנטענת סינכרונית — טאב אמיתי לכל דבר.
PdfCommentatorsTab _tab(String title) {
  final sourceTab = PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );
  sourceTab.pdfHeadings = PdfHeadings(
    bookTitle: title,
    headingsMap: {'פרק א': 1},
  );
  sourceTab.currentTitle.value = 'פרק א';
  sourceTab.currentTextLineNumber = 1;
  sourceTab.currentTextLineNumberEnd = 9;
  return PdfCommentatorsTab(sourceTab: sourceTab);
}

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return <OpenedTab>[];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
