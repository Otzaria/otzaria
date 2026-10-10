import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
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

class _GrantedRegistry extends PluginRegistryRepository {
  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

class _Field implements PluginSearchFieldBinding {
  TextEditingValue value = const TextEditingValue(
    text: 'ברכות',
    selection: TextSelection.collapsed(offset: 5),
  );

  @override
  PluginSearchField get field => PluginSearchField.inBook;

  @override
  TextEditingValue get currentValue => value;

  @override
  void applyPluginText(TextEditingValue next) => value = next;

  @override
  void submit() {}
}

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: 'Voice',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: 'Voice',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '0.9.99',
    sdkVersion: '1.x',
    permissions: const ['search.field_actions'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Voice',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late PluginSearchFieldSessionService sessions;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    sessions = PluginSearchFieldSessionService.forTesting(
      (_, _, _, {preferBackground = false, instanceId}) async {},
    );
  });

  PluginBridgeHandler handlerFor(String pluginId) {
    final plugin = _plugin(pluginId);
    return PluginBridgeHandler(
      plugin,
      registry: _GrantedRegistry(),
      adapter: PluginBridgeAdapter(
        plugin,
        instanceId: 'background',
        searchFieldSessions: sessions,
        pluginRepository: _GrantedRegistry(),
        dependencies: PluginBridgeDependencies(
          historyBloc: _MockHistoryBloc(),
          tabsBloc: _MockTabsBloc(),
          navigationBloc: _MockNavigationBloc(),
          calendarCubit: _MockCalendarCubit(),
          workspaceBloc: _MockWorkspaceBloc(),
          searchRepository: _MockSearchRepository(),
          personalNotesRepository: _MockPersonalNotesRepository(),
          bookOpenCoordinator: _MockBookOpenCoordinator(),
          themePayloadBuilder: () => <String, dynamic>{},
          showConfirmDialog: ({required title, required content}) async => true,
          showWarningDialog:
              ({required title, required content, required subtitle}) async =>
                  true,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> call(
    PluginBridgeHandler handler,
    String method,
    Map<String, dynamic> payload,
  ) async =>
      await handler.handleRpcForTesting([
            {'method': method, 'payload': payload},
          ])
          as Map<String, dynamic>;

  test('RPC אמיתי כותב לשדה; סשן של תוסף אחר מחזיר error.not_found', () async {
    final field = _Field();
    await sessions.press(binding: field, pluginId: 'voice', actionId: 'd');
    final sessionId = sessions.sessionFor(field, 'voice', 'd')!.id;

    final ok = await call(handlerFor('voice'), 'search.setFieldText', {
      'sessionId': sessionId,
      'text': 'דף ב',
    });
    expect(ok['success'], isTrue);
    expect(field.value.text, 'ברכות דף ב');

    final foreign = await call(handlerFor('other'), 'search.setFieldText', {
      'sessionId': sessionId,
      'text': 'דריסה',
    });
    expect(foreign['error']['code'], 'error.not_found');

    final badState = await call(
      handlerFor('voice'),
      'search.setFieldActionState',
      {'sessionId': sessionId, 'state': 'loud'},
    );
    expect(badState['error']['code'], 'error.invalid_params');

    final end = await call(handlerFor('voice'), 'search.endFieldSession', {
      'sessionId': sessionId,
    });
    expect(end['success'], isTrue);
    final afterEnd = await call(handlerFor('voice'), 'search.setFieldText', {
      'sessionId': sessionId,
      'text': 'x',
    });
    expect(afterEnd['error']['code'], 'error.not_found');
    expect(field.value.text, 'ברכות דף ב');
  });
}
