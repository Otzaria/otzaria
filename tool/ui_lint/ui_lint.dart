// מנוע ui_lint (docs/design-system/CI_ENFORCEMENT.md): כללי התקן על lib/ ב-AST.
// לא מייבא את package:otzaria, כדי שהבדיקה והדוח ירוצו בלי Flutter.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'ast_helpers.dart';
import 'rules/rules.dart';

export 'rules/rules.dart' show uiLintRules;

const configRelativePath = 'tool/ui_lint/config.yaml';
const baselineRelativePath = 'tool/ui_lint/baseline.json';

/// כללים עד השלב הזה חוסמים חריגות חדשות ב-`test/design_system/ui_lint_test.dart`
/// (CI_ENFORCEMENT.md §6, רמה 3): גם כללי הטוקנים. שלב 4 בדוח בלבד.
const blockingStage = 3;

/// כלל אחד של התקן.
abstract class UiLintRule {
  const UiLintRule();

  /// `UIL-xxx`, לפי הקטלוג ב-CI_ENFORCEMENT.md.
  String get id;

  /// מה הכלל אוסר.
  String get title;

  /// במה להשתמש במקום, והסעיף בתקן.
  String get hint;

  /// השלב בקטלוג (CI_ENFORCEMENT.md §3.3). עד [blockingStage] הכלל חוסם.
  int get stage;

  bool get isBlocking => stage <= blockingStage;

  void check(UiLintFile file);
}

/// קובץ אחד בזמן הבדיקה: ה-AST שלו וערוץ הדיווח.
class UiLintFile {
  UiLintFile._(
    this.root,
    this.path,
    this.unit,
    this.lineInfo,
    this._source,
    this._findings,
  );

  /// שורש המאגר, לכלל שצריך לקרוא קובץ נוסף (רשימה רשומה).
  final String root;

  /// נתיב יחסי לשורש המאגר, עם `/`.
  final String path;
  final CompilationUnit unit;
  final LineInfo lineInfo;
  final String _source;
  final List<UiLintFinding> _findings;

  /// [identity] מחליף את קוד הצומת בטביעה של ה-baseline. כלל שמדווח על
  /// בנאי עם תוכן גדול (דיאלוג שלם) מעביר את שם הבנאי, כדי ששינוי בתוכן לא
  /// יהפוך חריגה ישנה לחדשה.
  void report(UiLintRule rule, AstNode node, {String? identity}) {
    final location = lineInfo.getLocation(node.offset);
    _findings.add(
      UiLintFinding(
        rule: rule.id,
        path: path,
        line: location.lineNumber,
        column: location.columnNumber,
        snippet: _snippet(_source.substring(node.offset, node.end)),
        scope: scopeOf(node),
        fingerprint: _fingerprint(identity ?? node.toSource()),
      ),
    );
  }
}

class UiLintFinding {
  const UiLintFinding({
    required this.rule,
    required this.path,
    required this.line,
    required this.column,
    required this.snippet,
    required this.scope,
    required this.fingerprint,
  });

  final String rule;
  final String path;
  final int line;
  final int column;
  final String snippet;
  final String scope;
  final String fingerprint;

  /// מפתח ה-baseline: בלי מספרי שורות, כדי שהזזת קוד ופורמט לא ישברו אותו.
  String get baselineKey => '$rule|$path|$scope|$fingerprint';

  Map<String, Object> toJson() => {
    'rule': rule,
    'path': path,
    'line': line,
    'column': column,
    'scope': scope,
    'fp': fingerprint,
    'snippet': snippet,
  };

  @override
  String toString() => '$path:$line: $rule $snippet';
}

/// הערת `// ui-lint: allow UIL-xxx — נימוק` תקינה.
class UiLintAllow {
  UiLintAllow(this.path, this.line, this.rule, this.reason);

  final String path;

  /// השורה של ההערה עצמה.
  final int line;
  final String rule;
  final String reason;
  bool used = false;
}

/// הערת allow פגומה או מיותרת, שגיאת תחביר או שגיאת קונפיגורציה.
class UiLintProblem {
  const UiLintProblem(this.path, this.line, this.message);

  final String path;
  final int line;
  final String message;

  @override
  String toString() => '$path:$line: $message';
}

class UiLintResult {
  UiLintResult(this.findings, this.allows, this.problems);

  final List<UiLintFinding> findings;
  final List<UiLintAllow> allows;
  final List<UiLintProblem> problems;
}

// ── קונפיגורציה ──────────────────────────────────────────────────────────────

class PathExclusion {
  PathExclusion(this.pattern, this.reason) : _regex = _globToRegExp(pattern);

  final String pattern;
  final String reason;
  final RegExp _regex;

  bool matches(String path) => _regex.hasMatch(path);
}

RegExp _globToRegExp(String glob) {
  final buffer = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final char = glob[i];
    if (char == '*') {
      if (i + 1 < glob.length && glob[i + 1] == '*') {
        i++;
        // `**/` תואם גם אפס תיקיות.
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          i++;
          buffer.write('(?:.*/)?');
        } else {
          buffer.write('.*');
        }
      } else {
        buffer.write('[^/]*');
      }
    } else {
      buffer.write(RegExp.escape(char));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

/// החרגות לפי נתיב, כל אחת עם נימוק. החרגות לפי הקשר תחבירי (CustomPainter,
/// `pw.*`, `BoxShadow`) כתובות בכללים עצמם.
class UiLintConfig {
  UiLintConfig({
    this.globalExcludes = const [],
    this.ruleExcludes = const {},
    this.strictRules = const {},
  });

  final List<PathExclusion> globalExcludes;
  final Map<String, List<PathExclusion>> ruleExcludes;

  /// כללים נעולים (`strict: true`, CI_ENFORCEMENT.md §6 רמה 4): החוב שלהם
  /// נגמר, כל חריגה בהם חוסמת בלי קשר לשלב, ו־`--allow-growth` לא מוסיף להם
  /// רשומות baseline. חריג בודד עדיין אפשרי בהערת allow עם נימוק.
  final Set<String> strictRules;

  bool isStrict(String rule) => strictRules.contains(rule);

  bool excludesFile(String path) => globalExcludes.any((e) => e.matches(path));

  bool excludes(String rule, String path) =>
      ruleExcludes[rule]?.any((e) => e.matches(path)) ?? false;

  static UiLintConfig parse(String yamlSource) {
    final doc = loadYaml(yamlSource);
    if (doc is! YamlMap) throw const FormatException('config.yaml ריק');
    List<PathExclusion> exclusions(Object? list, String where) {
      if (list == null) return const [];
      if (list is! YamlList) {
        throw FormatException('$where: exclude חייב להיות רשימה');
      }
      return [
        for (final entry in list)
          if (entry is YamlMap &&
              entry['path'] is String &&
              (entry['reason'] as Object?) is String &&
              (entry['reason'] as String).trim().isNotEmpty)
            PathExclusion(entry['path'] as String, entry['reason'] as String)
          else
            throw FormatException('$where: לכל החרגה נדרשים path ו-reason'),
      ];
    }

    final rules = <String, List<PathExclusion>>{};
    final strict = <String>{};
    final rulesNode = doc['rules'];
    if (rulesNode is YamlMap) {
      for (final MapEntry(:key, :value) in rulesNode.entries) {
        rules[key as String] = exclusions(
          value is YamlMap ? value['exclude'] : null,
          key,
        );
        final flag = value is YamlMap ? value['strict'] : null;
        if (flag != null && flag is! bool) {
          throw FormatException('$key: strict חייב להיות true או false');
        }
        if (flag == true) strict.add(key);
      }
    }
    return UiLintConfig(
      globalExcludes: exclusions(doc['exclude'], 'exclude'),
      ruleExcludes: rules,
      strictRules: strict,
    );
  }

  static UiLintConfig load(String root) =>
      parse(File(p.join(root, configRelativePath)).readAsStringSync());
}

// ── הרצה ─────────────────────────────────────────────────────────────────────

final _allowComment = RegExp(r'^\s*//\s*ui-lint\s*:\s*allow\b(.*)$');
final _allowBody = RegExp(r'^\s+(UIL-\d{3})\s*(?:—|--)\s*(.*)$');
const _minReasonLength = 12;

/// בודק מקור אחד כאילו הוא נמצא ב-[path] (יחסי לשורש המאגר).
UiLintResult lintSource(
  String source,
  String path, {
  required UiLintConfig config,
  List<UiLintRule> rules = uiLintRules,
  String root = '.',
}) {
  final findings = <UiLintFinding>[];
  final problems = <UiLintProblem>[];
  if (config.excludesFile(path)) return UiLintResult(findings, [], problems);

  final parsed = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  );
  for (final error in parsed.errors) {
    problems.add(
      UiLintProblem(
        path,
        parsed.lineInfo.getLocation(error.offset).lineNumber,
        'שגיאת תחביר: ${error.message}',
      ),
    );
  }
  final file = UiLintFile._(
    root,
    path,
    parsed.unit,
    parsed.lineInfo,
    source,
    findings,
  );
  final ruleIds = {for (final rule in rules) rule.id};
  for (final rule in rules) {
    if (!config.excludes(rule.id, path)) rule.check(file);
  }

  final allows = _parseAllows(source, path, ruleIds, problems);
  final targets = {
    for (final allow in allows) allow: _targetLine(source, allow.line),
  };
  findings.removeWhere((finding) {
    for (final allow in allows) {
      if (allow.rule == finding.rule && targets[allow] == finding.line) {
        allow.used = true;
        return true;
      }
    }
    return false;
  });
  for (final allow in allows) {
    if (!allow.used) {
      problems.add(
        UiLintProblem(
          path,
          allow.line,
          'הערת allow ל-${allow.rule} לא השתיקה דבר: הסר אותה',
        ),
      );
    }
  }
  findings.sort(
    (a, b) => a.line != b.line ? a.line - b.line : a.column - b.column,
  );
  return UiLintResult(findings, allows, problems);
}

/// בודק את כל קובצי ה-Dart תחת `lib/` של [root].
UiLintResult runUiLint(
  String root, {
  UiLintConfig? config,
  List<UiLintRule> rules = uiLintRules,
}) {
  final effectiveConfig = config ?? UiLintConfig.load(root);
  final files =
      Directory(p.join(root, 'lib'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final findings = <UiLintFinding>[];
  final allows = <UiLintAllow>[];
  final problems = <UiLintProblem>[];
  for (final file in files) {
    final relative = p.relative(file.path, from: root).replaceAll(r'\', '/');
    final result = lintSource(
      file.readAsStringSync(),
      relative,
      config: effectiveConfig,
      rules: rules,
      root: root,
    );
    findings.addAll(result.findings);
    allows.addAll(result.allows);
    problems.addAll(result.problems);
  }
  return UiLintResult(findings, allows, problems);
}

List<UiLintAllow> _parseAllows(
  String source,
  String path,
  Set<String> ruleIds,
  List<UiLintProblem> problems,
) {
  final allows = <UiLintAllow>[];
  final lines = const LineSplitter().convert(source);
  for (var i = 0; i < lines.length; i++) {
    final comment = _allowComment.firstMatch(lines[i]);
    if (comment == null) continue;
    final line = i + 1;
    final body = _allowBody.firstMatch(comment.group(1)!);
    if (body == null) {
      problems.add(
        UiLintProblem(
          path,
          line,
          'הערת allow חייבת להיות "// ui-lint: allow UIL-xxx — נימוק": כלל אחד, '
          'בלי all ובלי רשימה',
        ),
      );
      continue;
    }
    final rule = body.group(1)!;
    final reason = body.group(2)!.trim();
    if (!ruleIds.contains(rule)) {
      problems.add(UiLintProblem(path, line, 'הערת allow לכלל לא מוכר: $rule'));
    } else if (reason.length < _minReasonLength) {
      problems.add(
        UiLintProblem(
          path,
          line,
          'הערת allow ל-$rule בלי נימוק (לפחות $_minReasonLength תווים)',
        ),
      );
    } else {
      allows.add(UiLintAllow(path, line, rule, reason));
    }
  }
  return allows;
}

/// השורה שההערה בשורה [commentLine] חלה עליה: שורת הקוד הבאה.
int _targetLine(String source, int commentLine) {
  final lines = const LineSplitter().convert(source);
  for (var i = commentLine; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.isNotEmpty && !trimmed.startsWith('//')) return i + 1;
  }
  return -1;
}

String _snippet(String source) {
  final firstLine = source.split('\n').first.trim();
  return firstLine.length > 120
      ? '${firstLine.substring(0, 117)}...'
      : firstLine;
}

/// FNV-1a של הקוד בלי רווחים: יציב מול פורמט, משתנה כשהביטוי עצמו משתנה.
String _fingerprint(String source) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(source.replaceAll(RegExp(r'\s+'), ''))) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ── baseline ─────────────────────────────────────────────────────────────────

/// חוב קיים שאינו מכשיל: כמה מופעים מותרים לכל מפתח.
class UiLintBaseline {
  UiLintBaseline(Map<String, int> counts) : counts = Map.unmodifiable(counts);

  final Map<String, int> counts;

  int get size => counts.values.fold(0, (sum, n) => sum + n);

  factory UiLintBaseline.fromFindings(Iterable<UiLintFinding> findings) {
    final counts = <String, int>{};
    for (final finding in findings) {
      counts.update(finding.baselineKey, (n) => n + 1, ifAbsent: () => 1);
    }
    return UiLintBaseline(counts);
  }

  factory UiLintBaseline.parse(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    if (decoded['version'] != 1) {
      throw const FormatException('גרסת baseline לא נתמכת');
    }
    final counts = <String, int>{};
    final rules = decoded['rules'] as Map<String, dynamic>;
    for (final MapEntry(key: rule, value: files) in rules.entries) {
      for (final MapEntry(key: path, value: entries)
          in (files as Map<String, dynamic>).entries) {
        for (final entry in (entries as List).cast<Map<String, dynamic>>()) {
          counts['$rule|$path|${entry['scope']}|${entry['fp']}'] =
              entry['n'] as int;
        }
      }
    }
    return UiLintBaseline(counts);
  }

  static UiLintBaseline load(String root) {
    final file = File(p.join(root, baselineRelativePath));
    return file.existsSync()
        ? UiLintBaseline.parse(file.readAsStringSync())
        : UiLintBaseline(const {});
  }

  /// JSON ממוין, רשומה בשורה, כדי שה-diff ב-PR יראה רק את מה שהשתנה.
  String toJsonString() {
    final rules = <String, Map<String, List<String>>>{};
    for (final key in counts.keys.toList()..sort()) {
      final [rule, path, scope, fp] = key.split('|');
      final entry = jsonEncode({'scope': scope, 'fp': fp, 'n': counts[key]});
      rules.putIfAbsent(rule, () => {}).putIfAbsent(path, () => []).add(entry);
    }
    final out = StringBuffer('{\n  "version": 1,\n  "rules": {');
    var firstRule = true;
    for (final MapEntry(key: rule, value: files) in rules.entries) {
      out.write('${firstRule ? '' : ','}\n    ${jsonEncode(rule)}: {');
      firstRule = false;
      var firstFile = true;
      for (final MapEntry(key: path, value: entries) in files.entries) {
        out
          ..write('${firstFile ? '' : ','}\n      ${jsonEncode(path)}: [\n')
          ..write(entries.map((e) => '        $e').join(',\n'))
          ..write('\n      ]');
        firstFile = false;
      }
      out.write('\n    }');
    }
    out.write('\n  }\n}\n');
    return out.toString();
  }

  BaselineComparison compare(List<UiLintFinding> findings) {
    final seen = <String, int>{};
    final newFindings = <UiLintFinding>[];
    for (final finding in findings) {
      final key = finding.baselineKey;
      final n = seen.update(key, (n) => n + 1, ifAbsent: () => 1);
      if (n > (counts[key] ?? 0)) newFindings.add(finding);
    }
    final dead = <String, int>{
      for (final MapEntry(:key, :value) in counts.entries)
        if ((seen[key] ?? 0) < value) key: value - (seen[key] ?? 0),
    };
    return BaselineComparison(newFindings, dead);
  }

  /// ה-baseline אחרי ריצה: רק מתכווץ, אלא אם [allowGrowth]. לכלל ב־
  /// [strictRules] לא נכתבת רשומה גם עם [allowGrowth].
  UiLintBaseline updated(
    List<UiLintFinding> findings, {
    bool allowGrowth = false,
    Set<String> strictRules = const {},
  }) {
    final actual = UiLintBaseline.fromFindings(
      findings.where((f) => !strictRules.contains(f.rule)),
    ).counts;
    if (allowGrowth) return UiLintBaseline(actual);
    return UiLintBaseline({
      for (final MapEntry(:key, :value) in counts.entries)
        if ((actual[key] ?? 0) > 0)
          key: value < actual[key]! ? value : actual[key]!,
    });
  }
}

class BaselineComparison {
  BaselineComparison(this.newFindings, this.dead);

  /// חריגות שאינן ב-baseline.
  final List<UiLintFinding> newFindings;

  /// רשומות baseline (מפתח → כמות) שכבר לא מנוצלות.
  final Map<String, int> dead;
}
