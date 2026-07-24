import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class FakePluginRegistryRepository extends Mock
    implements PluginRegistryRepository {
  InstalledPlugin? plugin;
  final List<InstalledPlugin> savedPlugins = [];
  final Map<String, bool?> permissions = {};

  /// מה ש-getNextUserOrderForNewPlugin יחזיר. ברירת מחדל null = אין סדר ידני.
  int? nextUserOrderForNewPlugin;

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => plugin;

  @override
  Future<void> savePlugin(InstalledPlugin plugin) async {
    savedPlugins.add(plugin);
  }

  @override
  Future<bool?> getPermission(String id, String perm) async =>
      permissions['$id|$perm'];

  @override
  Future<void> setPermission(String id, String perm, bool granted) async {
    permissions['$id|$perm'] = granted;
  }

  @override
  Future<int?> getNextUserOrderForNewPlugin() async =>
      nextUserOrderForNewPlugin;
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

  group('PluginInstallerService', () {
    late Directory tempDir;
    late PluginInstallerService installer;
    late FakePluginRegistryRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('otzaria_installer_test_');
      repository = FakePluginRegistryRepository();
      installer = PluginInstallerService(
        repository: repository,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('prepareInstall accepts app.user_email.read permission', () async {
      final archivePath = p.join(tempDir.path, 'plugin.zip');
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'schemaVersion': 1,
              'id': 'test.user.email.plugin',
              'version': '1.0.0',
              'name': 'User Email',
              'entrypoint': 'index.html',
              'permissions': ['app.user_email.read'],
            }),
          ),
        )
        ..addFile(ArchiveFile.string('index.html', '<html></html>'));

      final zipData = ZipEncoder().encode(archive);
      expect(zipData, isNotNull);
      File(archivePath).writeAsBytesSync(zipData);

      final preparedInstall = await installer.prepareInstall(archivePath);

      expect(preparedInstall.manifest.permissions, ['app.user_email.read']);
      await Directory(preparedInstall.tempDirPath).delete(recursive: true);
    });

    test('prepareInstall rejects invalid toolTab icon name', () async {
      final archivePath = p.join(tempDir.path, 'plugin_invalid_icon.zip');
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'schemaVersion': 1,
              'id': 'test.invalid.icon.name',
              'version': '1.0.0',
              'name': 'Invalid Icon',
              'entrypoint': 'index.html',
              'contributes': {
                'toolTab': {
                  'title': 'Invalid Icon',
                  'iconName': 'calendar_24_light',
                },
              },
            }),
          ),
        )
        ..addFile(ArchiveFile.string('index.html', '<html></html>'));

      final zipData = ZipEncoder().encode(archive);
      expect(zipData, isNotNull);
      File(archivePath).writeAsBytesSync(zipData);

      expect(
        () => installer.prepareInstall(archivePath),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('toolTab.iconName חייב להיות שם אייקון FluentUI'),
          ),
        ),
      );
    });

    test(
      'prepareInstall parses allowOrderBeforeBuiltIns from manifest',
      () async {
        final archivePath = p.join(tempDir.path, 'plugin_allow_before.zip');
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'schemaVersion': 1,
                'id': 'test.allow.before.builtins',
                'version': '1.0.0',
                'name': 'Leading Plugin',
                'entrypoint': 'index.html',
                'contributes': {
                  'toolTab': {
                    'title': 'Leading Plugin',
                    'order': 5,
                    'allowOrderBeforeBuiltIns': true,
                  },
                },
              }),
            ),
          )
          ..addFile(ArchiveFile.string('index.html', '<html></html>'));

        final zipData = ZipEncoder().encode(archive);
        expect(zipData, isNotNull);
        File(archivePath).writeAsBytesSync(zipData);

        final preparedInstall = await installer.prepareInstall(archivePath);

        expect(preparedInstall.manifest.allowOrderBeforeBuiltIns, isTrue);
        await Directory(preparedInstall.tempDirPath).delete(recursive: true);
      },
    );

    test(
      'prepareInstall tolerates installed pre-release version without crashing',
      () async {
        repository.plugin = InstalledPlugin(
          pluginId: 'test.prerelease.plugin',
          name: 'Prerelease',
          version: '1.0.0-beta',
          installPath: tempDir.path,
          entrypointPath: 'index.html',
          enabled: true,
          pinned: false,
          manifest: _buildInstalledManifest(
            id: 'test.prerelease.plugin',
            version: '1.0.0',
            name: 'Prerelease',
          ),
          installedAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );

        final archivePath = p.join(tempDir.path, 'plugin_prerelease.zip');
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'schemaVersion': 1,
                'id': 'test.prerelease.plugin',
                'version': '1.0.1',
                'name': 'Prerelease',
                'entrypoint': 'index.html',
              }),
            ),
          )
          ..addFile(ArchiveFile.string('index.html', '<html></html>'));

        final zipData = ZipEncoder().encode(archive);
        expect(zipData, isNotNull);
        File(archivePath).writeAsBytesSync(zipData);

        final preparedInstall = await installer.prepareInstall(archivePath);
        expect(preparedInstall.manifest.version, '1.0.1');
        await Directory(preparedInstall.tempDirPath).delete(recursive: true);
      },
    );

    test('finalizeInstall preserves existingPlugin.userOrder on update — '
        'manual reorder must survive plugin updates/reinstalls', () async {
      const pluginId = 'test.reorder.persist';
      repository.plugin = InstalledPlugin(
        pluginId: pluginId,
        name: 'Reorder Pers',
        version: '1.0.0',
        installPath: tempDir.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: true,
        manifest: _buildInstalledManifest(
          id: pluginId,
          version: '1.0.0',
          name: 'Reorder Pers',
        ),
        installedAt: DateTime(2024),
        updatedAt: DateTime(2024),
        userOrder: 7,
      );

      // מכינים tempDir שמדמה את מה ש-prepareInstall מייצר.
      final stagedDir = Directory.systemTemp.createTempSync(
        'otzaria_install_staging_',
      );
      File(p.join(stagedDir.path, 'manifest.json')).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.1',
          'name': 'Reorder Pers',
          'entrypoint': 'index.html',
        }),
      );
      File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');

      final newManifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': pluginId,
        'version': '1.0.1',
        'name': 'Reorder Pers',
        'entrypoint': 'index.html',
      });

      await installer.finalizeInstall(
        stagedDir.path,
        newManifest,
        allowOrderBeforeBuiltInsGranted: true,
      );

      expect(repository.savedPlugins, hasLength(1));
      expect(
        repository.savedPlugins.single.userOrder,
        7,
        reason:
            'userOrder of the previously installed plugin must be '
            'preserved across updates — otherwise the user loses their '
            'manual ordering on every reinstall.',
      );
    });

    test('finalizeInstall leaves userOrder=null on a fresh first-time install '
        'when no other plugin has a manual order yet', () async {
      // אין plugin קיים — repository.plugin = null
      // וגם אין סדר ידני בשום תוסף אחר — nextUserOrderForNewPlugin = null
      const pluginId = 'test.fresh.install';

      final stagedDir = Directory.systemTemp.createTempSync(
        'otzaria_install_staging_',
      );
      File(p.join(stagedDir.path, 'manifest.json')).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.0',
          'name': 'Fresh',
          'entrypoint': 'index.html',
        }),
      );
      File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');

      final newManifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': pluginId,
        'version': '1.0.0',
        'name': 'Fresh',
        'entrypoint': 'index.html',
      });

      await installer.finalizeInstall(
        stagedDir.path,
        newManifest,
        allowOrderBeforeBuiltInsGranted: false,
      );

      expect(
        repository.savedPlugins.single.userOrder,
        isNull,
        reason:
            'a fresh install with no prior manual order should '
            'default to manifest order',
      );
    });

    test('finalizeInstall assigns userOrder=max+1 for a new plugin when '
        'others were already ordered manually — preserves the manual block '
        'and appends the new plugin at the end', () async {
      // user already reordered some plugins — repository tells us the next
      // free slot is 3 (i.e. existing manual orders were 0,1,2).
      repository.plugin = null; // new install
      repository.nextUserOrderForNewPlugin = 3;

      const pluginId = 'test.append.after.manual';
      final stagedDir = Directory.systemTemp.createTempSync(
        'otzaria_install_staging_',
      );
      File(p.join(stagedDir.path, 'manifest.json')).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.0',
          'name': 'New',
          'entrypoint': 'index.html',
        }),
      );
      File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');

      final newManifest = PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': pluginId,
        'version': '1.0.0',
        'name': 'New',
        'entrypoint': 'index.html',
      });

      await installer.finalizeInstall(
        stagedDir.path,
        newManifest,
        allowOrderBeforeBuiltInsGranted: false,
      );

      expect(
        repository.savedPlugins.single.userOrder,
        3,
        reason:
            'new plugin must inherit max+1 so it lands AFTER the '
            'manually-ordered block, not before it',
      );
    });

    test(
      'finalizeInstall stores allowOrderBeforeBuiltInsGranted from the install screen',
      () async {
        const pluginId = 'test.leading.plugin';

        final stagedDir = Directory.systemTemp.createTempSync(
          'otzaria_install_staging_',
        );
        File(p.join(stagedDir.path, 'manifest.json')).writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'id': pluginId,
            'version': '1.0.0',
            'name': 'Leading Plugin',
            'entrypoint': 'index.html',
            'contributes': {
              'toolTab': {
                'title': 'Leading Plugin',
                'order': 5,
                'allowOrderBeforeBuiltIns': true,
              },
            },
          }),
        );
        File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');

        final newManifest = PluginManifest.fromJson({
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.0',
          'name': 'Leading Plugin',
          'entrypoint': 'index.html',
          'contributes': {
            'toolTab': {
              'title': 'Leading Plugin',
              'order': 5,
              'allowOrderBeforeBuiltIns': true,
            },
          },
        });

        await installer.finalizeInstall(
          stagedDir.path,
          newManifest,
          allowOrderBeforeBuiltInsGranted: false,
        );

        expect(
          repository.savedPlugins.single.allowOrderBeforeBuiltInsGranted,
          isFalse,
        );
        expect(
          repository.savedPlugins.single.allowsOrderBeforeBuiltIns,
          isFalse,
          reason:
              'when the user disables the feature at install time, the '
              'plugin must not be able to use it later',
        );
      },
    );
  });
}

PluginManifest _buildInstalledManifest({
  required String id,
  required String version,
  required String name,
}) {
  return PluginManifest(
    schemaVersion: 1,
    id: id,
    name: name,
    version: version,
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '0.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: name,
    toolTabOrder: 900,
    defaultPinned: false,
    publishedDataTypes: const [],
  );
}
