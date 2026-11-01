import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
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

import '../test_helpers/fake_view_window.dart';

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
    Widget Function(Widget child)? wrap,
    PluginSystemState? pluginState,
  }) async {
    tabsBloc = _TestTabsBloc(state);
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
    historyBloc = _TestHistoryBloc();
    workspaceBloc = _TestWorkspaceBloc();
    final pluginBloc = _TestPluginBloc(pluginState ?? PluginSystemInitial());
    final navigationBloc = _TestNavigationBloc();
    addTearDown(() async {
      await tabsBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
      await workspaceBloc.close();
      await pluginBloc.close();
      await navigationBloc.close();
    });

    late List<AppContextMenuEntry> entries;
    final tree = MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
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
    );
    await tester.pumpWidget(wrap == null ? tree : wrap(tree));
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

  group('שכפול תוסף מורשה', () {
    InstalledPlugin plugin(bool allows) => InstalledPlugin(
      pluginId: 'com.example.plugin',
      name: 'תוסף',
      version: '1.0.0',
      installPath: '/',
      entrypointPath: 'index.html',
      enabled: true,
      pinned: true,
      manifest: PluginManifest.fromJson({
        'id': 'com.example.plugin',
        'name': 'תוסף',
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {'allowMultipleInstances': allows},
        },
      }),
      installedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    testWidgets('שכפול מופיע רק לאחר הצהרת המניפסט', (tester) async {
      final tab = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
      for (final allows in [false, true]) {
        final entries = await buildEntries(
          tester,
          tab: tab,
          state: TabsState(tabs: [tab], currentTabIndex: 0),
          pluginState: PluginSystemLoaded([plugin(allows)]),
        );
        expect(entries.any((e) => e.label == 'שיכפול'), allows);
      }
    });

    testWidgets('שכפול מעתיק מצב למופע נוסף ליד הטאב שנלחץ', (tester) async {
      final tab = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
      final other = _StubTab('ספר אחר');
      final key = (pluginId: tab.toolId, instanceId: tab.instanceId);
      PluginRestoreStateStore.instance.set(key, {'page': 4});
      addTearDown(() => PluginRestoreStateStore.instance.remove(key));
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab, other], currentTabIndex: 1),
        pluginState: PluginSystemLoaded([plugin(true)]),
      );
      entryOf(entries, 'שיכפול').onTap!();
      await tester.pump();
      final event = tabsBloc.addedEvents.whereType<AddTab>().single;
      final copy = event.tab as ToolTab;
      addTearDown(copy.dispose);
      expect(copy.instanceId, isNot(tab.instanceId));
      expect(copy.allowMultipleInstances, isTrue);
      expect(copy.dedupeKey, isNull);
      expect(event.index, 1);
      expect(
        PluginRestoreStateStore.instance.jsonOf((
          pluginId: copy.toolId,
          instanceId: copy.instanceId,
        )),
        '{"page":4}',
      );
    });
  });

  /// ריבוי תצוגות: היעדים הם חלונות ה-Dart והראשי, וההעברה ישירה בלי אפיק.
  group('"העבר לחלון קיים" בריבוי תצוגות', () {
    late InProcessTabDrops drops;
    late FakeViewWindows windows;
    final received = <(int, OpenedTab)>[];

    InProcessTabDropTarget target(
      int slot,
      String title, {
      bool accepts = true,
    }) => InProcessTabDropTarget(
      dragState: ExternalTabDragState(),
      devicePixelRatio: () => 1,
      receive: (tab, _) {
        expectSync(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
        received.add((slot, tab));
        return accepts;
      },
      describe: () => (title: title, tabCount: 2, activeWorkspaceId: null),
    );

    setUp(() {
      MultiViewMode.debugOverride = true;
      RunnerWindowChannel.debugSupportedOverride = true;
      received.clear();
    });

    tearDown(() {
      InProcessTabDrops.debugOverride = null;
      MultiViewMode.debugOverride = false;
      RunnerWindowChannel.debugSupportedOverride = null;
    });

    testWidgets('מהראשי: מפרט את חלונות ה-Dart ומעביר ישירות', (tester) async {
      windows = FakeViewWindows(tester);
      final a = windows.registry.open(size: const Size(800, 600))!;
      final b = windows.registry.open(size: const Size(800, 600))!;
      drops = InProcessTabDrops(registry: windows.registry);
      InProcessTabDrops.debugOverride = drops;
      drops.register(AppWindowId.primary, target(1, 'ראשי'));
      drops.register(a.id, target(a.slot, 'חלון א'));
      drops.register(b.id, target(b.slot, 'חלון ב'));

      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final submenu = entryOf(entries, 'העבר לחלון קיים').children!;
      expect(submenu.map((e) => e.label), [
        WindowMessages.peerWithTabs('חלון א', 2),
        WindowMessages.peerWithTabs('חלון ב', 2),
      ]);

      submenu[1].onTap!();
      await tester.pump();

      expect(received.single.$1, b.slot);
      expect(received.single.$2, isNot(same(tab)));
      expect(tabsBloc.addedEvents.whereType<RemoveTab>().single.tab, same(tab));
    });

    testWidgets('סירוב היעד משאיר את הכרטיסיה האחרונה במקור', (tester) async {
      windows = FakeViewWindows(tester);
      final a = windows.registry.open(size: const Size(800, 600))!;
      drops = InProcessTabDrops(registry: windows.registry);
      InProcessTabDrops.debugOverride = drops;
      drops.register(a.id, target(a.slot, 'חלון א', accepts: false));
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      entryOf(entries, 'העבר לחלון קיים').children!.single.onTap!();
      await tester.pump();

      expect(received.single.$1, a.slot);
      expect(received.single.$2, isNot(same(tab)));
      expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
      expect(tabsBloc.state.tabs.single, same(tab));
    });

    testWidgets('מחלון Dart: הראשי ברשימה כל עוד הוא מוצג', (tester) async {
      windows = FakeViewWindows(tester);
      final a = windows.registry.open(size: const Size(800, 600))!;
      drops = InProcessTabDrops(registry: windows.registry);
      InProcessTabDrops.debugOverride = drops;
      drops.register(AppWindowId.primary, target(1, 'ראשי'));
      drops.register(a.id, target(a.slot, 'חלון א'));
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');

      Future<List<AppContextMenuEntry>> fromView() => buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
        wrap: (child) => AppWindowScope(
          controller: a.controller,
          geometry: a.controller,
          keys: a.keys,
          child: child,
        ),
      );

      final entries = await fromView();
      expect(
        entryOf(entries, 'העבר לחלון קיים').children!.map((e) => e.label),
        [WindowMessages.peerWithTabs('ראשי', 2)],
      );

      // הראשי נסגר (מוסתר): אין יעד, ולכן אין תת-תפריט.
      drops.setMainShown(false);
      final hidden = await fromView();
      expect(hidden.any((e) => e.label == 'העבר לחלון קיים'), isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('"חלון חדש"', () {
    tearDown(() => RunnerWindowChannel.debugSupportedOverride = null);

    testWidgets('macOS בלי handshake: אף פריט של חלון אחר אינו מופיע', (
      tester,
    ) async {
      RunnerWindowChannel.debugSupportedOverride = null;
      MultiViewMode.debugOverride = null;
      MultiViewMode.debugIsMacOS = true;
      addTearDown(() {
        MultiViewMode.debugOverride = false;
        MultiViewMode.debugResetMacRunner();
      });
      final tab = _StubTab('ספר א');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      final labels = entries.map((entry) => entry.label).toSet();
      for (final label in ['חלון חדש', 'העבר לחלון חדש', 'העבר לחלון קיים']) {
        expect(labels, isNot(contains(label)));
      }
    });

    testWidgets('אינו מופיע כשריבוי חלונות אינו נתמך', (tester) async {
      RunnerWindowChannel.debugSupportedOverride = false;
      final tab = _StubTab('ספר א');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      expect(entries.any((entry) => entry.label == 'חלון חדש'), isFalse);
    });
  });

  group('פתיחת חלון עוברת דרך WindowOpener.current', () {
    late _FakeWindowOpener opener;

    setUp(() {
      RunnerWindowChannel.debugSupportedOverride = true;
      opener = _FakeWindowOpener();
      WindowOpener.debugOverride = opener;
    });

    tearDown(() {
      WindowOpener.debugOverride = null;
      RunnerWindowChannel.debugSupportedOverride = null;
    });

    for (final accepted in [true, false]) {
      testWidgets('"העבר לחלון חדש" ממתין לאישור: $accepted', (tester) async {
        opener.openResult = Completer<bool>();
        final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
        final entries = await buildEntries(
          tester,
          tab: tab,
          state: TabsState(tabs: [tab], currentTabIndex: 0),
        );

        entryOf(entries, 'העבר לחלון חדש').onTap!();
        await tester.pump();

        expect(opener.calls, ['canOpenAnotherWindow', 'openWindow']);
        expect(opener.openedTabs.single, same(tab));
        expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
        expect(tabsBloc.state.tabs.single, same(tab));

        opener.openResult!.complete(accepted);
        await tester.pump();

        if (accepted) {
          expect(
            tabsBloc.addedEvents.whereType<RemoveTab>().single.tab,
            same(tab),
          );
        } else {
          expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
          expect(tabsBloc.state.tabs.single, same(tab));
          expect(opener.calls.last, 'reportOpenWindowFailure');
        }
      });
    }

    testWidgets('"חלון חדש" פותח חלון ריק', (tester) async {
      final tab = _StubTab('ספר א');
      final entries = await buildEntries(
        tester,
        tab: tab,
        state: TabsState(tabs: [tab], currentTabIndex: 0),
      );

      entryOf(entries, 'חלון חדש').onTap!();
      await tester.pump();

      expect(opener.calls, ['openEmptyWindow']);
      expect(opener.openedTabs, isEmpty);
      expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
      expect(tabsBloc.state.tabs.single, same(tab));
    });
  });
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  final List<TabsEvent> addedEvents = [];

  @override
  void add(TabsEvent event) {
    addedEvents.add(event);
    if (event is AddTab) {
      scheduleMicrotask(
        () => emit(state.copyWith(tabs: [...state.tabs, event.tab])),
      );
    }
  }

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

class _FakeWindowOpener implements WindowOpener {
  final List<String> calls = [];
  final List<OpenedTab?> openedTabs = [];
  Completer<bool>? openResult;

  @override
  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    ({int left, int top, int width, int height})? bounds,
    bool inheritPlacement = true,
  }) async {
    calls.add('openWindow');
    openedTabs.add(tab);
    return openResult?.future ?? true;
  }

  @override
  Future<bool> openEmptyWindow() async {
    calls.add('openEmptyWindow');
    return true;
  }

  @override
  Future<bool> restoreLastClosedWindow() async {
    calls.add('restoreLastClosedWindow');
    return true;
  }

  @override
  Future<bool> canOpenAnotherWindow() async {
    calls.add('canOpenAnotherWindow');
    return true;
  }

  @override
  Future<({int count, int max})?> windowCount() async => (count: 1, max: 4);

  @override
  Future<void> reportOpenWindowFailure() async {
    calls.add('reportOpenWindowFailure');
  }
}

class _TestPluginBloc extends Cubit<PluginSystemState>
    implements PluginSystemBloc {
  _TestPluginBloc(super.initialState);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc() : super(NavigationState.initial(true));
  @override
  void add(NavigationEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
