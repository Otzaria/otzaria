import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/search/settings_search_field.dart';
import 'package:otzaria/settings/search/settings_search_results_view.dart';
import 'package:otzaria/settings/view/settings_screen.dart';

import '../test_helpers/memory_cache_provider.dart';

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _PluginBloc extends Cubit<PluginSystemState> implements PluginSystemBloc {
  _PluginBloc() : super(PluginSystemInitial());

  void publish(PluginSystemState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

InstalledPlugin _plugin({String name = 'תוסף מיוחד', String description = ''}) {
  return InstalledPlugin(
    pluginId: 'org.search.fixture',
    name: name,
    version: '1.0.0',
    installPath: '/plugins/fixture',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    manifest: PluginManifest.fromJson({
      'schemaVersion': 1,
      'id': 'org.search.fixture',
      'name': name,
      'description': description,
      'version': '1.0.0',
      'entrypoint': 'index.html',
    }),
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  for (final width in [360.0, 1400.0]) {
    testWidgets('חיפוש פעיל מתעדכן עם טעינה, שינוי והסרת תוסף ($width)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final settings = _SettingsBloc();
      final navigation = _NavigationBloc();
      final plugins = _PluginBloc();
      addTearDown(plugins.close);
      whenListen(
        settings,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(
          settingsLanguageCode: 'he',
        ),
      );
      whenListen(
        navigation,
        const Stream<NavigationState>.empty(),
        initialState: const NavigationState(currentScreen: Screen.settings),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RepositoryProvider<SettingsRepository>.value(
            value: _SettingsRepository(),
            child: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsBloc>.value(value: settings),
                BlocProvider<NavigationBloc>.value(value: navigation),
                BlocProvider<PluginSystemBloc>.value(value: plugins),
              ],
              child: const MySettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(SettingsSearchField),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, 'תוסף מיוחד');
      await tester.pumpAndSettle();
      SettingsSearchResultsView results() =>
          tester.widget(find.byType(SettingsSearchResultsView));
      expect(results().results, isEmpty);
      final editor = tester.widget<EditableText>(field);
      final editingValue = editor.controller.value;
      expect(editor.focusNode.hasFocus, isTrue);

      Future<void> publish(PluginSystemState state) async {
        plugins.publish(state);
        await tester.pumpAndSettle();
        expect(
          tester.widget<EditableText>(field).controller.value,
          editingValue,
        );
        expect(
          tester.widget<EditableText>(field).focusNode,
          same(editor.focusNode),
        );
        expect(editor.focusNode.hasFocus, isTrue);
      }

      await publish(PluginSystemLoading());
      expect(results().results, isEmpty);
      final plugin = _plugin();
      await publish(PluginSystemLoaded([plugin]));
      expect(results().results.single.title, 'תוסף מיוחד');
      final beforePin = results();
      await publish(
        PluginSystemLoaded([plugin.copyWith(pinnedToNavRail: true)]),
      );
      expect(
        results(),
        same(beforePin),
        reason: 'הצמדה אינה משנה את אינדקס החיפוש',
      );

      await publish(
        PluginSystemLoaded([
          _plugin(name: 'שם חדש', description: 'תוסף מיוחד'),
        ]),
      );
      expect(results().results.single.title, 'שם חדש');
      await publish(PluginSystemLoaded([_plugin(name: 'שם חדש')]));
      expect(results().results, isEmpty);
      await publish(PluginSystemLoaded([plugin]));
      expect(results().results.single.title, 'תוסף מיוחד');
      await publish(const PluginSystemLoaded([]));
      expect(results().results, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
