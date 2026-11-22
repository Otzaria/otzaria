import 'dart:io';

import 'package:test/test.dart';

import '../../tool/ui_lint/ui_lint.dart';

/// קטלוג הכללים ב־`docs/design-system/CI_ENFORCEMENT.md` מול מה שהכלי מדווח:
/// בלי זה המספרים במסמך נשארים מיושנים (בביקורת 17.11: 741 מול 653, 17 נעולים
/// מול 21). המסמך קורא "מצב נבדק אוטומטית" בין שני סימוני HTML.
const _docPath = 'docs/design-system/CI_ENFORCEMENT.md';

final _config = UiLintConfig.load('.');

/// שורות הקטלוג (§3.3): מזהה הכלל → תאים של השורה.
Map<String, List<String>> _catalogRows(String doc) {
  final rows = <String, List<String>>{};
  final start = doc.indexOf('### 3.3');
  final end = doc.indexOf('### 3.4');
  if (start < 0 || end <= start) throw StateError('חסר סעיף 3.3 במסמך');
  for (final line in doc.substring(start, end).split('\n')) {
    final match = RegExp(r'^\| (UIL-\d{3}) \|').firstMatch(line);
    if (match == null) continue;
    final cells = line
        .split(RegExp(r'(?<!\\)\|'))
        .map((c) => c.trim())
        .toList()
        .sublist(1);
    cells.removeLast();
    rows[match.group(1)!] = cells;
  }
  return rows;
}

Map<String, int> _statusBlock(String doc) {
  final block = RegExp(
    r'<!-- ui-lint-status -->\n(.*?)<!-- /ui-lint-status -->',
    dotAll: true,
  ).firstMatch(doc);
  expect(block, isNotNull, reason: 'חסר בלוק "<!-- ui-lint-status -->" במסמך');
  return {
    for (final m in RegExp(
      r'^- ([a-z-]+): (\d+)$',
      multiLine: true,
    ).allMatches(block!.group(1)!))
      m.group(1)!: int.parse(m.group(2)!),
  };
}

void main() {
  // בלי תלות בסוף שורה של המערכת (autocrlf ב־Windows).
  final doc = File(_docPath).readAsStringSync().replaceAll('\r\n', '\n');
  final rows = _catalogRows(doc);
  final baseline = UiLintBaseline.load('.');
  final debtByRule = <String, int>{};
  for (final MapEntry(:key, :value) in baseline.counts.entries) {
    debtByRule.update(
      key.split('|').first,
      (n) => n + value,
      ifAbsent: () => value,
    );
  }

  test('כל כלל בקטלוג חוסם מופיע במסמך, ולא להפך', () {
    final registry = {for (final r in uiLintRules) r.id};
    expect(
      rows.keys.toSet().intersection(registry).length,
      registry.length,
      reason:
          'כללים חסרים בקטלוג של $_docPath: '
          '${registry.difference(rows.keys.toSet()).toList()..sort()}',
    );
    expect(
      rows.keys.toSet().difference(registry),
      isEmpty,
      reason: 'שורה בקטלוג של $_docPath לכלל שלא קיים ב־uiLintRules',
    );
  });

  test('העמודה "baseline" פותחת במספר המופעים האמיתי', () {
    final wrong = <String>[];
    for (final MapEntry(:key, :value) in rows.entries) {
      final cell = value[4];
      final stated = int.tryParse(
        RegExp(r'^\**(\d+)').firstMatch(cell)?.group(1) ?? '',
      );
      final actual = debtByRule[key] ?? 0;
      if (stated != actual) wrong.add('$key: במסמך $stated, בפועל $actual');
    }
    expect(
      wrong,
      isEmpty,
      reason: 'להתחיל את תא ה־baseline במספר הנכון ($_docPath §3.3)',
    );
  });

  test('"strict" בעמודה האחרונה תואם את config.yaml', () {
    final wrong = <String>[];
    for (final MapEntry(:key, :value) in rows.entries) {
      final stated = value.last.contains('strict');
      if (stated != _config.isStrict(key)) {
        wrong.add('$key: במסמך ${stated ? 'נעול' : 'לא נעול'}');
      }
    }
    expect(wrong, isEmpty, reason: 'מצב הנעילה במסמך שונה מ־config.yaml');
  });

  test('בלוק "מצב נבדק אוטומטית" תואם את הכלי', () {
    final stated = _statusBlock(doc);
    final actual = {
      'baseline': baseline.size,
      'rules': uiLintRules.length,
      'strict': _config.strictRules.length,
      'allows': _config.maxAllows.values.fold(0, (a, b) => a + b),
      'path-exclusions': _config.ruleExcludes.values.fold(
        0,
        (a, b) => a + b.length,
      ),
      'pending': uiLintPendingRules.length,
    };
    expect(
      stated,
      actual,
      reason:
          'לעדכן את הבלוק ב־$_docPath. הערכים הנכונים:\n'
          '${actual.entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}',
    );
  });

  test('כל כלל מועמד מתועד במסמך', () {
    for (final rule in uiLintPendingRules) {
      expect(doc, contains(rule.id), reason: '${rule.id} חסר ב־$_docPath');
    }
  });
}
