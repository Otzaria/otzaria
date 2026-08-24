import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

PluginManifest _manifest({
  Map<String, dynamic>? startup,
  List<String> permissions = const ['app.startup_contributions'],
  List<Map<String, dynamic>> databaseSources = const [],
}) => PluginManifest.fromJson({
  'id': 'p1',
  'name': 'P1',
  'version': '1.0.0',
  'entrypoint': 'index.html',
  'permissions': permissions,
  'contributes': {
    'databaseSources': databaseSources,
    'startup': ?startup,
  },
});

InstalledPlugin _plugin(PluginManifest manifest) => InstalledPlugin(
  pluginId: 'p1',
  name: 'P1',
  version: '1.0.0',
  installPath: '/tmp/p1',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: manifest,
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _FakeRepo implements PluginRegistryRepository {
  _FakeRepo(this.plugins);

  List<InstalledPlugin> plugins;

  @override
  Future<void> setPermission(String id, String perm, bool granted) async {}

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => [];

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => plugins;

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  Future<String?> getKV(String a, String b, String c) async => null;

  @override
  Future<void> setKV(String a, String b, String c, String d) async {}

  @override
  Future<void> removeKV(String a, String b, String c) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeclarativeHost implements DeclarativePluginHost {
  final removed = <String>[];
  int syncs = 0;
  bool failNextSync = false;

  @override
  void removePlugin(String pluginId) => removed.add(pluginId);

  @override
  Future<void> syncPlugins(List<InstalledPlugin> plugins) async {
    syncs++;
    if (failNextSync) {
      failNextSync = false;
      throw StateError('sync failed');
    }
  }

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
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;
  late _FakeDeclarativeHost host;

  PluginSystemBloc build() {
    final bloc = PluginSystemBloc(repository: repo, declarativeHost: host);
    addTearDown(bloc.close);
    return bloc;
  }

  // מצב זהה אינו נפלט שוב מהבלוק, ולכן ממתינים לתור האירועים ולא ל-stream.
  Future<void> pump(PluginSystemBloc bloc, PluginSystemEvent event) async {
    bloc.add(event);
    await pumpEventQueue(times: 200);
  }

  setUp(() {
    host = _FakeDeclarativeHost();
    repo = _FakeRepo([
      _plugin(
        _manifest(
          startup: {
            'toolbarItems': [
              {'id': 'b', 'title': 'B', 'icon': 'apps_24_regular'},
            ],
          },
        ),
      ),
    ]);
  });

  test('שינוי הרשאה שהוא no-op עדיין מסנכרן מחדש אחרי removePlugin', () async {
    final bloc = build();
    await pump(bloc, LoadPlugins());
    expect(host.syncs, 1);

    // אין שינוי במניפסט/הרשאות — החתימה זהה, ובלי איפוסה המחיקה הייתה נשארת.
    await pump(
      bloc,
      const SetPluginPermissionRequested(
        pluginId: 'p1',
        permission: 'reader.open',
        granted: true,
      ),
    );

    expect(host.removed, ['p1']);
    expect(host.syncs, 2);
  });

  test('כשל בסנכרון אינו שומר את החתימה — הטעינה הבאה מנסה שוב', () async {
    host.failNextSync = true;
    final bloc = build();
    await pump(bloc, LoadPlugins());
    expect(bloc.state, isA<PluginSystemError>());
    expect(host.syncs, 1);

    await pump(bloc, LoadPlugins());
    expect(host.syncs, 2);
  });

  test(
    'שינוי databaseSources בלי שינוי startup/version מהפך את החתימה',
    () async {
      final bloc = build();
      await pump(bloc, LoadPlugins());
      expect(host.syncs, 1);

      // אותה גרסה, אותו startup — רק המניפסט השתנה.
      repo.plugins = [
        _plugin(
          _manifest(
            startup: {
              'toolbarItems': [
                {'id': 'b', 'title': 'B', 'icon': 'apps_24_regular'},
              ],
            },
            databaseSources: [
              {'id': 'src', 'path': 'data.db'},
            ],
          ),
        ),
      ];
      await pump(bloc, LoadPlugins());
      expect(host.syncs, 2);
    },
  );

  test('startup ריק אך קיים נכלל בחתימה ולכן שינוי בו מסנכרן', () async {
    repo.plugins = [
      _plugin(_manifest(startup: const {'keepAlive': true})),
    ];
    final bloc = build();
    await pump(bloc, LoadPlugins());
    expect(host.syncs, 1);

    repo.plugins = [
      _plugin(_manifest(startup: const {'keepAlive': false})),
    ];
    await pump(bloc, LoadPlugins());
    expect(host.syncs, 2);
  });

  test('טעינה חוזרת ללא שינוי אינה מסנכרנת שוב', () async {
    final bloc = build();
    await pump(bloc, LoadPlugins());
    await pump(bloc, LoadPlugins());
    expect(host.syncs, 1);
  });
}
