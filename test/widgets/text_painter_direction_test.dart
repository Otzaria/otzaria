import 'dart:io';

import 'package:test/test.dart';

/// כל TextPainter ב-lib מקבל textDirection (issue #1474).
///
/// `layout()` זורק בלעדיו: "TextPainter.textDirection must be set to a
/// non-null value" — ולכן הפרמטר הזה אינו מיותר, גם אם הוא `rtl`.
void main() {
  test('אין TextPainter בלי textDirection (issue #1474)', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (final (i, line) in lines.indexed) {
        if (!line.contains('TextPainter(')) continue;
        // גוף הקריאה מסתיים בסוגר הסוגר; די בחלון קצר כדי לכסות אותו.
        final body = lines.skip(i).take(12).join('\n');
        if (body.contains('textDirection')) continue;
        hits.add('${entity.path}:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      hits,
      isEmpty,
      reason:
          'TextPainter בלי textDirection זורק ב-layout(). הכלל ב-CLAUDE.md '
          'נגד textDirection: rtl חל על Text בלבד:\n${hits.join('\n')}',
    );
  });
}
