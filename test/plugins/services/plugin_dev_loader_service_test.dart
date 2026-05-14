import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:mockito/mockito.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FakePluginRegistryRepository extends Mock
    implements PluginRegistryRepository {
  InstalledPlugin? savedPlugin;

  InstalledPlugin? mockExistingPlugin;
  List<PluginPermissionGrant> mockExistingGrants = [];
  Map<String, bool> recordedGrants = {};

  @override
  Future<void> saveDevelopmentPlugin(InstalledPlugin plugin) async {
    savedPlugin = plugin;
  }

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => mockExistingPlugin;

  @override
  Future<bool?> getPermission(String id, String perm) async =>
      recordedGrants[perm];

  @override
  Future<void> setPermission(String id, String perm, bool granted) async {
    recordedGrants[perm] = granted;
  }

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      mockExistingGrants;

  // Dummy implementations for the rest
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
  @override
  Future<void> savePlugin(InstalledPlugin plugin) async {}
  @override
  Future<void> detachDevelopmentPlugin(String pluginId) async {}
  @override
  Future<void> updatePinState(String id, bool pinned) async {}
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

  group('PluginDevLoaderService', () {
    late Directory tempDir;
    late FakePluginRegistryRepository fakeRepo;
    late PluginDevLoaderService devLoader;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('otzaria_plugin_test_');
      fakeRepo = FakePluginRegistryRepository();
      devLoader = PluginDevLoaderService(repository: fakeRepo);

      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      manifestFile.writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'id': 'test.dev.repo.plugin',
        'version': '1.0.0',
        'name': 'Real Loader Test',
        'entrypoint': 'index.html',
        'permissions': ['app.info.read'] // valid permission
      }));

      final entrypointFile = File(p.join(tempDir.path, 'index.html'));
      entrypointFile.createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('loadDevelopmentPlugin parses directory and saves via repository',
        () async {
      await devLoader.loadDevelopmentPlugin(tempDir.path);
      expect(fakeRepo.savedPlugin, isNotNull);
      expect(fakeRepo.savedPlugin!.pluginId, 'test.dev.repo.plugin');
      expect(fakeRepo.savedPlugin!.name, 'Real Loader Test');
      expect(fakeRepo.savedPlugin!.sourceType, 'development');
      expect(fakeRepo.savedPlugin!.devRootPath, tempDir.path);
      expect(fakeRepo.savedPlugin!.isDevelopment, isTrue);
      // Ensure the validator rules were passed seamlessly via the loader
      expect(
          fakeRepo.savedPlugin!.manifest.permissions.contains('app.info.read'),
          isTrue);
    });

    test('loadDevelopmentPlugin throws exception on invalid schema', () async {
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      manifestFile.writeAsStringSync(jsonEncode({
        'schemaVersion': 2, // Invalid
        'id': 'test.schema.plugin',
        'version': '1.0.0',
        'name': 'Bad Schema',
        'entrypoint': 'index.html',
      }));

      expect(
        () => devLoader.loadDevelopmentPlugin(tempDir.path),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('אינה נתמכת'))),
      );
    });

    test('loadDevelopmentPlugin throws exception on missing entrypoint',
        () async {
      File(p.join(tempDir.path, 'index.html'))
          .deleteSync(); // missing entrypoint
      expect(
        () => devLoader.loadDevelopmentPlugin(tempDir.path),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('לא נמצא בתיקייה'))),
      );
    });

    test('loadDevelopmentPlugin throws exception on duplicate packaged plugin',
        () async {
      // Create a mocked packaged plugin with same ID
      fakeRepo.mockExistingPlugin = InstalledPlugin(
        pluginId: 'test.dev.repo.plugin',
        name: 'Existing Packaged Plugin',
        version: '1.0.0',
        installPath: tempDir.path,
        entrypointPath: 'dummy.html',
        enabled: true,
        pinned: true,
        manifest: PluginManifest(
          schemaVersion: 1,
          id: 'test.dev.repo.plugin',
          version: '1.0.0',
          minAppVersion: '1.0.0',
          name: 'Existing Packaged Plugin',
          entrypoint: 'dummy.html',
          defaultPinned: true,
          permissions: [],
          description: 'test',
          author: 'tester',
          homepage: 'https://test.com',
          sdkVersion: '1.0.0',
          networkEnabled: false,
          networkAllowlist: [],
          toolTabTitle: 'Tab',
          toolTabOrder: 0,
          publishedDataTypes: [],
        ),
        installedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sourceType: 'packaged',
      );

      expect(
        () => devLoader.loadDevelopmentPlugin(tempDir.path),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            contains('כבר קיים תוסף מותקן (רגיל) עם אותו מזהה.'))),
      );
    });

    test('loadDevelopmentPlugin throws exception on invalid permission',
        () async {
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      manifestFile.writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'id': 'test.schema.plugin',
        'version': '1.0.0',
        'name': 'Bad Permission',
        'entrypoint': 'index.html',
        'permissions': ['malicious.admin.access']
      }));

      expect(
        () => devLoader.loadDevelopmentPlugin(tempDir.path),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'message', contains('הרשאה לא חוקית'))),
      );
    });

    test(
        'loadDevelopmentPlugin throws exception when iconName has invalid format',
        () async {
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      manifestFile.writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'id': 'test.icon.invalid.name',
        'version': '1.0.0',
        'name': 'Bad Icon Name',
        'entrypoint': 'index.html',
        'contributes': {
          'toolTab': {'title': 'Bad Icon', 'iconName': 'not-a-valid-icon'}
        }
      }));

      expect(
        () => devLoader.loadDevelopmentPlugin(tempDir.path),
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
        'loadDevelopmentPlugin preserves existing grants and clears removed permissions',
        () async {
      // Setup: existing plugin had two permissions – app.info.read (granted), network.request (denied)
      fakeRepo.mockExistingPlugin = InstalledPlugin(
        pluginId: 'test.grants.plugin',
        name: 'Grants Plugin',
        version: '1.0.0',
        installPath: tempDir.path,
        entrypointPath: 'dummy.html',
        enabled: true,
        pinned: true,
        manifest: PluginManifest(
            schemaVersion: 1,
            id: 'test.grants.plugin',
            version: '1.0.0',
            minAppVersion: '1.0.0',
            name: 'Grants Plugin',
            entrypoint: 'dummy.html',
            defaultPinned: true,
            permissions: ['app.info.read', 'network.request'],
            description: '',
            author: '',
            homepage: '',
            sdkVersion: '',
            networkEnabled: false,
            networkAllowlist: [],
            toolTabTitle: '',
            toolTabOrder: 1,
            publishedDataTypes: []),
        installedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sourceType: 'development',
      );

      // getPermission reads from recordedGrants (fixed above).
      // app.info.read = granted, network.request = denied previously.
      fakeRepo.recordedGrants = {
        'app.info.read': true,
        'network.request': false,
      };

      // New manifest: network.request removed, app.info.read kept.
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      manifestFile.writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'id': 'test.grants.plugin',
        'version': '1.0.1',
        'name': 'Grants Plugin Update',
        'entrypoint': 'index.html',
        'permissions': ['app.info.read']
      }));
      File(p.join(tempDir.path, 'index.html')).createSync();

      await devLoader.loadDevelopmentPlugin(tempDir.path);

      // ASSERT 1: network.request was removed from new manifest →
      // setPermission(false) must have been called to explicitly revoke it.
      expect(
        fakeRepo.recordedGrants['network.request'],
        false,
        reason: 'network.request נמחק מהמניפסט החדש – חייב להתאפס ל-false',
      );

      // ASSERT 2: app.info.read existed in recordedGrants (returned by getPermission) →
      // service should NOT call setPermission again (it skips permissions already in existingGrants).
      // Therefore recordedGrants['app.info.read'] stays at its original value (true), not reset.
      expect(
        fakeRepo.recordedGrants['app.info.read'],
        true,
        reason:
            'app.info.read כבר היה קיים ב-recordedGrants – לא אמור להיות נכתב מחדש',
      );
    });
  });
}
