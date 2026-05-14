import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';

void main() {
  group('PluginManifestValidator', () {
    test('accepts current app version with prerelease suffix', () async {
      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.prerelease',
        name: 'Validator Plugin',
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
        toolTabTitle: 'Validator Plugin',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: 'assets/plugin-sdk/example',
          currentAppVersion: '1.0.0-beta',
        ),
        completes,
      );
    });
  });
}
