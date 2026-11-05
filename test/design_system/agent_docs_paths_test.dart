import 'dart:io';

import 'package:test/test.dart';

/// מסמכי ההנחיה שסוכנים ותורמים קוראים לפני שינוי. נתיב שמופיע בהם חייב
/// להתקיים, אחרת הם שולחים לקובץ שנמחק או זז.
const _docs = [
  'AGENTS.md',
  '.github/PULL_REQUEST_TEMPLATE.md',
  'docs/agent_ui_reference.md',
  'docs/agent_test_map.md',
  'docs/design-system/DESIGN_SYSTEM.md',
  'docs/design-system/DESIGN_DECISIONS.md',
  'docs/design-system/CI_ENFORCEMENT.md',
];

/// נתיב בתוך המאגר בין גרשיים הפוכים, כמו `lib/core/ui_snack.dart:12`.
final _codePath = RegExp(
  r'`((?:lib|test|tool|docs|\.github)/[A-Za-z0-9_./-]+?)(?::\d+(?:-\d+)?)?`',
);

/// קטע מחוק (`~~...~~`) מתעד קובץ שהוסר בכוונה.
final _struck = RegExp(r'~~[^~]*~~');

/// הנתיבים שבמסמך, בלי קטעים מחוקים.
Iterable<String> _pathsIn(String text) sync* {
  for (final line in text.split('\n')) {
    for (final m in _codePath.allMatches(line.replaceAll(_struck, ''))) {
      yield m.group(1)!;
    }
  }
}

/// הנתיבים בעץ "Key Code Locations" של AGENTS.md. כל רמה מוזחת בארבעה
/// תווים, ושורה בלי ענף היא שורש (`lib/`, `tool/ui_lint/`).
List<String> _treePaths(String agents) {
  final start = agents.indexOf('### Key Code Locations');
  final open = agents.indexOf('```', start) + 3;
  final block = agents.substring(open, agents.indexOf('```', open));
  final stack = <String>[];
  final paths = <String>[];
  for (final raw in block.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final branch = line.indexOf(RegExp('[├└]── '));
    final depth = branch < 0 ? 0 : branch ~/ 4 + 1;
    final name = (branch < 0 ? line : line.substring(branch + 4))
        .trim()
        .split(RegExp(r'\s'))
        .first;
    stack
      ..length = depth
      ..add(name.endsWith('/') ? name : '$name/');
    paths.add(stack.join().replaceAll(RegExp(r'/$'), ''));
  }
  return paths;
}

void main() {
  for (final doc in _docs) {
    test('כל נתיב ב-$doc קיים', () {
      final text = File(doc).readAsStringSync().replaceAll('\r\n', '\n');
      final paths = _pathsIn(text).toSet();
      expect(paths, isNotEmpty, reason: 'הסורק לא מצא אף נתיב ב-$doc');
      final missing = {
        for (final p in paths)
          if (!File(p).existsSync() && !Directory(p).existsSync()) p,
      };
      expect(missing, isEmpty);
    });
  }

  test('הסורק: נתיב במאגר נמצא בלי מספר השורה, ומחוק או חיצוני לא', () {
    expect(
      _pathsIn(
        'ראו `lib/core/ui_snack.dart:12`, ~~`lib/gone.dart`~~, '
        '`changes/74a-white-9f` ו־`AppTokens.iconMD`',
      ).toList(),
      ['lib/core/ui_snack.dart'],
    );
  });

  test('כל נתיב בעץ הקוד של AGENTS.md קיים', () {
    final paths = _treePaths(
      File('AGENTS.md').readAsStringSync().replaceAll('\r\n', '\n'),
    );
    expect(paths, contains('lib/core/ui_snack.dart'));
    final missing = [
      for (final p in paths)
        if (!File(p).existsSync() && !Directory(p).existsSync()) p,
    ];
    expect(missing, isEmpty);
  });
}
