// ignore_for_file: avoid_print
//
// Design-system summary of a CI run, as Markdown for $GITHUB_STEP_SUMMARY.
//
//   dart tool/ci/design_report.dart \
//     --lint-json=lint.json            # dart tool/ui_lint_cli.dart --format=json
//     --base-baseline=base.json        # baseline.json of the PR base (git show)
//     --head-baseline=tool/ui_lint/baseline.json
//     --responsive=responsive-reports  # file or directory of *.jsonl
//     --goldens-dir=golden-failures    # test/goldens/**/failures/ artifact
//     --needs-json=needs.json          # toJSON(needs) of the workflow
//     --run-ci=true|false              # false: the blocking jobs did not run
//     --run-url=https://github.com/...   # link to the run (artifacts)
//
// Every input is optional. A missing input is reported as "not produced", so
// the summary never claims a clean result for a stage that did not run.
// Dart only, no Flutter: it runs in any job after a checkout.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  String? flag(String name) {
    for (final arg in args) {
      if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
    }
    return null;
  }

  Object? json(String? path) {
    if (path == null || !File(path).existsSync()) return null;
    return jsonDecode(File(path).readAsStringSync());
  }

  final report = DesignReport(
    lint: json(flag('lint-json')) as Map<String, dynamic>?,
    baseBaseline: json(flag('base-baseline')) as Map<String, dynamic>?,
    headBaseline:
        json(flag('head-baseline') ?? 'tool/ui_lint/baseline.json')
            as Map<String, dynamic>?,
    responsive: _readResponsive(flag('responsive')),
    goldenFiles: _listFiles(flag('goldens-dir')),
    needs: json(flag('needs-json')) as Map<String, dynamic>?,
    // An empty value (a gate that produced no output) is "unknown".
    runCi: (flag('run-ci') ?? '').isEmpty ? null : flag('run-ci') == 'true',
    runUrl: flag('run-url'),
  );
  print(report.toMarkdown());
}

List<String>? _listFiles(String? dir) {
  if (dir == null || !Directory(dir).existsSync()) return null;
  return [
    for (final file in Directory(dir).listSync(recursive: true))
      if (file is File) file.path.replaceAll(r'\', '/'),
  ];
}

List<ResponsiveFailure>? _readResponsive(String? path) {
  if (path == null) return null;
  final files = <File>[];
  if (File(path).existsSync()) {
    files.add(File(path));
  } else if (Directory(path).existsSync()) {
    files.addAll(
      Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl')),
    );
  } else {
    return null;
  }
  return [for (final f in files) ...parseResponsiveLines(f.readAsStringSync())];
}

/// One failing scenario x viewport of the responsive harness
/// (`RESPONSIVE_REPORT`, one JSON object per line).
class ResponsiveFailure {
  const ResponsiveFailure({
    required this.scenario,
    required this.viewport,
    required this.issues,
    this.screenshot,
  });

  final String scenario;
  final String viewport;

  /// `(kind, detail)`; an error without issues is `('error', message)`.
  final List<(String, String)> issues;
  final String? screenshot;
}

/// Parses harness JSON lines; a damaged line is skipped, not fatal.
List<ResponsiveFailure> parseResponsiveLines(String text) {
  final failures = <ResponsiveFailure>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    try {
      final map = jsonDecode(line) as Map<String, dynamic>;
      final issues = [
        for (final issue in (map['issues'] as List? ?? const []))
          (
            '${(issue as Map)['kind']}',
            '${issue['detail']}',
          ),
      ];
      final error = map['error'];
      if (issues.isEmpty && error != null) issues.add(('error', '$error'));
      failures.add(
        ResponsiveFailure(
          scenario: '${map['scenario']}',
          viewport: '${map['viewport']}',
          issues: issues,
          screenshot: map['screenshot'] as String?,
        ),
      );
    } on Object {
      continue;
    }
  }
  return failures;
}

/// `n` per rule in a baseline.json (`rules -> path -> [{scope, fp, n}]`).
Map<String, int> baselineByRule(Map<String, dynamic> baseline) => {
  for (final MapEntry(key: rule, value: files)
      in (baseline['rules'] as Map<String, dynamic>).entries)
    rule: _sum(files as Map<String, dynamic>),
};

/// `n` per top-level `lib/` module in a baseline.json.
Map<String, int> baselineByModule(Map<String, dynamic> baseline) {
  final modules = <String, int>{};
  for (final files in (baseline['rules'] as Map<String, dynamic>).values) {
    for (final MapEntry(key: path, value: entries)
        in (files as Map<String, dynamic>).entries) {
      modules.update(
        moduleOfPath(path),
        (n) => n + _count(entries as List),
        ifAbsent: () => _count(entries),
      );
    }
  }
  return modules;
}

int _count(List entries) =>
    entries.fold(0, (sum, e) => sum + ((e as Map)['n'] as int));

int _sum(Map<String, dynamic> files) =>
    files.values.fold(0, (sum, entries) => sum + _count(entries as List));

/// The module of a `lib/...` path (a file directly in `lib/` is `lib`).
String moduleOfPath(String path) {
  final parts = path.split('/');
  return parts.length > 2 && parts.first == 'lib' ? parts[1] : 'lib';
}

/// The test name of a golden failure artifact file
/// (`foo_masterImage.png`, `_testImage`, `_isolatedDiff`, `_maskedDiff`).
Map<String, List<String>> goldenFailuresByTest(List<String> files) {
  final suffix = RegExp(
    r'_(masterImage|testImage|isolatedDiff|maskedDiff)\.png$',
  );
  final byTest = <String, List<String>>{};
  for (final file in files) {
    final match = suffix.firstMatch(file);
    if (match == null) continue;
    final name = file
        .substring(0, match.start)
        .split('/')
        .reversed
        .take(3)
        .toList()
        .reversed
        .join('/');
    byTest.putIfAbsent(name, () => []).add(match.group(1)!);
  }
  return byTest;
}

class DesignReport {
  const DesignReport({
    this.lint,
    this.baseBaseline,
    this.headBaseline,
    this.responsive,
    this.goldenFiles,
    this.needs,
    this.runCi,
    this.runUrl,
  });

  final Map<String, dynamic>? lint;
  final Map<String, dynamic>? baseBaseline;
  final Map<String, dynamic>? headBaseline;
  final List<ResponsiveFailure>? responsive;
  final List<String>? goldenFiles;
  final Map<String, dynamic>? needs;
  final bool? runCi;
  final String? runUrl;

  static const _jobNames = {
    'analyze': 'Analyze (ui_lint, analyze, packages)',
    'test': 'Linux test shards',
    'test_windows': 'Windows tests',
    'goldens_windows': 'Goldens (Windows)',
    'responsive_ui': 'Responsive (full tier, UI changes)',
    'build_windows': 'Build (Windows)',
    'build_linux': 'Build (Linux)',
    'native_linux': 'Native (Linux)',
    'native_macos': 'Native (macOS)',
  };

  String toMarkdown() {
    final out = StringBuffer('# סיכום עיצוב ו-UI\n\n');
    if (runCi == false) {
      out.writeln(
        '> **הבדיקות החוסמות לא רצו:** אין תווית `run-ci`. רצו רק שער ה-lint '
        'וה-guards. גם בדיקות ה-responsive, ה-goldens והבניות מדולגות עד '
        'שמוסיפים את התווית.\n',
      );
    }
    _lintSections(out);
    _responsiveSection(out);
    _goldenSection(out);
    _platformSection(out);
    _reproduceSection(out);
    return out.toString();
  }

  // ── ui_lint ────────────────────────────────────────────────────────────────

  static String _delta(int? base, int head) {
    if (base == null) return '—';
    final d = head - base;
    return d > 0 ? '+$d' : '$d';
  }

  void _lintSections(StringBuffer out) {
    final lint = this.lint;
    if (lint == null) {
      out.writeln(
        '## ui_lint\n\nלא הופק דוח ui_lint (השלב לא רץ או נכשל לפני הדוח).\n',
      );
      return;
    }
    final rules = (lint['rules'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final findings = (lint['findings'] as List).cast<Map<String, dynamic>>();
    final fresh = (lint['new'] as List).cast<Map<String, dynamic>>();
    final allows = (lint['allows'] as List).cast<Map<String, dynamic>>();
    final head = headBaseline == null ? null : baselineByRule(headBaseline!);
    final base = baseBaseline == null ? null : baselineByRule(baseBaseline!);

    int countOf(List<Map<String, dynamic>> list, String id) =>
        list.where((f) => f['rule'] == id).length;

    out
      ..writeln('## 1. ui_lint לפי כלל\n')
      ..writeln(
        base == null
            ? '_baseline של הבסיס לא זמין: עמודת ההפרש ריקה._\n'
            : '_הפרש = baseline ב-head פחות baseline בבסיס. חיובי = חוב גדל._\n',
      )
      ..writeln(
        '| כלל | תיאור | סה"כ | baseline בבסיס | baseline ב-head | הפרש | '
        'חדשות | allow/תקרה |',
      )
      ..writeln('|---|---|---|---|---|---|---|---|');
    var growth = 0;
    for (final rule in rules.where((r) => r['pending'] != true)) {
      final id = rule['id'] as String;
      final headN = head?[id] ?? 0;
      final delta = base == null ? null : headN - (base[id] ?? 0);
      if (delta != null && delta > 0) growth += delta;
      out.writeln(
        '| $id${rule['strict'] == true ? ' (strict)' : ''} | ${rule['title']} | '
        '${countOf(findings, id)} | ${base == null ? '—' : base[id] ?? 0} | '
        '$headN | ${_delta(base == null ? null : (base[id] ?? 0), headN)} | '
        '${countOf(fresh, id)} | ${countOf(allows, id)}/${rule['allowCap']} |',
      );
    }
    out.writeln();
    if (growth > 0) {
      out.writeln(
        '**ה-baseline גדל ב-$growth מופעים מול הבסיס.** הגדלה דורשת את '
        'התווית `ui-baseline` של המתחזק.\n',
      );
    }
    if (fresh.isNotEmpty) {
      out.writeln('### חריגות חדשות (לא ב-baseline)\n');
      for (final f in fresh.take(20)) {
        out.writeln(
          '- `${f['path']}:${f['line']}` ${f['rule']}: `${f['snippet']}`',
        );
      }
      if (fresh.length > 20) out.writeln('- ... ועוד ${fresh.length - 20}');
      out.writeln();
    }

    final pending = rules.where((r) => r['pending'] == true).toList();
    final pendingFindings = (lint['pending'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (pending.isNotEmpty) {
      out
        ..writeln('### כללים מועמדים (דוח בלבד, לא חוסמים)\n')
        ..writeln('| כלל | תיאור | התאמות | מתאחד עם |')
        ..writeln('|---|---|---|---|');
      for (final rule in pending) {
        out.writeln(
          '| ${rule['id']} | ${rule['title']} | '
          '${countOf(pendingFindings, rule['id'] as String)} | '
          '${rule['extendsRule'] ?? '—'} |',
        );
      }
      out.writeln();
    }

    // Modules with debt.
    final headModules = headBaseline == null
        ? <String, int>{}
        : baselineByModule(headBaseline!);
    final baseModules = baseBaseline == null
        ? null
        : baselineByModule(baseBaseline!);
    final allowByModule = <String, int>{};
    for (final allow in allows) {
      allowByModule.update(
        moduleOfPath(allow['path'] as String),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final modules = {...headModules.keys, ...allowByModule.keys}.toList()
      ..sort((a, b) {
        final byDebt =
            ((headModules[b] ?? 0) + (allowByModule[b] ?? 0)) -
            ((headModules[a] ?? 0) + (allowByModule[a] ?? 0));
        return byDebt != 0 ? byDebt : a.compareTo(b);
      });
    out
      ..writeln('## 2. מודולים עם חוב (10 המובילים)\n')
      ..writeln('| מודול | baseline | הפרש מול הבסיס | allow |')
      ..writeln('|---|---|---|---|');
    for (final module in modules.take(10)) {
      out.writeln(
        '| `$module` | ${headModules[module] ?? 0} | '
        '${_delta(baseModules == null ? null : (baseModules[module] ?? 0), headModules[module] ?? 0)} | '
        '${allowByModule[module] ?? 0} |',
      );
    }
    out.writeln();
  }

  // ── responsive ─────────────────────────────────────────────────────────────

  void _responsiveSection(StringBuffer out) {
    out.writeln('## 3. כשלי responsive\n');
    final failures = responsive;
    if (failures == null) {
      out.writeln('לא הופק דוח responsive (השכבה לא רצה, או שלא נשמר קובץ).\n');
      return;
    }
    if (failures.isEmpty) {
      out.writeln('אין כשלים בדוח.\n');
      return;
    }
    out
      ..writeln('${failures.length} תרחישים נכשלו.\n')
      ..writeln('| תרחיש | חלון | סוג | פרט | צילום |')
      ..writeln('|---|---|---|---|---|');
    for (final failure in failures) {
      final shot = failure.screenshot == null
          ? '—'
          : '`${failure.screenshot!.split('/').last}`';
      final issues = failure.issues.isEmpty
          ? [('—', '—')]
          : failure.issues.take(3).toList();
      for (final (kind, detail) in issues) {
        out.writeln(
          '| ${_cell(failure.scenario)} | ${failure.viewport} | $kind | '
          '${_cell(detail, 110)} | $shot |',
        );
      }
    }
    out.writeln();
    if (runUrl != null) {
      out.writeln(
        'הצילומים נמצאים ב-artifact `responsive-failures` בתחתית [עמוד '
        'הריצה]($runUrl).\n',
      );
    }
  }

  static String _cell(String text, [int max = 80]) {
    final flat = text.replaceAll('|', r'\|').replaceAll(RegExp(r'\s+'), ' ');
    return flat.length > max ? '${flat.substring(0, max - 3)}...' : flat;
  }

  // ── goldens ────────────────────────────────────────────────────────────────

  void _goldenSection(StringBuffer out) {
    out.writeln('## 4. כשלי golden\n');
    final files = goldenFiles;
    if (files == null) {
      out.writeln(
        'אין תיקיית כשלים: ה-goldens לא רצו, או שעברו '
        '(ה-artifact `golden-failures` נוצר רק בכשל).\n',
      );
      return;
    }
    final byTest = goldenFailuresByTest(files);
    if (byTest.isEmpty) {
      out.writeln('אין תמונות כשל.\n');
      return;
    }
    out
      ..writeln('| בדיקה | תמונות |')
      ..writeln('|---|---|');
    for (final MapEntry(:key, :value) in byTest.entries) {
      out.writeln('| `$key` | ${(value..sort()).join(', ')} |');
    }
    out.writeln(
      '\nהתמונות ב-artifact `golden-failures`'
      '${runUrl == null ? '' : ' ([עמוד הריצה]($runUrl))'}. שינוי מכוון: '
      'להריץ את `Regenerate goldens` ולבקש את התווית `goldens-approved`.\n',
    );
  }

  // ── platforms ──────────────────────────────────────────────────────────────

  void _platformSection(StringBuffer out) {
    out.writeln('## 5. מצב לפי פלטפורמה\n');
    final needs = this.needs;
    if (needs == null) {
      out.writeln('מצב ה-jobs לא הועבר לדוח.\n');
      return;
    }
    out
      ..writeln('| Job | תוצאה |')
      ..writeln('|---|---|');
    for (final MapEntry(:key, :value) in needs.entries) {
      if (key == 'gate' || key == 'changes') continue;
      final result = (value as Map)['result'];
      out.writeln(
        '| ${_jobNames[key] ?? key} | ${result == 'skipped' ? 'skipped (לא רץ)' : result} |',
      );
    }
    out.writeln(
      '\n`skipped` אינו הצלחה: ללא התווית `run-ci` כל ה-jobs שמעל מדולגים '
      'חוץ מ-Analyze.\n',
    );
  }

  // ── reproduce ──────────────────────────────────────────────────────────────

  void _reproduceSection(StringBuffer out) {
    out.writeln('''
## 6. שחזור מקומי

```
dart tool/ui_lint_cli.dart --format=md          # הדוח המלא
dart tool/ui_lint_cli.dart --check              # השער החוסם
flutter test test/design_system/ui_lint_test.dart
flutter test test/design_system/responsive/ --dart-define=RESPONSIVE_TIER=full
flutter test test/goldens/<משפחה>               # Windows בלבד, Flutter 3.47.7
```

בלי Windows: להריץ את workflow ‏`Regenerate goldens` ולהוריד את ה-artifact.''');
  }
}
