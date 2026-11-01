import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

import '../../tool/ui_lint/ast_helpers.dart';

/// השורות שבהן נבנה TextPainter בלי textDirection בבנאי.
List<int> _textPaintersWithoutDirection(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  return [
    for (final call in ctorCallsNamed(parsed.unit, {'TextPainter'}))
      if (call.constructor == null && call.named('textDirection') == null)
        parsed.lineInfo.getLocation(call.node.offset).lineNumber,
  ];
}

void main() {
  test('הסורק מוצא TextPainter בלי textDirection, עם new ובלעדיו', () {
    final source = File(
      'test/design_system/fixtures/text_painter_without_direction.dart',
    ).readAsStringSync();
    final marked = [
      for (final (i, line) in source.split('\n').indexed)
        if (line.trimRight().endsWith('// LINT')) i + 1,
    ];
    expect(marked, hasLength(3));
    expect(_textPaintersWithoutDirection(source), marked);
  });

  test('כל TextPainter ב-lib מקבל textDirection', () {
    final hits = <String>[];
    var scanned = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      scanned += 'TextPainter('.allMatches(source).length;
      for (final line in _textPaintersWithoutDirection(source)) {
        hits.add('${entity.path}:$line');
      }
    }

    expect(scanned, greaterThan(0));
    expect(
      hits,
      isEmpty,
      reason:
          'TextPainter חייב לקבל textDirection לפני layout():\n'
          '${hits.join('\n')}',
    );
  });
}
