import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const builds = {
    '.github/workflows/build-and-announce.yml': {
      'build_macos': ['Build Flutter macOS app (Universal Binary, with retry)'],
    },
    '.github/workflows/macos_runner.yml': {
      'macos_runner': [
        'Build macOS app (debug, with retry)',
        'Run RunnerTests (XCTest)',
      ],
    },
  };

  for (final workflow in builds.entries) {
    final document = loadYaml(File(workflow.key).readAsStringSync()) as YamlMap;
    for (final job in workflow.value.entries) {
      final steps = document['jobs'][job.key]['steps'] as YamlList;
      for (final name in job.value) {
        test('$name מקבל טוקן להפעלת ONNX API fallback', () {
          final step = steps.cast<YamlMap>().singleWhere(
            (step) => step['name'] == name,
          );
          expect(step['env']?['GH_TOKEN'], r'${{ github.token }}');
        });
      }
    }
  }
}
