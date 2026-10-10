import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<ProcessResult> _run(
  String command,
  List<String> args,
  String directory,
) => Process.run(command, args, workingDirectory: directory);

Future<void> _checked(
  String command,
  List<String> args,
  String directory,
) async {
  final result = await _run(command, args, directory);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

void _write(Directory directory, String path, String content) {
  final file = File(p.join(directory.path, path));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

Future<ProcessResult> _buildName(Directory directory) => _run('python3', [
  p.absolute('tool/version/app_store_build_name.py'),
  'pubspec.yaml',
  'tool/version/version.json',
], directory.path);

List<int> _components(String version) =>
    version.split('.').map(int.parse).toList();

bool _greaterThan(String next, String previous) {
  final a = _components(next);
  final b = _components(previous);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

void main() {
  var hasPwsh = false;
  try {
    hasPwsh = Process.runSync('pwsh', ['--version']).exitCode == 0;
  } on ProcessException {
    hasPwsh = false;
  }

  for (final scriptName in ['update_version.sh', 'update_version.ps1']) {
    test(
      '$scriptName: regular, two published hotfixes and all rollovers',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'app_store_version_',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        for (final args in [
          ['init', '-q'],
          ['config', 'user.name', 'Test'],
          ['config', 'user.email', 'test@example.invalid'],
          ['config', 'core.hooksPath', p.join(directory.path, 'no-hooks')],
        ]) {
          await _checked('git', args, directory.path);
        }
        _write(directory, '.gitignore', 'external/\n');
        _write(
          directory,
          'pubspec.yaml',
          'version: 0.9.97+99700\nname: otzaria\n',
        );
        _write(
          directory,
          'lib/main.dart',
          'const int _latestReleasedBuildNumber = 99700;\n',
        );
        for (final name in ['otzaria', 'otzaria_full']) {
          _write(
            directory,
            'installer/$name.iss',
            '#define MyAppVersion "0.9.97"\n',
          );
        }
        _write(
          directory,
          'android/local.properties',
          'flutter.versionName=0.9.97\nflutter.versionCode=99700\n',
        );
        _write(directory, 'assets/יומן שינויים.md', '* **0.9.97**\n  - קודם\n');
        for (final name in ['app_store_whats_new.py', 'play_whats_new.py']) {
          _write(
            directory,
            'tool/version/$name',
            File('tool/version/$name').readAsStringSync(),
          );
        }

        var previous = '0.9.98';
        var previousBuild = 99700;
        for (final release in [
          ('0.9.98', 0, '0.9.9800'),
          ('0.9.98', 1, '0.9.9801'),
          ('0.9.98', 2, '0.9.9802'),
          ('0.9.98', 99, '0.9.9899'),
          ('0.9.99', 0, '0.9.9900'),
          ('0.9.99', 99, '0.9.9999'),
          ('0.10.0', 0, '0.10.0'),
          ('0.99.99', 99, '0.99.9999'),
          ('1.0.0', 0, '1.0.0'),
        ]) {
          final (version, hotfix, expected) = release;
          final parts = _components(version);
          final code =
              parts[0] * 1000000 + parts[1] * 10000 + parts[2] * 100 + hotfix;
          _write(
            directory,
            'tool/version/version.json',
            jsonEncode({'version': version, 'hotfix': hotfix}),
          );
          final changelog = File(
            p.join(directory.path, 'assets/יומן שינויים.md'),
          );
          final note = 'שינוי $version תיקון $hotfix';
          changelog.writeAsStringSync(
            '  - $note\n${changelog.readAsStringSync()}',
          );
          final script = p.absolute('tool/version/$scriptName');
          await _checked(
            scriptName.endsWith('.ps1') ? 'pwsh' : 'bash',
            scriptName.endsWith('.ps1')
                ? [
                    '-NoLogo',
                    '-NoProfile',
                    '-File',
                    script,
                    'tool/version/version.json',
                  ]
                : [script, 'tool/version/version.json'],
            directory.path,
          );
          final result = await _buildName(directory);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
          final iosVersion = (result.stdout as String).trim();
          expect(iosVersion, expected);
          expect(iosVersion, matches(r'^\d+\.\d+\.\d+$'));
          expect(iosVersion.length, lessThanOrEqualTo(18));
          expect(_greaterThan(iosVersion, previous), isTrue);
          expect(code, greaterThan(previousBuild));
          expect(
            File(
              p.join(directory.path, 'pubspec.yaml'),
            ).readAsLinesSync().first,
            'version: $version+$code',
          );
          final android = File(
            p.join(directory.path, 'android/local.properties'),
          ).readAsStringSync();
          expect(android, contains('flutter.versionName=$version'));
          expect(android, contains('flutter.versionCode=$code'));
          expect(
            changelog.readAsLinesSync().first,
            '* **$version${hotfix > 0 ? '.$hotfix' : ''}**',
          );
          await _checked('python3', [
            'tool/version/app_store_whats_new.py',
            'notes.txt',
          ], directory.path);
          expect(
            File(p.join(directory.path, 'notes.txt')).readAsStringSync(),
            '• $note',
          );
          final commit = await _run('git', [
            'log',
            '-1',
            '--format=%s',
          ], directory.path);
          expect((commit.stdout as String).trim(), version);
          previous = iosVersion;
          previousBuild = code;
        }
      },
      skip: scriptName.endsWith('.ps1') && !hasPwsh
          ? 'pwsh is unavailable'
          : false,
    );
  }

  test('mismatched release metadata fails before iOS build', () async {
    final directory = Directory.systemTemp.createTempSync(
      'app_store_mismatch_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    _write(
      directory,
      'tool/version/version.json',
      jsonEncode({'version': '0.9.98', 'hotfix': 1}),
    );
    for (final version in ['0.9.98+99800', '0.9.99+99901', '0.9.98+99802']) {
      _write(directory, 'pubspec.yaml', 'version: $version\n');
      final result = await _buildName(directory);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('אינם תואמים'));
    }
    for (final data in [
      {'version': '0.9.98', 'hotfix': 100},
      {'version': '0.9.98', 'hotfix': -1},
      {'version': '0.9.98', 'hotfix': 1.5},
      {'version': '0.9.100', 'hotfix': 0},
      {'version': '0.100.0', 'hotfix': 0},
      {'version': '0.9.98.1', 'hotfix': 0},
    ]) {
      _write(directory, 'tool/version/version.json', jsonEncode(data));
      expect((await _buildName(directory)).exitCode, isNot(0));
    }
  });

  test('iOS workflow uses the derived version from the release commit', () {
    final parent =
        loadYaml(
              File(
                '.github/workflows/build-and-announce.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final child =
        loadYaml(
              File('.github/workflows/deploy-app-store.yml').readAsStringSync(),
            )
            as YamlMap;
    final jobs = parent['jobs'] as YamlMap;
    final trigger = jobs['trigger_app_store_deploy'] as YamlMap;
    expect(trigger['with']['ref'], r'${{ needs.bump_version.outputs.sha }}');
    expect(trigger['with'], jobs['trigger_google_play_deploy']['with']);
    final steps = child['jobs']['deploy_app_store']['steps'] as YamlList;
    expect(steps.first['with']['ref'], r'${{ inputs.ref || github.ref }}');
    final build = steps.firstWhere(
      (step) => step['name'] == 'Build Flutter iOS (unsigned)',
    );
    expect(
      build['run'],
      contains(
        'tool/version/app_store_build_name.py pubspec.yaml tool/version/version.json',
      ),
    );
    expect(build['run'], contains(r'--build-name="$IOS_BUILD_NAME"'));
    expect(build['run'], isNot(contains('--build-number')));
    expect(
      steps.any(
        (step) => (step['run'] ?? '').toString().contains(
          'tool/version/app_store_whats_new.py',
        ),
      ),
      isTrue,
    );
  });
}
