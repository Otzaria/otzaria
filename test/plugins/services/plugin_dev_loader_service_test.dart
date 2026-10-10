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

  /// מה ש-getNextUserOrderForNewPlugin יחזיר. ברירת מחדל null = אין סדר ידני.
  int? nextUserOrderForNewPlugin;

  @override
  Future<int?> getNextUserOrderForNewPlugin() async =>
      nextUserOrderForNewPlugin;

  @override
  Future<void> saveDevelopmentPluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
  ) async {
    savedPlugin = plugin;
    recordedGrants = Map.of(permissions);
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

class _RealHttpOverrides extends HttpOverrides {}

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
      manifestFile.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'id': 'test.dev.repo.plugin',
          'version': '1.0.0',
          'name': 'Real Loader',
          'entrypoint': 'index.html',
          // הרשאה תקפה שאינה הרשאת בסיס — כדי שהחלטות משתמש יישמרו עליה.
          'permissions': ['reader.open'],
        }),
      );

      final entrypointFile = File(p.join(tempDir.path, 'index.html'));
      entrypointFile.createSync();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'loadDevelopmentPlugin parses directory and saves via repository',
      () async {
        await devLoader.loadDevelopmentPlugin(tempDir.path);
        expect(fakeRepo.savedPlugin, isNotNull);
        expect(fakeRepo.savedPlugin!.pluginId, 'test.dev.repo.plugin');
        expect(fakeRepo.savedPlugin!.name, 'Real Loader');
        expect(fakeRepo.savedPlugin!.sourceType, 'development');
        expect(fakeRepo.savedPlugin!.devRootPath, tempDir.path);
        expect(fakeRepo.savedPlugin!.isDevelopment, isTrue);
        // Ensure the validator rules were passed seamlessly via the loader
        expect(
          fakeRepo.savedPlugin!.manifest.permissions.contains('reader.open'),
          isTrue,
        );
      },
    );

    test('explicit development grants are saved with the plugin', () async {
      final manifest = await devLoader.fetchDevelopmentManifest(tempDir.path);

      await devLoader.loadDevelopmentPlugin(
        tempDir.path,
        preValidatedManifest: manifest,
        grantedPermissions: const {'reader.open': false},
        allowOrderBeforeBuiltInsGranted: false,
      );

      expect(fakeRepo.recordedGrants, {'reader.open': false});
      expect(
        fakeRepo.savedPlugin!.allowOrderBeforeBuiltInsGranted,
        isFalse,
      );
    });

    test(
      'loadDevelopmentPlugin loads a plugin whose minAppVersion is newer '
      'than the installed app — dev plugins bypass version compatibility',
      () async {
        final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
        manifestFile.writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'id': 'test.future.version.plugin',
            'version': '1.0.0',
            'name': 'Future Ver',
            'entrypoint': 'index.html',
            'minAppVersion': '99.0.0', // גרסה עתידית גבוהה מהמותקנת (1.0.0)
            'permissions': ['app.info.read'],
          }),
        );

        await devLoader.loadDevelopmentPlugin(tempDir.path);

        expect(fakeRepo.savedPlugin, isNotNull);
        expect(fakeRepo.savedPlugin!.pluginId, 'test.future.version.plugin');
      },
    );

    test('loadDevelopmentPlugin throws exception on invalid schema', () async {
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      manifestFile.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 2, // Invalid
          'id': 'test.schema.plugin',
          'version': '1.0.0',
          'name': 'Bad Schema',
          'entrypoint': 'index.html',
        }),
      );

      expect(
        () => devLoader.loadDevelopmentPlugin(tempDir.path),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('אינה נתמכת'),
          ),
        ),
      );
    });

    test(
      'loadDevelopmentPlugin throws exception on missing entrypoint',
      () async {
        File(
          p.join(tempDir.path, 'index.html'),
        ).deleteSync(); // missing entrypoint
        expect(
          () => devLoader.loadDevelopmentPlugin(tempDir.path),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('לא נמצא בתיקייה'),
            ),
          ),
        );
      },
    );

    test(
      'loadDevelopmentPlugin throws exception on duplicate packaged plugin',
      () async {
        // Create a mocked packaged plugin with same ID
        fakeRepo.mockExistingPlugin = InstalledPlugin(
          pluginId: 'test.dev.repo.plugin',
          name: 'Existing Pkg',
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
            name: 'Existing Pkg',
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
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('כבר קיים תוסף מותקן (רגיל) עם אותו מזהה.'),
            ),
          ),
        );
      },
    );

    test(
      'loadDevelopmentPlugin throws exception on invalid permission',
      () async {
        final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
        manifestFile.writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'id': 'test.schema.plugin',
            'version': '1.0.0',
            'name': 'Bad Permission',
            'entrypoint': 'index.html',
            'permissions': ['malicious.admin.access'],
          }),
        );

        expect(
          () => devLoader.loadDevelopmentPlugin(tempDir.path),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('הרשאה לא חוקית'),
            ),
          ),
        );
      },
    );

    test(
      'loadDevelopmentPlugin throws exception when iconName has invalid format',
      () async {
        final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
        manifestFile.writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'id': 'test.icon.invalid.name',
            'version': '1.0.0',
            'name': 'Bad Icon Name',
            'entrypoint': 'index.html',
            'contributes': {
              'toolTab': {
                'title': 'Bad Icon Name',
                'iconName': 'not-a-valid-icon',
              },
            },
          }),
        );

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
      },
    );

    test(
      'loadDevelopmentPlugin preserves existing grants and clears removed permissions',
      () async {
        // Setup: existing plugin had two permissions – reader.open (granted), network.request (denied)
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
            permissions: ['reader.open', 'network.request'],
            description: '',
            author: '',
            homepage: '',
            sdkVersion: '',
            networkEnabled: false,
            networkAllowlist: [],
            toolTabTitle: '',
            toolTabOrder: 1,
            publishedDataTypes: [],
          ),
          installedAt: DateTime.now(),
          updatedAt: DateTime.now(),
          sourceType: 'development',
        );

        // getPermission reads from recordedGrants (fixed above).
        // reader.open = granted, network.request = denied previously.
        fakeRepo.recordedGrants = {
          'reader.open': true,
          'network.request': false,
        };

        // New manifest: network.request removed, reader.open kept.
        final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
        manifestFile.writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'id': 'test.grants.plugin',
            'version': '1.0.1',
            'name': 'Grants Update',
            'entrypoint': 'index.html',
            'permissions': ['reader.open'],
          }),
        );
        File(p.join(tempDir.path, 'index.html')).createSync();

        await devLoader.loadDevelopmentPlugin(tempDir.path);

        expect(fakeRepo.recordedGrants, isNot(contains('network.request')));
        expect(
          fakeRepo.recordedGrants['reader.open'],
          true,
        );
      },
    );

    test(
      'loadDevelopmentPlugin preserves existingPlugin.userOrder on reload — '
      'manual ordering must survive dev plugin hot-reloads/manifest edits',
      () async {
        fakeRepo.mockExistingPlugin = InstalledPlugin(
          pluginId: 'test.dev.repo.plugin',
          name: 'Real Loader',
          version: '0.9.0',
          installPath: tempDir.path,
          entrypointPath: 'index.html',
          enabled: true,
          pinned: true,
          manifest: PluginManifest(
            schemaVersion: 1,
            id: 'test.dev.repo.plugin',
            version: '0.9.0',
            minAppVersion: '1.0.0',
            name: 'Real Loader',
            entrypoint: 'index.html',
            defaultPinned: true,
            permissions: ['app.info.read'],
            description: '',
            author: '',
            homepage: '',
            sdkVersion: '',
            networkEnabled: false,
            networkAllowlist: const [],
            toolTabTitle: '',
            toolTabOrder: 900,
            publishedDataTypes: const [],
          ),
          installedAt: DateTime.utc(2024),
          updatedAt: DateTime.utc(2024),
          sourceType: 'development',
          devRootPath: tempDir.path,
          userOrder: 3,
        );

        await devLoader.loadDevelopmentPlugin(tempDir.path);

        expect(fakeRepo.savedPlugin, isNotNull);
        expect(
          fakeRepo.savedPlugin!.userOrder,
          3,
          reason:
              'userOrder of the existing dev plugin must be preserved across '
              'reload — otherwise editing the manifest resets manual ordering.',
        );
      },
    );

    test('loadDevelopmentPlugin leaves userOrder=null on a first-time load '
        'when no other plugin has a manual order yet', () async {
      // אין mockExistingPlugin ואין סדר ידני שמור — userOrder צריך להישאר null
      await devLoader.loadDevelopmentPlugin(tempDir.path);

      expect(
        fakeRepo.savedPlugin!.userOrder,
        isNull,
        reason:
            'first-time dev load with no prior manual order must '
            'default to manifest order',
      );
    });

    test('loadDevelopmentPlugin assigns userOrder=max+1 for a new dev plugin '
        'when others were already ordered manually', () async {
      // אין mockExistingPlugin (זה דגם של "first-time load") אבל
      // כן יש סדר ידני קיים, אז התוסף החדש מצטרף לסוף.
      fakeRepo.nextUserOrderForNewPlugin = 7;

      await devLoader.loadDevelopmentPlugin(tempDir.path);

      expect(
        fakeRepo.savedPlugin!.userOrder,
        7,
        reason:
            'new dev plugin should be appended after the manual '
            'block — not inserted before it',
      );
    });

    // issue #1481: ה-URL הגיע לסריקת קבצים, ו-Directory.existsSync זרק ב-Windows.
    test('fetchLocalhostManifest does not treat the URL as a folder', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            File(p.join(tempDir.path, 'manifest.json')).readAsStringSync(),
          )
          ..close();
      });

      // TestWidgetsFlutterBinding מחליף את HttpClient בכזה שמחזיר תמיד 400.
      final manifest = await HttpOverrides.runWithHttpOverrides(
        () => devLoader.fetchLocalhostManifest(
          'http://localhost:${server.port}',
        ),
        _RealHttpOverrides(),
      );

      expect(manifest.id, 'test.dev.repo.plugin');
    });
  });
}
