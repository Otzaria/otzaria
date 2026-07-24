import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PluginManifestValidator', () {
    test('accepts current app version with prerelease suffix', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.prerelease',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0-beta',
        ),
        completes,
      );
    });

    test('accepts a declared background entrypoint that exists', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_bg_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');
      await File(
        p.join(tempDir.path, 'background.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.background',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        backgroundEntrypoint: 'background.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        completes,
      );
    });

    test('throws when the plugin name exceeds 14 characters', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_name_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.longname',
        name: 'שם ארוך מאוד מהרשאה',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'שם ארוך מאוד מהרשאה',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(predicate((e) => e.toString().contains('לכל היותר 14 תווים'))),
      );
    });

    test('throws when the short description exceeds 150 characters', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_desc_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.longdesc',
        name: 'Validator',
        version: '1.0.0',
        description: 'א' * 151,
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(predicate((e) => e.toString().contains('לכל היותר 150 תווים'))),
      );
    });

    test('throws when toolTab.title differs from name', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_title_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.title',
        name: 'לוח שנה',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'כותרת אחרת',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(
          predicate((e) => e.toString().contains('השמות חייבים להיות זהים')),
        ),
      );
    });

    test('throws when toolTab.title is an explicit empty string', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_emptytitle_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.emptytitle',
        name: 'לוח שנה',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: '',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(
          predicate((e) => e.toString().contains('השמות חייבים להיות זהים')),
        ),
      );
    });

    test('throws when the declared background entrypoint is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_bg_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.background.missing',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        backgroundEntrypoint: 'background.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
