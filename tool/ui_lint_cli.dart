// ignore_for_file: avoid_print
//
// דוח ui_lint על lib/, מול tool/ui_lint/baseline.json.
//
//   dart tool/ui_lint_cli.dart [--format=md|github|json]
//   dart tool/ui_lint_cli.dart --update-baseline [--allow-growth]
//
// --update-baseline רק מוחק רשומות שתוקנו; הוספה דורשת --allow-growth.
// כלל נעול (strict: true ב־config.yaml) לא מקבל רשומות גם עם --allow-growth.
// github: טבלה ל-$GITHUB_STEP_SUMMARY ו-annotations לחריגות החדשות בלבד.
// מצב דוח: היציאה היא 0 גם כשיש חריגות.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ui_lint/ui_lint.dart';

const _maxAnnotations = 10;

void main(List<String> args) {
  var format = 'md';
  var update = false;
  var allowGrowth = false;
  for (final arg in args) {
    if (arg.startsWith('--format=')) {
      format = arg.substring('--format='.length);
    } else if (arg == '--update-baseline') {
      update = true;
    } else if (arg == '--allow-growth') {
      allowGrowth = true;
    } else {
      stderr.writeln('ארגומנט לא מוכר: $arg');
      exit(64);
    }
  }
  if (!{'md', 'github', 'json'}.contains(format)) {
    stderr.writeln('--format חייב להיות md, github או json');
    exit(64);
  }

  final root = Directory.current.path;
  final config = UiLintConfig.load(root);
  final result = runUiLint(root, config: config);
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
  switch (format) {
    case 'json':
      print(_json(result, comparison));
    case 'github':
      final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
      final markdown = _markdown(result, comparison, config);
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
      print(_markdown(result, comparison, config));
  }
}

UiLintRule _rule(String id) => uiLintRules.firstWhere((r) => r.id == id);

String _markdown(
  UiLintResult result,
  BaselineComparison comparison,
  UiLintConfig config,
) {
  final buffer = StringBuffer('## ui_lint (מצב דוח)\n\n')
    ..writeln('| כלל | תיאור | סה"כ | ב-baseline | חדשות | allow |')
    ..writeln('|---|---|---|---|---|---|');
  for (final rule in uiLintRules) {
    final total = result.findings.where((f) => f.rule == rule.id).length;
    final fresh = comparison.newFindings.where((f) => f.rule == rule.id).length;
    final allows = result.allows.where((a) => a.rule == rule.id).length;
    buffer.writeln(
      '| ${rule.id}${config.isStrict(rule.id) ? ' (strict)' : ''} | '
      '${rule.title} | $total | ${total - fresh} | $fresh | $allows |',
    );
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

String _json(UiLintResult result, BaselineComparison comparison) =>
    const JsonEncoder.withIndent('  ').convert({
      'findings': [for (final f in result.findings) f.toJson()],
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
