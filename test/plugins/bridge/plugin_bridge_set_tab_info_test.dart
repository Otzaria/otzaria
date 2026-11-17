import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_api_catalog.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_tab_info.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _RecordingTabsBloc extends Mock implements TabsBloc {
  TabsState currentState = const TabsState(tabs: [], currentTabIndex: 0);
  final List<TabsEvent> events = [];

  @override
  TabsState get state => currentState;

  @override
  void add(TabsEvent event) => events.add(event);
}

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockPluginRegistryRepository extends Mock
    implements PluginRegistryRepository {}

const _pluginId = 'test.plugin';

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: _pluginId,
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: _pluginId,
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'שני טורים',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late _RecordingTabsBloc tabsBloc;

  PluginBridgeAdapter buildAdapter(String instanceId) => PluginBridgeAdapter(
    _plugin(),
    instanceId: instanceId,
    dependencies: PluginBridgeDependencies(
      historyBloc: _MockHistoryBloc(),
      tabsBloc: tabsBloc,
      navigationBloc: _MockNavigationBloc(),
      calendarCubit: _MockCalendarCubit(),
      workspaceBloc: _MockWorkspaceBloc(),
      searchRepository: _MockSearchRepository(),
      personalNotesRepository: _MockPersonalNotesRepository(),
      bookOpenCoordinator: _MockBookOpenCoordinator(),
      themePayloadBuilder: () => <String, dynamic>{},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async => true,
    ),
    pluginRepository: _MockPluginRegistryRepository(),
  );

  ToolTab pluginTab(String instanceId, {String toolId = _pluginId}) => ToolTab(
    toolId: toolId,
    title: 'שני טורים',
    instanceId: instanceId,
    allowMultipleInstances: true,
  );

  void openTabs(List<ToolTab> tabs) {
    tabsBloc.currentState = TabsState(tabs: tabs, currentTabIndex: 0);
  }

  SetPluginTabInfo lastEvent() => tabsBloc.events.single as SetPluginTabInfo;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() => tabsBloc = _RecordingTabsBloc());

  test('בלי הרשאת manifest, מגרסה 0.9.99', () {
    expect(
      PluginBridgeHandler.methodPermissions['ui.setTabInfo'],
      PluginBridgeHandler.noManifestPermission,
    );
    expect(pluginApiMinVersions['ui.setTabInfo'], '0.9.99');
  });

  test('מעדכן את הטאב של המופע הקורא בלבד', () async {
    final mine = pluginTab('mine');
    final sibling = pluginTab('sibling');
    final other = pluginTab('mine', toolId: 'other.plugin');
    openTabs([sibling, other, mine]);

    final result = await buildAdapter('mine').execute('ui', 'setTabInfo', {
      'title': '  בראשית א  ',
      'tooltip': 'בראשית פרק א',
    });

    expect(result, isTrue);
    final event = lastEvent();
    expect(event.tab, same(mine));
    expect(event.update.title, 'בראשית א');
    expect(event.update.tooltip, 'בראשית פרק א');
  });

  test('מוצא את הטאב גם כחלונית בתוך טאב מפוצל', () async {
    final pane = pluginTab('mine');
    tabsBloc.currentState = TabsState(
      tabs: [
        CombinedTab(
          rightTab: TextBookTab(book: TextBook(title: 'בראשית'), index: 0),
          leftTab: pane,
        ),
      ],
      currentTabIndex: 0,
    );

    expect(
      await buildAdapter('mine').execute('ui', 'setTabInfo', {'title': 'א'}),
      isTrue,
    );
    expect(lastEvent().tab, same(pane));
  });

  test('שדה חסר אינו נוגע בשדה, null מאפס', () async {
    openTabs([pluginTab('mine')]);

    await buildAdapter('mine').execute('ui', 'setTabInfo', {'title': 'א'});
    expect(lastEvent().update.hasTooltip, isFalse);

    tabsBloc.events.clear();
    await buildAdapter('mine').execute('ui', 'setTabInfo', {'tooltip': null});
    final update = lastEvent().update;
    expect(update.hasTitle, isFalse);
    expect(update.hasTooltip, isTrue);
    expect(update.tooltip, isNull);
  });

  test('כותרת ארוכה ותווי בקרה מנוקים לפני שנשלחים לטאב', () async {
    openTabs([pluginTab('mine')]);

    await buildAdapter('mine').execute('ui', 'setTabInfo', {
      'title': 'א' * 500,
      'tooltip': 'ב${String.fromCharCode(0x202E)}' * 1000,
    });

    final update = lastEvent().update;
    expect(update.title!.length, kMaxPluginTabTitleLength);
    expect(update.tooltip!.length, kMaxPluginTabTooltipLength);
    expect(update.tooltip, isNot(contains(String.fromCharCode(0x202E))));
  });

  test('מופע בלי טאב (רקע, או שהטאב נסגר) — false ובלי אירוע', () async {
    openTabs([pluginTab('sibling')]);

    final result = await buildAdapter('mine').execute('ui', 'setTabInfo', {
      'title': 'א',
    });

    expect(result, isFalse);
    expect(tabsBloc.events, isEmpty);
  });

  test('פרמטרים שגויים נדחים כ-invalid_params ולא נשלח אירוע', () async {
    openTabs([pluginTab('mine')]);
    final adapter = buildAdapter('mine');
    for (final args in <Map<String, dynamic>>[
      {},
      {'title': 5},
      {
        'tooltip': <String>['א'],
      },
    ]) {
      expect(
        () => adapter.execute('ui', 'setTabInfo', args),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
        reason: '$args',
      );
    }
    expect(tabsBloc.events, isEmpty);
  });
}
