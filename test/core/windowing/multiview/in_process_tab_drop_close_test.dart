import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import '../../../test_helpers/fake_view_window.dart';
import '../../../test_helpers/memory_cache_provider.dart';

class _MemorySessions extends WindowSessionStore {
  final Map<int, WindowSession> rows = {};
  final List<int> boundsWrites = [];
  final List<WindowSession> loaded = [];

  @override
  Future<void> save(
    int slot, {
    required String tabsJson,
    required int currentIndex,
  }) async {
    final old = rows[slot];
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: tabsJson,
      currentIndex: currentIndex,
      activeWorkspaceId: old?.activeWorkspaceId,
      boundsJson: old?.boundsJson,
    );
  }

  WindowSession _row(int slot) =>
      rows[slot] ?? WindowSession(slot: slot, tabsJson: '[]', currentIndex: 0);

  @override
  Future<void> saveActiveWorkspace(int slot, String? workspaceId) async {
    final old = _row(slot);
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: old.tabsJson,
      currentIndex: old.currentIndex,
      activeWorkspaceId: workspaceId,
      boundsJson: old.boundsJson,
    );
  }

  @override
  Future<void> saveBounds(int slot, String? boundsJson) async {
    boundsWrites.add(slot);
    final old = _row(slot);
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: old.tabsJson,
      currentIndex: old.currentIndex,
      activeWorkspaceId: old.activeWorkspaceId,
      boundsJson: boundsJson,
    );
  }

  @override
  Future<String?> loadBoundsJson(int slot) async => rows[slot]?.boundsJson;

  @override
  Future<WindowSession?> load(int slot) async {
    final row = rows[slot];
    if (row != null) loaded.add(row);
    return row;
  }

  @override
  Future<void> delete(int slot) async => rows.remove(slot);
}

class _Nav extends Cubit<NavigationState> implements NavigationBloc {
  _Nav() : super(NavigationState.initial(false));
  @override
  void add(NavigationEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'העברה נקלטת לפני האישור ונשמרת בשחזור החלון שנסגר',
    (tester) async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      MultiViewMode.debugOverride = true;
      final windows = FakeViewWindows(tester);
      final entry = windows.registry.open(size: const Size(800, 600))!;
      final sessions = _MemorySessions();
      final bloc = TabsBloc(
        repository: TabsRepository(
          sessions: sessions,
          window: entry.tabsSession,
        ),
        session: entry.tabsSession,
        withCompanion: (tab) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return tab;
        },
      );
      final nav = _Nav();
      final drops = InProcessTabDrops(registry: windows.registry);
      final opener = ViewWindowOpener(
        registry: windows.registry,
        sessions: sessions,
        isMainWindowVisible: () async => true,
      );
      await tester.pumpWidget(
        AppWindowScope(
          controller: entry.controller,
          geometry: entry.controller,
          keys: entry.keys,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<NavigationBloc>.value(value: nav),
            ],
            child: InProcessTabDropReceiver(
              drops: drops,
              child: MaterialApp(
                navigatorKey: entry.keys.navigator,
                home: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      final source = ToolTab(toolId: 'builtin.calendar', title: 'transferred');
      final accepted = await drops.sendTabToWindow(entry.slot, source);
      await tester.pump();
      expect(accepted, isTrue);
      final tabsAtAcknowledgement = bloc.state.tabs
          .map((t) => t.title)
          .toList();
      final close = ViewWindowCloseFlow(
        entry: entry,
        opener: opener,
        confirm: (_, _) async => true,
        discardSession: sessions.delete,
      );
      final closing = close.run();
      await tester.pump();
      expect(await closing, isTrue);
      expect(windows.stubOf(entry).destroyed, isTrue);
      final closedCount = opener.closedCountForTest;
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await bloc.close();
        await nav.close();
      });
      await tester.pump(const Duration(seconds: 1));
      source.dispose();
      MultiViewMode.debugOverride = null;
      expect(tabsAtAcknowledgement, ['transferred']);
      expect(await sessions.load(entry.slot), isNull);
      expect(closedCount, 1);
      expect(
        sessions.loaded.any((s) => s.tabsJson.contains('transferred')),
        isTrue,
        reason:
            'An accepted tab must be available in restored or persisted destination',
      );
    },
  );
}
