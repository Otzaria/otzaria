import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';

class FakeRepository extends Mock implements PluginRegistryRepository {
  final Map<String, InstalledPlugin> plugins = {};
  final List<String> savedIds = [];

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => plugins[id];

  @override
  Future<void> savePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
  ) async {
    plugins[plugin.pluginId] = plugin;
    savedIds.add(plugin.pluginId);
  }

  @override
  Future<int?> getNextUserOrderForNewPlugin() async => null;
}

void writePluginArchive(String path, String pluginId) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.0',
          'name': 'Bundled',
          'entrypoint': 'index.html',
        }),
      ),
    )
    ..addFile(ArchiveFile.string('index.html', '<html></html>'));
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Otzaria',
    packageName: 'com.otzaria.app',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  late Directory tempDir;
  late Directory bundleDir;
  late FakeRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = Directory.systemTemp.createTempSync('otzaria_bundled_seed_');
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data'));
    bundleDir = Directory(p.join(tempDir.path, 'bundled_plugins'))
      ..createSync();
    repository = FakeRepository();
  });

  tearDown(() {
    AppPaths.debugOverrideDataRootPath(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  BundledPluginSeedService buildService(Set<String> allowedIds) {
    return BundledPluginSeedService(
      repository: repository,
      allowedIds: allowedIds,
      bundleDirPath: bundleDir.path,
    );
  }

  test('מתקין תוסף מהרשימה שארכיונו קיים ומסמן אותו כמטופל', () async {
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'test.bundled',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isTrue);
    expect(repository.savedIds, ['test.bundled']);
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      'test.bundled',
    );
  });

  test('תוסף שסומן כמטופל אינו מותקן שוב — גם אחרי שהמשתמש הסיר', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySeededBundledPlugins,
      'test.bundled',
    );
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'test.bundled',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
  });

  test('ארכיון שאינו ברשימת ההיתר אינו מותקן', () async {
    writePluginArchive(
      p.join(bundleDir.path, 'not.allowed.otzplugin'),
      'not.allowed',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
  });

  test('ארכיון שמצהיר מזהה שונה משם הקובץ נדחה', () async {
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'some.other.plugin',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
    // כשל אינו מסומן כמטופל — אבל גם לא מנוסה בלולאה באותה קריאה.
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      '',
    );
  });

  test('תוסף שכבר מותקן מסומן כמטופל בלי להתקין מחדש', () async {
    repository.plugins['test.bundled'] = InstalledPlugin(
      pluginId: 'test.bundled',
      name: 'Bundled',
      version: '2.0.0',
      installPath: p.join(tempDir.path, 'existing'),
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      manifest: PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': 'test.bundled',
        'version': '2.0.0',
        'name': 'Bundled',
        'entrypoint': 'index.html',
      }),
      installedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'test.bundled',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      'test.bundled',
    );
  });

  test('ארכיון חסר אינו מסומן כמטופל — ינוסה שוב בעלייה הבאה', () async {
    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      '',
    );
  });
}
