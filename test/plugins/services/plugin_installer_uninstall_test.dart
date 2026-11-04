import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';
import 'bundled_plugin_seed_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pluginId = 'test.uninstall';
  late Directory root;
  late PluginRegistryRepository repository;
  late Directory installDir;
  late Directory dataDir;
  late Directory cacheDir;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('otzaria_uninstall_');
    AppPaths.debugOverrideDataRootPath(p.join(root.path, 'data'));
  });

  tearDownAll(() async {
    PluginSystemDatabase.instance.openDatabase?.close();
    AppPaths.debugOverrideDataRootPath(null);
    await root.delete(recursive: true);
  });

  Future<Directory> populated(String path) async {
    final dir = Directory(path);
    await File(p.join(dir.path, 'nested', 'a.txt')).create(recursive: true);
    await File(p.join(dir.path, 'b.txt')).writeAsString('x');
    return dir;
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = PluginRegistryRepository();
    installDir = await populated(p.join(root.path, 'install'));
    dataDir = await populated(await AppPaths.getPluginDataPath(pluginId));
    cacheDir = await populated(await AppPaths.getPluginCachePath(pluginId));
    await repository.savePluginWithPermissions(
      fixture.installedPlugin(pluginId, installDir.path),
      const {},
    );
  });

  tearDown(() async {
    await PluginInstallerService(
      repository: repository,
    ).uninstallPlugin(pluginId);
  });

  test('הסרה מוחקת את רשומת התוסף ואת תיקיות ההתקנה, data ו-cache', () async {
    await PluginInstallerService(
      repository: repository,
    ).uninstallPlugin(pluginId);

    expect(await repository.getPlugin(pluginId), isNull);
    expect(await installDir.exists(), isFalse);
    expect(await dataDir.exists(), isFalse);
    expect(await cacheDir.exists(), isFalse);
  });

  test('איפוס נתונים מוחק data ו-cache ומשאיר את קבצי התוסף', () async {
    await PluginInstallerService(
      repository: repository,
    ).resetPluginData(pluginId);

    expect(await repository.getPlugin(pluginId), isNotNull);
    expect(await installDir.exists(), isTrue);
    expect(await dataDir.exists(), isFalse);
    expect(await cacheDir.exists(), isFalse);
  });
}
