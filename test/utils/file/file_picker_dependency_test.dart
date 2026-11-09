import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('כל מימושי בורר הקבצים נטענים מאותו קומיט משולב', () {
    const directories = {
      'file_picker': 'file_picker',
      'file_picker_platform_interface': 'file_picker_platform_interface',
      'android_file_picker': 'file_picker_android',
      'file_picker_darwin': 'file_picker_darwin',
      'file_picker_linux': 'file_picker_linux',
      'windows_file_picker': 'file_picker_windows',
      'file_picker_web': 'file_picker_web',
    };
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config = jsonDecode(configFile.readAsStringSync()) as Map;
    final packages = (config['packages'] as List).cast<Map>();
    final locked =
        (loadYaml(File('pubspec.lock').readAsStringSync())
                as YamlMap)['packages']
            as YamlMap;
    final checkouts = <Uri>{};
    final commits = <String>{};

    for (final entry in directories.entries) {
      final package = packages.singleWhere((p) => p['name'] == entry.key);
      final root = Directory.fromUri(
        configFile.uri.resolve(package['rootUri'] as String),
      ).uri;
      expect(root.path, endsWith('/packages/${entry.value}/'));
      checkouts.add(root.resolve('../../'));
      final dependency = locked[entry.key] as YamlMap;
      expect(dependency['source'], 'git');
      final source = dependency['description'] as YamlMap;
      expect(source['url'], 'https://github.com/Otzaria/flutter_file_picker');
      expect(source['ref'], 'codex/integrated-fixes');
      expect(source['path'], 'packages/${entry.value}');
      commits.add(source['resolved-ref'] as String);
    }

    expect(checkouts, hasLength(1));
    expect(commits, hasLength(1));
  });
}
