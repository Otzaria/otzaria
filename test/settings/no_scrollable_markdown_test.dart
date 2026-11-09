import 'dart:io';

import 'package:test/test.dart';

// MarkdownBody שומר היקף תוכן מדויק בתוך הגולל החיצוני.
final _pattern = RegExp(r'(?<![\w.])Markdown\(');

void main() {
  test('הסורק: Markdown( נתפס, MarkdownBody ו-_buildMarkdown( לא', () {
    expect(_pattern.hasMatch('child: Markdown(data: d)'), isTrue);
    expect(_pattern.hasMatch('const Markdown(data: d)'), isTrue);
    expect(_pattern.hasMatch('MarkdownBody(data: d)'), isFalse);
    expect(_pattern.hasMatch('_buildMarkdown(data)'), isFalse);
  });

  test('אין שימוש ב-Markdown הגלילתי ב-lib — רק MarkdownBody', () {
    final pattern = _pattern;
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          violations.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'נמצא שימוש ב-Markdown הגלילתי:\n${violations.join('\n')}\n\n'
          'החלף ב-MarkdownBody בתוך SingleChildScrollView — לפס גלילה יציב.',
    );
  });
}
