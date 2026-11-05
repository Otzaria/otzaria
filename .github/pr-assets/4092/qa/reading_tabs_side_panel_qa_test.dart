import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
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
    bool initiallyCollapsed = true,
    double panelWidth = 220,
    Size viewSize = const Size(800, 600),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await Settings.init(cacheProvider: MemorySettingsCache());
    tabs = [for (var i = 0; i < tabCount; i++) _StubTab('כרטיסייה $i')];
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
    settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(
        readingTabsPlacement: SettingsRepository.readingTabsPlacementSide,
        readingTabsColumnCollapsed: initiallyCollapsed,
        readingTabsColumnWidth: panelWidth,
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
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


  FocusNode expandFocus(WidgetTester tester) {
    final icon = find.descendant(
      of: find.byTooltip('הרחב את עמודת הכרטיסיות'),
      matching: find.byType(Icon),
    ).first;
    return Focus.of(tester.element(icon));
  }

  testWidgets('QA hover preserves reader keyboard focus and live state', (tester) async {
    await pumpPanel(tester);
    final reader = contentKey.currentState!;
    reader.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    final mouse = await hoverPanel(tester);
    expect(reader.focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await mouse.moveTo(contentRect(tester).center);
    await settleHover(tester);
    expect(reader.focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(reader.keyPresses, 3);
    expect(contentKey.currentState, same(reader));
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('QA header focus survives hover and Enter pins once', (tester) async {
    await pumpPanel(tester);
    final focus = expandFocus(tester);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    await hoverPanel(tester);
    expect(expandFocus(tester), same(focus));
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(settingsBloc.state.readingTabsColumnCollapsed, isFalse);
    expect(settingsBloc.addedEvents.whereType<UpdateReadingTabsColumnCollapsed>(), hasLength(1));
  });

  testWidgets('QA hidden panel is lazy and excluded from focus and semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPanel(tester, initiallyShown: false);
    final reader = contentKey.currentState!;
    expect(find.byType(VerticalReadingTabStrip), findsNothing);
    shown.value = true;
    await tester.pumpAndSettle();
    final focus = expandFocus(tester);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!.toStringDeep(), contains('הרחב את עמודת הכרטיסיות'));
    shown.value = false;
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!.toStringDeep(), isNot(contains('הרחב את עמודת הכרטיסיות')));
    reader.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.tapAt(const Offset(780, 20));
    await tester.pump();
    expect(reader.taps, 1);
    expect(settingsBloc.addedEvents, isEmpty);
    expect(contentKey.currentState, same(reader));
    semantics.dispose();
  });

  testWidgets('QA hiding before opening delay cancels stale hover work', (tester) async {
    await pumpPanel(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: contentRect(tester).center);
    final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
    await mouse.moveTo(Offset(rail.center.dx, rail.bottom - 20));
    await tester.pump(const Duration(milliseconds: 120));
    shown.value = false;
    await tester.pump();
    await mouse.moveTo(const Offset(100, 300));
    shown.value = true;
    await tester.pump();
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('QA hiding during closing delay does not reopen when shown', (tester) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    await mouse.moveTo(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 120));
    shown.value = false;
    await tester.pump();
    shown.value = true;
    await tester.pump();
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('QA down before opening delay freezes collapse until release', (tester) async {
    await pumpPanel(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: contentRect(tester).center);
    final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
    final empty = Offset(rail.center.dx, rail.bottom - 20);
    await mouse.moveTo(empty);
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.down(empty);
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    await mouse.moveTo(contentRect(tester).center);
    await mouse.up();
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('QA native pointer cancellation unfreezes hover without a drop', (tester) async {
    await pumpPanel(tester);
    final mouse = await tester.createGesture(pointer: 41, kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: contentRect(tester).center);
    final rail = tester.getRect(find.byType(VerticalReadingTabStrip));
    await mouse.moveTo(Offset(rail.center.dx, rail.bottom - 20));
    await settleHover(tester);
    final start = tester.getCenter(find.text(tabs.first.title));
    await mouse.moveTo(start);
    await mouse.down(start);
    await mouse.moveTo(const Offset(100, 300));
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    GestureBinding.instance.cancelPointer(41);
    await tester.pump();
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    expect(drops, isEmpty);
    expect(tabsBloc.addedEvents.whereType<MoveTab>(), isEmpty);
    await mouse.up();
    await tester.pump();
    await mouse.moveTo(Offset(rail.center.dx, rail.bottom - 20));
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    expect(settingsBloc.addedEvents, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('QA all active pointers must finish before the preview retracts', (tester) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    final rect = tester.getRect(find.byType(VerticalReadingTabStrip));
    final first = await tester.startGesture(Offset(rect.right - 20, rect.bottom - 20), pointer: 51);
    final second = await tester.startGesture(Offset(rect.right - 20, rect.bottom - 60), pointer: 52);
    await mouse.moveTo(const Offset(100, 300));
    await first.up();
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    await second.cancel();
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  for (final direction in TextDirection.values) {
    testWidgets('QA constrained host and large text remain bounded: $direction', (tester) async {
      await pumpPanel(
        tester,
        direction: direction,
        viewSize: const Size(345, 260),
        panelWidth: 400,
        textScale: 3,
        tabCount: 25,
      );
      final before = contentRect(tester);
      final reader = contentKey.currentState;
      final mouse = await hoverPanel(tester);
      expect(strip(tester).width, 345);
      final rect = tester.getRect(find.byType(VerticalReadingTabStrip));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(345));
      expect(contentRect(tester), before);
      expect(tester.takeException(), isNull);
      await mouse.moveTo(const Offset(-20, 100));
      await settleHover(tester);
      expect(strip(tester).collapsed, isTrue);
      expect(contentKey.currentState, same(reader));
      expect(settingsBloc.addedEvents, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('QA resize while floating preserves content state and saved width', (tester) async {
    await pumpPanel(tester, panelWidth: 400);
    final mouse = await hoverPanel(tester);
    final reader = contentKey.currentState;
    final list = tester.state(find.byType(ReadingTabStrip));
    tester.view.physicalSize = const Size(345, 400);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(contentRect(tester).width, 345 - kCollapsedTabsColumnWidth);
    expect(settingsBloc.state.readingTabsColumnWidth, 400);
    expect(contentKey.currentState, same(reader));
    expect(tester.state(find.byType(ReadingTabStrip)), same(list));
    await mouse.moveTo(const Offset(100, 200));
    await settleHover(tester);
    expect(tester.takeException(), isNull);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  testWidgets('QA search popup keeps focus and responds after hover retracts', (tester) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    await tester.tap(find.byTooltip('חיפוש כרטיסיות'));
    await tester.pumpAndSettle();
    expect(find.byType(TabSearchPanel), findsOneWidget);
    await mouse.moveTo(const Offset(100, 300));
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    final editor = find.byType(EditableText);
    expect(editor, findsOneWidget);
    final focus = tester.widget<EditableText>(editor).focusNode;
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.enterText(editor, 'כרטיסייה 1');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabsBloc.addedEvents.whereType<SetCurrentTab>().single.index, 1);
    expect(find.byType(TabSearchPanel), findsNothing);
    expect(settingsBloc.addedEvents, isEmpty);
  });

  for (final cancel in [false, true]) {
    testWidgets('QA late pointer finish after panel disposal cancel=$cancel', (tester) async {
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
    });
  }

  testWidgets('QA mouse collapse clears preview and does not re-open itself', (tester) async {
    await pumpPanel(tester);
    final mouse = await hoverPanel(tester);
    var at = tester.getCenter(find.byTooltip('הרחב את עמודת הכרטיסיות'));
    await mouse.moveTo(at);
    await mouse.down(at);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(settingsBloc.state.readingTabsColumnCollapsed, isFalse);
    at = tester.getCenter(find.byTooltip('כווץ את עמודת הכרטיסיות'));
    await mouse.moveTo(at);
    await mouse.down(at);
    await mouse.up();
    await settleHover(tester);
    expect(settingsBloc.state.readingTabsColumnCollapsed, isTrue);
    expect(strip(tester).collapsed, isTrue);
    await mouse.moveBy(const Offset(0, 3));
    await settleHover(tester);
    expect(strip(tester).collapsed, isTrue);
    await mouse.moveTo(contentRect(tester).center);
    await mouse.moveTo(at);
    await settleHover(tester);
    expect(strip(tester).collapsed, isFalse);
    expect(settingsBloc.addedEvents.whereType<UpdateReadingTabsColumnCollapsed>(), hasLength(2));
  });
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
  List<OpenedTab> get recentlyClosedTabs => [];

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
  int keyPresses = 0;
  final focus = FocusNode(debugLabel: 'QA reader');

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyA) {
        keyPresses++;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => taps++),
      child: const SizedBox.expand(),
    ),
  );
}
