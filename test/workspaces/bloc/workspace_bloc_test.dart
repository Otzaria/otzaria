import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkspaceBloc tab isolation', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('שומר snapshot נפרד של הטאבים בעת החלפת שולחן עבודה', () async {
      final firstWorkspace = Workspace(name: 'א', tabs: const []);
      final secondWorkspace = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [firstWorkspace, secondWorkspace],
        activeWorkspaceId: firstWorkspace.id,
      );

      List<OpenedTab>? callbackTabs;
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (tabs, _) {
          callbackTabs = tabs;
        },
      )..add(LoadWorkspaces());

      // Wait for LoadWorkspaces to complete (isLoading transitions false→true→false)
      await bloc.stream.firstWhere((s) => !s.isLoading);

      final liveTab = _createTextTab('ספר חי');
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: secondWorkspace.id,
          currentTabsToSave: [liveTab],
          currentTabIndexToSave: 0,
        ),
      );

      // Wait for workspace switch to complete (activeWorkspaceId changes)
      await bloc.stream.firstWhere(
        (s) => s.activeWorkspaceId == secondWorkspace.id,
      );

      final savedWorkspace = bloc.state.workspaces.firstWhere(
        (w) => w.id == firstWorkspace.id,
      );
      expect(savedWorkspace.tabs, hasLength(1));
      expect(savedWorkspace.tabs.first, isNot(same(liveTab)));
      expect(callbackTabs, isNotNull);
      expect(callbackTabs, isEmpty);

      await bloc.close();
      liveTab.dispose();
    });

    test('מעביר ל-UI עותקים נפרדים של טאבי שולחן העבודה היעד', () async {
      final targetTab = _createTextTab('ספר יעד');
      final sourceWorkspace = Workspace(name: 'א', tabs: const []);
      final targetWorkspace = Workspace(name: 'ב', tabs: [targetTab]);
      final repository = _FakeWorkspaceRepository(
        workspaces: [sourceWorkspace, targetWorkspace],
        activeWorkspaceId: sourceWorkspace.id,
      );

      List<OpenedTab>? callbackTabs;
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (tabs, _) {
          callbackTabs = tabs;
        },
      )..add(LoadWorkspaces());

      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: targetWorkspace.id,
          currentTabsToSave: const [],
          currentTabIndexToSave: 0,
        ),
      );

      await bloc.stream.firstWhere(
        (s) => s.activeWorkspaceId == targetWorkspace.id,
      );

      expect(callbackTabs, isNotNull);
      expect(callbackTabs, hasLength(1));
      expect(callbackTabs!.first, isNot(same(targetWorkspace.tabs.first)));

      await bloc.close();
      targetTab.dispose();
    });

    test('מחליף מצב פעיל רק אחרי שה-UI החליף את הטאבים', () async {
      final sourceWorkspace = Workspace(name: 'א', tabs: const []);
      final targetWorkspace = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [sourceWorkspace, targetWorkspace],
        activeWorkspaceId: sourceWorkspace.id,
      );
      final callbackStarted = Completer<void>();
      final allowTabReplacement = Completer<void>();
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (_, _) {
          callbackStarted.complete();
          return allowTabReplacement.future;
        },
      )..add(LoadWorkspaces());

      await bloc.stream.firstWhere((state) => !state.isLoading);
      final switched = bloc.stream.firstWhere(
        (state) => state.activeWorkspaceId == targetWorkspace.id,
      );
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: targetWorkspace.id,
          currentTabsToSave: const [],
          currentTabIndexToSave: 0,
        ),
      );

      await callbackStarted.future;
      expect(bloc.state.activeWorkspaceId, sourceWorkspace.id);

      allowTabReplacement.complete();
      await switched;
      await bloc.close();
    });
  });
}

TextBookTab _createTextTab(String title) {
  return TextBookTab(
    book: TextBook(title: title),
    index: 0,
  );
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({
    required List<Workspace> workspaces,
    required String this._activeWorkspaceId,
  }) : _workspaces = List<Workspace>.from(workspaces);

  List<Workspace> _workspaces;
  String? _activeWorkspaceId;

  @override
  (List<Workspace>, String?) loadWorkspaces() =>
      (List<Workspace>.from(_workspaces), _activeWorkspaceId);

  @override
  Future<void> saveWorkspaces(
    List<Workspace> workspaces,
    String? currentWorkspaceId,
  ) async {
    _workspaces = List<Workspace>.from(workspaces);
    _activeWorkspaceId = currentWorkspaceId;
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
