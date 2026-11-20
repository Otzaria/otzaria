import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/design_report.dart';

Map<String, dynamic> _baseline(Map<String, Map<String, int>> rules) => {
  'version': 1,
  'rules': {
    for (final MapEntry(key: rule, value: files) in rules.entries)
      rule: {
        for (final MapEntry(key: path, value: n) in files.entries)
          path: [
            {'scope': 'A.build', 'fp': '11111111', 'n': n},
          ],
      },
  },
};

Map<String, dynamic> _lint({
  List<Map<String, dynamic>> fresh = const [],
  List<Map<String, dynamic>> pending = const [],
}) => {
  'rules': [
    {
      'id': 'UIL-017',
      'title': 'fontSize ליטרלי',
      'strict': false,
      'pending': false,
      'allowCap': 1,
    },
    {
      'id': 'UIL-020',
      'title': 'ריווח מחוץ לסולם',
      'strict': true,
      'pending': false,
      'allowCap': 0,
    },
    {
      'id': 'UIL-034',
      'title': 'IconButton גולמי',
      'pending': true,
      'extendsRule': null,
    },
  ],
  'findings': [
    {'rule': 'UIL-017', 'path': 'lib/search/a.dart'},
    {'rule': 'UIL-017', 'path': 'lib/search/b.dart'},
    {'rule': 'UIL-020', 'path': 'lib/tools/c.dart'},
  ],
  'new': fresh,
  'pending': pending,
  'allows': [
    {'path': 'lib/search/a.dart', 'rule': 'UIL-017'},
  ],
};

void main() {
  group('baseline', () {
    final baseline = _baseline({
      'UIL-017': {'lib/search/a.dart': 3, 'lib/search/b.dart': 2},
      'UIL-020': {'lib/main.dart': 1},
    });

    test('סכום לפי כלל ולפי מודול', () {
      expect(baselineByRule(baseline), {'UIL-017': 5, 'UIL-020': 1});
      expect(baselineByModule(baseline), {'search': 5, 'lib': 1});
    });
  });

  group('responsive', () {
    test('שורות JSON של ה-harness, כולל שורה פגומה וכשל בלי issues', () {
      final failures = parseResponsiveLines('''
{"scenario":"דיאלוג","viewport":"390x640","issues":[{"kind":"overflow","detail":"20px"}],"error":null,"screenshot":"/tmp/s.png"}
not json
{"scenario":"סרגל","viewport":"320x480","issues":[],"error":"Expected: visible","screenshot":null}
''');
      expect(failures, hasLength(2));
      expect(failures.first.issues.single, ('overflow', '20px'));
      expect(failures.last.issues.single, ('error', 'Expected: visible'));
    });
  });

  group('golden', () {
    test('קבצי הכשל מקובצים לפי בדיקה', () {
      final byTest = goldenFailuresByTest([
        'g/app_card/failures/light_masterImage.png',
        'g/app_card/failures/light_testImage.png',
        'g/app_card/failures/light_isolatedDiff.png',
        'g/app_card/failures/readme.txt',
      ]);
      expect(byTest.keys.single, endsWith('light'));
      expect(byTest.values.single, hasLength(3));
    });
  });

  group('דוח Markdown', () {
    final base = _baseline({
      'UIL-017': {'lib/search/a.dart': 3},
      'UIL-020': {'lib/tools/c.dart': 1},
    });
    final head = _baseline({
      'UIL-017': {'lib/search/a.dart': 2},
      'UIL-020': {'lib/tools/c.dart': 2},
    });

    test('טבלת כללים עם הפרש מול הבסיס והתראה על גידול', () {
      final md = DesignReport(
        lint: _lint(),
        baseBaseline: base,
        headBaseline: head,
      ).toMarkdown();
      expect(
        md,
        contains('| UIL-017 | fontSize ליטרלי | 2 | 3 | 2 | -1 | 0 | 1/1 |'),
      );
      expect(
        md,
        contains(
          '| UIL-020 (strict) | ריווח מחוץ לסולם | 1 | 1 | 2 | +1 | 0 | 0/0 |',
        ),
      );
      expect(md, contains('ה-baseline גדל ב-1 מופעים'));
    });

    test('בלי baseline של הבסיס אין הפרש, ובלי דוח lint נאמר במפורש', () {
      final md = DesignReport(lint: _lint(), headBaseline: head).toMarkdown();
      expect(md, contains('baseline של הבסיס לא זמין'));
      expect(md, isNot(contains('ה-baseline גדל')));
      expect(
        const DesignReport().toMarkdown(),
        contains('לא הופק דוח ui_lint'),
      );
    });

    test('מודולים לפי חוב, וכללים מועמדים בנפרד', () {
      final md = DesignReport(
        lint: _lint(
          pending: [
            {'rule': 'UIL-034'},
            {'rule': 'UIL-034'},
          ],
        ),
        baseBaseline: base,
        headBaseline: head,
      ).toMarkdown();
      expect(md, contains('| `tools` | 2 | +1 | 0 |'));
      expect(md, contains('| `search` | 2 | -1 | 1 |'));
      expect(md, contains('| UIL-034 | IconButton גולמי | 2 | — |'));
    });

    test('חריגה חדשה מופיעה עם מיקום', () {
      final md = DesignReport(
        lint: _lint(
          fresh: [
            {
              'rule': 'UIL-017',
              'path': 'lib/x.dart',
              'line': 7,
              'snippet': 'fontSize: 13',
            },
          ],
        ),
        headBaseline: head,
      ).toMarkdown();
      expect(md, contains('- `lib/x.dart:7` UIL-017: `fontSize: 13`'));
    });

    test('כשלי responsive ו-golden מופיעים, ובלעדיהם נאמר שלא רצו', () {
      final md = DesignReport(
        responsive: parseResponsiveLines(
          '{"scenario":"דיאלוג","viewport":"390x640","issues":'
          '[{"kind":"overflow","detail":"20px | right"}],"error":null,'
          '"screenshot":"/tmp/shots/a.png"}\n',
        ),
        goldenFiles: ['g/app_card/failures/light_testImage.png'],
        runUrl: 'https://example.test/run/1',
      ).toMarkdown();
      expect(
        md,
        contains('| דיאלוג | 390x640 | overflow | 20px \\| right | `a.png` |'),
      );
      expect(md, contains('artifact `responsive-failures`'));
      expect(md, contains('light_testImage'.replaceAll('_testImage', '')));

      final empty = const DesignReport().toMarkdown();
      expect(empty, contains('לא הופק דוח responsive'));
      expect(empty, contains('אין תיקיית כשלים'));
    });

    test('בלי run-ci הדוח אומר שהבדיקות החוסמות לא רצו', () {
      expect(
        const DesignReport(runCi: false).toMarkdown(),
        contains('הבדיקות החוסמות לא רצו'),
      );
      expect(
        const DesignReport(runCi: true).toMarkdown(),
        isNot(contains('הבדיקות החוסמות לא רצו')),
      );
    });

    test('מצב פלטפורמות: skipped לא נראה כהצלחה, gate ו-changes מוסתרים', () {
      final md = DesignReport(
        needs: {
          'gate': {'result': 'success'},
          'changes': {'result': 'success'},
          'analyze': {'result': 'success'},
          'goldens_windows': {'result': 'skipped'},
          'test': {'result': 'failure'},
        },
      ).toMarkdown();
      expect(
        md,
        contains('| Analyze (ui_lint, analyze, packages) | success |'),
      );
      expect(md, contains('| Goldens (Windows) | skipped (לא רץ) |'));
      expect(md, contains('| Linux test shards | failure |'));
      expect(md, isNot(contains('| gate |')));
    });

    test('שחזור מקומי כולל את הפקודות', () {
      final md = const DesignReport().toMarkdown();
      expect(md, contains('dart tool/ui_lint_cli.dart --check'));
      expect(md, contains('RESPONSIVE_TIER=full'));
      expect(md, contains('Regenerate goldens'));
    });
  });
}
