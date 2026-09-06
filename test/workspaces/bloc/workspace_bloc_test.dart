import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
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
        onWorkspaceTabsChanged: (tabs, _, _) {
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
        onWorkspaceTabsChanged: (tabs, _, _) {
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
        onWorkspaceTabsChanged: (_, _, _) {
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

    test('כשל שמירה משאיר את הכרטיסיות במקומן ואינו מחליף שולחן', () async {
      final firstWorkspace = Workspace(name: 'א', tabs: const []);
      final secondWorkspace = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [firstWorkspace, secondWorkspace],
        activeWorkspaceId: firstWorkspace.id,
      )..failMutate = false;

      var callbackCalls = 0;
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (_, _, _) => callbackCalls++,
      )..add(LoadWorkspaces());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      repository.failMutate = true;
      final liveTab = _createTextTab('ספר חי');
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: secondWorkspace.id,
          currentTabsToSave: [liveTab],
          currentTabIndexToSave: 0,
        ),
      );

      await bloc.stream.firstWhere((s) => s.error != null);

      // ⚠️ זה הלב: ההחלפה משחררת את הכרטיסיות של השולחן הנעזב, ולכן היא
      // אסורה כשהשמירה נכשלה — אחרת הן אינן בשום box ובשום state.
      expect(callbackCalls, 0);
      expect(bloc.state.activeWorkspaceId, firstWorkspace.id);

      await bloc.close();
      liveTab.dispose();
    });

    test('שגיאה אינה נמחקת ב-emit הבא, ו-clearError מאפס אותה', () {
      final state = WorkspaceState(workspaces: const [], error: 'boom');

      expect(state.copyWith(isLoading: true).error, 'boom');
      expect(state.copyWith(clearError: true).error, isNull);
    });

    test('copyWith יכול לאפס את השולחן הפעיל ל-null', () {
      final state = WorkspaceState(
        workspaces: const [],
        activeWorkspaceId: 'w1',
      );

      expect(state.copyWith(activeWorkspaceId: null).activeWorkspaceId, 'w1');
      expect(
        state.copyWith(clearActiveWorkspaceId: true).activeWorkspaceId,
        isNull,
      );
    });
  });

  group('WorkspaceBloc בחלון משני', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      WindowRole.isSecondary = true;
    });

    tearDown(() => WindowRole.isSecondary = false);

    test('אינו ננעל על השולחן של הבעלים כשהרשימה חוזרת לא ריקה', () async {
      // המרוץ: `load` מחזיר רשימה ריקה כי הבעלים עוד טוען, אבל עד ה-`mutate`
      // הרשימה שלו כבר קיימת — וה-`apply` מחזיר את השולחנות שלו.
      final ownerWorkspace = Workspace(name: 'של הבעלים', tabs: const []);
      final repository = _FakeWorkspaceRepository.empty()
        ..workspacesOnMutate = [ownerWorkspace];

      final bloc = WorkspaceBloc(repository: repository)..add(LoadWorkspaces());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(bloc.state.workspaces, hasLength(1));
      expect(bloc.state.activeWorkspaceId, isNull);

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

  /// רשימה ריקה בטעינה — כמו חלון משני שנפתח בזמן שהבעלים עוד טוען.
  _FakeWorkspaceRepository.empty()
    : _workspaces = <Workspace>[],
      _activeWorkspaceId = null;

  List<Workspace> _workspaces;
  String? _activeWorkspaceId;

  /// `mutateWorkspaces` זורק — כמו `SharedHiveUnavailable` בחלון משני.
  bool failMutate = false;

  /// מה שיהיה ברשימה ברגע ה-`mutate`, גם אם הטעינה החזירה ריק.
  List<Workspace>? workspacesOnMutate;

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async =>
      (List<Workspace>.from(_workspaces), _activeWorkspaceId);

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) async {
    if (failMutate) throw StateError('shared store unavailable');
    final current = workspacesOnMutate ?? _workspaces;
    _workspaces = List<Workspace>.from(apply(List<Workspace>.from(current)));
    workspacesOnMutate = null;
    return List<Workspace>.from(_workspaces);
  }

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {
    _activeWorkspaceId = id;
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
