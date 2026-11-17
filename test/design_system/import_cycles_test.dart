import 'dart:io';

import 'package:test/test.dart';

/// תיקיות של שכבת התשתית: בתוך כל אחת אין מחזור ייבוא, כדי שקובץ אחד בה
/// ייטען בלי לגרור את כולה (CYCLES §1–2).
const _dirs = ['lib/theme', 'lib/widgets/dialogs'];

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// הקשתות בין קבצי [dir] בלבד, מ־`import`/`export` (package או יחסי).
Map<String, Set<String>> _graph(String dir) {
  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.uri.pathSegments.last)
      .toSet();
  final pkgPrefix = 'package:otzaria/${dir.substring('lib/'.length)}/';
  return {
    for (final name in files)
      name: {
        for (final m in _directive.allMatches(
          File('$dir/$name').readAsStringSync(),
        ))
          m.group(1)!.startsWith(pkgPrefix)
              ? m.group(1)!.substring(pkgPrefix.length)
              : m.group(1)!,
      }.intersection(files),
  };
}

/// רכיבי הקשירות החזקה (Tarjan) עם יותר מקובץ אחד.
List<List<String>> _cycles(Map<String, Set<String>> g) {
  var index = 0;
  final idx = <String, int>{}, low = <String, int>{};
  final stack = <String>[], onStack = <String>{};
  final out = <List<String>>[];
  void visit(String v) {
    idx[v] = low[v] = index++;
    stack.add(v);
    onStack.add(v);
    for (final w in g[v]!) {
      if (!idx.containsKey(w)) {
        visit(w);
        low[v] = low[v]! < low[w]! ? low[v]! : low[w]!;
      } else if (onStack.contains(w)) {
        low[v] = low[v]! < idx[w]! ? low[v]! : idx[w]!;
      }
    }
    if (low[v] == idx[v]) {
      final scc = <String>[];
      String w;
      do {
        w = stack.removeLast();
        onStack.remove(w);
        scc.add(w);
      } while (w != v);
      if (scc.length > 1) out.add(scc..sort());
    }
  }

  for (final v in g.keys) {
    if (!idx.containsKey(v)) visit(v);
  }
  return out;
}

void main() {
  for (final dir in _dirs) {
    test('$dir: אין מחזור ייבוא', () {
      expect(_cycles(_graph(dir)), isEmpty);
    });
  }
}
