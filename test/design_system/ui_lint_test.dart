import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

import '../../tool/ui_lint/ast_helpers.dart';
import '../../tool/ui_lint/ui_lint.dart';

const _fixtures = 'test/design_system/fixtures';

/// נתיב של פיצ'ר רגיל, שאף החרגה בקונפיגורציה לא חלה עליו.
const _featurePath = 'lib/feature/view/feature_screen.dart';

final _config = UiLintConfig.load('.');

String _fixture(String name) =>
    File('$_fixtures/$name.dart').readAsStringSync();

UiLintResult _lint(String name, {String path = _featurePath}) =>
    lintSource(_fixture(name), path, config: _config);

/// השורות שמסומנות `// LINT` בקובץ.
List<int> _markedLines(String source) => [
  for (final (i, line) in source.split('\n').indexed)
    if (line.trimRight().endsWith('// LINT')) i + 1,
];

void main() {
  test('לכל כלל יש מזהה ייחודי בקטלוג', () {
    final ids = uiLintRules.map((r) => r.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^UIL-\d{3}$')));
    }
  });

  for (final rule in uiLintRules) {
    final suffix = rule.id.toLowerCase().replaceAll('-', '_');

    group(rule.id, () {
      test('violating: מוצא בדיוק את השורות המסומנות', () {
        final source = _fixture('violating_$suffix');
        final lines = _lint(
          'violating_$suffix',
        ).findings.where((f) => f.rule == rule.id).map((f) => f.line).toList();
        expect(_markedLines(source), isNotEmpty);
        expect(lines, _markedLines(source));
      });

      test('clean: שימוש תקין ושימושים מוחרגים לא נתפסים', () {
        final result = _lint('clean_$suffix');
        expect(result.findings.where((f) => f.rule == rule.id), isEmpty);
        expect(result.problems, isEmpty);
      });

      test('allowed: הערת allow תקינה משתיקה את החריגה', () {
        final result = _lint('allowed_$suffix');
        expect(result.findings.where((f) => f.rule == rule.id), isEmpty);
        expect(result.problems, isEmpty);
        expect(result.allows.single.rule, rule.id);
        expect(result.allows.single.used, isTrue);
      });
    });
  }

  group('ניתוח AST לא מפוענח', () {
    test('ctorCallsNamed מוצא בנאי בכל הצורות', () {
      final unit = parseString(
        content: '''
import 'package:pdf/widgets.dart' as pw;
final a = Foo();
final b = const Foo();
final c = new Foo();
final d = Foo.named();
final e = pw.Foo();
final f = pw.Foo.named();
final g = foo();
final h = bar.foo();
final i = Bar();
''',
      ).unit;
      final calls = ctorCallsNamed(unit, {'Foo'});
      expect(calls, hasLength(6));
      expect(
        calls.map((c) => (c.constructor, c.importPrefix)),
        [
          (null, null),
          (null, null),
          (null, null),
          ('named', null),
          (null, 'pw'),
          ('named', 'pw'),
        ],
      );
    });

    test('scopeOf: מחלקה ומתודה, בלי מספרי שורות', () {
      final result = lintSource(
        '''
import 'package:flutter/material.dart';
class Screen extends StatelessWidget {
  const Screen({super.key});
  @override
  Widget build(BuildContext context) => const Text('x', style: TextStyle(fontSize: 13));
}
const top = TextStyle(fontSize: 11);
''',
        _featurePath,
        config: _config,
      );
      expect(result.findings.map((f) => f.scope), ['Screen.build', 'top']);
    });
  });

  group('החרגות לפי נתיב', () {
    test('שכבת הטוקנים פטורה מכללי הצבע, הגופן והרדיוס', () {
      for (final suffix in ['uil_015', 'uil_017', 'uil_019']) {
        expect(
          _lint(
            'violating_$suffix',
            path: 'lib/theme/app_tokens.dart',
          ).findings,
          isEmpty,
          reason: suffix,
        );
      }
    });

    test('רכיבי הדיאלוג המשותפים פטורים מ-UIL-001', () {
      expect(
        _lint(
          'violating_uil_001',
          path: 'lib/widgets/dialogs/app_dialogs.dart',
        ).findings.where((f) => f.rule == 'UIL-001'),
        isEmpty,
      );
    });

    test('קבצים שנוצרו אוטומטית לא נבדקים', () {
      expect(
        _lint('violating_uil_015', path: 'lib/feature/feature.g.dart').findings,
        isEmpty,
      );
    });

    test('החרגה בלי reason היא שגיאת קונפיגורציה', () {
      expect(
        () => UiLintConfig.parse(
          'rules:\n  UIL-015:\n    exclude:\n'
          '      - path: lib/x/**\n',
        ),
        throwsFormatException,
      );
    });
  });

  test('הערות allow פגומות או מיותרות מדווחות ולא משתיקות', () {
    final result = _lint('bad_allows');
    expect(result.allows.where((a) => a.used), isEmpty);
    expect(result.findings.where((f) => f.rule == 'UIL-004'), hasLength(4));
    expect(result.problems.map((p) => p.line), [3, 6, 9, 12, 15]);
  });

  group('baseline', () {
    final source = _fixture('violating_uil_017');
    final findings = lintSource(source, _featurePath, config: _config).findings;
    final baseline = UiLintBaseline.fromFindings(findings);

    test('אותו קוד: אין חריגות חדשות ואין baseline מת', () {
      final comparison = baseline.compare(findings);
      expect(comparison.newFindings, isEmpty);
      expect(comparison.dead, isEmpty);
    });

    test('הזזת קוד ופורמט לא שוברים את ה-baseline', () {
      final moved = lintSource(
        '\n\n${source.replaceAll('(fontSize: 13)', '(\n  fontSize: 13,\n)')}',
        _featurePath,
        config: _config,
      ).findings;
      expect(baseline.compare(moved).newFindings, isEmpty);
    });

    test('חריגה חדשה מזוהה, גם כשהיא זהה לחריגה קיימת', () {
      final added = lintSource(
        '$source\nconst TextStyle again = TextStyle(fontSize: 13);\n'
        'const TextStyle other = TextStyle(fontSize: 15);\n',
        _featurePath,
        config: _config,
      ).findings;
      final comparison = baseline.compare(added);
      expect(comparison.newFindings.map((f) => f.snippet), [
        'fontSize: 13',
        'fontSize: 15',
      ]);
    });

    test('תיקון משאיר baseline מת, ו-updated רק מכווץ', () {
      final fixed = findings.skip(1).toList();
      expect(baseline.compare(fixed).dead, hasLength(1));
      final shrunk = baseline.updated(fixed);
      expect(shrunk.size, baseline.size - 1);
      expect(shrunk.compare(fixed).dead, isEmpty);

      final grown = findings + findings;
      expect(baseline.updated(grown).size, baseline.size);
      expect(
        baseline.updated(grown, allowGrowth: true).size,
        2 * baseline.size,
      );
    });

    test('הסריאליזציה הפיכה', () {
      final parsed = UiLintBaseline.parse(baseline.toJsonString());
      expect(parsed.counts, baseline.counts);
    });

    test('קובץ ה-baseline במאגר תקין וכתוב בפורמט של הכלי', () {
      final text = File(baselineRelativePath).readAsStringSync();
      final stored = UiLintBaseline.parse(text);
      expect(stored.toJsonString(), text);
      final known = uiLintRules.map((r) => r.id).toSet();
      expect(
        stored.counts.keys.map((k) => k.split('|').first).toSet(),
        everyElement(isIn(known)),
      );
    });
  });
}
