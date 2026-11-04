import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  /// stub חסר state — אין מה לשכפל.
  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

void main() {
  late _TestTabsBloc tabsBloc;
  late _TestHistoryBloc historyBloc;
  late List<OpenedTab> tabs;
  late List<OpenedTab> closedTabs;

  Future<void> openMenu(
    WidgetTester tester, {
    List<String> openTitles = const ['בראשית', 'שמות', 'ויקרא'],
    List<String> closedTitles = const ['במדבר'],
  }) async {
    tabs = openTitles.map(_StubTab.new).toList();
    closedTabs = closedTitles.map(_StubTab.new).toList();
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0))
      ..closedTabs = closedTabs;
    historyBloc = _TestHistoryBloc();

    addTearDown(() async {
      await tabsBloc.close();
      await historyBloc.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: TabSearchButton(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TabSearchButton));
    await tester.pumpAndSettle();
  }

  testWidgets('הכפתור פותח חלונית עם שתי הרשימות', (tester) async {
    await openMenu(tester);

    expect(find.text('כרטיסיות פתוחות'), findsOneWidget);
    expect(find.text('נסגרו לאחרונה'), findsOneWidget);
    expect(find.text('בראשית'), findsOneWidget);
    expect(find.text('במדבר'), findsOneWidget);
  });

  testWidgets('הקלדה בשדה החיפוש מסננת את הרשימות', (tester) async {
    await openMenu(tester);

    await tester.enterText(find.byType(TextField), 'שמו');
    await tester.pumpAndSettle();

    expect(find.text('שמות'), findsOneWidget);
    expect(find.text('בראשית'), findsNothing);
    // הכותרת של סעיף ריק אינה מוצגת.
    expect(find.text('נסגרו לאחרונה'), findsNothing);
  });

  testWidgets('שאילתה ללא התאמות מציגה הודעה', (tester) async {
    await openMenu(tester);

    await tester.enterText(find.byType(TextField), 'איןכזה');
    await tester.pumpAndSettle();

    expect(find.text('אין כרטיסיות תואמות'), findsOneWidget);
  });

  testWidgets('לחיצה על כרטיסיה פתוחה ממקדת אותה וסוגרת את החלונית', (
    tester,
  ) async {
    await openMenu(tester);

    await tester.tap(find.text('ויקרא'));
    await tester.pumpAndSettle();

    final selected = tabsBloc.addedEvents.whereType<SetCurrentTab>().toList();
    expect(selected.single.index, 2);
    expect(find.text('כרטיסיות פתוחות'), findsNothing);
  });

  testWidgets('כפתור ה-X סוגר את הכרטיסיה ומשאיר את החלונית פתוחה', (
    tester,
  ) async {
    await openMenu(tester);

    await tester.tap(find.byTooltip('סגור כרטיסיה').first);
    await tester.pumpAndSettle();

    expect(
      tabsBloc.addedEvents.whereType<RemoveTab>().map((e) => e.tab),
      contains(same(tabs[0])),
    );
    expect(
      historyBloc.addedEvents.whereType<AddHistory>().map((e) => e.tab),
      contains(same(tabs[0])),
    );
    expect(find.text('כרטיסיות פתוחות'), findsOneWidget);
  });

  testWidgets('הקיצור סוגר חלונית פתוחה במקום לערום עוד אחת', (tester) async {
    await openMenu(tester);
    expect(find.byType(TabSearchPanel), findsOneWidget);

    // הקיצור אינו עובר דרך הכפתור: בחלונית פתוחה המחסום חוסם לחיצה עליו.
    final context = tester.element(find.byType(TabSearchButton));

    showTabSearchMenu(context);
    await tester.pumpAndSettle();
    expect(find.byType(TabSearchPanel), findsNothing);

    showTabSearchMenu(context);
    await tester.pumpAndSettle();
    expect(find.byType(TabSearchPanel), findsOneWidget);

    showTabSearchMenu(context);
    showTabSearchMenu(context);
    await tester.pumpAndSettle();
    expect(
      find.byType(TabSearchPanel),
      findsOneWidget,
      reason: 'שלוש הקשות רצופות אינן משאירות שתי חלוניות',
    );
  });

  testWidgets('"הצג את כל ההיסטוריה" סוגר את החלונית ופותח את ההיסטוריה', (
    tester,
  ) async {
    await openMenu(tester);

    await tester.tap(find.text('הצג את כל ההיסטוריה'));
    await tester.pumpAndSettle();

    expect(find.byType(TabSearchPanel), findsNothing);
    expect(find.byType(HistoryDialog), findsOneWidget);
  });

  testWidgets('לחיצה על כרטיסיה שנסגרה משחזרת אותה', (tester) async {
    await openMenu(tester);

    await tester.tap(find.text('במדבר'));
    await tester.pumpAndSettle();

    final restored = tabsBloc.addedEvents
        .whereType<RestoreClosedTab>()
        .toList();
    expect(restored.single.tab, same(closedTabs.single));
  });

  testWidgets('כפתור הניקוי מרוקן את רשימת הנסגרות לאחרונה (issue #1414)', (
    tester,
  ) async {
    await openMenu(tester);

    await tester.tap(find.byTooltip('נקה את הרשימה'));
    await tester.pumpAndSettle();

    expect(
      tabsBloc.addedEvents.whereType<ClearRecentlyClosedTabs>(),
      hasLength(1),
    );
    expect(find.text('נסגרו לאחרונה'), findsNothing);
    expect(find.text('במדבר'), findsNothing);
    // החלונית נשארת פתוחה והכרטיסיות הפתוחות אינן נוגעות בניקוי.
    expect(find.byType(TabSearchPanel), findsOneWidget);
    expect(find.text('בראשית'), findsOneWidget);
  });

  testWidgets('אין כפתור ניקוי כשאין כרטיסיות שנסגרו (issue #1414)', (
    tester,
  ) async {
    await openMenu(tester, closedTitles: const []);

    expect(find.text('נסגרו לאחרונה'), findsNothing);
    expect(find.byTooltip('נקה את הרשימה'), findsNothing);
  });

  testWidgets('חלונית פתוחה בחלון אחד אינה נסגרת מהפתיחה בחלון אחר', (
    tester,
  ) async {
    tabsBloc = _TestTabsBloc(
      TabsState(tabs: [_StubTab('בראשית')], currentTabIndex: 0),
    );
    historyBloc = _TestHistoryBloc();
    addTearDown(() async {
      await tabsBloc.close();
      await historyBloc.close();
    });
    final window = _FakeWindow();
    final a = AppWindowKeys();
    final b = AppWindowKeys();

    Widget windowTree(AppWindowKeys keys, String label) => AppWindowScope(
      controller: window,
      geometry: window,
      keys: keys,
      child: MaterialApp(
        navigatorKey: keys.navigator,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(children: [Text(label), const TabSearchButton()]),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
        ],
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              Expanded(child: windowTree(a, 'חלון א')),
              Expanded(child: windowTree(b, 'חלון ב')),
            ],
          ),
        ),
      ),
    );
    final contextA = tester.element(find.text('חלון א'));
    final contextB = tester.element(find.text('חלון ב'));
    Finder panelIn(AppWindowKeys keys) => find.descendant(
      of: find.byKey(keys.navigator),
      matching: find.byType(TabSearchPanel),
    );

    await tester.tap(find.byType(TabSearchButton).first);
    await tester.pumpAndSettle();
    expect(isTabSearchMenuOnTop(contextA), isTrue);
    expect(isTabSearchMenuOnTop(contextB), isFalse);

    // פתיחה ב-ב אינה מתפרשת כ"סגור את הפתוחה" של א.
    showTabSearchMenu(contextB);
    await tester.pumpAndSettle();
    expect(panelIn(a), findsOneWidget);
    expect(panelIn(b), findsOneWidget);

    showTabSearchMenu(contextB);
    await tester.pumpAndSettle();
    expect(panelIn(b), findsNothing);
    expect(panelIn(a), findsOneWidget);
  });

  group('ניווט בחיצים מהשדה אל הרשימה (issue #3485)', () {
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);
    const arrowDown = LogicalKeyboardKey.arrowDown;
    const arrowUp = LogicalKeyboardKey.arrowUp;
    const enter = LogicalKeyboardKey.enter;

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Iterable<int> selectedIndexes() =>
        tabsBloc.addedEvents.whereType<SetCurrentTab>().map((e) => e.index);

    testWidgets(
      '↓ עובר לרשומות, ↑ מהראשונה חוזר לשדה, ו-Enter ממקד את המסומנת',
      (tester) async {
        await openMenu(tester);

        for (final key in [arrowDown, arrowDown, arrowUp, arrowUp, enter]) {
          await press(tester, key);
        }
        expect(tabsBloc.addedEvents, isEmpty);
        expect(find.byType(TabSearchPanel), findsOneWidget);

        for (final key in [arrowDown, arrowDown, enter]) {
          await press(tester, key);
        }
        expect(selectedIndexes(), [1]);
        expect(find.byType(TabSearchPanel), findsNothing);
      },
      variant: windows,
    );

    testWidgets(
      'סינון מאפס את הסימון; ברשימה ריקה אין מה לבחור, ובמסוננת משחזרים',
      (tester) async {
        await openMenu(tester);
        for (final key in [arrowDown, arrowDown, arrowDown]) {
          await press(tester, key);
        }

        await tester.enterText(find.byType(TextField), 'איןכזה');
        await tester.pumpAndSettle();
        await press(tester, arrowDown);
        await press(tester, enter);
        expect(tabsBloc.addedEvents, isEmpty);
        expect(find.byType(TabSearchPanel), findsOneWidget);

        // "מ": "שמות" הפתוחה ו"במדבר" שנסגרה; החץ השלישי נשאר באחרונה.
        await tester.enterText(find.byType(TextField), 'מ');
        await tester.pumpAndSettle();
        for (final key in [arrowDown, arrowDown, arrowDown, enter]) {
          await press(tester, key);
        }
        final restored = tabsBloc.addedEvents.whereType<RestoreClosedTab>();
        expect(restored.single.tab, same(closedTabs.single));
        expect(selectedIndexes(), isEmpty);
      },
      variant: windows,
    );

    testWidgets(
      'סגירת הכרטיסיה המסומנת ב-X מעבירה את הסימון לזו שבאה במקומה',
      (tester) async {
        await openMenu(tester);

        await press(tester, arrowDown);
        await tester.tap(find.byTooltip('סגור כרטיסיה').first);
        await tester.pumpAndSettle();
        expect(find.text('בראשית'), findsNothing);

        await press(tester, enter);

        // אחרי הסגירה "שמות" היא הראשונה ברשימה.
        expect(selectedIndexes(), [0]);
        expect(find.byType(TabSearchPanel), findsNothing);
      },
      variant: windows,
    );

    testWidgets(
      'הרשומה המסומנת נגללת לתצוגה',
      (tester) async {
        await openMenu(
          tester,
          openTitles: [for (var i = 0; i < 30; i++) 'כרטיסיה $i'],
          closedTitles: const [],
        );
        expect(find.text('כרטיסיה 29').hitTestable(), findsNothing);

        for (var i = 0; i < 30; i++) {
          await press(tester, arrowDown);
        }

        expect(find.text('כרטיסיה 29').hitTestable(), findsOneWidget);
        await press(tester, enter);
        expect(selectedIndexes(), [29]);
      },
      variant: windows,
    );
  });
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  final List<TabsEvent> addedEvents = [];
  List<OpenedTab> closedTabs = const [];

  @override
  List<OpenedTab> get recentlyClosedTabs => closedTabs;

  /// הניקוי מדומה כמו ב-bloc האמיתי: הרשימה מתרוקנת, ו-`forceUpdate` הוא
  /// מה שמרענן את החלונית — הרשימה אינה חלק מה-state.
  @override
  void add(TabsEvent event) {
    addedEvents.add(event);
    if (event is ClearRecentlyClosedTabs) {
      closedTabs = const [];
      emit(state.copyWith(forceUpdate: true));
    }
    if (event is RemoveTab) {
      emit(
        state.copyWith(
          tabs: state.tabs.where((t) => !identical(t, event.tab)).toList(),
          currentTabIndex: 0,
        ),
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  final List<HistoryEvent> addedEvents = [];

  @override
  void add(HistoryEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
