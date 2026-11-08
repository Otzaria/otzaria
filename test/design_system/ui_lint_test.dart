import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

import '../../tool/ui_lint/ast_helpers.dart';
import '../../tool/ui_lint/ui_lint.dart';

const _fixtures = 'test/design_system/fixtures';

/// נתיב של פיצ'ר רגיל, שאף החרגה בקונפיגורציה לא חלה עליו.
const _featurePath = 'lib/feature/view/feature_screen.dart';

/// נתיב לכלל שחל רק על חלק מ-lib.
const _rulePaths = {
  'UIL-024': 'lib/widgets/misc/shared_widget.dart',
  'UIL-025': 'lib/widgets/misc/shared_widget.dart',
};

final _config = UiLintConfig.load('.');

String _fixture(String name) =>
    File('$_fixtures/$name.dart').readAsStringSync();

UiLintResult _lint(String name, {String path = _featurePath}) =>
    lintSource(_fixture(name), path, config: _config);

/// סימוני השורות הצפויות; סימון בלוק נשאר ליד הבנאי גם אחרי פירמוט.
List<int> _markedLines(String source) => [
  for (final (i, line) in source.split('\n').indexed)
    if (line.trimRight().endsWith('// LINT') || line.contains('/* LINT */'))
      i + 1,
];

void main() {
  test('לכל כלל יש מזהה ייחודי בקטלוג ושלב', () {
    final ids = uiLintRules.map((r) => r.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final rule in uiLintRules) {
      expect(rule.id, matches(RegExp(r'^UIL-\d{3}$')));
      expect(rule.stage, inInclusiveRange(1, 4), reason: rule.id);
    }
  });

  group('lib מול ה-baseline (חוסם)', () {
    late final UiLintResult result;
    late final BaselineComparison comparison;

    setUpAll(() {
      result = runUiLint('.', config: _config);
      comparison = UiLintBaseline.load('.').compare(result.findings);
    });

    test('הסורק מוצא את החוב הקיים', () {
      expect(result.findings, isNotEmpty);
    });

    test('אין חריגות חדשות בכללים החוסמים', () {
      final fresh = [
        for (final finding in comparison.newFindings)
          if (_ruleOf(finding).isBlocking || _config.isStrict(finding.rule))
            finding,
      ];
      expect(
        fresh,
        isEmpty,
        reason:
            'חריגה חדשה מהתקן (docs/design-system/CI_ENFORCEMENT.md). '
            'לתקן לפי ההצעה, או להוסיף מעליה '
            '"// ui-lint: allow UIL-xxx — נימוק". '
            'חריגה ישנה שהביטוי שלה השתנה מופיעה גם כ-baseline מת: '
            'dart tool/ui_lint_cli.dart --update-baseline --allow-growth '
            '(ui_baseline_guard בודק שהספירה לא גדלה):\n'
            '${fresh.map(_describe).join('\n')}',
      );
    });

    test('אין baseline מת', () {
      expect(
        comparison.dead.keys,
        isEmpty,
        reason:
            'חריגות שתוקנו עדיין רשומות ב-baseline. '
            'הרץ: dart tool/ui_lint_cli.dart --update-baseline. '
            'אם החריגה לא תוקנה אלא הביטוי שלה השתנה (היא מופיעה גם '
            'כחריגה חדשה): --update-baseline --allow-growth',
      );
    });

    test('אין הערות allow פגומות או מיותרות', () {
      expect(result.problems.map((p) => '$p'), isEmpty);
    });

    test('כלל בלי חוב ב-baseline נעול (strict), וכלל נעול בלי חוב', () {
      final withDebt = UiLintBaseline.load(
        '.',
      ).counts.keys.map((k) => k.split('|').first).toSet();
      final unlocked = [
        for (final rule in uiLintRules)
          if (!withDebt.contains(rule.id) && !_config.isStrict(rule.id))
            rule.id,
      ];
      final lockedWithDebt = [
        for (final rule in _config.strictRules)
          if (withDebt.contains(rule)) rule,
      ];
      expect(
        unlocked,
        isEmpty,
        reason:
            'החוב של הכלל נגמר: להוסיף לו "strict: true" ב-'
            'tool/ui_lint/config.yaml, כדי שחריגה לא תחזור דרך '
            '--allow-growth (CI_ENFORCEMENT.md §6, רמה 4)',
      );
      expect(
        lockedWithDebt,
        isEmpty,
        reason:
            'כלל נעול לא מקבל רשומות baseline: לתקן את החריגה, או להוסיף '
            'מעליה "// ui-lint: allow UIL-xxx — נימוק"',
      );
    });
  });

  for (final rule in uiLintRules) {
    final suffix = rule.id.toLowerCase().replaceAll('-', '_');
    final path = _rulePaths[rule.id] ?? _featurePath;

    group(rule.id, () {
      test('violating: מוצא בדיוק את השורות המסומנות', () {
        final source = _fixture('violating_$suffix');
        final lines = _lint(
          'violating_$suffix',
          path: path,
        ).findings.where((f) => f.rule == rule.id).map((f) => f.line).toList();
        expect(_markedLines(source), isNotEmpty);
        expect(lines, _markedLines(source));
      });

      test('clean: שימוש תקין ושימושים מוחרגים לא נתפסים', () {
        final result = _lint('clean_$suffix', path: path);
        expect(result.findings.where((f) => f.rule == rule.id), isEmpty);
        expect(result.problems, isEmpty);
      });

      test('allowed: הערת allow תקינה משתיקה את החריגה', () {
        final result = _lint('allowed_$suffix', path: path);
        expect(result.findings.where((f) => f.rule == rule.id), isEmpty);
        expect(result.problems, isEmpty);
        expect(result.allows.single.rule, rule.id);
        expect(result.allows.single.used, isTrue);
      });
    });
  }

  group('UIL-024 לפי נתיב', () {
    const source = '''
import '../../tabs/view/pane_drag_handle.dart';
import '../controls/bar_button.dart';
import 'package:otzaria/models/books.dart';
''';

    List<int> lines(String path) => [
      for (final f in lintSource(source, path, config: _config).findings)
        if (f.rule == 'UIL-024') f.line,
    ];

    test('ייבוא יחסי מחוץ ל-lib/widgets נתפס, ובתוכו מותר', () {
      expect(lines('lib/widgets/misc/shared_widget.dart'), [1, 3]);
    });

    test("קובץ פיצ'ר רשאי לייבא פיצ'ר", () {
      expect(lines(_featurePath), isEmpty);
    });
  });

  test("UIL-025 חל רק על lib/widgets: קוד פיצ'ר קורא את ההגדרה", () {
    List<UiLintFinding> found(String path) => [
      for (final f in _lint('violating_uil_025', path: path).findings)
        if (f.rule == 'UIL-025') f,
    ];
    expect(found('lib/widgets/misc/shared_widget.dart'), hasLength(3));
    expect(found(_featurePath), isEmpty);
  });

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
final j = const Foo.named();
final k = const pw.Foo.named();
''',
      ).unit;
      final calls = ctorCallsNamed(unit, {'Foo'});
      expect(calls, hasLength(8));
      expect(
        calls.map((c) => (c.constructor, c.importPrefix)),
        [
          (null, null),
          (null, null),
          (null, null),
          ('named', null),
          (null, 'pw'),
          ('named', 'pw'),
          ('named', null),
          ('named', 'pw'),
        ],
      );
    });

    test('prefix של ייבוא Flutter נמחק, prefix אחר (pw) נשאר', () {
      final unit = parseString(
        content: '''
import 'package:flutter/material.dart' as m;
import 'package:pdf/widgets.dart' as pw;
final a = m.Card();
final b = const m.TextButton.icon();
final c = pw.Card();
''',
      ).unit;
      expect(
        ctorCallsNamed(unit, {'Card', 'TextButton'}).map((c) => c.head),
        ['Card', 'TextButton.icon', 'pw.Card'],
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
    test('שכבת הטוקנים פטורה מכללי הטוקנים', () {
      for (final suffix in [
        'uil_015',
        'uil_016',
        'uil_017',
        'uil_019',
        'uil_020',
        'uil_021',
        'uil_023',
        'uil_029',
      ]) {
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

    test('strict נקרא מהקונפיגורציה, וערך שאינו bool הוא שגיאה', () {
      final config = UiLintConfig.parse(
        'rules:\n  UIL-015:\n    strict: true\n'
        '  UIL-016:\n    strict: false\n',
      );
      expect(config.strictRules, {'UIL-015'});
      expect(
        () => UiLintConfig.parse('rules:\n  UIL-015:\n    strict: yes-ish\n'),
        throwsFormatException,
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

    test('שינוי בתוכן של דיאלוג גולמי לא הופך אותו לחריגה חדשה', () {
      List<UiLintFinding> dialogs(String body) => lintSource(
        "import 'package:flutter/material.dart';\n"
        'Widget build() => Dialog(child: $body);\n',
        _featurePath,
        config: _config,
      ).findings;
      final before = UiLintBaseline.fromFindings(dialogs("Text('א')"));
      final edited = before.compare(dialogs("Column(children: [Text('ב')])"));
      expect(edited.newFindings, isEmpty);
      expect(edited.dead, isEmpty);
    });

    test('שינוי בילד של Positioned לא הופך אותו לחריגה חדשה', () {
      List<UiLintFinding> positioned(
        String child, {
        String left = '4',
      }) => lintSource(
        "import 'package:flutter/material.dart';\n"
        'Widget build() => Positioned(left: $left, top: 0, child: $child);\n',
        _featurePath,
        config: _config,
      ).findings;
      final before = UiLintBaseline.fromFindings(positioned("Text('א')"));
      final edited = before.compare(
        positioned("Column(children: [Text('ב')])"),
      );
      expect(edited.newFindings, isEmpty);
      expect(edited.dead, isEmpty);
      // שינוי בכיוון עצמו כן נתפס.
      final moved = before.compare(positioned("Text('א')", left: '8'));
      expect(moved.newFindings, hasLength(1));
    });

    test('כלל נעול לא נכנס ל-baseline גם עם allowGrowth', () {
      final grown = baseline.updated(
        findings + findings,
        allowGrowth: true,
        strictRules: {'UIL-017'},
      );
      expect(grown.size, 0);
      expect(baseline.updated(findings, strictRules: {'UIL-017'}).size, 0);
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

UiLintRule _ruleOf(UiLintFinding finding) =>
    uiLintRules.firstWhere((r) => r.id == finding.rule);

String _describe(UiLintFinding finding) {
  final rule = _ruleOf(finding);
  return '${finding.path}:${finding.line}: ${finding.snippet} — '
      '${rule.id} ${rule.title}. במקום: ${rule.hint}';
}
