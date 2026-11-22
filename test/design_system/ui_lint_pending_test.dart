import 'dart:io';

import 'package:test/test.dart';

import '../../tool/ui_lint/ui_lint.dart';

const _fixtures = 'test/design_system/fixtures';

/// נתיב של פיצ'ר רגיל, שאף החרגה בקונפיגורציה לא חלה עליו.
const _featurePath = 'lib/feature/view/feature_screen.dart';

final _config = UiLintConfig.load('.');

String _fixture(String name) =>
    File('$_fixtures/$name.dart').readAsStringSync();

List<int> _markedLines(String source) => [
  for (final (i, line) in source.split('\n').indexed)
    if (line.trimRight().endsWith('// LINT') || line.contains('/* LINT */'))
      i + 1,
];

List<int> _found(String fixture, String rule, {String path = _featurePath}) => [
  for (final f in lintSource(
    _fixture(fixture),
    path,
    config: _config,
    rules: uiLintPendingRules,
  ).findings)
    if (f.rule == rule) f.line,
];

void main() {
  test('כלל מועמד לא נכנס לקטלוג החוסם, ומזהה שלו ייחודי', () {
    final active = uiLintRules.map((r) => r.id).toSet();
    final pending = uiLintPendingRules.map((r) => r.id).toList();
    expect(pending.toSet(), hasLength(pending.length));
    expect(pending.toSet().intersection(active), isEmpty);
    for (final rule in uiLintPendingRules) {
      expect(rule.id, matches(RegExp(r'^UIL-\d{3}$')));
      expect(rule.isBlocking, isFalse, reason: rule.id);
      final extended = rule.extendsRule;
      if (extended != null) expect(active, contains(extended));
    }
  });

  group('כללים מועמדים (דוח בלבד)', () {
    for (final rule in uiLintPendingRules) {
      final suffix = rule.id.toLowerCase().replaceAll('-', '_');
      group(rule.id, () {
        test('violating: מוצא בדיוק את השורות המסומנות', () {
          final marked = _markedLines(_fixture('violating_$suffix'));
          expect(marked, isNotEmpty);
          expect(_found('violating_$suffix', rule.id), marked);
        });

        test('clean: שימוש תקין לא נתפס', () {
          expect(_found('clean_$suffix', rule.id), isEmpty);
        });
      });
    }

    test('UIL-034: בתוך lib/widgets IconButton מותר (הרכיבים המשותפים)', () {
      expect(
        _found(
          'violating_uil_034',
          'UIL-034',
          path: 'lib/widgets/controls/app_icon_button.dart',
        ),
        isEmpty,
      );
    });
  });

  group('שער ה־CI (gateFailures)', () {
    UiLintFinding finding(String rule, {String scope = 'a'}) => UiLintFinding(
      rule: rule,
      path: 'lib/a.dart',
      line: 3,
      column: 1,
      snippet: 'x',
      scope: scope,
      fingerprint: '11111111',
    );

    List<GateFailure> failures(
      List<UiLintFinding> findings, {
      UiLintBaseline? baseline,
      UiLintConfig? config,
      List<UiLintProblem> problems = const [],
    }) {
      final comparison = (baseline ?? UiLintBaseline(const {})).compare(
        findings,
      );
      return gateFailures(
        UiLintResult(findings, [], problems),
        comparison,
        config ?? UiLintConfig(),
      );
    }

    test('חריגה חדשה בכלל חוסם (שלב 3) מכשילה', () {
      final result = failures([finding('UIL-020')]);
      expect(result, hasLength(1));
      expect(result.single.path, 'lib/a.dart');
      expect(result.single.line, 3);
    });

    test('אותה חריגה בתוך ה־baseline לא מכשילה', () {
      final baseline = UiLintBaseline.fromFindings([finding('UIL-020')]);
      expect(failures([finding('UIL-020')], baseline: baseline), isEmpty);
    });

    test('כלל בשלב 4 שאינו נעול לא חוסם, ונעול כן', () {
      expect(failures([finding('UIL-025')]), isEmpty);
      expect(
        failures(
          [finding('UIL-025')],
          config: UiLintConfig(strictRules: {'UIL-025'}),
        ),
        hasLength(1),
      );
      expect(failures([finding('UIL-034')]), isEmpty);
    });

    test('baseline מת והערת allow פגומה מכשילים', () {
      final baseline = UiLintBaseline.fromFindings([finding('UIL-020')]);
      expect(failures(const [], baseline: baseline), hasLength(1));
      expect(
        failures(
          const [],
          problems: const [UiLintProblem('lib/a.dart', 7, 'allow פגומה')],
        ),
        hasLength(1),
      );
    });
  });

  group('ui_lint_cli --check (תהליך אמיתי על מאגר זמני)', () {
    late Directory repo;
    late String cli;

    setUpAll(() {
      cli = File('tool/ui_lint_cli.dart').absolute.path;
      repo = Directory.systemTemp.createTempSync('ui_lint_check_');
      File('${repo.path}/tool/ui_lint/config.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('rules:\n  UIL-004:\n    strict: true\n');
      File('${repo.path}/tool/ui_lint/baseline.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{\n  "version": 1,\n  "rules": {}\n}\n');
      File('${repo.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('const x = 1;\n');
    });

    tearDownAll(() => repo.deleteSync(recursive: true));

    ProcessResult run(String arg) => Process.runSync(
      'dart',
      [cli, arg],
      workingDirectory: repo.path,
      runInShell: true,
    );

    test('מאגר נקי: יציאה 0', () {
      final result = run('--check');
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test('חריגה חדשה: יציאה 1, והקבצים לא משתנים', () {
      final baselineBefore = File(
        '${repo.path}/tool/ui_lint/baseline.json',
      ).readAsStringSync();
      File('${repo.path}/lib/a.dart').writeAsStringSync(
        "import 'package:flutter/material.dart';\n"
        'Color c(BuildContext context) => Theme.of(context).primaryColor;\n',
      );
      final result = run('--check');
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('UIL-004'));
      expect(
        File('${repo.path}/tool/ui_lint/baseline.json').readAsStringSync(),
        baselineBefore,
      );
    });

    test('דוח רגיל (בלי --check) נשאר בקוד יציאה 0 גם עם חריגה', () {
      final result = run('--format=md');
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });
  });
}
