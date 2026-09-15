import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _MockPluginRegistryRepository extends Mock
    implements PluginRegistryRepository {}

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return <OpenedTab>[];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
}

InstalledPlugin _plugin() => InstalledPlugin(
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
    permissions: const ['reader.open'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'עורך',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  const key = (pluginId: 'test.plugin', instanceId: 'tab-3');
  final registry = PluginUnsavedChangesRegistry.instance;

  PluginBridgeAdapter buildAdapter(
    TabsBloc tabsBloc, {
    bool warningAnswer = true,
    List<String>? warningsShown,
  }) => PluginBridgeAdapter(
    _plugin(),
    instanceId: 'tab-3',
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
          ({required title, required content, required subtitle}) async {
            warningsShown?.add(content);
            return warningAnswer;
          },
    ),
    pluginRepository: _MockPluginRegistryRepository(),
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() => registry.removeInstance(key));

  group('ui.setUnsavedChanges', () {
    test('אינה דורשת הרשאת manifest', () {
      expect(
        PluginBridgeHandler.methodPermissions['ui.setUnsavedChanges'],
        PluginBridgeHandler.noManifestPermission,
      );
    });

    test('מרימה ומנקה את הדגל של המופע הקורא בלבד', () async {
      final adapter = buildAdapter(_MockTabsBloc());

      expect(
        await adapter.execute('ui', 'setUnsavedChanges', {
          'hasChanges': true,
          'message': 'הטיוטה תאבד',
        }),
        isTrue,
      );
      expect(registry.hasUnsavedChanges(key), isTrue);
      expect(registry.messageFor(key), 'הטיוטה תאבד');
      expect(
        registry.hasUnsavedChanges((
          pluginId: 'test.plugin',
          instanceId: 'other',
        )),
        isFalse,
      );

      await adapter.execute('ui', 'setUnsavedChanges', {'hasChanges': false});
      expect(registry.hasUnsavedChanges(key), isFalse);
    });

    test('hasChanges שאינו בוליאני נדחה כ-invalid_params', () async {
      final adapter = buildAdapter(_MockTabsBloc());
      expect(
        () => adapter.execute('ui', 'setUnsavedChanges', {'hasChanges': 'yes'}),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.invalid_params'),
          ),
        ),
      );
      expect(registry.hasUnsavedChanges(key), isFalse);
    });

    test('dispose של האדפטר מנקה את הדגל', () async {
      final adapter = buildAdapter(_MockTabsBloc());
      await adapter.execute('ui', 'setUnsavedChanges', {'hasChanges': true});
      adapter.dispose();
      expect(registry.hasUnsavedChanges(key), isFalse);
    });
  });

  group('reader.closeTab על כרטיסיה מפוצלת עם תוסף שיש בו שינויים', () {
    late TabsBloc tabsBloc;

    setUp(() => tabsBloc = TabsBloc(repository: _FakeTabsRepository()));
    tearDown(() => tabsBloc.close());

    Future<void> openSplitWithDirtyPlugin() async {
      final pluginPane = ToolTab(
        toolId: 'test.plugin',
        title: 'עורך',
        instanceId: 'tab-3',
      );
      final combined = CombinedTab(
        rightTab: TextBookTab(book: TextBook(title: 'ברכות'), index: 0),
        leftTab: pluginPane,
      );
      tabsBloc.add(ReplaceAllTabs([combined], 0));
      await tabsBloc.stream
          .firstWhere((TabsState s) => s.tabs.length == 1)
          .timeout(const Duration(seconds: 5));
      registry.set(key, hasChanges: true, message: 'הטיוטה תאבד');
    }

    test('ביטול בדיאלוג משאיר את הכרטיסיה ומחזיר false', () async {
      await openSplitWithDirtyPlugin();
      final shown = <String>[];
      final result = await buildAdapter(
        tabsBloc,
        warningAnswer: false,
        warningsShown: shown,
      ).execute('reader', 'closeTab', {'index': 0});

      expect(result, isFalse);
      expect(shown.single, contains('הטיוטה תאבד'));
      expect(tabsBloc.state.tabs, hasLength(1));
    });

    test('אישור בדיאלוג סוגר את הכרטיסיה', () async {
      await openSplitWithDirtyPlugin();
      final result = await buildAdapter(
        tabsBloc,
      ).execute('reader', 'closeTab', {'index': 0});
      await tabsBloc.stream
          .firstWhere((TabsState s) => s.tabs.isEmpty)
          .timeout(const Duration(seconds: 5));

      expect(result, isTrue);
    });
  });
}
