import 'dart:async';
import 'dart:io';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/models/books.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
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
  installedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

InstalledPlugin _startupPlugin(String id, {String version = '1.0.0'}) =>
    InstalledPlugin(
      pluginId: id,
      name: id,
      version: version,
      installPath: '/plugins/$id',
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      manifest: PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': id,
        'name': id,
        'version': version,
        'entrypoint': 'index.html',
        'permissions': const ['app.startup_contributions'],
        'contributes': {
          'startup': {
            'toolbarItems': [
              {'id': 'b1', 'title': 'כפתור', 'icon': 'apps_24_regular'},
            ],
          },
        },
      }),
      installedAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// סופר קריאות syncPlugins כדי לאמת שהסנכרון היקר מדולג כשהקלט לא השתנה.
class _CountingHost implements DeclarativePluginHost {
  int syncCount = 0;

  @override
  Future<void> syncPlugins(List<InstalledPlugin> plugins) async => syncCount++;

  @override
  void removePlugin(String pluginId) {}

  @override
  Future<void> readerBookChanged(Book? book, {required String context}) async {}

  @override
  Future<void> dispatchAction(
    String pluginId,
    CompiledDeclarativeAction action,
  ) async {}

  @override
  Future<void> dispatchSelectionAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> selectionPayload,
  ) async {}

  @override
  Future<void> dispatchLibraryBookAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> bookPayload,
  ) async {}

  @override
  void dispose() {}
}

class _FakeRepo implements PluginRegistryRepository {
  List<InstalledPlugin> plugins;

  _FakeRepo(this.plugins);

  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => List.of(plugins);

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => null;

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  Future<bool?> getPermission(String id, String perm) async => null;

  Map<String, List<String>> grantedByPlugin = {};

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async =>
      grantedByPlugin[id] ?? const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
    'שני חלונות חולקים צופה וטעינה אחת ושחרור חלון אינו מפסיק את האחר',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp('plugin-watch-');
      final script = File('${directory.path}/index.js');
      await script.writeAsString('initial');
      final plugin = _plugin('watch.shared').copyWith(
        sourceType: 'development',
        devRootPath: directory.path,
      );
      final a = PluginSystemBloc(repository: _FakeRepo([]));
      final b = PluginSystemBloc(repository: _FakeRepo([]));
      final runtime = PluginRuntimeDispatcher.instance;
      var reloaded = Completer<void>();
      var reloads = 0;
      runtime.registerReloadCallback(plugin.pluginId, () async {
        reloads++;
        if (!reloaded.isCompleted) reloaded.complete();
      });
      addTearDown(() async {
        if (!a.isClosed) await a.close();
        await b.close();
        runtime.unregisterReloadCallback(plugin.pluginId);
        await directory.delete(recursive: true);
      });
      expect(a.devWatchService, same(b.devWatchService));
      a.devWatchService.syncWatchers([plugin]);
      await a.devWatchService.watching(plugin.pluginId);
      await script.writeAsString('changed');
      await reloaded.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(reloads, 1);
      await a.close();
      final nextReload = runtime.reloadPlugin(plugin.pluginId);
      await nextReload;
      expect(reloads, 2);
    },
  );

  group('LoadPlugins', () {
    test('טעינה ראשונה עוברת דרך PluginSystemLoading', () async {
      final bloc = PluginSystemBloc(repository: _FakeRepo([_plugin('a')]));
      addTearDown(bloc.close);

      final emitted = <PluginSystemState>[];
      final sub = bloc.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      bloc.add(LoadPlugins());
      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

      expect(emitted.first, isA<PluginSystemLoading>());
    });

    // רגרסיה: מצב "טוען" בטעינה חוזרת גרם לכל צרכן שבודק `is! PluginSystemLoaded`
    // לראות לרגע קטלוג ריק — ולתוסף פתוח להיטען מאפס (ראה tool_tab_screen).
    test('טעינה חוזרת אינה חוזרת ל-PluginSystemLoading', () async {
      final repo = _FakeRepo([_plugin('a')]);
      final bloc = PluginSystemBloc(repository: repo);
      addTearDown(bloc.close);

      bloc.add(LoadPlugins());
      await bloc.stream.firstWhere((s) => s is PluginSystemLoaded);

      final emitted = <PluginSystemState>[];
      final sub = bloc.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      // התוצאה חייבת להשתנות כדי שה-Bloc יפיץ state חדש בכלל.
      repo.plugins = [_plugin('a'), _plugin('b')];
      bloc.add(LoadPlugins());
      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

      expect(emitted.whereType<PluginSystemLoading>(), isEmpty);
    });

    test(
      'טעינה חוזרת אינה מסנכרנת שוב את ה-host כשהקלט הדקלרטיבי לא השתנה',
      () async {
        final repo = _FakeRepo([_startupPlugin('a')])
          ..grantedByPlugin['a'] = ['app.startup_contributions'];
        final host = _CountingHost();
        final bloc = PluginSystemBloc(repository: repo, declarativeHost: host);
        addTearDown(bloc.close);

        bloc.add(LoadPlugins());
        await bloc.stream.firstWhere((s) => s is PluginSystemLoaded);
        expect(host.syncCount, 1);

        // הוספת תוסף בלי contributes.startup משנה את ה-state (טעינה חוזרת) אך
        // לא את קלט הסנכרון הדקלרטיבי — ולכן אין syncPlugins נוסף.
        repo.plugins = [_startupPlugin('a'), _plugin('b')];
        bloc.add(LoadPlugins());
        await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
        expect(host.syncCount, 1);
      },
    );

    test('טעינה חוזרת מסנכרנת שוב כשגרסת תוסף התרומות משתנה', () async {
      final repo = _FakeRepo([_startupPlugin('a')])
        ..grantedByPlugin['a'] = ['app.startup_contributions'];
      final host = _CountingHost();
      final bloc = PluginSystemBloc(repository: repo, declarativeHost: host);
      addTearDown(bloc.close);

      bloc.add(LoadPlugins());
      await bloc.stream.firstWhere((s) => s is PluginSystemLoaded);
      expect(host.syncCount, 1);

      repo.plugins = [_startupPlugin('a', version: '1.0.1')];
      bloc.add(LoadPlugins());
      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
      expect(host.syncCount, 2);
    });
  });
}
