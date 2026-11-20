// ignore_for_file: avoid_print
//
// דוח ui_lint על lib/ ועל חבילת תפריט ההקשר, מול tool/ui_lint/baseline.json.
//
//   dart tool/ui_lint_cli.dart [--format=md|github|json|modules]
//   dart tool/ui_lint_cli.dart --check
//   dart tool/ui_lint_cli.dart --update-baseline [--allow-growth]
//
// --check: שער חוסם ל־CI. יציאה 1 כשיש חריגה חדשה בכלל חוסם או נעול, baseline
// מת, הערת allow פגומה או חריגה מ־max_allows; לא כותב קבצים.
// --update-baseline רק מוחק רשומות שתוקנו; הוספה דורשת --allow-growth.
// כלל נעול (strict: true ב־config.yaml) לא מקבל רשומות גם עם --allow-growth.
// github: טבלה ל-$GITHUB_STEP_SUMMARY ו-annotations לחריגות החדשות בלבד.
// modules: מצב לפי מודול (תיקייה ראשית ב־lib), נגזר מה־baseline ומה־allow.
// github מוסיף גם אותה ל־$GITHUB_STEP_SUMMARY.
// בלי --check זה מצב דוח: היציאה היא 0 גם כשיש חריגות.
// כללים מועמדים (uiLintPendingRules) מדווחים כמספרים בלבד ואינם חוסמים.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ui_lint/ui_lint.dart';

const _maxAnnotations = 10;

void main(List<String> args) {
  var format = 'md';
  var update = false;
  var allowGrowth = false;
  var check = false;
  for (final arg in args) {
    if (arg.startsWith('--format=')) {
      format = arg.substring('--format='.length);
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (arg == '--allow-growth') {
      allowGrowth = true;
    } else if (arg == '--check') {
      check = true;
    } else {
      stderr.writeln('ארגומנט לא מוכר: $arg');
      exit(64);
    }
  }
  if (!{'md', 'github', 'json', 'modules'}.contains(format)) {
    stderr.writeln('--format חייב להיות md, github, json או modules');
    exit(64);
  }
  if (check && (update || allowGrowth)) {
    stderr.writeln(
      '--check לא כותב קבצים: אי־אפשר לשלב אותו עם --update-baseline',
    );
    exit(64);
  }

  final root = Directory.current.path;
  final config = UiLintConfig.load(root);
  final pendingIds = {for (final rule in uiLintPendingRules) rule.id};
  final full = runUiLint(
    root,
    config: config,
    rules: [...uiLintRules, ...uiLintPendingRules],
  );
  final pending = [
    for (final f in full.findings)
      if (pendingIds.contains(f.rule)) f,
  ];
  final result = UiLintResult(
    [
      for (final f in full.findings)
        if (!pendingIds.contains(f.rule)) f,
    ],
    [
      for (final a in full.allows)
        if (!pendingIds.contains(a.rule)) a,
    ],
    full.problems,
  );
  final baseline = UiLintBaseline.load(root);

  if (update) {
    final next = baseline.updated(
      result.findings,
      allowGrowth: allowGrowth,
      strictRules: config.strictRules,
    );
    File(p.join(root, baselineRelativePath)).writeAsStringSync(
      next.toJsonString(),
    );
    print('baseline: ${baseline.size} → ${next.size} מופעים');
    final locked = {
      for (final f in result.findings)
        if (config.isStrict(f.rule)) f.rule,
    };
    if (locked.isNotEmpty) {
      print(
        'כללים נעולים עם חריגות, שלא נכנסו ל-baseline: '
        '${(locked.toList()..sort()).join(', ')}',
      );
    }
    return;
  }

  final comparison = baseline.compare(result.findings);
  if (check) {
    exit(_check(result, comparison, config));
  }
  final modules = moduleStatusMarkdown(
    moduleStatuses(baseline, result.allows, _libModules(root)),
  );
  switch (format) {
    case 'json':
      print(_json(result, comparison, pending, config));
    case 'modules':
      print(modules);
    case 'github':
      final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
      final markdown = [
        _markdown(result, comparison, config, pending),
        modules,
      ].join('\n');
      if (summary == null) {
        print(markdown);
      } else {
        File(summary).writeAsStringSync(markdown, mode: FileMode.append);
      }
      for (final finding in comparison.newFindings.take(_maxAnnotations)) {
        final rule = _rule(finding.rule);
        print(
          '::warning file=${finding.path},line=${finding.line},'
          'title=${finding.rule}::${rule.title}. במקום: ${rule.hint}',
        );
      }
      for (final problem in result.problems.take(_maxAnnotations)) {
        print(
          '::warning file=${problem.path},line=${problem.line},'
          'title=ui-lint::${problem.message}',
        );
      }
    default:
      print(_markdown(result, comparison, config, pending));
  }
}

/// מצב `--check`: מדפיס כל כשל ומחזיר את קוד היציאה.
int _check(
  UiLintResult result,
  BaselineComparison comparison,
  UiLintConfig config,
) {
  final failures = gateFailures(result, comparison, config);
  final annotate = Platform.environment['GITHUB_ACTIONS'] == 'true';
  for (final failure in failures) {
    stderr.writeln(failure.message);
    if (annotate) {
      final location = failure.path == null
          ? ''
          : ' file=${failure.path},line=${failure.line}';
      print('::error$location title=ui-lint::${failure.message}');
    }
  }
  if (failures.isEmpty) {
    print(
      'ui_lint --check: תקין (baseline ${comparison.newFindings.length} חדשות)',
    );
    return 0;
  }
  stderr.writeln('ui_lint --check: ${failures.length} כשלים');
  return 1;
}

UiLintRule _rule(String id) => uiLintRules.firstWhere((r) => r.id == id);

/// כל התיקיות הראשיות תחת lib, והחבילות הנסרקות.
List<String> _libModules(String root) => [
  for (final entity in Directory(p.join(root, 'lib')).listSync())
    if (entity is Directory) p.basename(entity.path),
  for (final dir in uiLintScanDirs)
    if (dir.startsWith('packages/')) dir.split('/')[1],
];

String _markdown(
  UiLintResult result,
  BaselineComparison comparison,
  UiLintConfig config,
  List<UiLintFinding> pending,
) {
  final buffer = StringBuffer('## ui_lint (מצב דוח)\n\n')
    ..writeln('| כלל | תיאור | סה"כ | ב-baseline | חדשות | allow/תקרה |')
    ..writeln('|---|---|---|---|---|---|');
  for (final rule in uiLintRules) {
    final total = result.findings.where((f) => f.rule == rule.id).length;
    final fresh = comparison.newFindings.where((f) => f.rule == rule.id).length;
    final allows = result.allows.where((a) => a.rule == rule.id).length;
    buffer.writeln(
      '| ${rule.id}${config.isStrict(rule.id) ? ' (strict)' : ''} | '
      '${rule.title} | $total | ${total - fresh} | $fresh | '
      '$allows/${config.maxAllowsFor(rule.id)} |',
    );
  }
  if (pending.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('### כללים מועמדים (דוח בלבד, לא חוסמים)')
      ..writeln()
      ..writeln('| כלל | תיאור | התאמות | מתאחד עם |')
      ..writeln('|---|---|---|---|');
    for (final rule in uiLintPendingRules) {
      final count = pending.where((f) => f.rule == rule.id).length;
      buffer.writeln(
        '| ${rule.id} | ${rule.title} | $count | ${rule.extendsRule ?? '—'} |',
      );
    }
  }
  if (comparison.newFindings.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('### חריגות חדשות (לא ב-baseline)')
      ..writeln();
    for (final finding in comparison.newFindings) {
      buffer.writeln(
        '- `${finding.path}:${finding.line}` ${finding.rule}: '
        '`${finding.snippet}` — במקום: ${_rule(finding.rule).hint}',
      );
    }
  }
  if (comparison.dead.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln(
        '### baseline מת (${comparison.dead.length} רשומות) — '
        'הרץ `dart tool/ui_lint_cli.dart --update-baseline`',
      );
  }
  if (result.problems.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('### בעיות')
      ..writeln();
    for (final problem in result.problems) {
      buffer.writeln('- `${problem.path}:${problem.line}` ${problem.message}');
    }
  }
  final allows = result.allows;
  if (allows.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('### חריגים מתועדים (allow)')
      ..writeln();
    for (final allow in allows) {
      buffer.writeln(
        '- `${allow.path}:${allow.line}` ${allow.rule}: ${allow.reason}',
      );
    }
  }
  return buffer.toString();
}

String _json(
  UiLintResult result,
  BaselineComparison comparison,
  List<UiLintFinding> pending,
  UiLintConfig config,
) => const JsonEncoder.withIndent('  ').convert({
  'rules': [
    for (final rule in uiLintRules)
      {
        'id': rule.id,
        'title': rule.title,
        'stage': rule.stage,
        'strict': config.isStrict(rule.id),
        'pending': false,
        'allowCap': config.maxAllowsFor(rule.id),
      },
    for (final rule in uiLintPendingRules)
      {
        'id': rule.id,
        'title': rule.title,
        'stage': rule.stage,
        'pending': true,
        'extendsRule': rule.extendsRule,
      },
  ],
  'findings': [for (final f in result.findings) f.toJson()],
  'pending': [for (final f in pending) f.toJson()],
  'new': [for (final f in comparison.newFindings) f.toJson()],
  'dead_baseline': comparison.dead,
  'problems': [
    for (final problem in result.problems)
      {
        'path': problem.path,
        'line': problem.line,
        'message': problem.message,
      },
  ],
  'allows': [
    for (final allow in result.allows)
      {
        'path': allow.path,
        'line': allow.line,
        'rule': allow.rule,
        'reason': allow.reason,
      },
  ],
});
