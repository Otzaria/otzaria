import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Future<({int status, List<String> aptArgs})> _installDependencies({
  String depends = 'libsecret-1-0, libexample:any (>= 2) | libalternative',
  int metadataStatus = 0,
  int aptStatus = 0,
}) async {
  final workflow =
      loadYaml(
            File(
              '.github/workflows/wpe_strip_released_bundle_smoke.yml',
            ).readAsStringSync(),
          )
          as YamlMap;
  final steps = workflow['jobs']['released-bundle']['steps'] as YamlList;
  final script = steps
      .cast<YamlMap>()
      .map((step) => step['run'])
      .whereType<String>()
      .singleWhere((run) => run.contains('apt-get satisfy'));
  final temp = Directory.systemTemp.createTempSync('wpe-deb-dependencies-');
  addTearDown(() => temp.deleteSync(recursive: true));
  final bin = Directory('${temp.path}/bin')..createSync();
  final commands = {
    'dpkg-deb': r'''#!/usr/bin/env bash
printf '%s\n' "$SMOKE_DEPENDS"
exit "$SMOKE_METADATA_STATUS"
''',
    'sudo': r'''#!/usr/bin/env bash
printf '%s\0' "$@" > "$SMOKE_APT_ARGS"
exit "$SMOKE_APT_STATUS"
''',
  };
  for (final entry in commands.entries) {
    final file = File('${bin.path}/${entry.key}')
      ..writeAsStringSync(entry.value);
    expect((await Process.run('chmod', ['+x', file.path])).exitCode, 0);
  }
  final args = File('${temp.path}/apt-args');
  final result = await Process.run(
    'bash',
    ['-c', script],
    environment: {
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'RUNNER_TEMP': temp.path,
      'SMOKE_DEPENDS': depends,
      'SMOKE_METADATA_STATUS': '$metadataStatus',
      'SMOKE_APT_STATUS': '$aptStatus',
      'SMOKE_APT_ARGS': args.path,
    },
  );
  return (
    status: result.exitCode,
    aptArgs: args.existsSync()
        ? args
              .readAsStringSync()
              .split('\u0000')
              .where((s) => s.isNotEmpty)
              .toList()
        : <String>[],
  );
}

const _historicalMissingDependencies = [
  'libwayland-server0',
  'libegl1',
  'libgles2',
  'libgl1',
  'libgbm1',
  'libx11-xcb1',
  'libcurl4',
  'libxmu6',
];

void main() {
  test('DEB declares providers of unbundled runtime ELF dependencies', () {
    final config =
        loadYaml(
              File('linux/packaging/deb/make_config.yaml').readAsStringSync(),
            )
            as YamlMap;
    expect(config['dependencies'], containsAll(_historicalMissingDependencies));
  });
  test(
    'smoke resolves the DEB dependency expression as one argument',
    () async {
      const depends = 'libsecret-1-0,\n libexample:any (>= 2) | libalternative';
      final result = await _installDependencies(depends: depends);
      expect(result.status, 0);
      expect(result.aptArgs, [
        'apt-get',
        'satisfy',
        '-y',
        '--no-install-recommends',
        '$depends, ${_historicalMissingDependencies.join(', ')}',
      ]);
    },
    skip: Platform.isWindows,
  );

  test('smoke stops when dependency metadata cannot be read', () async {
    final result = await _installDependencies(metadataStatus: 2);
    expect(result.status, isNot(0));
    expect(result.aptArgs, isEmpty);
  }, skip: Platform.isWindows);

  test('smoke rejects absent dependency metadata', () async {
    final result = await _installDependencies(depends: '');
    expect(result.status, isNot(0));
    expect(result.aptArgs, isEmpty);
  }, skip: Platform.isWindows);

  test('smoke propagates an unsatisfiable package dependency', () async {
    final result = await _installDependencies(aptStatus: 100);
    expect(result.status, 100);
  }, skip: Platform.isWindows);
}
