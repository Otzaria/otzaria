import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class FakePluginRegistryRepository extends Mock
    implements PluginRegistryRepository {
  InstalledPlugin? plugin;
  final List<InstalledPlugin> savedPlugins = [];
  final Map<String, bool?> permissions = {};
  bool failAtomicSave = false;

  /// מה ש-getNextUserOrderForNewPlugin יחזיר. ברירת מחדל null = אין סדר ידני.
  int? nextUserOrderForNewPlugin;

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => plugin;

  @override
  Future<void> savePlugin(InstalledPlugin plugin) async {
    savedPlugins.add(plugin);
  }

  @override
  Future<void> savePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> grants,
  ) async {
    if (failAtomicSave) throw StateError('forced atomic save failure');
    savedPlugins.add(plugin);
    permissions.removeWhere((key, _) => key.startsWith('${plugin.pluginId}|'));
    for (final entry in grants.entries) {
      permissions['${plugin.pluginId}|${entry.key}'] = entry.value;
    }
  }

  @override
  Future<bool?> getPermission(String id, String perm) async =>
      permissions['$id|$perm'];

  @override
  Future<void> setPermission(String id, String perm, bool granted) async {
    permissions['$id|$perm'] = granted;
  }

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async => [
    for (final entry in permissions.entries)
      if (entry.key.startsWith('$id|') && entry.value != null)
        PluginPermissionGrant(
          pluginId: id,
          permission: entry.key.substring(id.length + 1),
          granted: entry.value!,
          grantedAt: DateTime(2024),
        ),
  ];

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
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      repository = FakePluginRegistryRepository();
      installer = PluginInstallerService(
        repository: repository,
      );
    });

    tearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'iOS store version preserves minimum and maximum plugin requirements',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          PackageInfo.setMockInitialValues(
            appName: 'Otzaria',
            packageName: 'com.otzaria.app',
            version: '1.0.0',
            buildNumber: '1',
            buildSignature: '',
          );
        });
        PackageInfo.setMockInitialValues(
          appName: 'Otzaria',
          packageName: 'com.otzaria.app',
          version: '0.9.9801',
          buildNumber: '99801',
          buildSignature: '',
        );
        for (final requirement in [
          ('0.9.99', null, false),
          ('0.9.98', '0.9.98', true),
          ('0.9.97', '0.9.97', false),
        ]) {
          final (minimum, maximum, compatible) = requirement;
          final archivePath = _writeArchive(tempDir, 'version.zip', {
            'schemaVersion': 1,
            'id': 'test.ios.version',
            'version': '1.0.0',
            'name': 'iOS Version',
            'entrypoint': 'index.html',
            'minAppVersion': minimum,
            'maxAppVersion': ?maximum,
          });
          if (compatible) {
            final prepared = await installer.prepareInstall(archivePath);
            await Directory(prepared.tempDirPath).delete(recursive: true);
          } else {
            await expectLater(
              installer.prepareInstall(archivePath),
              throwsA(
                predicate(
                  (error) => error.toString().contains('אך מותקנת 0.9.98'),
                ),
              ),
            );
          }
        }
      },
    );

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
      'prepareInstall rejects malformed declarative startup fields',
      () async {
        final archivePath = p.join(tempDir.path, 'plugin_invalid_startup.zip');
        final archive = Archive()
          ..addFile(
            ArchiveFile.string(
              'manifest.json',
              jsonEncode({
                'schemaVersion': 1,
                'id': 'test.invalid.startup',
                'version': '1.0.0',
                'name': 'Bad Startup',
                'entrypoint': 'index.html',
                'minAppVersion': '0.9.97',
                'permissions': ['app.startup_contributions'],
                'contributes': {
                  'startup': {
                    'toolbarItems': [
                      {
                        'id': 'button',
                        'title': 'Button',
                        'icon': 'apps_24_regular',
                      },
                    ],
                    'keepAlive': 'yes',
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
              contains('keepAlive חייב להיות bool'),
            ),
          ),
        );
      },
    );

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

    test('prepareInstall collects the previous permission decisions', () async {
      const pluginId = 'test.previous.grants';
      repository.plugin = InstalledPlugin(
        pluginId: pluginId,
        name: 'Prev Grants',
        version: '1.0.0',
        installPath: tempDir.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: _buildInstalledManifest(
          id: pluginId,
          version: '1.0.0',
          name: 'Prev Grants',
          permissions: const ['app.info.read', 'notes.read'],
        ),
        installedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      repository.permissions['$pluginId|app.info.read'] = true;
      repository.permissions['$pluginId|notes.read'] = false;

      final archivePath = _writeArchive(tempDir, 'prev_grants.zip', {
        'schemaVersion': 1,
        'id': pluginId,
        'version': '1.0.1',
        'name': 'Prev Grants',
        'entrypoint': 'index.html',
        'permissions': ['app.info.read', 'notes.read', 'ui.feedback'],
      });

      final prepared = await installer.prepareInstall(archivePath);

      expect(
        prepared.previousGrantedPermissions,
        {
          'app.info.read': true,
          'notes.read': false,
        },
        reason: 'ui.feedback חדשה — אין עליה החלטה קודמת',
      );
      await Directory(prepared.tempDirPath).delete(recursive: true);
    });

    test('prepareInstall reports no previous order decision when the old '
        'manifest never asked for it', () async {
      const pluginId = 'test.order.first.request';
      repository.plugin = InstalledPlugin(
        pluginId: pluginId,
        name: 'Order First',
        version: '1.0.0',
        installPath: tempDir.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: _buildInstalledManifest(
          id: pluginId,
          version: '1.0.0',
          name: 'Order First',
        ),
        installedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

      final archivePath = _writeArchive(tempDir, 'order_first.zip', {
        'schemaVersion': 1,
        'id': pluginId,
        'version': '1.0.1',
        'name': 'Order First',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {
            'title': 'Order First',
            'allowOrderBeforeBuiltIns': true,
          },
        },
      });

      final prepared = await installer.prepareInstall(archivePath);

      expect(
        prepared.previousAllowOrderBeforeBuiltInsGranted,
        isNull,
        reason:
            'InstalledPlugin stores false when the manifest never asked — '
            'a first-time request must not look like a past refusal',
      );
      await Directory(prepared.tempDirPath).delete(recursive: true);
    });

    test(
      'prepareInstall keeps a real past refusal of the order request',
      () async {
        const pluginId = 'test.order.refused';
        repository.plugin = InstalledPlugin(
          pluginId: pluginId,
          name: 'Order Refused',
          version: '1.0.0',
          installPath: tempDir.path,
          entrypointPath: 'index.html',
          enabled: true,
          pinned: false,
          allowOrderBeforeBuiltInsGranted: false,
          manifest: _buildInstalledManifest(
            id: pluginId,
            version: '1.0.0',
            name: 'Order Refused',
            allowOrderBeforeBuiltIns: true,
          ),
          installedAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );

        final archivePath = _writeArchive(tempDir, 'order_refused.zip', {
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.1',
          'name': 'Order Refused',
          'entrypoint': 'index.html',
          'contributes': {
            'toolTab': {
              'title': 'Order Refused',
              'allowOrderBeforeBuiltIns': true,
            },
          },
        });

        final prepared = await installer.prepareInstall(archivePath);

        expect(prepared.previousAllowOrderBeforeBuiltInsGranted, isFalse);
        await Directory(prepared.tempDirPath).delete(recursive: true);
      },
    );

    test('finalizeInstall stores the explicit permission decisions', () async {
      const pluginId = 'test.explicit.grants';
      final stagedDir = Directory.systemTemp.createTempSync(
        'otzaria_install_staging_',
      );
      File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');
      final manifest = _buildInstalledManifest(
        id: pluginId,
        version: '1.0.0',
        name: 'Explicit Grants',
        permissions: const [
          'app.startup_contributions',
          'reader.open',
        ],
      );

      await installer.finalizeInstall(
        stagedDir.path,
        manifest,
        allowOrderBeforeBuiltInsGranted: false,
        grantedPermissions: const {
          'app.startup_contributions': false,
          'reader.open': true,
        },
      );

      expect(repository.permissions, {
        '$pluginId|app.startup_contributions': false,
        '$pluginId|reader.open': true,
      });
    });

    test('finalizeInstall rejects an incomplete permission map', () async {
      const pluginId = 'test.incomplete.grants';
      final stagedDir = Directory.systemTemp.createTempSync(
        'otzaria_install_staging_',
      );
      File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');
      final manifest = _buildInstalledManifest(
        id: pluginId,
        version: '1.0.0',
        name: 'Incomplete Grants',
        permissions: const ['app.startup_contributions'],
      );

      await expectLater(
        installer.finalizeInstall(
          stagedDir.path,
          manifest,
          allowOrderBeforeBuiltInsGranted: false,
          grantedPermissions: const {},
        ),
        throwsArgumentError,
      );

      expect(repository.savedPlugins, isEmpty);
      expect(repository.permissions, isEmpty);
    });

    test('כשל בשמירה משאיר את קבצי הגרסה הישנה פעילים', () async {
      const pluginId = 'test.filesystem.rollback';
      final oldInstallPath = await AppPaths.getPluginInstallPath(pluginId);
      final oldEntrypoint = File(p.join(oldInstallPath, 'index.html'));
      await oldEntrypoint.create(recursive: true);
      await oldEntrypoint.writeAsString('old-version');
      repository.plugin = InstalledPlugin(
        pluginId: pluginId,
        name: 'Filesystem Rollback',
        version: '1.0.0',
        installPath: oldInstallPath,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: _buildInstalledManifest(
          id: pluginId,
          version: '1.0.0',
          name: 'Filesystem Rollback',
          permissions: const ['app.startup_contributions'],
        ),
        installedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      repository.permissions['$pluginId|app.startup_contributions'] = true;
      repository.failAtomicSave = true;
      final stagedDir = Directory(p.join(tempDir.path, 'new-release'))
        ..createSync();
      File(p.join(stagedDir.path, 'index.html')).writeAsStringSync(
        'new-version',
      );
      final newManifest = _buildInstalledManifest(
        id: pluginId,
        version: '2.0.0',
        name: 'Filesystem Rollback',
        permissions: const ['app.startup_contributions'],
      );

      await expectLater(
        installer.finalizeInstall(
          stagedDir.path,
          newManifest,
          allowOrderBeforeBuiltInsGranted: false,
          grantedPermissions: const {'app.startup_contributions': false},
        ),
        throwsStateError,
      );

      expect(await oldEntrypoint.readAsString(), 'old-version');
      expect(repository.savedPlugins, isEmpty);
      expect(
        repository.permissions['$pluginId|app.startup_contributions'],
        isTrue,
      );
      final releases = Directory(p.dirname(oldInstallPath))
          .listSync()
          .whereType<Directory>()
          .where(
            (directory) => p.basename(directory.path).startsWith('.release-'),
          );
      expect(releases, isEmpty);
    });

    test('commit מוצלח מצביע ל-release חדש ורק אז מוחק את הישן', () async {
      const pluginId = 'test.release.swap';
      final oldInstallPath = await AppPaths.getPluginInstallPath(pluginId);
      final oldEntrypoint = File(p.join(oldInstallPath, 'index.html'));
      await oldEntrypoint.create(recursive: true);
      await oldEntrypoint.writeAsString('old-version');
      repository.plugin = InstalledPlugin(
        pluginId: pluginId,
        name: 'Release Swap',
        version: '1.0.0',
        installPath: oldInstallPath,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: _buildInstalledManifest(
          id: pluginId,
          version: '1.0.0',
          name: 'Release Swap',
        ),
        installedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final sourceDir = Directory(p.join(tempDir.path, 'swap-source'))
        ..createSync();
      File(p.join(sourceDir.path, 'index.html')).writeAsStringSync(
        'new-version',
      );
      final newManifest = _buildInstalledManifest(
        id: pluginId,
        version: '2.0.0',
        name: 'Release Swap',
      );

      await installer.finalizeInstall(
        sourceDir.path,
        newManifest,
        allowOrderBeforeBuiltInsGranted: false,
        grantedPermissions: const {},
      );

      final activePath = repository.savedPlugins.single.installPath;
      expect(activePath, isNot(oldInstallPath));
      expect(p.dirname(activePath), p.dirname(oldInstallPath));
      expect(
        await File(p.join(activePath, 'index.html')).readAsString(),
        'new-version',
      );
      expect(await Directory(oldInstallPath).exists(), isFalse);
    });

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
        grantedPermissions: const {},
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

    test(
      'finalizeInstall preserves showInTools=false on update — '
      'a plugin hidden from tools must stay hidden after an update',
      () async {
        const pluginId = 'test.hidden.persist';
        repository.plugin = InstalledPlugin(
          pluginId: pluginId,
          name: 'Hidden Pers',
          version: '1.0.0',
          installPath: tempDir.path,
          entrypointPath: 'index.html',
          enabled: true,
          pinned: false,
          showInTools: false,
          manifest: _buildInstalledManifest(
            id: pluginId,
            version: '1.0.0',
            name: 'Hidden Pers',
          ),
          installedAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );

        final stagedDir = Directory.systemTemp.createTempSync(
          'otzaria_install_staging_',
        );
        File(p.join(stagedDir.path, 'manifest.json')).writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'id': pluginId,
            'version': '1.0.1',
            'name': 'Hidden Pers',
            'entrypoint': 'index.html',
          }),
        );
        File(p.join(stagedDir.path, 'index.html')).writeAsStringSync('<html/>');

        final newManifest = PluginManifest.fromJson({
          'schemaVersion': 1,
          'id': pluginId,
          'version': '1.0.1',
          'name': 'Hidden Pers',
          'entrypoint': 'index.html',
        });

        await installer.finalizeInstall(
          stagedDir.path,
          newManifest,
          allowOrderBeforeBuiltInsGranted: false,
          grantedPermissions: const {},
        );

        expect(repository.savedPlugins, hasLength(1));
        expect(
          repository.savedPlugins.single.showInTools,
          isFalse,
          reason:
              '"הסתר מהממשק" is a user decision — an update must not reset it.',
        );
      },
    );

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
        grantedPermissions: const {},
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
        grantedPermissions: const {},
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
          grantedPermissions: const {},
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

/// כותב חבילת תוסף מינימלית (manifest + entrypoint) ומחזיר את נתיב ה-zip.
String _writeArchive(
  Directory dir,
  String fileName,
  Map<String, dynamic> manifest,
) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
    ..addFile(ArchiveFile.string('index.html', '<html></html>'));
  final archivePath = p.join(dir.path, fileName);
  File(archivePath).writeAsBytesSync(ZipEncoder().encode(archive));
  return archivePath;
}

PluginManifest _buildInstalledManifest({
  required String id,
  required String version,
  required String name,
  List<String> permissions = const [],
  bool allowOrderBeforeBuiltIns = false,
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
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: name,
    toolTabOrder: 900,
    allowOrderBeforeBuiltIns: allowOrderBeforeBuiltIns,
    defaultPinned: false,
    publishedDataTypes: const [],
  );
}
