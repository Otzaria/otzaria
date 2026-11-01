import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('מדיניות פרסום, הכרזה ופריסה לחנויות מול API מדומה', () async {
    final result = await Process.run(
      'python3',
      [
        'tool/release/test_latest_release_policy.py',
      ],
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('רק ריליס שפורסם כ-Latest מפעיל פריסה לחנויות', () {
    final workflow =
        loadYaml(
              File(
                '.github/workflows/build-and-announce.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    for (final name in [
      'trigger_google_play_deploy',
      'trigger_app_store_deploy',
    ]) {
      final job = jobs[name] as YamlMap;
      expect(job['needs'], contains('create_release'));
      expect(job['if'], contains("needs.create_release.result == 'success'"));
      expect(
        job['if'],
        contains("needs.create_release.outputs.is_latest == 'true'"),
      );
      expect(job['if'], isNot(contains('check_version')));
    }
    for (final (file, name) in [
      ('deploy-google-play.yml', 'deploy_play'),
      ('deploy-app-store.yml', 'deploy_app_store'),
    ]) {
      final child =
          loadYaml(File('.github/workflows/$file').readAsStringSync())
              as YamlMap;
      final steps = child['jobs'][name]['steps'] as YamlList;
      expect(steps[1]['name'], 'Verify checkout is the Latest release');
      final guards = steps.where(
        (step) => (step['run']?.toString() ?? '').contains(
          '--assert-current-checkout',
        ),
      );
      expect(guards, hasLength(2));
    }
  });
}
