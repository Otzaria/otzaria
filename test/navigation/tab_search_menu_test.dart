import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
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
import 'package:otzaria/tabs/reading_screen.dart';

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
    Map<OpenedTab, FocusNode>? paneFocusNodes,
    List<OpenedTab>? contentFocusRequests,
  }) async {
    tabs = openTitles.map(_StubTab.new).toList();
    closedTabs = closedTitles.map(_StubTab.new).toList();
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0))
      ..closedTabs = closedTabs;
    historyBloc = _TestHistoryBloc();
    final focusRepository = FocusRepository.forWindow(AppWindowKeys());
    if (paneFocusNodes != null) {
      for (final tab in [...tabs, ...closedTabs]) {
        final node = FocusNode(debugLabel: tab.title);
        paneFocusNodes[tab] = node;
        focusRepository.registerTabContentFocusRequester(tab, () {
          contentFocusRequests?.add(tab);
          node.requestFocus();
        });
      }
    }

    addTearDown(() async {
      for (final entry
          in paneFocusNodes?.entries ?? <MapEntry<OpenedTab, FocusNode>>[]) {
        focusRepository.unregisterTabContentFocusRequester(entry.key);
        entry.value.dispose();
      }
      await tabsBloc.close();
      await historyBloc.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          RepositoryProvider<FocusRepository>.value(value: focusRepository),
        ],
        child: MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                if (paneFocusNodes != null) ...[
                  const ReadingScreen(),
                  BlocBuilder<TabsBloc, TabsState>(
                    builder: (context, state) => Stack(
                      children: [
                        for (final tab in state.tabs)
                          ExcludeFocus(
                            key: ObjectKey(tab),
                            excluding: !identical(tab, state.activePane),
                            child: Focus(
                              focusNode: paneFocusNodes[tab],
                              child: const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const Align(
                  alignment: Alignment.topRight,
                  child: TabSearchButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (paneFocusNodes != null) {
      paneFocusNodes[tabs.first]!.requestFocus();
      await tester.pump();
      // קיצור המקלדת פותח מהקורא בלי להעביר קודם פוקוס לכפתור.
      showTabSearchMenu(tester.element(find.byType(TabSearchButton)));
    } else {
      await tester.tap(find.byType(TabSearchButton));
    }
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
    final nodes = <OpenedTab, FocusNode>{};
    final focusRequests = <OpenedTab>[];
    await openMenu(
      tester,
      paneFocusNodes: nodes,
      contentFocusRequests: focusRequests,
    );
    await tester.tap(find.byTooltip('סגור כרטיסיה').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('הצג את כל ההיסטוריה'));
    await tester.pumpAndSettle();

    expect(find.byType(TabSearchPanel), findsNothing);
    expect(find.byType(HistoryDialog), findsOneWidget);
    expect(focusRequests, isEmpty);
    expect(nodes.values.any((node) => node.hasFocus), isFalse);
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
        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        final selection = controller.selection;
        await press(tester, arrowDown);
        expect(controller.selection, selection);
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

    testWidgets('סגירת הכרטיסיה המסומנת ב-X מעבירה את הסימון לזו שבאה במקומה', (
      tester,
    ) async {
      await openMenu(tester);

      await press(tester, arrowDown);
      await tester.tap(find.byTooltip('סגור כרטיסיה').first);
      await tester.pumpAndSettle();
      expect(find.text('בראשית'), findsNothing);

      await press(tester, enter);

      // אחרי הסגירה "שמות" היא הראשונה ברשימה.
      expect(selectedIndexes(), [0]);
      expect(find.byType(TabSearchPanel), findsNothing);
    }, variant: windows);

    testWidgets('הרשומה המסומנת נגללת לתצוגה', (tester) async {
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
    }, variant: windows);

    Finder resultsScrollable() => find.descendant(
      of: find.byType(TabSearchPanel),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );

    FocusNode fieldFocus(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).focusNode!;

    for (final alreadyHighlighted in [false, true]) {
      testWidgets(
        'חץ חושף רשומה לא בנויה אחרי גלילה ידנית (סימון קודם: $alreadyHighlighted)',
        (tester) async {
          await openMenu(
            tester,
            openTitles: [for (var i = 0; i < 60; i++) 'כרטיסיה $i'],
            closedTitles: const [],
          );
          if (alreadyHighlighted) await press(tester, arrowDown);

          await tester.drag(resultsScrollable(), const Offset(0, -3000));
          await tester.pumpAndSettle();
          expect(find.text('כרטיסיה 59').hitTestable(), findsOneWidget);
          final expectedIndex = alreadyHighlighted ? 1 : 0;
          expect(find.text('כרטיסיה $expectedIndex'), findsNothing);

          await press(tester, arrowDown);
          expect(
            find.text('כרטיסיה $expectedIndex').hitTestable(),
            findsOneWidget,
          );
          expect(fieldFocus(tester).hasFocus, isTrue);
          await press(tester, enter);
          expect(selectedIndexes(), [expectedIndex]);
        },
        variant: windows,
      );
    }

    testWidgets('Alt+Shift+Down בוחר טקסט בעברית ואינו מסמן רשומה', (
      tester,
    ) async {
      await openMenu(tester, openTitles: const ['כרטיסיה']);
      await tester.enterText(find.byType(TextField), 'כרטיסיה');
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
      await press(tester, enter);
      expect(selectedIndexes(), isEmpty);
      expect(find.byType(TabSearchPanel), findsOneWidget);
    }, variant: windows);

    testWidgets('Enter עם מקש שינוי אינו מפעיל את הרשומה המסומנת', (
      tester,
    ) async {
      await openMenu(tester);
      await press(tester, arrowDown);
      for (final modifier in [
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.shiftLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(enter);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(selectedIndexes(), isEmpty);
        expect(find.byType(TabSearchPanel), findsOneWidget);
      }
      await press(tester, enter);
      expect(selectedIndexes(), [0]);
    }, variant: windows);

    testWidgets('סגירת טאב רקע אינה חוטפת פוקוס, והבחירה הבאה ממקדת את התוכן', (
      tester,
    ) async {
      final nodes = <OpenedTab, FocusNode>{};
      final focusRequests = <OpenedTab>[];
      await openMenu(
        tester,
        paneFocusNodes: nodes,
        contentFocusRequests: focusRequests,
      );
      expect(fieldFocus(tester).hasFocus, isTrue);

      await tester.tap(find.byTooltip('סגור כרטיסיה').at(1));
      await tester.pumpAndSettle();
      expect(fieldFocus(tester).hasFocus, isTrue);
      expect(focusRequests, isEmpty);

      await press(tester, LogicalKeyboardKey.escape);
      expect(nodes[tabs.first]!.hasPrimaryFocus, isTrue);
      expect(focusRequests, isEmpty);
      await tester.tap(find.byType(TabSearchButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'וי');
      await tester.pumpAndSettle();
      await press(tester, arrowDown);
      await press(tester, enter);
      expect(selectedIndexes(), [1]);
      expect(nodes[tabs[2]]!.hasPrimaryFocus, isTrue);
      expect(focusRequests, contains(same(tabs[2])));
    }, variant: windows);

    testWidgets(
      'סגירת הפעיל ושחזור בחלונית שומרים את השדה ומחזירים פוקוס למשוחזר בביטול',
      (tester) async {
        final nodes = <OpenedTab, FocusNode>{};
        final focusRequests = <OpenedTab>[];
        await openMenu(
          tester,
          paneFocusNodes: nodes,
          contentFocusRequests: focusRequests,
        );
        await tester.tap(find.byTooltip('סגור כרטיסיה').first);
        await tester.pumpAndSettle();
        expect(tabsBloc.state.activePane, same(tabs[1]));
        expect(fieldFocus(tester).hasFocus, isTrue);
        expect(focusRequests, isEmpty);

        await tester.tap(find.byTooltip('שחזר כרטיסיה'));
        await tester.pumpAndSettle();
        expect(tabsBloc.state.activePane, same(closedTabs.single));
        expect(fieldFocus(tester).hasFocus, isTrue);
        expect(focusRequests, isEmpty);

        await tester.tapAt(const Offset(10, 550));
        await tester.pumpAndSettle();
        expect(find.byType(TabSearchPanel), findsNothing);
        expect(nodes[closedTabs.single]!.hasPrimaryFocus, isTrue);
        expect(nodes[tabs.first]!.hasFocus, isFalse);
        expect(focusRequests, contains(same(closedTabs.single)));
      },
      variant: windows,
    );

    testWidgets('Escape אחרי סגירת הטאב הפעיל ממקד את הטאב שנכנס במקומו', (
      tester,
    ) async {
      final nodes = <OpenedTab, FocusNode>{};
      final focusRequests = <OpenedTab>[];
      await openMenu(
        tester,
        paneFocusNodes: nodes,
        contentFocusRequests: focusRequests,
      );
      await tester.tap(find.byTooltip('סגור כרטיסיה').first);
      await tester.pumpAndSettle();
      expect(fieldFocus(tester).hasFocus, isTrue);
      expect(focusRequests, isEmpty);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(TabSearchPanel), findsNothing);
      expect(nodes[tabs[1]]!.hasPrimaryFocus, isTrue);
      expect(nodes[tabs.first]!.hasFocus, isFalse);
      expect(focusRequests, contains(same(tabs[1])));
    }, variant: windows);

    testWidgets('סינון אחרי גלילה לקצה מציג מיד את הרשימה שהתקצרה', (
      tester,
    ) async {
      await openMenu(
        tester,
        openTitles: [for (var i = 0; i < 60; i++) 'כרטיסיה $i'],
        closedTitles: const [],
      );
      await tester.drag(resultsScrollable(), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('כרטיסיה 59').hitTestable(), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'כרטיסיה 0');
      await tester.pumpAndSettle();
      expect(
        find
            .descendant(
              of: resultsScrollable(),
              matching: find.text('כרטיסיה 0'),
            )
            .hitTestable(),
        findsOneWidget,
      );
      await press(tester, enter);
      expect(selectedIndexes(), isEmpty);
      await press(tester, arrowDown);
      await press(tester, enter);
      expect(selectedIndexes(), [0]);
    }, variant: windows);
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
      final remaining = state.tabs
          .where((t) => !identical(t, event.tab))
          .toList();
      final removedIndex = state.tabs.indexOf(event.tab);
      final nextIndex = removedIndex < state.currentTabIndex
          ? state.currentTabIndex - 1
          : state.currentTabIndex;
      emit(
        state.copyWith(
          tabs: remaining,
          currentTabIndex: remaining.isEmpty
              ? 0
              : nextIndex.clamp(0, remaining.length - 1),
        ),
      );
    }
    if (event is SetCurrentTab) {
      emit(state.copyWith(currentTabIndex: event.index));
    }
    if (event is RestoreClosedTab) {
      closedTabs = closedTabs
          .where((tab) => !identical(tab, event.tab))
          .toList();
      emit(
        state.copyWith(
          tabs: [...state.tabs, event.tab],
          currentTabIndex: state.tabs.length,
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
