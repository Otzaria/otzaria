import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:path/path.dart' as path;

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
}

class _DevelopmentRepo extends _FakeRepo {
  final plugins = <InstalledPlugin>[];
  Map<String, bool> permissions = {};

  @override
  Future<InstalledPlugin?> getPlugin(String id) async =>
      plugins.where((plugin) => plugin.pluginId == id).firstOrNull;

  @override
  Future<int?> getNextUserOrderForNewPlugin() async => null;

  @override
  Future<void> saveDevelopmentPluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> grants,
  ) async {
    plugins.add(plugin);
    permissions = Map.of(grants);
  }

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => List.of(plugins);

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async =>
      List.of(plugins);
}

/// מחזיר PreparedInstall קבוע — הטסט בודק את ההעברה לבלוק, לא את הפריקה.
class _StubInstaller extends PluginInstallerService {
  _StubInstaller(this.prepared) : super(repository: _FakeRepo());

  final PreparedInstall prepared;

  @override
  Future<PreparedInstall> prepareInstall(
    String archivePath, {
    bool forceOverwrite = false,
  }) async => prepared;
}

PluginManifest _manifest() => PluginManifest.fromJson({
  'schemaVersion': 1,
  'id': 'test.plugin',
  'name': 'תוסף',
  'version': '1.0.1',
  'entrypoint': 'index.html',
  'permissions': ['app.info.read', 'notes.read'],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('התקנת תוסף פיתוח מתיקייה', () {
    late Directory directory;
    late _DevelopmentRepo repository;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('otzaria-dev-install');
      repository = _DevelopmentRepo();
      await File(path.join(directory.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'id': 'test.ui.plugin',
          'name': 'UI Dev Plugin',
          'version': '1.0.0',
          'entrypoint': 'index.html',
          'permissions': [],
        }),
      );
      await File(path.join(directory.path, 'index.html')).writeAsString('');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    blocTest<PluginSystemBloc, PluginSystemState>(
      'תוסף חדש ממתין לאישור הרשאות ורק אז נשמר ונטען',
      build: () => PluginSystemBloc(repository: repository),
      act: (bloc) async {
        final pending = bloc.stream.firstWhere(
          (state) => state is PluginSystemDevInstallRequiresPermissions,
        );
        bloc.add(LoadDevelopmentPluginRequested(directory.path));
        final request =
            (await pending) as PluginSystemDevInstallRequiresPermissions;

        expect(request.manifest.id, 'test.ui.plugin');
        expect(request.sourcePath, directory.path);
        expect(request.sourceType, 'development');
        expect(repository.plugins, isEmpty);

        final loaded = bloc.stream.firstWhere(
          (state) => state is PluginSystemLoaded,
        );
        bloc.add(
          ConfirmDevPluginInstall(
            manifest: request.manifest,
            sourcePath: request.sourcePath,
            sourceType: request.sourceType,
            grantedPermissions: const {},
            allowOrderBeforeBuiltInsGranted: false,
          ),
        );
        await loaded;
      },
      expect: () => [
        isA<PluginSystemDevInstallRequiresPermissions>(),
        isA<PluginSystemLoading>(),
        isA<PluginSystemLoaded>().having(
          (state) => state.plugins.single.pluginId,
          'pluginId',
          'test.ui.plugin',
        ),
      ],
      verify: (_) {
        final plugin = repository.plugins.single;
        expect(plugin.pluginId, 'test.ui.plugin');
        expect(plugin.name, 'UI Dev Plugin');
        expect(plugin.sourceType, 'development');
        expect(plugin.devRootPath, directory.path);
        expect(repository.permissions, isEmpty);
      },
    );
  });

  test(
    'InstallPluginRequested מעביר הרשאות קודמות ומקור יוזמה אל ה-state',
    () async {
      const previousGrants = {'app.info.read': false};
      final bloc = PluginSystemBloc(
        repository: _FakeRepo(),
        installerService: _StubInstaller(
          PreparedInstall(
            _manifest(),
            '/tmp/staged',
            true,
            previousVersion: '1.0.0',
            previousGrantedPermissions: previousGrants,
          ),
        ),
      );
      addTearDown(bloc.close);

      final pending = bloc.stream.firstWhere(
        (s) => s is PluginSystemInstallRequiresPermissions,
      );
      bloc.add(const InstallPluginRequested('/tmp/plugin.zip'));

      final requiresPermissions =
          (await pending) as PluginSystemInstallRequiresPermissions;
      expect(requiresPermissions.previousVersion, '1.0.0');
      expect(requiresPermissions.previousGrantedPermissions, previousGrants);
      expect(requiresPermissions.isUserInitiated, isFalse);
    },
  );

  test('שומר התקנה יזומה במסלול התקנת קובץ', () async {
    final bloc = PluginSystemBloc(
      repository: _FakeRepo(),
      installerService: _StubInstaller(
        PreparedInstall(_manifest(), '/tmp/staged', false),
      ),
    );
    addTearDown(bloc.close);

    final pending = bloc.stream.firstWhere(
      (s) => s is PluginSystemInstallRequiresPermissions,
    );
    bloc.add(
      const InstallPluginRequested(
        '/tmp/plugin.otzplugin',
        isUserInitiated: true,
      ),
    );

    final state = (await pending) as PluginSystemInstallRequiresPermissions;
    expect(state.isUserInitiated, isTrue);
  });
}
