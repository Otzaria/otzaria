import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final pin in [false, true]) {
    test(
      'queued ${pin ? 'pin' : 'snapshot'} keeps its source and plugin state',
      () async {
        final live = ToolTab(toolId: 'test.plugin', title: 'live-A');
        final key = (pluginId: live.toolId, instanceId: live.instanceId);
        final restore = PluginRestoreStateStore.instance;
        restore.set(key, {
          'nested': {'page': 1},
        });
        final env = await _Harness.create(live: [live], pinned: !pin);
        final gate = env.repository.blockNextMutation();
        final switched = env.switchTo('B');
        await gate.started.future;
        final saved = Completer<bool>();
        env.bloc.add(
          pin
              ? SetWorkspacePinned(
                  workspaceId: 'A',
                  isPinned: true,
                  tabsToSave: env.live,
                  onCompleted: saved.complete,
                )
              : UpdateCurrentWorkspaceTabs(
                  sourceWorkspaceId: 'A',
                  tabs: env.live,
                  activeTabIndex: 0,
                  onCompleted: saved.complete,
                ),
        );
        restore.set(key, {
          'nested': {'page': 2},
        });
        gate.release.complete();
        expect(await switched, isTrue);
        expect(await saved.future, isTrue);

        expect(env.titles('B'), ['saved-B']);
        expect(env.titles('A'), ['live-A']);
        final snapshot = env.repository.items.firstWhere((w) => w.id == 'A');
        final restored = snapshot.tabs.single as ToolTab;
        expect(snapshot.isPinned, isTrue);
        expect(restored.instanceId, isNot(live.instanceId));
        expect(restore.has(key), isFalse);
        expect(
          restore.stateOf((
            pluginId: restored.toolId,
            instanceId: restored.instanceId,
          )),
          {
            'nested': {'page': 1},
          },
        );
      },
    );
  }

  test(
    'snapshot whose source was deleted never writes to the active target',
    () async {
      final live = ToolTab(toolId: 'test.plugin', title: 'live-A');
      final env = await _Harness.create(live: [live], pinned: true);
      final gate = env.repository.blockNextMutation();
      final switched = env.switchTo('B');
      await gate.started.future;
      final saved = Completer<bool>();
      env.bloc.add(
        UpdateCurrentWorkspaceTabs(
          sourceWorkspaceId: 'A',
          tabs: env.live,
          activeTabIndex: 0,
          onCompleted: saved.complete,
        ),
      );
      env.repository.items.removeWhere((w) => w.id == 'A');
      gate.release.complete();
      await switched;
      expect(await saved.future, isFalse);
      expect(env.repository.items.any((w) => w.id == 'A'), isFalse);
      expect(env.titles('B'), ['saved-B']);
    },
  );

  for (final sourceId in <String?>['A', null]) {
    test(
      'queued switch from $sourceId rejects a source replaced by an earlier switch',
      () async {
        final env = await _Harness.create(activeId: sourceId);
        final gate = env.repository.blockNextMutation();
        final first = env.switchTo('B');
        await gate.started.future;
        final stale = Completer<bool?>();
        env.bloc.add(
          SwitchToWorkspace(
            sourceWorkspaceId: sourceId,
            targetWorkspaceId: 'C',
            readCurrentTabs: () => throw StateError('stale reader was called'),
            onCompleted: stale.complete,
          ),
        );
        gate.release.complete();
        expect(await first, isTrue);
        expect(await stale.future, isNull);
        expect(env.bloc.state.activeWorkspaceId, 'B');
        expect(env.titles('B'), ['saved-B']);
        expect(env.titles('C'), ['saved-C']);
        expect(env.repository.mutations, 1);
        expect(env.bloc.state.isChangingTabs, isFalse);
      },
    );
  }

  for (final targetId in ['B', 'C']) {
    test(
      'move queued behind a switch never removes tabs or writes to $targetId',
      () async {
        final env = await _Harness.create();
        final selected = env.live.first;
        final gate = env.repository.blockNextMutation();
        final switched = env.switchTo('B');
        await gate.started.future;
        final moved = env.move([selected], targetId);
        gate.release.complete();
        await switched;
        expect(await moved, isFalse);
        expect(env.removals, 0);
        expect(env.titles('A'), ['live-1', 'live-2']);
        expect(env.titles('B'), ['saved-B']);
        expect(env.titles('C'), ['saved-C']);
        expect(env.live.map((tab) => tab.title), ['saved-B']);
      },
    );
  }

  test(
    'move then switch waits for live removal and saves only the remaining tabs',
    () async {
      final env = await _Harness.create();
      final selected = env.live.first;
      final gate = env.repository.blockNextMutation();
      final removal = _Gate();
      addTearDown(removal.finish);
      final moved = env.move([selected], 'B', beforeRemoval: removal.hold);
      await gate.started.future;
      final switched = env.switchTo('C');
      expect(env.live, contains(selected));
      gate.release.complete();
      await removal.started.future;
      expect(env.repository.mutations, 1);
      expect(env.bloc.state.isChangingTabs, isTrue);
      expect(env.bloc.state.activeWorkspaceId, 'A');
      removal.release.complete();
      expect(await moved, isTrue);
      expect(await switched, isTrue);
      expect(env.bloc.state.isChangingTabs, isFalse);
      expect(env.titles('A'), ['live-2']);
      expect(env.titles('B'), ['saved-B', 'live-1']);
      expect(env.titles('C'), ['saved-C']);
      expect(env.live.map((tab) => tab.title), ['saved-C']);
    },
  );

  for (final repeatSelection in [false, true]) {
    test(
      'queued moves use the remaining live selection: repeat=$repeatSelection',
      () async {
        final env = await _Harness.create();
        final firstTab = env.live.first;
        final secondTab = repeatSelection ? firstTab : env.live.last;
        final gate = env.repository.blockNextMutation();
        final first = env.move([firstTab], 'B');
        await gate.started.future;
        final second = env.move([secondTab], 'C');
        gate.release.complete();
        expect(await first, isTrue);
        expect(await second, !repeatSelection);
        expect(env.titles('A'), repeatSelection ? ['live-2'] : isEmpty);
        expect(env.titles('B'), ['saved-B', 'live-1']);
        expect(
          env.titles('C'),
          repeatSelection ? ['saved-C'] : ['saved-C', 'live-2'],
        );
        expect(
          env.live.map((tab) => tab.title),
          repeatSelection ? ['live-2'] : isEmpty,
        );
      },
    );
  }

  for (final deletedId in ['A', 'B']) {
    test(
      'move keeps live tabs when $deletedId disappears before the mutation',
      () async {
        final env = await _Harness.create();
        final originals = List.of(env.live);
        final gate = env.repository.blockNextMutation(beforeApply: true);
        final moved = env.move([originals.first], 'B');
        await gate.started.future;
        env.repository.items.removeWhere((w) => w.id == deletedId);
        gate.release.complete();
        expect(await moved, isFalse);
        expect(env.live, originals);
        expect(env.removals, 0);
        expect(env.repository.items.any((w) => w.id == deletedId), isFalse);
        expect(env.titles(deletedId == 'A' ? 'B' : 'A'), [
          deletedId == 'A' ? 'saved-B' : 'saved-A',
        ]);
      },
    );
  }

  test('move failure keeps the original live tabs and target', () async {
    final env = await _Harness.create();
    final originals = List.of(env.live);
    env.repository.failMutation = true;
    expect(await env.move([originals.first], 'B'), isFalse);
    expect(env.live, originals);
    expect(env.removals, 0);
    expect(env.titles('B'), ['saved-B']);
    expect(env.bloc.state.isChangingTabs, isFalse);
  });

  test(
    'switch preserves live tabs in a new workspace if its source was deleted',
    () async {
      final env = await _Harness.create();
      final gate = env.repository.blockNextMutation(beforeApply: true);
      final switched = env.switchTo('B');
      await gate.started.future;
      env.repository.items.removeWhere((w) => w.id == 'A');
      gate.release.complete();
      expect(await switched, isTrue);
      final recovered = env.repository.items.singleWhere(
        (w) => w.id != 'B' && w.id != 'C',
      );
      expect(recovered.id, isNot('A'));
      expect(recovered.tabs.map((tab) => tab.title), ['live-1', 'live-2']);
      expect(env.live.map((tab) => tab.title), ['saved-B']);
    },
  );

  test(
    'switch to a deleted target leaves live tabs and source unchanged',
    () async {
      final env = await _Harness.create();
      final originals = List.of(env.live);
      final gate = env.repository.blockNextMutation(beforeApply: true);
      final switched = env.switchTo('B');
      await gate.started.future;
      env.repository.items.removeWhere((w) => w.id == 'B');
      gate.release.complete();
      expect(await switched, isNull);
      expect(env.live, originals);
      expect(env.titles('A'), ['saved-A']);
      expect(env.bloc.state.isChangingTabs, isFalse);
    },
  );

  test(
    'active workspace follows replaced tabs before slow active-id persistence',
    () async {
      final env = await _Harness.create();
      final gate = _Gate();
      addTearDown(gate.finish);
      env.repository.beforeSaveActive = gate.hold;
      final switched = env.switchTo('B');
      await gate.started.future;
      expect(env.live.map((tab) => tab.title), ['saved-B']);
      expect(env.bloc.state.activeWorkspaceId, 'B');
      expect(env.bloc.state.isChangingTabs, isTrue);
      gate.release.complete();
      expect(await switched, isTrue);
      expect(env.bloc.state.isChangingTabs, isFalse);
    },
  );
}

class _Harness {
  _Harness(this.repository, this.live) {
    bloc = WorkspaceBloc(
      repository: repository,
      onWorkspaceTabsChanged: (tabs, _, _) {
        for (final tab in live) {
          _dispose(tab);
        }
        live = tabs;
      },
    );
  }

  final _Repository repository;
  late final WorkspaceBloc bloc;
  List<OpenedTab> live;
  final _disposed = <OpenedTab>{};
  int removals = 0;

  static Future<_Harness> create({
    List<OpenedTab>? live,
    String? activeId = 'A',
    bool pinned = false,
  }) async {
    final env = _Harness(
      _Repository([
        Workspace(
          id: 'A',
          name: 'A',
          tabs: [_Tab('saved-A')],
          isPinned: pinned,
        ),
        Workspace(id: 'B', name: 'B', tabs: [_Tab('saved-B')]),
        Workspace(id: 'C', name: 'C', tabs: [_Tab('saved-C')]),
      ], activeId),
      live ?? [_Tab('live-1'), _Tab('live-2')],
    );
    addTearDown(() async {
      env.repository.releaseGates();
      await env.bloc.close();
      for (final tab in {...env.live, ...env.repository.ownedTabs}) {
        env._dispose(tab);
      }
    });
    env.bloc.add(LoadWorkspaces());
    await env.bloc.stream.firstWhere((state) => !state.isLoading);
    return env;
  }

  void _dispose(OpenedTab tab) {
    if (_disposed.add(tab)) tab.dispose();
  }

  WorkspaceTabs readTabs() => (tabs: live, activeTabIndex: 0, activePane: null);

  Future<bool?> switchTo(String targetId) {
    final completed = Completer<bool?>();
    bloc.add(
      SwitchToWorkspace(
        sourceWorkspaceId: bloc.state.activeWorkspaceId,
        targetWorkspaceId: targetId,
        readCurrentTabs: readTabs,
        onCompleted: completed.complete,
      ),
    );
    return completed.future;
  }

  Future<bool> move(
    List<OpenedTab> tabs,
    String targetId, {
    Future<void> Function()? beforeRemoval,
  }) {
    final completed = Completer<bool>();
    bloc.add(
      MoveTabsToWorkspace(
        sourceWorkspaceId: bloc.state.activeWorkspaceId,
        tabs: tabs,
        targetWorkspaceId: targetId,
        readCurrentTabs: readTabs,
        onTabsMoved: () async {
          await beforeRemoval?.call();
          live = live.where((tab) => !tabs.contains(tab)).toList();
          for (final tab in tabs) {
            _dispose(tab);
          }
          removals++;
        },
        onCompleted: completed.complete,
      ),
    );
    return completed.future;
  }

  List<String> titles(String id) => repository.items
      .firstWhere((w) => w.id == id)
      .tabs
      .map((tab) => tab.title)
      .toList();
}

class _Tab extends OpenedTab {
  _Tab(super.title);

  @override
  OpenedTab clone() => _Tab(title);

  @override
  Map<String, dynamic> toJson() => throw UnsupportedError('test-only tab');
}

class _Gate {
  final started = Completer<void>();
  final release = Completer<void>();

  Future<void> hold() {
    started.complete();
    return release.future;
  }

  void finish() {
    if (!release.isCompleted) release.complete();
  }
}

class _Repository extends WorkspaceRepository {
  _Repository(this.items, this.activeId) {
    ownedTabs.addAll(items.expand((w) => w.tabs));
  }

  List<Workspace> items;
  String? activeId;
  final ownedTabs = <OpenedTab>{};
  final _gates = <_Gate>[];
  ({_Gate gate, bool beforeApply})? _nextGate;
  Future<void> Function()? beforeSaveActive;
  bool failMutation = false;
  int mutations = 0;

  _Gate blockNextMutation({bool beforeApply = false}) {
    final gate = _Gate();
    _gates.add(gate);
    _nextGate = (gate: gate, beforeApply: beforeApply);
    return gate;
  }

  void releaseGates() {
    for (final gate in _gates) {
      gate.finish();
    }
  }

  @override
  Stream<void> get remoteChanges => const Stream.empty();

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async =>
      (List.of(items), activeId);

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {
    await beforeSaveActive?.call();
    activeId = id;
  }

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace>) apply,
  ) async {
    mutations++;
    final blocked = _nextGate;
    _nextGate = null;
    if (blocked?.beforeApply == true) await blocked!.gate.hold();
    if (failMutation) throw StateError('failed to persist');
    items = apply(List.of(items));
    ownedTabs.addAll(items.expand((w) => w.tabs));
    final result = List<Workspace>.of(items);
    if (blocked?.beforeApply == false) await blocked!.gate.hold();
    return result;
  }
}
