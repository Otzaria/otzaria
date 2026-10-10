import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File(
    '.github/workflows/build-and-announce.yml',
  ).readAsStringSync();
  final installer = File('installer/otzaria.iss').readAsStringSync();

  int indexOfStep(String name) {
    final at = workflow.indexOf('- name: $name');
    expect(at, greaterThan(-1), reason: 'השלב "$name" אינו ב-workflow');
    return at;
  }

  group('חיווט המעדכן העצמאי ל-CI', () {
    test('המעדכן מקומפל לתיקיית ה-Release בשתי הארכיטקטורות', () {
      for (final arch in ['x64', 'arm64']) {
        expect(
          workflow,
          contains(
            'build\\windows\\$arch\\runner\\Release\\otzaria_updater.exe',
          ),
          reason: arch,
        );
      }
      expect(
        workflow,
        contains('dart compile exe tool/updater/otzaria_updater.dart'),
      );
    });

    test('הקומפילציה קודמת לאריזה ולמניפסט, ולכן המעדכן נכלל בהם', () {
      expect(
        indexOfStep('Build differential updater helper (x64)'),
        lessThan(indexOfStep('Zip Windows build')),
      );
      expect(
        indexOfStep('Build differential updater helper (x64)'),
        lessThan(indexOfStep('Generate application file manifest (x64)')),
      );
      expect(
        indexOfStep('Build differential updater helper (ARM64)'),
        lessThan(indexOfStep('Zip Windows ARM64 build')),
      );
      expect(
        indexOfStep('Build differential updater helper (ARM64)'),
        lessThan(indexOfStep('Build regular installer (ARM64)')),
      );
    });

    test('כישלון בקומפילציה אינו מפיל את הבנייה', () {
      for (final name in [
        'Build differential updater helper (x64)',
        'Build differential updater helper (ARM64)',
      ]) {
        final at = indexOfStep(name);
        expect(
          workflow.substring(at, at + 300),
          contains('continue-on-error: true'),
          reason: name,
        );
      }
    });

    test('המתקין לא שונה — הוא כבר אורז את כל תיקיית ה-Release', () {
      expect(
        installer,
        contains(r'..\build\windows\{#AppArch}\runner\Release'),
      );
      expect(installer, isNot(contains('otzaria_updater')));
    });
  });
}
