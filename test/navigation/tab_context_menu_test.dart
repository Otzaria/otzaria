import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/view/tab_context_menu.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => _StubTab(title)..isPinned = isPinned;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

void main() {
  late _TestTabsBloc tabsBloc;
  late _TestSettingsBloc settingsBloc;
  late _TestHistoryBloc historyBloc;
  late _TestWorkspaceBloc workspaceBloc;

  /// בונה את פריטי התפריט של [tab] מתוך עץ ווידג'טים עם כל ה-blocs.
  Future<List<AppContextMenuEntry>> buildEntries(
    WidgetTester tester, {
    required OpenedTab tab,
    required TabsState state,
  }) async {
    tabsBloc = _TestTabsBloc(state);
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
    historyBloc = _TestHistoryBloc();
    workspaceBloc = _TestWorkspaceBloc();
    addTearDown(() async {
      await tabsBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
      await workspaceBloc.close();
    });

    late List<AppContextMenuEntry> entries;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) {
                entries = buildTabContextMenuEntries(
                  context,
                  tab,
                  state,
                  onCloseTab: (_) {},
                  onCloseSelectedTabs: () {},
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return entries;
  }

  AppContextMenuEntry entryOf(
    List<AppContextMenuEntry> entries,
    String label,
  ) => entries.firstWhere((entry) => entry.label == label);

  testWidgets('"סגור את האחרים" שומר את הכרטיסייה שנלחצה, לא את הפעילה', (
    tester,
  ) async {
    final tabs = [_StubTab('ספר א'), _StubTab('ספר ב'), _StubTab('ספר ג')];
    final entries = await buildEntries(
      tester,
      tab: tabs[2],
      state: TabsState(tabs: tabs, currentTabIndex: 0),
    );

    entryOf(entries, 'סגור את האחרים').onTap!();
    await tester.pump();

    final event = tabsBloc.addedEvents.whereType<CloseOtherTabs>().single;
    expect(
      event.keepTab,
      same(tabs[2]),
      reason:
          'לחיצה ימנית אינה מחליפה כרטיסייה פעילה — הפעולה חייבת לשמור '
          'את הכרטיסייה שעליה נפתח התפריט (issue #1094)',
    );
  });

  testWidgets('"סגור את האחרים" על הכרטיסייה הפעילה שומר עליה', (tester) async {
    final tabs = [_StubTab('ספר א'), _StubTab('ספר ב')];
    final entries = await buildEntries(
      tester,
      tab: tabs[1],
      state: TabsState(tabs: tabs, currentTabIndex: 1),
    );

    entryOf(entries, 'סגור את האחרים').onTap!();
    await tester.pump();

    expect(
      tabsBloc.addedEvents.whereType<CloseOtherTabs>().single.keepTab,
      same(tabs[1]),
    );
  });

  testWidgets('"סגור כרטיסיות משמאל" סוגר רק את שאחריה, ולא מוצמדות', (
    tester,
  ) async {
    final tabs = [
      _StubTab('ספר א'),
      _StubTab('ספר ב'),
      _StubTab('ספר ג')..isPinned = true,
      _StubTab('ספר ד'),
    ];
    final entries = await buildEntries(
      tester,
      tab: tabs[1],
      state: TabsState(tabs: tabs, currentTabIndex: 0),
    );

    entryOf(entries, 'סגור כרטיסיות משמאל').onTap!();
    await tester.pump();

    expect(
      tabsBloc.addedEvents.whereType<RemoveTabs>().single.tabs,
      [same(tabs[3])],
    );
  });

  testWidgets('"סגור כרטיסיות משמאל" לא מוצג כשאין מה לסגור', (tester) async {
    final tabs = [_StubTab('ספר א'), _StubTab('ספר ב')..isPinned = true];
    final entries = await buildEntries(
      tester,
      tab: tabs[0],
      state: TabsState(tabs: tabs, currentTabIndex: 0),
    );

    expect(entries.any((e) => e.label == 'סגור כרטיסיות משמאל'), isFalse);
  });

  /// מיזוג חלון של כרטיסיה אחת חזרה לחלון המקור — המחווה הטבעית של
  /// issue #1187. חלון שהתרוקן נשאר פתוח על הספרייה, ולכן אין מה לחסום.
  group('העברת הכרטיסיה האחרונה בחלון', () {
    late _FakeRunner runner;

    setUp(() {
      MultiWindowService.debugSupportedOverride = true;
      WindowBus.namespace = _namespace;
      runner = _FakeRunner()..install();
    });

    tearDown(() {
      runner.uninstall();
      MultiWindowService.debugSupportedOverride = null;
      MultiWindowService.publishKnownPeers(const []);
      WindowBus.namespace = 'otzaria.window';
    });

    testWidgets('לחלון קיים — עוברת', (tester) async {
      final peer = _FakePeer(2)..register();
      addTearDown(peer.dispose);
      MultiWindowService.publishKnownPeers(const [
        WindowPeer(slot: 2, title: 'חלון שני', tabCount: 1),
      ]);
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      await tester.runAsync(() async {
        entryOf(entries, 'העבר לחלון קיים').children!.single.onTap!();
        // ⚠️ המסירה עוברת ב-ReceivePort אמיתי, ש-FakeAsync של pumpAndSettle
        // אינו מקדם — ההמתנה חייבת להיות בזמן אמת.
        // RemoveTab נשלח רק אחרי אישור המסירה, כלומר אחרי שהיעד כבר קיבל.
        for (
          var i = 0;
          i < 200 &&
              (peer.receivedTabs == 0 ||
                  tabsBloc.addedEvents.whereType<RemoveTab>().isEmpty);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(peer.receivedTabs, 1);
      expect(tabsBloc.addedEvents.whereType<RemoveTab>().single.tab, same(tab));
    });

    testWidgets('לחלון חדש — עוברת, והחלון נשאר פתוח על הספרייה', (
      tester,
    ) async {
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      await tester.runAsync(() async {
        entryOf(entries, 'העבר לחלון חדש').onTap!();
        await runner.opened.future.timeout(const Duration(seconds: 5));
      });
      await tester.pump();

      expect(runner.openWindowCalls, 1);
      expect(tabsBloc.addedEvents.whereType<RemoveTab>().single.tab, same(tab));
    });
  });

  group('"חלון חדש"', () {
    late _FakeRunner runner;

    setUp(() => runner = _FakeRunner());

    tearDown(() {
      runner.uninstall();
      MultiWindowService.debugSupportedOverride = null;
    });

    testWidgets('פותח חלון ריק ואינו נוגע בכרטיסיה', (tester) async {
      MultiWindowService.debugSupportedOverride = true;
      runner.install();
      final tab = _StubTab('ספר א');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      await tester.runAsync(() async {
        entryOf(entries, 'חלון חדש').onTap!();
        await runner.opened.future.timeout(const Duration(seconds: 5));
      });
      await tester.pump();

      expect(runner.openWindowCalls, 1);
      expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
    });

    testWidgets('אינו מופיע כשריבוי חלונות אינו נתמך', (tester) async {
      MultiWindowService.debugSupportedOverride = false;
      final tab = _StubTab('ספר א');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      expect(entries.any((entry) => entry.label == 'חלון חדש'), isFalse);
    });
  });
}

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.tabcontextmenu';

class _FakeRunner {
  int openWindowCalls = 0;
  final Completer<void> opened = Completer<void>();

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
          switch (call.method) {
            case 'windowCount':
              return {'count': 2, 'max': 4, 'engines': 2};
            case 'openWindow':
              openWindowCalls++;
              if (!opened.isCompleted) opened.complete();
              return true;
            default:
              return null;
          }
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, null);
  }
}

/// חלון יעד מדומה על האפיק.
class _FakePeer {
  _FakePeer(this.slot);

  final int slot;
  int receivedTabs = 0;
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    _port.listen((message) {
      final map = message as Map;
      final reply = map['reply'] as SendPort;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      if (body['type'] == MultiWindowService.requestReceiveTab) {
        receivedTabs++;
        reply.send({'ok': true, 'result': true});
        return;
      }
      reply.send({'ok': true, 'result': null});
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    _port.close();
  }
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

  @override
  void add(SettingsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _TestWorkspaceBloc() : super(WorkspaceState.initial());

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
