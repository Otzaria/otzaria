import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/navigation/view/vertical_reading_tab_strip.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  late _TestTabsBloc tabsBloc;
  late _TestSettingsBloc settingsBloc;
  late GlobalKey<_ContentProbeState> contentKey;
  late ValueNotifier<bool> shown;
  late ExternalTabDragState externalDrag;
  late List<OpenedTab> tabs;
  late List<(OpenedTab, PaneDropSide)> drops;

  Future<void> pumpPanel(
    WidgetTester tester, {
    TextDirection direction = TextDirection.rtl,
    int tabCount = 3,
    bool initiallyShown = true,
  }) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tabs = [for (var i = 0; i < tabCount; i++) _StubTab('כרטיסייה $i')];
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
    settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(
        readingTabsPlacement: SettingsRepository.readingTabsPlacementSide,
        readingTabsColumnCollapsed: true,
        readingTabsColumnWidth: 220,
      ),
    );
    final historyBloc = _TestHistoryBloc();
    final workspaceBloc = _TestWorkspaceBloc();
    shown = ValueNotifier(initiallyShown);
    externalDrag = ExternalTabDragState();
    contentKey = GlobalKey<_ContentProbeState>();
    drops = [];
    final content = PaneDropTarget(
      tab: _StubTab('אזור הקריאה'),
      onDrop: (tab, side) => drops.add((tab, side)),
      child: _ContentProbe(key: contentKey),
    );

    addTearDown(() async {
      await tabsBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
      await workspaceBloc.close();
      shown.dispose();
      externalDrag.drag.dispose();
      externalDrag.dropIndex.dispose();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: ExternalTabDragScope(
                state: externalDrag,
                child: ValueListenableBuilder<bool>(
                  valueListenable: shown,
                  builder: (context, show, child) => ReadingTabsSidePanel(
                    show: show,
                    child: child!,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect contentRect(WidgetTester tester) =>
      tester.getRect(find.byKey(contentKey));

  VerticalReadingTabStrip strip(WidgetTester tester) =>
      tester.widget<VerticalReadingTabStrip>(
        find.byType(VerticalReadingTabStrip),
      );

  Future<void> settleHover(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> hoverPanel(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: contentRect(tester).center);
    final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
    await mouse.moveTo(Offset(rail.center.dx, rail.bottom - 20));
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    return mouse;
  }

  for (final direction in TextDirection.values) {
    testWidgets('ריחוף צף בלי להזיז את התוכן לאורך ההנפשה: $direction', (
      tester,
    ) async {
      await pumpPanel(tester, direction: direction);
      final before = contentRect(tester);
      final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
      final readerState = contentKey.currentState;
      final stripState = tester.state(find.byType(ReadingTabStrip));
      expect(rail.width, kCollapsedTabsColumnWidth);
      expect(before.width, 800 - kCollapsedTabsColumnWidth);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: before.center);
      await mouse.moveTo(Offset(rail.center.dx, rail.bottom - 20));
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(contentRect(tester), before);
      }
      expect(strip(tester).collapsed, isFalse);
      expect(strip(tester).width, 220);
      final expanded = tester.getRect(find.byType(VerticalReadingTabStrip));
      expect(expanded.width, greaterThan(kCollapsedTabsColumnWidth));
      expect(expanded.top, rail.top);
      expect(expanded.bottom, rail.bottom);
      if (direction == TextDirection.rtl) {
        expect(expanded.right, rail.right);
        expect(expanded.left, lessThan(before.right));
      } else {
        expect(expanded.left, rail.left);
        expect(expanded.right, greaterThan(before.left));
      }

      await mouse.moveTo(before.center);
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(contentRect(tester), before);
      }
      expect(strip(tester).collapsed, isTrue);
      expect(tester.state(find.byType(ReadingTabStrip)), same(stripState));
      expect(contentKey.currentState, same(readerState));
      expect(settingsBloc.addedEvents, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('כותרת ו-X בשטח הצף מקבלים לחיצות: $direction', (
      tester,
    ) async {
      await pumpPanel(tester, direction: direction);
      final mouse = await hoverPanel(tester);
      final title = find.text(tabs[1].title);
      final target = tester.getCenter(title);
      expect(contentRect(tester).contains(target), isTrue);

      await mouse.moveTo(target);
      await tester.pump();
      await mouse.down(target);
      await mouse.up();
      await tester.pump();
      expect(tabsBloc.addedEvents.whereType<SetCurrentTab>().single.index, 1);

      final row = find.ancestor(
        of: title,
        matching: find.byWidgetPredicate((w) => w is Draggable<OpenedTab>),
      );
      final close = find.descendant(
        of: row,
        matching: find.byTooltip('סגור כרטיסיה'),
      );
      expect(close, findsOneWidget);
      final closePoint = tester.getCenter(close);
      expect(contentRect(tester).contains(closePoint), isTrue);
      await mouse.moveTo(closePoint);
      await tester.pump();
      await mouse.down(closePoint);
      await mouse.up();
      await tester.pump();

      expect(tabsBloc.addedEvents.whereType<RemoveTab>().single.tab, tabs[1]);
      expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), hasLength(1));
      expect(contentKey.currentState!.taps, 0);
      expect(settingsBloc.addedEvents, isEmpty);
    });
  }

  testWidgets('מעבר קצר אינו פותח, ולחיצה מהירה על אייקון בוחרת כרטיסייה', (
    tester,
  ) async {
    await pumpPanel(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: contentRect(tester).center);
    final target = tester.getCenter(find.byTooltip(tabs[1].title));
    await mouse.moveTo(target);
    await tester.pump(const Duration(milliseconds: 50));
    expect(strip(tester).collapsed, isTrue);
    await mouse.down(target);
    await mouse.up();
    await mouse.moveTo(contentRect(tester).center);
    await settleHover(tester);

    expect(tabsBloc.addedEvents.whereType<SetCurrentTab>().single.index, 1);
    expect(strip(tester).collapsed, isTrue);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('ריחוף משאיר את אותה הכרטיסייה ואת כפתורי הכותרת תחת הסמן', (
    tester,
  ) async {
    await pumpPanel(tester);
    final iconPoint = tester.getCenter(find.byTooltip(tabs[1].title));
    final expandButton = find.byTooltip('הרחב את עמודת הכרטיסיות');
    final searchButton = find.byTooltip('חיפוש כרטיסיות');
    final expandBefore = tester.getRect(expandButton);
    final searchBefore = tester.getRect(searchButton);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: contentRect(tester).center);
    await mouse.moveTo(iconPoint);
    await settleHover(tester);

    expect(strip(tester).collapsed, isFalse);
    final row = find.byWidgetPredicate(
      (w) => w is Draggable<OpenedTab> && identical(w.data, tabs[1]),
    );
    expect(tester.getRect(row).center.dy, iconPoint.dy);
    expect(tester.getRect(expandButton), expandBefore);
    expect(tester.getRect(searchButton), searchBefore);
    await mouse.down(iconPoint);
    await mouse.up();
    await tester.pump();
    expect(tabsBloc.addedEvents.whereType<SetCurrentTab>().single.index, 1);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  ]) {
    testWidgets('ריחוף וגלילה ב-$kind אינם מרחיבים את העמודה', (
      tester,
    ) async {
      await pumpPanel(tester, tabCount: 30);
      final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
      final pointer = await tester.createGesture(kind: kind);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: rail.center);
      await settleHover(tester);
      expect(strip(tester).collapsed, isTrue);

      await pointer.down(rail.center);
      await pointer.moveBy(const Offset(0, -80));
      await tester.pump();
      await pointer.moveBy(const Offset(0, -30));
      await pointer.up();
      await settleHover(tester);

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ReadingTabStrip),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, greaterThan(0));
      expect(strip(tester).collapsed, isTrue);
      expect(settingsBloc.addedEvents, isEmpty);
    });
  }

  testWidgets('חזרה לפני תום השהיית הסגירה שומרת את העמודה פתוחה', (
    tester,
  ) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    final expanded = tester.getRect(find.byType(VerticalReadingTabStrip));
    await mouse.moveTo(contentRect(tester).center);
    await tester.pump(const Duration(milliseconds: 80));
    await mouse.moveTo(expanded.center);
    await settleHover(tester);

    expect(strip(tester).collapsed, isFalse);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('התוכן שמחוץ לעמודה הצפה נשאר לחיץ', (tester) async {
    await pumpPanel(tester);
    await hoverPanel(tester);
    final content = contentRect(tester);
    await tester.tapAt(Offset(content.left + 30, content.center.dy));
    await tester.pump();

    expect(contentKey.currentState!.taps, 1);
    expect(strip(tester).collapsed, isFalse);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('כפתור ההרחבה בזמן ריחוף נועץ את ההעדפה הקבועה', (
    tester,
  ) async {
    await pumpPanel(tester);
    final readerState = contentKey.currentState;
    final mouse = await hoverPanel(tester);
    expect(settingsBloc.state.readingTabsColumnCollapsed, isTrue);

    await tester.tap(find.byTooltip('הרחב את עמודת הכרטיסיות'));
    await tester.pumpAndSettle();
    expect(settingsBloc.state.readingTabsColumnCollapsed, isFalse);
    expect(
      settingsBloc.addedEvents
          .whereType<UpdateReadingTabsColumnCollapsed>()
          .single
          .collapsed,
      isFalse,
    );
    expect(contentRect(tester).width, 800 - 220);
    await mouse.moveTo(contentRect(tester).center);
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    expect(contentKey.currentState, same(readerState));

    await tester.tap(find.byTooltip('כווץ את עמודת הכרטיסיות'));
    await settleHover(tester);
    expect(settingsBloc.state.readingTabsColumnCollapsed, isTrue);
    expect(contentRect(tester).width, 800 - kCollapsedTabsColumnWidth);
    expect(settingsBloc.addedEvents, hasLength(2));
  });

  testWidgets('גלילת הכרטיסיות ו-State נשמרים לאורך ריחוף והסתרה', (
    tester,
  ) async {
    await pumpPanel(tester, tabCount: 30);
    final mouse = await hoverPanel(tester);
    final stripFinder = find.byType(ReadingTabStrip);
    final originalStripState = tester.state(stripFinder);
    final readerState = contentKey.currentState;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: stripFinder, matching: find.byType(Scrollable)),
    );
    final panel = tester.getRect(find.byType(VerticalReadingTabStrip));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: panel.center,
        scrollDelta: const Offset(0, 220),
      ),
    );
    await tester.pumpAndSettle();
    final scrolled = scrollable.position.pixels;
    expect(scrolled, greaterThan(0));

    await mouse.moveTo(contentRect(tester).center);
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    expect(scrollable.position.pixels, scrolled);

    shown.value = false;
    await tester.pumpAndSettle();
    expect(contentRect(tester).width, 800);
    shown.value = true;
    await tester.pumpAndSettle();
    expect(strip(tester).collapsed, isTrue);
    expect(tester.state(stripFinder), same(originalStripState));
    expect(contentKey.currentState, same(readerState));
    expect(scrollable.position.pixels, scrolled);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('גרירה מהשטח הצף ממשיכה לפיצול גם אחרי יציאה ממושכת', (
    tester,
  ) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    final before = contentRect(tester);
    final originalStripState = tester.state(find.byType(ReadingTabStrip));
    final start = tester.getCenter(find.text(tabs.first.title));
    expect(before.contains(start), isTrue);
    await mouse.moveTo(start);
    await mouse.down(start);
    await mouse.moveBy(const Offset(-25, 0));
    await tester.pump();
    await mouse.moveTo(Offset(before.left + 50, before.center.dy));
    await settleHover(tester);

    expect(strip(tester).collapsed, isFalse);
    expect(
      tester.state(find.byType(ReadingTabStrip)),
      same(originalStripState),
    );
    expect(contentRect(tester), before);
    await mouse.up();
    await settleHover(tester);

    expect(drops, [(tabs.first, PaneDropSide.end)]);
    expect(strip(tester).collapsed, isTrue);
    expect(tabsBloc.addedEvents.whereType<MoveTab>(), isEmpty);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('גרירה החוזרת לשטח הצף מסדרת כרטיסיות במקום לפצל', (
    tester,
  ) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    final start = tester.getCenter(find.text(tabs.first.title));
    final target = tester.getCenter(find.text(tabs.last.title));
    await mouse.moveTo(start);
    await mouse.down(start);
    await mouse.moveTo(contentRect(tester).center);
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    await mouse.moveTo(target);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    final moved = tabsBloc.addedEvents.whereType<MoveTab>().single;
    expect(moved.tab, tabs.first);
    expect(moved.newIndex, 2);
    expect(drops, isEmpty);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('יעד גרירה מחלון אחר נמדד גם בשטח שמעל התוכן', (
    tester,
  ) async {
    await pumpPanel(tester);
    await hoverPanel(tester);
    final target = tester.getCenter(find.text(tabs[1].title));
    expect(contentRect(tester).contains(target), isTrue);
    externalDrag.drag.value = ExternalTabDrag(
      title: 'כרטיסייה מחלון אחר',
      local: target,
    );
    await tester.pump();
    expect(externalDrag.dropIndex.value, isNotNull);
    externalDrag.drag.value = null;
    await tester.pump();
    expect(externalDrag.dropIndex.value, isNull);
  });

  testWidgets('תפריט ההקשר נשאר פעיל מחוץ לשטח העמודה', (tester) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    await tester.tapAt(
      tester.getCenter(find.text(tabs[1].title)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    final action = find.text('סגור את האחרים');
    expect(action, findsOneWidget);
    await mouse.moveTo(tester.getCenter(action));
    await settleHover(tester);
    await tester.tap(action);
    await settleHover(tester);

    expect(
      tabsBloc.addedEvents.whereType<CloseOtherTabs>().single.keepTab,
      tabs[1],
    );
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('הסרת המעטפת מבטלת שעון סגירה ממתין', (tester) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    await mouse.moveTo(contentRect(tester).center);
    await tester.pumpWidget(const SizedBox.shrink());
    await settleHover(tester);
    expect(tester.takeException(), isNull);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      '${cancel ? 'ביטול' : 'שחרור'} מצביע אחרי פירוק העמודה אינו קורא context מפורק',
      (tester) async {
        await pumpPanel(tester);
        final mouse = await hoverPanel(tester);
        final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
        final empty = Offset(rail.right - 20, rail.bottom - 20);
        await mouse.moveTo(empty);
        await mouse.down(empty);
        await tester.pumpWidget(const SizedBox.shrink());
        if (cancel) {
          await mouse.cancel();
        } else {
          await mouse.up();
        }
        await settleHover(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => _StubTab(title);

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  final List<TabsEvent> addedEvents = [];

  @override
  void add(TabsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _TestSettingsBloc(super.initialState);

  final List<SettingsEvent> addedEvents = [];

  @override
  void add(SettingsEvent event) {
    addedEvents.add(event);
    if (event is UpdateReadingTabsColumnCollapsed) {
      emit(state.copyWith(readingTabsColumnCollapsed: event.collapsed));
    } else if (event is UpdateReadingTabsColumnWidth) {
      emit(state.copyWith(readingTabsColumnWidth: event.width));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _TestWorkspaceBloc() : super(WorkspaceState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ContentProbe extends StatefulWidget {
  const _ContentProbe({super.key});

  @override
  State<_ContentProbe> createState() => _ContentProbeState();
}

class _ContentProbeState extends State<_ContentProbe> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: Center(child: Text('לחיצות בתוכן: $taps')),
  );
}
