import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../../helpers/memory_settings_cache.dart';

/// חלון משני חדש: יש שולחנות, אבל לחלון עוד אין שולחן פעיל.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  TextBookTab tab(String title) =>
      TextBookTab(book: TextBook(title: title), index: 0);

  Future<WorkspaceBloc> loaded(_Repo repo) async {
    final bloc = WorkspaceBloc(
      repository: repo,
      onWorkspaceTabsChanged: (_, _, _) {},
    )..add(LoadWorkspaces());
    await bloc.stream.firstWhere((s) => !s.isLoading);
    expect(bloc.state.activeWorkspaceId, isNull);
    return bloc;
  }

  test('MoveTabToWorkspace adds the tab to the target workspace', () async {
    final target = Workspace(name: 'יעד', tabs: const []);
    final repo = _Repo([target]);
    final bloc = await loaded(repo);

    bloc.add(
      MoveTabToWorkspace(
        tab: tab('ספר מועבר'),
        targetWorkspaceId: target.id,
        currentTabs: const [],
        currentTabIndex: 0,
      ),
    );
    await bloc.stream.first.timeout(const Duration(seconds: 2));

    final saved = repo.workspaces.firstWhere((w) => w.id == target.id);
    expect(saved.tabs.map((t) => t.title), contains('ספר מועבר'));
    await bloc.close();
  });

  test('SwitchToWorkspace keeps the open tabs in a workspace', () async {
    final target = Workspace(name: 'יעד', tabs: [tab('ספר ביעד')]);
    final repo = _Repo([target]);
    final bloc = await loaded(repo);

    bloc.add(
      SwitchToWorkspace(
        targetWorkspaceId: target.id,
        currentTabsToSave: [tab('ספר פתוח בחלון')],
        currentTabIndexToSave: 0,
      ),
    );
    await bloc.stream.firstWhere((s) => s.activeWorkspaceId == target.id);

    final titles = repo.workspaces.expand((w) => w.tabs).map((t) => t.title);
    expect(titles, contains('ספר פתוח בחלון'));
    await bloc.close();
  });
}

class _Repo extends WorkspaceRepository {
  _Repo(List<Workspace> initial) : workspaces = List.of(initial);
  List<Workspace> workspaces;

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async =>
      (List<Workspace>.of(workspaces), null);

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) async {
    workspaces = List.of(apply(List.of(workspaces)));
    return List.of(workspaces);
  }

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {}
}
