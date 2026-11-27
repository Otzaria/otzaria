import 'dart:async';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';
import 'bundled_plugin_seed_service_test.dart' as fixture;

class _PausedRepository extends PluginRegistryRepository {
  final ready = Completer<void>();
  final resume = Completer<void>();
  String? stagedPath;

  @override
  Future<void> upgradePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
    InstalledPlugin expectedPlugin,
    Map<String, bool> expectedPermissions,
  ) async {
    stagedPath = plugin.installPath;
    ready.complete();
    await resume.future;
    await super.upgradePluginWithPermissions(
      plugin,
      permissions,
      expectedPlugin,
      expectedPermissions,
    );
  }
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

  late Directory root;
  late _PausedRepository repository;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('otzaria_bundled_race_');
    AppPaths.debugOverrideDataRootPath(p.join(root.path, 'data'));
  });

  tearDownAll(() async {
    PluginSystemDatabase.instance.openDatabase?.close();
    AppPaths.debugOverrideDataRootPath(null);
    await root.delete(recursive: true);
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    PluginSafeMode.resetForTesting();
    repository = _PausedRepository();
    final old = Directory(p.join(root.path, 'old'));
    await old.create(recursive: true);
    await File(p.join(old.path, 'index.html')).writeAsString('old');
    await repository.savePluginWithPermissions(
      fixture.installedPlugin(
        'test.bundled',
        old.path,
        permissions: ['network.access'],
      ),
      const {'network.access': true},
    );
    await Settings.setValue<String>(
      SettingsRepository.keySeededBundledPlugins,
      'test.bundled',
    );
    fixture.writePluginArchive(
      p.join(root.path, 'test.bundled.otzplugin'),
      'test.bundled',
      version: '2.0.0',
      permissions: ['network.access'],
    );
  });

  BundledPluginSeedService service() => BundledPluginSeedService(
    repository: repository,
    installerService: PluginInstallerService(repository: repository),
    allowedIds: {'test.bundled'},
    bundleDirPath: root.path,
  );

  tearDown(() async {
    if (!repository.resume.isCompleted) repository.resume.complete();
    PluginNewTabPageRegistry.instance.remove('test.bundled');
    await PluginInstallerService().uninstallPlugin('test.bundled');
  });

  Future<void> waitForCommit(Future<bool> seeding) => Future.any([
    repository.ready.future,
    seeding.then<void>((registered) {
      throw StateError(
        'Bundled upgrade finished before commit barrier: $registered',
      );
    }),
  ]);

  test('הסרה ממופע אחר במהלך שדרוג מצורף אינה מתקינה את התוסף מחדש', () async {
    final seeding = service().seedPending();
    await waitForCommit(seeding);
    await PluginInstallerService(
      repository: PluginRegistryRepository(),
    ).uninstallPlugin('test.bundled');
    repository.resume.complete();
    final registered = await seeding;

    expect(await repository.getPlugin('test.bundled'), isNull);
    expect(await repository.getPluginPermissions('test.bundled'), isEmpty);
    expect(registered, isFalse);
    expect(await Directory(repository.stagedPath!).exists(), isFalse);
    expect(
      Settings.getValue<String>(SettingsRepository.keySeededBundledPlugins),
      'test.bundled',
    );
  });

  test(
    'שינוי הרשאה והעדפות ממופע אחר מבטל שדרוג ושומר את החלטת המשתמש',
    () async {
      final seeding = service().seedPending();
      await waitForCommit(seeding);
      final other = PluginRegistryRepository();
      await other.setPermission('test.bundled', 'network.access', false);
      await other.updateNavRailPinState('test.bundled', true);
      await other.reorderPlugins(['test.bundled']);
      await other.updateShowInTools('test.bundled', false);
      PluginNewTabPageRegistry.instance.register('test.bundled');
      repository.resume.complete();

      expect(await seeding, isFalse);
      final current = (await other.getPlugin('test.bundled'))!;
      expect(current.version, '1.0.0');
      expect(current.pinnedToNavRail, isTrue);
      expect(current.showInTools, isFalse);
      expect(current.userOrder, 0);
      expect(
        await other.getPermission('test.bundled', 'network.access'),
        isFalse,
      );
      expect(PluginNewTabPageRegistry.instance.activePluginId, 'test.bundled');
      expect(await Directory(repository.stagedPath!).exists(), isFalse);
      expect(
        Settings.getValue<String>(
          SettingsRepository.keyBundledPluginsUpgradeCheckedVersion,
        ),
        isNotEmpty,
      );
      expect(await service().seedPending(), isFalse);
    },
  );

  test(
    'שדרוג ללא שינוי מקביל שומר החלטות legacy, העדפות ונתוני תוסף',
    () async {
      final old = (await repository.getPlugin('test.bundled'))!;
      await repository.savePluginWithPermissions(
        fixture
            .installedPlugin(
              'test.bundled',
              old.installPath,
              permissions: ['ui.feedback'],
            )
            .copyWith(
              enabled: false,
              pinnedToNavRail: true,
              showInTools: false,
            ),
        {'ui.feedback': false},
      );
      await PluginSystemDatabase.instance.updatePluginsUserOrder({
        'test.bundled': 4,
      });
      await repository.setKV('test.bundled', 'default', 'saved', '"data"');
      fixture.writePluginArchive(
        p.join(root.path, 'test.bundled.otzplugin'),
        'test.bundled',
        version: '2.0.0',
        permissions: ['fs.folder_access'],
        minAppVersion: '0.9.97',
      );
      final seeding = service().seedPending();
      await waitForCommit(seeding);
      repository.resume.complete();

      expect(await seeding, isTrue);
      final current = (await repository.getPlugin('test.bundled'))!;
      expect(current.version, '2.0.0');
      expect(current.enabled, isFalse);
      expect(current.pinnedToNavRail, isTrue);
      expect(current.showInTools, isFalse);
      expect(current.userOrder, 4);
      expect(
        await repository.getPermission('test.bundled', 'fs.folder_access'),
        isFalse,
      );
      expect(
        await repository.getKV('test.bundled', 'default', 'saved'),
        '"data"',
      );
      expect(
        await File(p.join(current.installPath, 'index.html')).exists(),
        isTrue,
      );
    },
  );

  test('שתי בקשות seed שומרות רק שדרוג אחד ואין מחיקת גרסה מתחרה', () async {
    final first = service().seedPending();
    await waitForCommit(first);
    final other = PluginRegistryRepository();
    final second = await BundledPluginSeedService(
      repository: other,
      allowedIds: {'test.bundled'},
      bundleDirPath: root.path,
    ).seedPending();
    final committed = (await other.getPlugin('test.bundled'))!;
    expect(second, isTrue);
    repository.resume.complete();

    expect(await first, isFalse);
    expect(
      (await other.getPlugin('test.bundled'))!.installPath,
      committed.installPath,
    );
    expect(
      await File(p.join(committed.installPath, 'index.html')).exists(),
      isTrue,
    );
    expect(await Directory(repository.stagedPath!).exists(), isFalse);
  });
}
