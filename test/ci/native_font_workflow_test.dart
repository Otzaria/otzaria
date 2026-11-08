import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

String _step(String workflow, String command) {
  final data =
      loadYaml(File('.github/workflows/$workflow').readAsStringSync())
          as YamlMap;
  final jobs = data['jobs'] as YamlMap;
  return jobs.values
      .cast<YamlMap>()
      .expand((job) => (job['steps'] as YamlList).cast<YamlMap>())
      .map((step) => step['run'])
      .whereType<String>()
      .singleWhere((run) => run.contains(command))
      .replaceAll(r'${{ matrix.instances }}', '1');
}

const _command = r'''#!/usr/bin/python3
import json, os, pathlib, sys
args = sys.argv[1:]
def value(prefix):
    return next((arg[len(prefix):] for arg in args if arg.startswith(prefix)), None)
if pathlib.Path(sys.argv[0]).name == 'flutter':
    count = value('--dart-define=OTZARIA_FONT_PROBE_INSTANCES=')
    mode = value('--dart-define=OTZARIA_FONT_PROBE_TRANSPORT=')
    output = os.environ['PLUGIN_FONT_PROBE_REPORTS']
elif '--instances' in args:
    count, mode = args[args.index('--instances') + 1], 'ios'
    output = args[args.index('--output') + 1]
else:
    output, mode = args[1], 'validate'
    count = pathlib.Path(output).name.split('-')[0]
pathlib.Path(output).mkdir(parents=True, exist_ok=True)
with open(os.environ['CALLS_FILE'], 'a') as stream:
    stream.write(json.dumps({'count': count, 'mode': mode, 'output': output, 'args': args}) + '\n')
print(count, mode)
sys.exit(1 if count == '5' and mode == os.environ.get('FAIL_MODE') else 0)
''';

Future<({ProcessResult process, List<Map<String, dynamic>> calls})> _run(
  String script, {
  String? failMode,
  String? missingSetupFile,
}) async {
  final root = await Directory.systemTemp.createTemp('native-font-workflow-');
  try {
    final bin = await Directory('${root.path}/bin').create();
    for (final name in ['flutter', 'python3']) {
      final file = File('${bin.path}/$name');
      await file.writeAsString(_command);
      final chmod = await Process.run('chmod', ['+x', file.path]);
      expect(chmod.exitCode, 0);
    }
    final output = await Directory('${root.path}/reports').create();
    for (final name in ['workflow.json', 'rust-targets.log', 'pub-get.log']) {
      if (name == missingSetupFile) continue;
      await File('${output.path}/$name').writeAsString('{}');
    }
    final calls = File('${root.path}/calls.jsonl');
    final result = await Process.run(
      'bash',
      ['-c', script],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'CALLS_FILE': calls.path,
        'PLUGIN_FONT_PROBE_REPORTS': output.path,
        'IOS_FONT_PROBE_OUTPUT': output.path,
        'FONT_PROBE_INSTANCES': '1',
        'FONT_PROBE_ORDER': 'data scheme',
        'FAIL_MODE': ?failMode,
      },
    );
    return (
      process: result,
      calls: await calls.exists()
          ? (await calls.readAsLines())
                .map((line) => jsonDecode(line) as Map<String, dynamic>)
                .toList()
          : <Map<String, dynamic>>[],
    );
  } finally {
    await root.delete(recursive: true);
  }
}

void main() {
  test('iOS cannot hide a setup evidence copy failure', () async {
    final result = await _run(
      _step('ios_plugin_font_probe.yml', 'run_ios_plugin_fonts.py'),
      missingSetupFile: 'pub-get.log',
    );
    expect(result.process.exitCode, isNot(0));
    expect(result.calls, isEmpty);
  }, skip: Platform.isWindows);

  test('iOS retains setup evidence before any count can start', () async {
    final root = await Directory.systemTemp.createTemp('font-setup-evidence-');
    try {
      final result = await Process.run(
        'bash',
        [
          '-c',
          _step('ios_plugin_font_probe.yml', 'GITHUB_ENV'),
        ],
        environment: {
          'RUNNER_TEMP': root.path,
          'GITHUB_ENV': '${root.path}/environment',
          'GITHUB_SHA': 'source-commit',
          'GITHUB_RUN_ID': '123',
        },
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final workflow =
          loadYaml(
                File(
                  '.github/workflows/ios_plugin_font_probe.yml',
                ).readAsStringSync(),
              )
              as YamlMap;
      final uploads = (workflow['jobs'] as YamlMap).values
          .cast<YamlMap>()
          .expand((job) => (job['steps'] as YamlList).cast<YamlMap>())
          .where(
            (step) =>
                step['if'] == 'always()' &&
                step['uses'].toString().startsWith('actions/upload-artifact@'),
          );
      final retained = <String>[];
      for (final upload in uploads) {
        for (final path in (upload['with']['path'] as String).split('\n')) {
          final expanded = path.trim().replaceAll(
            r'${{ runner.temp }}',
            root.path,
          );
          if (await File(expanded).exists()) retained.add(expanded);
          if (await Directory(expanded).exists()) {
            retained.addAll(
              await Directory(expanded)
                  .list(recursive: true)
                  .where((entry) => entry is File)
                  .map((entry) => entry.path)
                  .toList(),
            );
          }
        }
      }
      expect(retained, contains('${root.path}/ios-plugin-fonts/workflow.json'));
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: Platform.isWindows);

  for (final fail in [false, true]) {
    test('macOS retains every fresh pair when a pair fails: $fail', () async {
      final result = await _run(
        _step('macos_plugin_font_probe.yml', 'flutter drive'),
        failMode: fail ? 'scheme' : null,
      );
      expect(
        result.process.exitCode,
        fail ? 1 : 0,
        reason: '${result.process.stdout}\n${result.process.stderr}',
      );
      expect(result.calls.map((call) => '${call['count']}:${call['mode']}'), [
        '1:data',
        '1:scheme',
        '5:scheme',
        '5:data',
        '10:data',
        '10:scheme',
      ]);
      expect(result.calls.map((call) => call['output']).toSet(), hasLength(3));
    }, skip: Platform.isWindows);

    test(
      'iOS retains all eighteen cases for each count on failure: $fail',
      () async {
        final result = await _run(
          _step('ios_plugin_font_probe.yml', 'run_ios_plugin_fonts.py'),
          failMode: fail ? 'ios' : null,
        );
        expect(
          result.process.exitCode,
          fail ? 1 : 0,
          reason: '${result.process.stdout}\n${result.process.stderr}',
        );
        expect(result.calls.map((call) => call['count']), ['1', '5', '10']);
        expect(
          result.calls.map((call) => call['output']).toSet(),
          hasLength(3),
        );
      },
      skip: Platform.isWindows,
    );

    test(
      'macOS validates every pair even when one count is invalid: $fail',
      () async {
        final result = await _run(
          _step('macos_plugin_font_probe.yml', 'compare_macos_plugin_fonts.py'),
          failMode: fail ? 'validate' : null,
        );
        expect(
          result.process.exitCode,
          fail ? 1 : 0,
          reason: '${result.process.stdout}\n${result.process.stderr}',
        );
        expect(result.calls.map((call) => call['count']), ['1', '5', '10']);
      },
      skip: Platform.isWindows,
    );
  }
}
