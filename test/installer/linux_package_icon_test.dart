import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:yaml/yaml.dart';

void main() {
  test('Linux packages use the pre-scaled 256px icon', () {
    final icon = File('assets/icon/icon_256.png');
    final decoded = img.decodeImage(icon.readAsBytesSync());
    expect(decoded, isNotNull);
    expect(decoded!.width, 256);
    expect(decoded.height, 256);

    final full = File('assets/icon/icon.png');
    expect(
      icon.lengthSync(),
      lessThan(full.lengthSync()),
      reason: 'package icon must remain the compact pre-scaled asset',
    );

    for (final path in const [
      'linux/packaging/deb/make_config.yaml',
      'linux/packaging/rpm/make_config.yaml',
    ]) {
      final yaml = loadYaml(File(path).readAsStringSync()) as YamlMap;
      expect(yaml['icon'], 'assets/icon/icon_256.png', reason: path);
    }
  });
}
