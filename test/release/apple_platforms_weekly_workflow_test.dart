import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final workflow = loadYaml(
    File('.github/workflows/apple_platforms_weekly.yml').readAsStringSync(),
  );
  final jobs = workflow['jobs'] as YamlMap;
  String runOf(String job) => (jobs[job]['steps'] as YamlList)
      .cast<YamlMap>()
      .map((s) => s['run'])
      .whereType<String>()
      .join('\n');

  test('runs weekly and by hand, never on pull requests', () {
    // YAML 1.1 reads the key `on` as true in some parsers.
    final on = (workflow['on'] ?? workflow[true]) as YamlMap;
    expect(on.keys, containsAll(['schedule', 'workflow_dispatch']));
    expect(on.keys, isNot(contains('pull_request')));
    final cron = (on['schedule'] as YamlList).single['cron'] as String;
    expect(cron.split(' '), hasLength(5));
    expect(cron.split(' ')[4], isNot('*'), reason: 'weekly, not daily');
  });

  test('both jobs run on a real Mac', () {
    for (final job in ['macos_tests', 'ios_build']) {
      expect(jobs[job]['runs-on'], 'macos-latest', reason: job);
    }
  });

  test('the test subset points at existing test directories', () {
    final command = RegExp(
      r'flutter test ([^\\]+(?:\\\n\s+[^\\]+)*)',
    ).firstMatch(runOf('macos_tests'))!.group(1)!;
    final dirs = command
        .split(RegExp(r'\s+'))
        .where((token) => token.startsWith('test/'));
    expect(dirs, isNotEmpty);
    for (final dir in dirs) {
      expect(Directory(dir).existsSync(), isTrue, reason: dir);
    }
  });

  test('iOS is built unsigned, with the Rust target the store build uses', () {
    expect(runOf('ios_build'), contains('flutter build ios'));
    expect(runOf('ios_build'), contains('--no-codesign'));
    final storeBuild = File(
      '.github/workflows/deploy-app-store.yml',
    ).readAsStringSync();
    expect(storeBuild, contains('aarch64-apple-ios'));
    final rust = (jobs['ios_build']['steps'] as YamlList)
        .cast<YamlMap>()
        .firstWhere((s) => '${s['uses']}'.startsWith('dtolnay/rust-toolchain'));
    expect(rust['with']['targets'], 'aarch64-apple-ios');
  });
}
