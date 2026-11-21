import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The files `dart run` compiles from [entry]. A conditional directive takes
/// the branch a plain Dart VM picks: `dart.library.io`, never `dart.library.ui`.
Map<String, String> _importsOf(String entry) {
  final directive = RegExp(
    r'''^\s*(?:import|export|part)\s+'([^']+)'((?:\s+if\s*\([^)]*\)\s*'[^']+')*)''',
    multiLine: true,
  );
  final branch = RegExp(r"if\s*\(\s*([\w.]+)[^)]*\)\s*'([^']+)'");
  final found = <String, String>{};
  final pending = [(p.normalize(entry), '')];
  while (pending.isNotEmpty) {
    final (file, from) = pending.removeLast();
    if (found.containsKey(file)) continue;
    found[file] = from;
    for (final match in directive.allMatches(File(file).readAsStringSync())) {
      var uri = match.group(1)!;
      for (final b in branch.allMatches(match.group(2)!)) {
        if (b.group(1) == 'dart.library.io') uri = b.group(2)!;
      }
      if (uri.startsWith('package:flutter/') || uri == 'dart:ui') {
        found['$uri (from $file)'] = file;
        continue;
      }
      final String? target;
      if (uri.startsWith('package:otzaria/')) {
        target = p.join('lib', uri.substring('package:otzaria/'.length));
      } else if (uri.contains(':')) {
        target = null;
      } else {
        target = p.join(p.dirname(file), uri);
      }
      if (target != null) pending.add((p.normalize(target), file));
    }
  }
  return found;
}

void main() {
  for (final tool in [
    'tool/personal_db_update.dart',
    'tool/validate_personal_db.dart',
  ]) {
    test('$tool runs with `dart run` (no Flutter import)', () {
      final flutter = _importsOf(tool).keys.where(
        (k) => k.startsWith('package:flutter/') || k.startsWith('dart:ui'),
      );
      expect(flutter, isEmpty);
    });
  }
}
