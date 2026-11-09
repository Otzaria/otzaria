import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('חבילת provider המותקנת כוללת את הרחבת DevTools הבנויה', () {
    final configFile = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(configFile.readAsStringSync())['packages'] as List)
            .cast<Map>();
    final provider = packages.singleWhere((p) => p['name'] == 'provider');
    final extension = Directory.fromUri(
      configFile.uri.resolve(provider['rootUri'] as String),
    ).uri.resolve('extension/devtools/');

    for (final asset in [
      'config.yaml',
      'build/index.html',
      'build/main.dart.js',
      'build/flutter.js',
      'build/assets/FontManifest.json',
      'build/assets/fonts/MaterialIcons-Regular.otf',
    ]) {
      final file = File.fromUri(extension.resolve(asset));
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Missing provider asset: $asset',
      );
      expect(file.lengthSync(), greaterThan(0));
    }
  });
}
