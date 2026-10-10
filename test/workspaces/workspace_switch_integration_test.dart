import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../helpers/memory_settings_cache.dart';

PdfBookTab leaf(String title) => PdfBookTab(
  book: PdfBook(title: title, path: '/nonexistent/$title.pdf'),
  pageNumber: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late UserStateDatabase database;
  late UserStateListStore store;
  late _ControlledWorkspaceRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    dir = Directory.systemTemp.createTempSync('workspace_integration_');
    database = UserStateDatabase.openAt('${dir.path}/state.db');
    store = UserStateListStore(database: database);
    repository = _ControlledWorkspaceRepository(
      store: store,
      sessions: WindowSessionStore(database: database),
      slot: () => 1,
    );
  });

  tearDown(() {
    store.dispose();
    database.close();
    dir.deleteSync(recursive: true);
  });

  Future<WorkspaceBloc> load(List<Workspace> workspaces) async {
    await repository.replaceWorkspaces(workspaces, workspaces.first.id);
    final bloc = WorkspaceBloc(repository: repository)..add(LoadWorkspaces());
    await bloc.stream.firstWhere((s) => !s.isLoading);
    addTearDown(bloc.close);
    return bloc;
  }

  test(
    'SQLite: pinned snapshot keeps split pane, index, zoom and independent copies',
    () async {
      final right = leaf('ימין')..savedZoom = 1.4;
      final left = leaf('שמאל')..savedZoom = 2.3;
      final split = CombinedTab(
        rightTab: right,
        leftTab: left,
        splitRatio: 0.3,
      );
      final fixed = Workspace(name: 'קבוע', tabs: [], isPinned: false);
      final other = Workspace(name: 'אחר', tabs: []);
      final bloc = await load([fixed, other]);
      final done = bloc.stream.firstWhere((s) => s.workspaces.first.isPinned);
      bloc.add(
        SetWorkspacePinned(
          workspaceId: fixed.id,
          isPinned: true,
          tabsToSave: [leaf('קודם'), split],
          tabIndexToSave: 1,
          activePaneToSave: kLeftPaneSide,
        ),
      );
      await done;
      right.savedZoom = 8.8;
      left.pageNumber = 9;
      final switched = bloc.stream.firstWhere(
        (s) => s.activeWorkspaceId == other.id,
      );
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: other.id,
          currentTabsToSave: [leaf('זמני')],
          currentTabIndexToSave: 0,
        ),
      );
      await switched;
      final saved = (await repository.loadWorkspaces()).$1.first;
      expect(saved.tabs.map((t) => t.title), ['קודם', split.title]);
      final restored = saved.tabs.last as CombinedTab;
      expect(saved.activeTabIndex, 1);
      expect(saved.activePane, kLeftPaneSide);
      expect(restored.splitRatio, 0.3);
      expect((restored.rightTab as PdfBookTab).savedZoom, 1.4);
      expect((restored.leftTab as PdfBookTab).pageNumber, 1);
    },
  );

  test(
    'SQLite: explicit snapshot save survives later departure; unpin restores normal stash',
    () async {
      final fixed = Workspace(
        name: 'קבוע',
        tabs: [leaf('ישן')],
        isPinned: true,
      );
      final other = Workspace(name: 'אחר', tabs: []);
      final bloc = await load([fixed, other]);
      var done = bloc.stream.firstWhere(
        (s) => s.workspaces.first.tabs.single.title == 'חדש',
      );
      bloc.add(
        UpdateCurrentWorkspaceTabs(tabs: [leaf('חדש')], activeTabIndex: 0),
      );
      await done;
      done = bloc.stream.firstWhere((s) => !s.workspaces.first.isPinned);
      bloc.add(SetWorkspacePinned(workspaceId: fixed.id, isPinned: false));
      await done;
      done = bloc.stream.firstWhere((s) => s.activeWorkspaceId == other.id);
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: other.id,
          currentTabsToSave: [leaf('אחרי ביטול')],
          currentTabIndexToSave: 0,
        ),
      );
      await done;
      expect(
        (await repository.loadWorkspaces()).$1.first.tabs.single.title,
        'אחרי ביטול',
      );
    },
  );

  test(
    'SQLite: moving out preserves source snapshot and moving into pinned appends',
    () async {
      final fixed = Workspace(
        name: 'קבוע',
        tabs: [leaf('מקור')],
        isPinned: true,
      );
      final other = Workspace(name: 'אחר', tabs: [leaf('יעד')], isPinned: true);
      final bloc = await load([fixed, other]);
      final moved = bloc.stream.firstWhere(
        (s) => s.workspaces.last.tabs.length == 2,
      );
      bloc.add(
        MoveTabToWorkspace(
          tab: leaf('מועבר'),
          targetWorkspaceId: other.id,
          currentTabs: [],
          currentTabIndex: 0,
        ),
      );
      await moved;
      final saved = (await repository.loadWorkspaces()).$1;
      expect(saved.first.tabs.single.title, 'מקור');
      expect(saved.last.tabs.map((t) => t.title), ['יעד', 'מועבר']);
    },
  );

  test(
    'SQLite: pin from a second connection is authoritative when the first leaves',
    () async {
      final fixed = Workspace(name: 'קבוע', tabs: [leaf('שמירה')]);
      final other = Workspace(name: 'אחר', tabs: []);
      final bloc = await load([fixed, other]);
      final db2 = UserStateDatabase.openAt('${dir.path}/state.db');
      final store2 = UserStateListStore(database: db2);
      final repo2 = WorkspaceRepository(
        store: store2,
        slot: () => 2,
        sessions: WindowSessionStore(database: db2),
      );
      await repo2.mutateWorkspaces(
        (ws) => ws
            .map((w) => w.id == fixed.id ? w.copyWith(isPinned: true) : w)
            .toList(),
      );
      final switched = bloc.stream.firstWhere(
        (s) => s.activeWorkspaceId == other.id,
      );
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: other.id,
          currentTabsToSave: [leaf('זמני')],
          currentTabIndexToSave: 0,
        ),
      );
      await switched;
      final saved = (await repo2.loadWorkspaces()).$1.first;
      expect(saved.isPinned, isTrue);
      expect(saved.tabs.single.title, 'שמירה');
      store2.dispose();
      db2.close();
    },
  );

  Future<_DialogHarness> openDialog(
    WidgetTester tester, {
    required List<Workspace> workspaces,
    List<OpenedTab> liveTabs = const [],
    Screen screen = Screen.library,
    Completer<void>? replaceGate,
  }) async {
    await repository.replaceWorkspaces(workspaces, workspaces.first.id);
    final harness = _DialogHarness(repository, replaceGate);
    addTearDown(harness.close);
    if (liveTabs.isNotEmpty) {
      final loaded = harness.tabs.stream.firstWhere((s) => s.tabs.isNotEmpty);
      harness.tabs.add(ReplaceAllTabs(liveTabs, 0));
      await loaded;
    }
    if (screen != Screen.library) {
      final navigated = harness.navigation.stream.firstWhere(
        (s) => s.currentScreen == screen,
      );
      harness.navigation.add(NavigateToScreen(screen));
      await navigated;
    }
    final loaded = harness.workspace.stream.firstWhere((s) => !s.isLoading);
    harness.workspace.add(LoadWorkspaces());
    await loaded;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.widget);
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    return harness;
  }

  for (final pinned in [false, true]) {
    for (final snapshotHasBooks in [true, false]) {
      testWidgets(
        'active workspace reload uses restored tabs: pinned=$pinned, savedBooks=$snapshotHasBooks',
        (tester) async {
          final liveTabs = snapshotHasBooks
              ? <OpenedTab>[]
              : [leaf('ספר זמני')];
          final harness = await openDialog(
            tester,
            workspaces: [
              Workspace(
                name: 'קבוע',
                tabs: snapshotHasBooks ? [leaf('ספר שמור')] : [],
                isPinned: pinned,
              ),
            ],
            liveTabs: liveTabs,
            screen: snapshotHasBooks ? Screen.library : Screen.reading,
          );
          await tester.tap(_tile('קבוע'));
          await tester.pumpAndSettle();
          final hasBooks = pinned ? snapshotHasBooks : liveTabs.isNotEmpty;
          expect(harness.tabs.state.tabs.isNotEmpty, hasBooks);
          expect(
            harness.navigation.state.currentScreen,
            hasBooks ? Screen.reading : Screen.library,
          );
          expect(find.byType(WorkspaceSwitcherDialog), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'navigation waits for replacement and uses fresh remote snapshot',
    (tester) async {
      final gate = Completer<void>();
      final target = Workspace(name: 'יעד', tabs: []);
      final harness = await openDialog(
        tester,
        workspaces: [
          Workspace(name: 'מקור', tabs: []),
          target,
        ],
        replaceGate: gate,
      );
      await repository.mutateWorkspaces(
        (ws) => ws
            .map(
              (w) => w.id == target.id
                  ? w.copyWith(tabs: [leaf('נוסף בחלון אחר')], isPinned: true)
                  : w,
            )
            .toList(),
      );
      await tester.tap(_tile('יעד'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(harness.navigation.state.currentScreen, Screen.library);
      expect(find.byType(WorkspaceSwitcherDialog), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(harness.workspace.state.activeWorkspaceId, target.id);
      expect(harness.tabs.state.tabs.single.title, 'נוסף בחלון אחר');
      expect(harness.navigation.state.currentScreen, Screen.reading);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('save failure preserves live tabs, screen and dialog', (
    tester,
  ) async {
    final source = Workspace(name: 'מקור', tabs: []);
    final harness = await openDialog(
      tester,
      workspaces: [
        source,
        Workspace(name: 'יעד', tabs: []),
      ],
      liveTabs: [leaf('חי')],
      screen: Screen.reading,
    );
    repository.failWrite = true;
    await tester.tap(_tile('יעד'));
    await tester.pumpAndSettle();
    expect(harness.workspace.state.error, isNotNull);
    expect(harness.workspace.state.activeWorkspaceId, source.id);
    expect(harness.tabs.state.tabs.single.title, 'חי');
    expect(harness.navigation.state.currentScreen, Screen.reading);
    expect(find.byType(WorkspaceSwitcherDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('target removed remotely does not navigate or close dialog', (
    tester,
  ) async {
    final source = Workspace(name: 'מקור', tabs: []);
    final target = Workspace(name: 'יעד', tabs: [leaf('יעד')]);
    final harness = await openDialog(tester, workspaces: [source, target]);
    await repository.mutateWorkspaces(
      (ws) => ws.where((w) => w.id != target.id).toList(),
    );
    await tester.tap(_tile('יעד'));
    await tester.pumpAndSettle();
    expect(harness.workspace.state.activeWorkspaceId, source.id);
    expect(harness.tabs.state.tabs, isEmpty);
    expect(harness.navigation.state.currentScreen, Screen.library);
    expect(find.byType(WorkspaceSwitcherDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'cancel unsaved changes leaves pinned snapshot and screen intact',
    (tester) async {
      final plugin = ToolTab(toolId: 'example.plugin', title: 'שינויים');
      final key = (pluginId: plugin.toolId, instanceId: plugin.instanceId);
      PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
      addTearDown(
        () => PluginUnsavedChangesRegistry.instance.removeInstance(key),
      );
      final pinned = Workspace(name: 'קבוע', tabs: [], isPinned: true);
      final harness = await openDialog(
        tester,
        workspaces: [pinned],
        liveTabs: [plugin],
        screen: Screen.reading,
      );
      await tester.tap(_tile('קבוע'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(harness.tabs.state.tabs.single, same(plugin));
      expect(harness.navigation.state.currentScreen, Screen.reading);
      expect(harness.workspace.state.activeWorkspaceId, pinned.id);
      expect((await repository.loadWorkspaces()).$1.single.tabs, isEmpty);
      expect(find.byType(WorkspaceSwitcherDialog), findsOneWidget);
      PluginUnsavedChangesRegistry.instance.removeInstance(key);
      await tester.tap(_tile('קבוע'));
      await tester.pumpAndSettle();
      expect(harness.tabs.state.tabs, isEmpty);
      expect(harness.navigation.state.currentScreen, Screen.library);
      expect(find.byType(WorkspaceSwitcherDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('confirmation saves fresh live tabs and pin state', (
    tester,
  ) async {
    final plugin = ToolTab(toolId: 'example.plugin', title: 'שינויים');
    final key = (pluginId: plugin.toolId, instanceId: plugin.instanceId);
    PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
    addTearDown(
      () => PluginUnsavedChangesRegistry.instance.removeInstance(key),
    );
    final source = Workspace(name: 'מקור', tabs: [], isPinned: true);
    final target = Workspace(name: 'יעד', tabs: []);
    final harness = await openDialog(
      tester,
      workspaces: [source, target],
      liveTabs: [plugin],
      screen: Screen.reading,
    );
    await tester.tap(_tile('יעד'));
    await tester.pumpAndSettle();
    final live = leaf('נוסף בזמן האישור');
    harness.tabs.add(AddTab(live));
    await tester.pumpAndSettle();
    await repository.mutateWorkspaces(
      (ws) => ws
          .map((w) => w.id == source.id ? w.copyWith(isPinned: false) : w)
          .toList(),
    );
    await tester.tap(find.text('סגור בכל זאת'));
    await tester.pumpAndSettle();
    final saved = (await repository.loadWorkspaces()).$1.first;
    expect(saved.isPinned, isFalse);
    expect(saved.tabs.map((t) => t.title), ['שינויים', 'נוסף בזמן האישור']);
    expect(saved.activeTabIndex, 1);
    expect(harness.workspace.state.activeWorkspaceId, target.id);
    expect(harness.navigation.state.currentScreen, Screen.library);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('closing dialog during replacement ignores late navigation', (
    tester,
  ) async {
    final gate = Completer<void>();
    final harness = await openDialog(
      tester,
      workspaces: [
        Workspace(name: 'קבוע', tabs: [leaf('קבוע')], isPinned: true),
      ],
      replaceGate: gate,
    );
    await tester.tap(_tile('קבוע'));
    await tester.pump();
    final dialogContext = tester.element(find.byType(WorkspaceSwitcherDialog));
    Navigator.of(dialogContext).pop();
    gate.complete();
    await tester.pumpAndSettle();
    expect(harness.navigation.state.currentScreen, Screen.library);
    expect(find.text('פתח'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('multiple taps during replacement perform a single switch', (
    tester,
  ) async {
    final gate = Completer<void>();
    final harness = await openDialog(
      tester,
      workspaces: [
        Workspace(name: 'מקור', tabs: []),
        Workspace(name: 'יעד', tabs: [leaf('יעד')]),
        Workspace(name: 'אחר', tabs: []),
      ],
      replaceGate: gate,
    );
    await tester.tap(_tile('יעד'));
    await tester.pump();
    await tester.tap(_tile('אחר'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(harness.replacements, 1);
    expect(harness.navigation.state.currentScreen, Screen.reading);
    expect(harness.workspace.state.activeWorkspace!.name, 'יעד');
    expect(find.text('פתח'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Finder _tile(String name) => find
    .descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
      matching: find.byType(InkWell),
    )
    .first;

class _DialogHarness {
  _DialogHarness(WorkspaceRepository repository, Completer<void>? replaceGate) {
    final tabsRepository = _TabsRepository();
    tabs = TabsBloc(repository: tabsRepository);
    navigation = NavigationBloc(
      repository: NavigationRepository(),
      tabsRepository: tabsRepository,
      activePaneStream: tabs.stream.map((s) => s.activePane).distinct(),
    );
    workspace = WorkspaceBloc(
      repository: repository,
      onWorkspaceTabsChanged: (restored, index, pane) async {
        replacements++;
        if (replaceGate != null) await replaceGate.future;
        final done = tabs.stream.firstWhere((s) => identical(s.tabs, restored));
        tabs.add(ReplaceAllTabs(restored, index, activePane: pane));
        await done;
      },
    );
  }

  late final TabsBloc tabs;
  late final NavigationBloc navigation;
  late final WorkspaceBloc workspace;
  int replacements = 0;

  Widget get widget => MultiBlocProvider(
    providers: [
      BlocProvider<WorkspaceBloc>.value(value: workspace),
      BlocProvider<TabsBloc>.value(value: tabs),
      BlocProvider<NavigationBloc>.value(value: navigation),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const WorkspaceSwitcherDialog(),
            ),
            child: const Text('פתח'),
          ),
        ),
      ),
    ),
  );

  Future<void> close() async {
    await workspace.close();
    await navigation.close();
    await tabs.close();
  }
}

class _ControlledWorkspaceRepository extends WorkspaceRepository {
  _ControlledWorkspaceRepository({super.store, super.sessions, super.slot});
  bool failWrite = false;

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) {
    if (failWrite) throw StateError('write failed');
    return super.mutateWorkspaces(apply);
  }
}

class _TabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs() => [];
  @override
  int loadCurrentTabIndex() => 0;
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
  @override
  Future<void> flushPendingWrites() async {}
}
