import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _StubTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = TabsState.initial();

  @override
  TabsState get state => currentState;
}

/// מחסן שולחנות עבודה בזיכרון — עוקף את Hive, שאינו פתוח בבדיקות.
class _InMemoryWorkspaceRepository extends WorkspaceRepository {
  _InMemoryWorkspaceRepository({
    List<Workspace> workspaces = const [],
    this.activeWorkspaceId,
  }) : workspaces = List<Workspace>.from(workspaces);

  List<Workspace> workspaces;
  String? activeWorkspaceId;

  @override
  (List<Workspace>, String?) loadWorkspaces() =>
      (List<Workspace>.from(workspaces), activeWorkspaceId);

  @override
  Future<void> saveWorkspaces(
    List<Workspace> workspaces,
    String? currentWorkspaceId,
  ) async {
    this.workspaces = List<Workspace>.from(workspaces);
    activeWorkspaceId = currentWorkspaceId;
  }
}

InstalledPlugin _plugin(List<String> permissions) => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _codedError(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

void main() {
  late _StubTabsBloc tabsBloc;
  late WorkspaceBloc workspaceBloc;
  late _InMemoryWorkspaceRepository workspaceRepository;
  late List<OpenedTab> loadedTabs;
  final trackedTabs = <OpenedTab>[];

  PluginBridgeAdapter buildAdapter() => PluginBridgeAdapter(
    _plugin(const ['workspace.read', 'workspace.manage']),
    dependencies: PluginBridgeDependencies(
      historyBloc: _MockHistoryBloc(),
      tabsBloc: tabsBloc,
      navigationBloc: _MockNavigationBloc(),
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: workspaceBloc,
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      bookmarkBloc: BookmarkBloc(BookmarkRepository()),
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
    ),
    pluginRepository: PluginRegistryRepository(),
  );

  /// כל טאב שנוצר בבדיקה נרשם כאן ומשוחרר ב-tearDown.
  T track<T extends OpenedTab>(T tab) {
    trackedTabs.add(tab);
    return tab;
  }

  TextBookTab textTab(String title) =>
      track(TextBookTab(book: TextBook(title: title), index: 0));

  /// מאתחל את הבלוק עם שולחנות [workspaces] ומחכה לסיום הטעינה. ה-callback
  /// מדמה את מה שעושה `main.dart`: מעדכן את TabsBloc בטאבים של השולחן החדש.
  Future<void> loadWorkspaces(
    List<Workspace> workspaces, {
    String? activeId,
  }) async {
    workspaceRepository = _InMemoryWorkspaceRepository(
      workspaces: workspaces,
      activeWorkspaceId: activeId ?? workspaces.first.id,
    );
    workspaceBloc = WorkspaceBloc(
      repository: workspaceRepository,
      onWorkspaceTabsChanged: (tabs, index) {
        loadedTabs = tabs;
        trackedTabs.addAll(tabs);
        tabsBloc.currentState = TabsState(tabs: tabs, currentTabIndex: index);
      },
    )..add(LoadWorkspaces());
    await workspaceBloc.stream.firstWhere((state) => !state.isLoading);
  }

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    tabsBloc = _StubTabsBloc();
    loadedTabs = const [];
    trackedTabs.clear();
  });

  tearDown(() async {
    await workspaceBloc.close();
    for (final tab in trackedTabs) {
      tab.dispose();
    }
    trackedTabs.clear();
  });

  group('workspace.list', () {
    test('מחזיר שם, סימון פעיל ומספר כרטיסיות', () async {
      final first = Workspace(name: 'עיון בגמרא', tabs: const []);
      final second = Workspace(name: 'הלכה', tabs: [textTab('שולחן ערוך')]);
      await loadWorkspaces([first, second], activeId: first.id);
      tabsBloc.currentState = TabsState(
        tabs: [textTab('ברכות'), textTab('שבת')],
        currentTabIndex: 0,
      );

      final data =
          await buildAdapter().execute('workspace', 'list', {}) as List;

      expect(data, hasLength(2));
      expect(data[0]['id'], first.id);
      expect(data[0]['name'], 'עיון בגמרא');
      expect(data[0]['isActive'], isTrue);
      // השולחן הפעיל נספר מהמצב החי ב-TabsBloc, לא מהעותק השמור (שהוא ריק).
      expect(data[0]['tabCount'], 2);
      expect(data[1]['isActive'], isFalse);
      expect(data[1]['tabCount'], 1);
    });

    test('כרטיסיית כלי אינה נספרת — עקבי עם openTabs', () async {
      await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);
      tabsBloc.currentState = TabsState(
        tabs: [
          textTab('ברכות'),
          track(ToolTab(toolId: 'gematria', title: 'גימטריה')),
          textTab('שבת'),
        ],
        currentTabIndex: 0,
      );

      final data =
          await buildAdapter().execute('workspace', 'list', {}) as List;

      expect(data.single['tabCount'], 2);
    });
  });

  test('workspace.getActive מחזיר את מזהה השולחן הפעיל ושמו', () async {
    final first = Workspace(name: 'א', tabs: const []);
    final second = Workspace(name: 'ב', tabs: const []);
    await loadWorkspaces([first, second], activeId: second.id);

    final data =
        await buildAdapter().execute('workspace', 'getActive', {})
            as Map<String, dynamic>;

    expect(data['id'], second.id);
    expect(data['name'], 'ב');
  });

  group('workspace.create', () {
    test('יוצר שולחן ריק ומחזיר את המזהה שנוצר', () async {
      await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);

      final data =
          await buildAdapter().execute('workspace', 'create', {
                'name': 'חברותא — יוסי',
              })
              as Map<String, dynamic>;

      expect(data['created'], isTrue);
      final created = workspaceBloc.state.workspaces.singleWhere(
        (workspace) => workspace.id == data['id'],
      );
      expect(created.name, 'חברותא — יוסי');
      expect(created.tabs, isEmpty);
    });

    test('reuseExisting מחזיר שולחן קיים באותו שם ואינו יוצר כפילות', () async {
      final existing = Workspace(name: 'חברותא — יוסי', tabs: const []);
      await loadWorkspaces([
        Workspace(name: 'א', tabs: const []),
        existing,
      ], activeId: existing.id);

      final data =
          await buildAdapter().execute('workspace', 'create', {
                'name': 'חברותא — יוסי',
                'reuseExisting': true,
              })
              as Map<String, dynamic>;

      expect(data['id'], existing.id);
      expect(data['created'], isFalse);
      expect(workspaceBloc.state.workspaces, hasLength(2));
    });

    test('בלי reuseExisting אותו שם יוצר שולחן נוסף', () async {
      await loadWorkspaces([Workspace(name: 'חברותא', tabs: const [])]);

      final data =
          await buildAdapter().execute('workspace', 'create', {
                'name': 'חברותא',
              })
              as Map<String, dynamic>;

      expect(data['created'], isTrue);
      expect(workspaceBloc.state.workspaces, hasLength(2));
    });

    test('יצירות מקבילות מחזירות את המזהה של השולחן המתאים', () async {
      await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);

      final results = await Future.wait([
        buildAdapter().execute('workspace', 'create', {'name': 'ב'}),
        buildAdapter().execute('workspace', 'create', {'name': 'ג'}),
      ]);
      final ids = results
          .cast<Map<String, dynamic>>()
          .map((result) => result['id'])
          .toSet();

      expect(ids, hasLength(2));
      expect(
        workspaceBloc.state.workspaces.map((workspace) => workspace.name),
        containsAll(['א', 'ב', 'ג']),
      );
    });

    test('switchTo עובר לשולחן החדש ושומר את הכרטיסיות הנוכחיות', () async {
      final first = Workspace(name: 'א', tabs: const []);
      await loadWorkspaces([first]);
      tabsBloc.currentState = TabsState(
        tabs: [textTab('ברכות')],
        currentTabIndex: 0,
      );

      final data =
          await buildAdapter().execute('workspace', 'create', {
                'name': 'חדש',
                'switchTo': true,
              })
              as Map<String, dynamic>;

      expect(workspaceBloc.state.activeWorkspaceId, data['id']);
      final saved = workspaceBloc.state.workspaces.singleWhere(
        (workspace) => workspace.id == first.id,
      );
      expect(saved.tabs.map((tab) => tab.title), ['ברכות']);
      expect(loadedTabs, isEmpty);
    });

    test('שם ריק נדחה כשגיאת ארגומנטים', () async {
      await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);

      expect(
        () => buildAdapter().execute('workspace', 'create', {'name': '  '}),
        _codedError('error.invalid_params'),
      );
    });

    test('שם ארוך מדי נדחה', () async {
      await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);

      expect(
        () => buildAdapter().execute('workspace', 'create', {
          'name': 'א' * 101,
        }),
        _codedError('error.invalid_params'),
      );
    });
  });

  group('workspace.switch', () {
    test('מעבר שומר את הכרטיסיות הפתוחות וטוען את של היעד', () async {
      final source = Workspace(name: 'מקור', tabs: const []);
      final target = Workspace(name: 'יעד', tabs: [textTab('שולחן ערוך')]);
      await loadWorkspaces([source, target], activeId: source.id);
      tabsBloc.currentState = TabsState(
        tabs: [textTab('ברכות'), textTab('שבת')],
        currentTabIndex: 1,
      );

      final result = await buildAdapter().execute('workspace', 'switch', {
        'id': target.id,
      });

      expect(result, isTrue);
      expect(workspaceBloc.state.activeWorkspaceId, target.id);
      final saved = workspaceBloc.state.workspaces.singleWhere(
        (workspace) => workspace.id == source.id,
      );
      expect(saved.tabs.map((tab) => tab.title), ['ברכות', 'שבת']);
      expect(saved.activeTabIndex, 1);
      expect(loadedTabs.map((tab) => tab.title), ['שולחן ערוך']);
    });

    test('כרטיסיית כלי נשמרת גם היא — נמסרת הרשימה המלאה', () async {
      final source = Workspace(name: 'מקור', tabs: const []);
      final target = Workspace(name: 'יעד', tabs: const []);
      await loadWorkspaces([source, target], activeId: source.id);
      tabsBloc.currentState = TabsState(
        tabs: [
          textTab('ברכות'),
          track(ToolTab(toolId: 'gematria', title: 'גימטריה')),
        ],
        currentTabIndex: 0,
      );

      await buildAdapter().execute('workspace', 'switch', {'id': target.id});

      final saved = workspaceBloc.state.workspaces.singleWhere(
        (workspace) => workspace.id == source.id,
      );
      expect(saved.tabs, hasLength(2));
    });

    test('מעברים מקבילים אינם דורסים את טאבי היעד', () async {
      final source = Workspace(name: 'מקור', tabs: const []);
      final middle = Workspace(name: 'אמצע', tabs: [textTab('שבת')]);
      final target = Workspace(name: 'יעד', tabs: [textTab('עירובין')]);
      await loadWorkspaces([source, middle, target], activeId: source.id);
      tabsBloc.currentState = TabsState(
        tabs: [textTab('ברכות')],
        currentTabIndex: 0,
      );

      await Future.wait([
        buildAdapter().execute('workspace', 'switch', {'id': middle.id}),
        buildAdapter().execute('workspace', 'switch', {'id': target.id}),
      ]);

      final savedMiddle = workspaceBloc.state.workspaces.singleWhere(
        (workspace) => workspace.id == middle.id,
      );
      expect(savedMiddle.tabs.map((tab) => tab.title), ['שבת']);
      expect(workspaceBloc.state.activeWorkspaceId, target.id);
      expect(loadedTabs.map((tab) => tab.title), ['עירובין']);
    });

    test('מזהה שאינו קיים מחזיר false ואינו מחליף שולחן', () async {
      final only = Workspace(name: 'א', tabs: const []);
      await loadWorkspaces([only]);

      final result = await buildAdapter().execute('workspace', 'switch', {
        'id': 'no-such-workspace',
      });

      expect(result, isFalse);
      expect(workspaceBloc.state.activeWorkspaceId, only.id);
    });

    test('מזהה חסר נדחה כשגיאת ארגומנטים', () async {
      await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);

      expect(
        () => buildAdapter().execute('workspace', 'switch', {}),
        _codedError('error.invalid_params'),
      );
    });

    test('מעבר לשולחן הפעיל מחזיר true ואינו עושה דבר', () async {
      final only = Workspace(name: 'א', tabs: const []);
      await loadWorkspaces([only]);
      tabsBloc.currentState = TabsState(
        tabs: [textTab('ברכות')],
        currentTabIndex: 0,
      );

      final result = await buildAdapter().execute('workspace', 'switch', {
        'id': only.id,
      });

      expect(result, isTrue);
      expect(loadedTabs, isEmpty);
    });
  });

  test('action שאינו קיים מוחזר כ-unknown_method', () async {
    await loadWorkspaces([Workspace(name: 'א', tabs: const [])]);

    expect(
      () => buildAdapter().execute('workspace', 'remove', {'id': 'x'}),
      _codedError('error.unknown_method'),
    );
  });
}
