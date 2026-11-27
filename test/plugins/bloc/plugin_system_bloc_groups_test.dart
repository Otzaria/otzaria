import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

class _FakeRepository implements PluginRegistryRepository {
  List<PluginGroup> groups = [];
  List<InstalledPlugin> plugins = [];
  Map<String, int?> userOrders = {};
  int groupReads = 0;
  int nextId = 0;
  Object? writeError;
  Object? readError;
  bool holdReads = false;
  final pendingReads = <Completer<PluginGroupsSnapshot>>[];
  Completer<List<InstalledPlugin>>? pendingPluginRead;
  Completer<void>? pendingPluginReadStarted;
  Completer<void>? pendingWrite;
  final calls = <String>[];

  Future<void> _write(String action) async {
    calls.add(action);
    if (writeError case final error?) throw error;
    if (pendingWrite case final pending?) await pending.future;
  }

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async {
    final pending = pendingPluginRead;
    pendingPluginRead = null;
    if (pending == null) return List.of(plugins);
    pendingPluginReadStarted?.complete();
    pendingPluginReadStarted = null;
    return await pending.future;
  }

  @override
  Future<List<String>> getGrantedPermissionNames(String pluginId) async => [];

  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<PluginGroupsSnapshot> getPluginGroupsSnapshot() async {
    groupReads++;
    if (readError case final error?) throw error;
    if (holdReads) {
      final pending = Completer<PluginGroupsSnapshot>();
      pendingReads.add(pending);
      return pending.future;
    }
    return _snapshot();
  }

  PluginGroupsSnapshot _snapshot() =>
      PluginGroupsSnapshot(groups: groups, userOrders: userOrders);

  @override
  Future<PluginGroupsSnapshot> createPluginGroup(
    String name,
    List<String> pluginIds,
  ) async {
    await _write('create');
    groups = [
      ...groups,
      PluginGroup(id: 'group-${nextId++}', name: name, pluginIds: pluginIds),
    ];
    return _snapshot();
  }

  @override
  Future<PluginGroupsSnapshot> updatePluginGroup(
    PluginGroup group, {
    PluginGroup? expectedGroup,
  }) async {
    await _write('update');
    groups = [
      for (final old in groups)
        if (old.id == group.id) group else old,
    ];
    return _snapshot();
  }

  @override
  Future<PluginGroupsSnapshot> deletePluginGroup(String groupId) async {
    await _write('delete');
    groups = groups.where((g) => g.id != groupId).toList();
    return _snapshot();
  }

  @override
  Future<PluginGroupsSnapshot> movePluginToGroup(
    String pluginId,
    String? groupId,
  ) async {
    await _write('move');
    groups = [
      for (final group in groups)
        PluginGroup(
          id: group.id,
          name: group.name,
          pluginIds: [
            ...group.pluginIds.where((id) => id != pluginId),
            if (group.id == groupId) pluginId,
          ],
        ),
    ];
    return _snapshot();
  }

  @override
  Future<void> reorderPlugins(List<String> orderedPluginIds) async {
    userOrders = {
      for (var index = 0; index < orderedPluginIds.length; index++)
        orderedPluginIds[index]: index,
    };
    plugins = _snapshot().applyOrderTo(plugins);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedPluginSystemBloc extends PluginSystemBloc {
  _ObservedPluginSystemBloc({required super.repository});

  final _eventCompletions = Map<PluginSystemEvent, Completer<void>>.identity();

  Future<void> whenProcessed(PluginSystemEvent event) =>
      (_eventCompletions[event] = Completer<void>()).future;

  @override
  void onDone(
    PluginSystemEvent event, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    super.onDone(event, error, stackTrace);
    final completion = _eventCompletions.remove(event);
    if (error == null) {
      completion?.complete();
    } else {
      completion?.completeError(error, stackTrace);
    }
  }
}

InstalledPlugin _plugin(String id, {int? userOrder}) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  userOrder: userOrder,
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {'title': id},
    },
  }),
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeRepository repository;
  late _ObservedPluginSystemBloc bloc;

  setUp(() {
    repository = _FakeRepository();
    bloc = _ObservedPluginSystemBloc(repository: repository);
  });

  tearDown(() => bloc.close());

  Future<PluginSystemLoaded> loadPlugins() async {
    final loaded = bloc.stream.firstWhere((s) => s is PluginSystemLoaded);
    bloc.add(LoadPlugins());
    return await loaded as PluginSystemLoaded;
  }

  Future<PluginSystemLoaded> loadGroups() async {
    final loaded = bloc.stream.firstWhere(
      (s) => s is PluginSystemLoaded && s.groupsLoaded,
    );
    bloc.add(const LoadPluginGroups());
    return await loaded as PluginSystemLoaded;
  }

  test(
    'groups are loaded on demand, never during initial plugin startup',
    () async {
      final initial = await loadPlugins();
      expect(repository.groupReads, 0);
      expect(initial.groupsLoaded, isFalse);
      expect(initial.groups, isEmpty);

      repository.groups = [PluginGroup(id: 'a', name: 'לימוד', pluginIds: [])];
      final loaded = await loadGroups();
      expect(repository.groupReads, 1);
      expect(loaded.groups, repository.groups);
      expect(() => loaded.groups.clear(), throwsUnsupportedError);
    },
  );

  test('completion waits for persistence and the refreshed state', () async {
    await loadPlugins();
    await loadGroups();
    repository.pendingWrite = Completer<void>();
    final completion = Completer<void>();
    var completed = false;
    final done = completion.future.then((_) => completed = true);
    bloc.add(
      CreatePluginGroupRequested(
        name: 'לימוד',
        pluginIds: ['a'],
        completion: completion,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect((bloc.state as PluginSystemLoaded).groups, isEmpty);

    repository.pendingWrite!.complete();
    await done;
    expect((bloc.state as PluginSystemLoaded).groups.single.pluginIds, ['a']);
  });

  test(
    'serializes different mutation types and preserves rapid moves',
    () async {
      await loadPlugins();
      repository.groups = [PluginGroup(id: 'g', name: 'לימוד', pluginIds: [])];
      await loadGroups();
      repository.pendingWrite = Completer<void>();
      final first = Completer<void>();
      final second = Completer<void>();
      final third = Completer<void>();
      bloc
        ..add(
          MovePluginToGroupRequested(
            pluginId: 'a',
            groupId: 'g',
            completion: first,
          ),
        )
        ..add(
          MovePluginToGroupRequested(
            pluginId: 'b',
            groupId: 'g',
            completion: second,
          ),
        )
        ..add(
          UpdatePluginGroupRequested(
            groupId: 'g',
            name: 'חזרות',
            pluginIds: ['a', 'b'],
            completion: third,
          ),
        );
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, ['move']);
      repository.pendingWrite!.complete();
      await Future.wait([first.future, second.future, third.future]);
      expect(repository.calls, ['move', 'move', 'update']);
      expect((bloc.state as PluginSystemLoaded).groups.single.name, 'חזרות');
      expect((bloc.state as PluginSystemLoaded).groups.single.pluginIds, [
        'a',
        'b',
      ]);
    },
  );

  test(
    'failed save completes with error and retains the visible state',
    () async {
      await loadPlugins();
      repository.groups = [
        PluginGroup(id: 'g', name: 'לימוד', pluginIds: ['a']),
      ];
      final before = await loadGroups();
      repository.writeError = const PluginGroupChanged();
      final completion = Completer<void>();
      final failure = expectLater(
        completion.future,
        throwsA(isA<PluginGroupChanged>()),
      );
      bloc.add(
        UpdatePluginGroupRequested(
          groupId: 'g',
          name: 'אחר',
          pluginIds: ['b'],
          expectedGroup: before.groups.single,
          completion: completion,
        ),
      );
      await failure;
      expect(bloc.state, before);
    },
  );

  test(
    'a failed group refresh preserves groups and unrelated plugin state',
    () async {
      await loadPlugins();
      repository.groups = [
        PluginGroup(id: 'g', name: 'לימוד', pluginIds: ['a']),
      ];
      final before = await loadGroups();
      repository.readError = StateError('unavailable');
      bloc.add(const LoadPluginGroups());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, before);
      expect(bloc.state, isNot(isA<PluginSystemError>()));
    },
  );

  test('ordinary plugin refreshes preserve loaded personal groups', () async {
    await loadPlugins();
    repository.groups = [
      PluginGroup(id: 'g', name: 'לימוד', pluginIds: ['a']),
    ];
    await loadGroups();
    repository.groups = [
      PluginGroup(id: 'g', name: 'חזרות', pluginIds: ['a', 'b']),
    ];
    final refreshed = await loadPlugins();
    expect(refreshed.groups.single.name, 'חזרות');
    expect(refreshed.groups.single.pluginIds, ['a', 'b']);
    expect(refreshed.groupsLoaded, isTrue);
  });

  test(
    'a late plugin refresh cannot overwrite a newer group snapshot',
    () async {
      repository.plugins = [_plugin('a'), _plugin('b')];
      await loadPlugins();
      await loadGroups();
      repository.holdReads = true;
      bloc.add(LoadPlugins());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const LoadPluginGroups());
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingReads, hasLength(2));
      final newer = [
        PluginGroup(id: 'g', name: 'חדש', pluginIds: ['a']),
      ];
      repository.pendingReads.last.complete(
        PluginGroupsSnapshot(groups: newer, userOrders: const {'b': 0, 'a': 1}),
      );
      await Future<void>.delayed(Duration.zero);
      repository.pendingReads.first.complete(
        PluginGroupsSnapshot(
          groups: [PluginGroup(id: 'g', name: 'ישן', pluginIds: [])],
          userOrders: const {'a': 0, 'b': 1},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as PluginSystemLoaded).groups, newer);
      expect(
        (bloc.state as PluginSystemLoaded).plugins.map((p) => p.pluginId),
        ['b', 'a'],
      );
    },
  );

  test(
    'a late plugin list cannot undo the order published with a group save',
    () async {
      repository.plugins = [_plugin('a'), _plugin('b'), _plugin('c')];
      repository.groups = [
        PluginGroup(id: 'g', name: 'יעד', pluginIds: ['c']),
      ];
      await loadPlugins();
      await loadGroups();
      final delayed = Completer<List<InstalledPlugin>>();
      final readStarted = Completer<void>();
      repository.pendingPluginRead = delayed;
      repository.pendingPluginReadStarted = readStarted;
      final load = LoadPlugins();
      final loadCompleted = bloc.whenProcessed(load);
      bloc.add(load);
      await readStarted.future;
      expect(repository.pendingPluginRead, isNull);

      repository.userOrders = {'b': 0, 'c': 1, 'a': 2};
      final completion = Completer<void>();
      bloc.add(
        MovePluginToGroupRequested(
          pluginId: 'a',
          groupId: 'g',
          completion: completion,
        ),
      );
      await completion.future;
      expect(
        (bloc.state as PluginSystemLoaded).plugins.map((p) => p.pluginId),
        ['b', 'c', 'a'],
      );
      delayed.complete(List.of(repository.plugins));
      await loadCompleted;
      final loaded = bloc.state as PluginSystemLoaded;
      expect(loaded.plugins.map((p) => p.pluginId), ['b', 'c', 'a']);
      expect(loaded.groups.single.pluginIds, ['c', 'a']);
    },
  );

  test('ordinary reordering supersedes an older group snapshot read', () async {
    repository.plugins = [_plugin('a'), _plugin('b'), _plugin('c')];
    await loadPlugins();
    await loadGroups();
    repository.holdReads = true;
    bloc.add(const LoadPluginGroups());
    await Future<void>.delayed(Duration.zero);
    expect(repository.pendingReads, hasLength(1));
    repository.holdReads = false;
    final reordered = bloc.stream.firstWhere(
      (state) =>
          state is PluginSystemLoaded && state.plugins.first.pluginId == 'c',
    );
    bloc.add(const ReorderPluginsRequested(['c', 'b', 'a']));
    await reordered;
    repository.pendingReads.single.complete(
      PluginGroupsSnapshot(
        groups: const [],
        userOrders: const {'a': 0, 'b': 1, 'c': 2},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      (bloc.state as PluginSystemLoaded).plugins.map((p) => p.pluginId),
      ['c', 'b', 'a'],
    );
  });

  test(
    'snapshot order can restore a null preference without changing flags',
    () {
      final first = _plugin('a', userOrder: 2).copyWith(enabled: false);
      final second = _plugin('b', userOrder: 0);
      final snapshot = PluginGroupsSnapshot(
        groups: const [],
        userOrders: const {'a': null, 'b': 0},
      );
      final ordered = snapshot.applyOrderTo([second, first]);
      expect(ordered.map((p) => p.pluginId), ['a', 'b']);
      expect(ordered.first.userOrder, isNull);
      expect(ordered.first.enabled, isFalse);
      expect(ordered.first.updatedAt, first.updatedAt);
      expect(identical(ordered.last, second), isTrue);
      expect(() => snapshot.userOrders.clear(), throwsUnsupportedError);
    },
  );

  test(
    'committed saves succeed without a fallible second database read',
    () async {
      await loadPlugins();
      await loadGroups();
      final reads = repository.groupReads;
      repository.readError = StateError('read unavailable');
      final completion = Completer<void>();
      bloc.add(
        CreatePluginGroupRequested(
          name: 'לימוד',
          pluginIds: ['a'],
          completion: completion,
        ),
      );
      await completion.future;
      expect(repository.groupReads, reads);
      expect((bloc.state as PluginSystemLoaded).groups.single.name, 'לימוד');
    },
  );

  test(
    'failures without a completion do not turn into unhandled errors',
    () async {
      await loadPlugins();
      await loadGroups();
      repository.writeError = StateError('unavailable');
      bloc.add(const DeletePluginGroupRequested('g'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<PluginSystemLoaded>());
      expect(repository.calls, ['delete']);
    },
  );

  test('state equality includes group name, membership and readiness', () {
    final first = PluginGroup(id: 'g', name: 'לימוד', pluginIds: ['a']);
    expect(
      PluginSystemLoaded(const [], groups: [first]),
      isNot(PluginSystemLoaded(const [], groups: [first], groupsLoaded: true)),
    );
    expect(
      PluginSystemLoaded(const [], groups: [first]),
      isNot(
        PluginSystemLoaded(
          const [],
          groups: [
            PluginGroup(id: 'g', name: 'חזרות', pluginIds: ['a']),
          ],
        ),
      ),
    );
    expect(
      PluginSystemLoaded(const [], groups: [first]),
      isNot(
        PluginSystemLoaded(
          const [],
          groups: [
            PluginGroup(id: 'g', name: 'לימוד', pluginIds: ['b']),
          ],
        ),
      ),
    );
  });
}
