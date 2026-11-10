import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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

  test('load and add share one queue across different event types', () async {
    final initial = Workspace(name: 'Existing', tabs: const []);
    final repository = _BlockedLoadRepository(initial);
    final bloc = WorkspaceBloc(repository: repository);
    addTearDown(() async {
      if (!repository.releaseLoad.isCompleted) {
        repository.releaseLoad.complete();
      }
      await bloc.close();
    });

    bloc.add(LoadWorkspaces());
    await repository.loadStarted.future.timeout(const Duration(seconds: 2));

    // The load has already captured a snapshot, but its read is delayed.
    // The add must wait for that read; otherwise the stale load result can
    // overwrite the freshly added workspace in the UI.
    bloc.add(
      const AddWorkspace(
        name: 'New',
        tabs: [],
        currentTabIndex: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.mutationCount, 0);

    final updated = bloc.stream.firstWhere(
      (state) => state.workspaces.length == 2,
    );
    repository.releaseLoad.complete();
    await updated.timeout(const Duration(seconds: 2));

    expect(repository.mutationCount, 1);
    expect(bloc.state.workspaces.map((w) => w.name), ['Existing', 'New']);
    expect(bloc.state.activeWorkspaceId, initial.id);
  });
}

class _BlockedLoadRepository extends WorkspaceRepository {
  _BlockedLoadRepository(Workspace workspace)
      : _workspaces = [workspace],
        _activeId = workspace.id;

  List<Workspace> _workspaces;
  String? _activeId;
  final loadStarted = Completer<void>();
  final releaseLoad = Completer<void>();
  int mutationCount = 0;

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async {
    final snapshot = List<Workspace>.from(_workspaces);
    final activeId = _activeId;
    loadStarted.complete();
    await releaseLoad.future;
    return (snapshot, activeId);
  }

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) async {
    mutationCount++;
    _workspaces = List<Workspace>.of(apply(List<Workspace>.of(_workspaces)));
    return List<Workspace>.of(_workspaces);
  }

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {
    _activeId = id;
  }
}
