import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('Linux packages use the pre-scaled 256px icon', () {
    final icon = File('assets/icon/icon_256.png');
    final Uint8List raw = icon.readAsBytesSync();
    expect(raw.length, greaterThan(24));
    expect(raw.sublist(0, 8), const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final ByteData header = ByteData.sublistView(raw);
    expect(header.getUint32(16, Endian.big), 256);
    expect(header.getUint32(20, Endian.big), 256);

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
