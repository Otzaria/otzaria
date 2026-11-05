import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';

PluginManifest _manifest(String id, String name, String version) =>
    PluginManifest.fromJson({
      'schemaVersion': 1,
      'id': id,
      'name': name,
      'version': version,
      'entrypoint': 'index.html',
    });

InstalledPlugin _installed(
  String id,
  String name,
  String version, {
  String sourceType = 'packaged',
}) => InstalledPlugin(
  pluginId: id,
  name: name,
  version: version,
  installPath: '/x/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: _manifest(id, name, version),
  installedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  sourceType: sourceType,
);

class _FakeRepo extends Mock implements PluginRegistryRepository {
  _FakeRepo(this.plugins);
  final List<InstalledPlugin> plugins;
  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => plugins;
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
}

/// finalizeInstall אינו נוגע בדיסק — הטסט בודק רק את זיהוי הכפילות אחריו.
class _StubInstaller extends PluginInstallerService {
  _StubInstaller(PluginRegistryRepository repo) : super(repository: repo);

  @override
  Future<void> finalizeInstall(
    String tempDirPath,
    PluginManifest manifest, {
    required Map<String, bool> grantedPermissions,
    InstalledPlugin? expectedPlugin,
    Map<String, bool> expectedPermissions = const {},
  }) async {}
}

const _name = 'וורד לאוצריא';

void main() {
  // UiSnack.showSuccess רץ לפני זיהוי הכפילות ודורש binding (בלי navigator הוא רק מדפיס).
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'תוסף מותקן באותו שם עם id אחר → PluginSystemDuplicateNameDetected',
    () async {
      final newManifest = _manifest('com.new.word', _name, '5.1.0');
      final repo = _FakeRepo([
        _installed('com.old.word', _name, '1.3.6'),
        _installed('com.new.word', _name, '5.1.0'),
        _installed('other.plugin', 'אחר', '1.0.0'),
        // תוסף פיתוח באותו שם אינו מועמד להסרה
        _installed('dev.word', _name, '0.0.1', sourceType: 'development'),
      ]);
      final bloc = PluginSystemBloc(
        repository: repo,
        installerService: _StubInstaller(repo),
      );
      addTearDown(bloc.close);

      final pending = bloc.stream.firstWhere(
        (s) => s is PluginSystemDuplicateNameDetected,
      );
      bloc.add(
        ConfirmPluginInstall('/tmp/staged', newManifest, const {}),
      );

      final state = (await pending) as PluginSystemDuplicateNameDetected;
      expect(state.installedPluginId, 'com.new.word');
      expect(state.pluginName, _name);
      expect(state.duplicates.map((p) => p.pluginId), ['com.old.word']);
    },
  );

  test('בלי כפילות שם — אין PluginSystemDuplicateNameDetected', () async {
    final newManifest = _manifest('com.new.word', _name, '5.1.0');
    final repo = _FakeRepo([
      _installed('com.new.word', _name, '5.1.0'),
      _installed('other.plugin', 'אחר', '1.0.0'),
    ]);
    final bloc = PluginSystemBloc(
      repository: repo,
      installerService: _StubInstaller(repo),
    );
    addTearDown(bloc.close);

    final emitted = <PluginSystemState>[];
    final sub = bloc.stream.listen(emitted.add);
    addTearDown(sub.cancel);
    bloc.add(ConfirmPluginInstall('/tmp/staged', newManifest, const {}));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(emitted.whereType<PluginSystemDuplicateNameDetected>(), isEmpty);
  });
}
