import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';

import '../../tool/ui_lint/ast_helpers.dart';

/// השורות שבהן נבנה `Markdown` הגלילתי. ב־AST: הערה, רווח לפני הסוגריים ו־
/// `MarkdownBody` לא מבלבלים את הסורק.
List<int> _scrollableMarkdown(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  return [
    for (final call in ctorCallsNamed(parsed.unit, {'Markdown'}))
      parsed.lineInfo.getLocation(call.node.offset).lineNumber,
  ];
}

// MarkdownBody שומר היקף תוכן מדויק בתוך הגולל החיצוני.
void main() {
  test('הסורק: Markdown נתפס בכל צורה, MarkdownBody והערה לא', () {
    expect(
      _scrollableMarkdown('''
final a = Markdown(data: d);
final b = const Markdown(data: d);
final c = Markdown (data: d);
final d = md.Markdown(data: d);
final e = MarkdownBody(data: d);
final f = _buildMarkdown(data);
// Markdown(data: d)
'''),
      [1, 2, 3, 4],
    );
  });

  test('אין שימוש ב-Markdown הגלילתי ב-lib — רק MarkdownBody', () {
    final violations = <String>[];
    var scanned = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('Markdown')) continue;
      scanned++;
      for (final line in _scrollableMarkdown(source)) {
        violations.add('${entity.path}:$line');
      }
    }

    expect(scanned, greaterThan(0), reason: 'הסורק לא מצא קבצים עם Markdown');
    expect(
      violations,
      isEmpty,
      reason:
          'נמצא שימוש ב-Markdown הגלילתי:\n${violations.join('\n')}\n\n'
          'החלף ב-MarkdownBody בתוך SingleChildScrollView — לפס גלילה יציב.',
    );
  });
}
