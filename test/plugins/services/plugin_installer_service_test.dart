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

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => plugin;
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
              'name': 'User Email Plugin',
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
              'name': 'Invalid Icon Name',
              'entrypoint': 'index.html',
              'contributes': {
                'toolTab': {
                  'title': 'Bad Icon',
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
        'prepareInstall tolerates installed pre-release version without crashing',
        () async {
      repository.plugin = InstalledPlugin(
        pluginId: 'test.prerelease.plugin',
        name: 'Prerelease Plugin',
        version: '1.0.0-beta',
        installPath: tempDir.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: _buildInstalledManifest(
          id: 'test.prerelease.plugin',
          version: '1.0.0',
          name: 'Prerelease Plugin',
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
              'name': 'Prerelease Plugin',
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
    });
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
