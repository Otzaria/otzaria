import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/links.dart';

List<LinkContentLine>? _viaSplit(String text, int start, int? endExclusiveIdx) {
  final lines = text.split('\n');
  if (start >= lines.length) return null;
  final end0 = ((endExclusiveIdx ?? start + 1) - 1).clamp(
    start,
    lines.length - 1,
  );
  return lines
      .sublist(start, end0 + 1)
      .indexed
      .map((e) => (lineIndex: start + e.$1, content: e.$2.trimRight()))
      .toList(growable: false);
}

void main() {
  const texts = <String>[
    '',
    '\n',
    'a',
    'a\n',
    'a\nb\nc',
    'a\r\nb  \r\n\r\nc\t\n',
    '\n\n\n',
    'שורה א  \nשורה ב\r\n\nשורה ד',
  ];

  test('שקילות מול split בכל התחלה וסוף, כולל מחוץ לטווח', () {
    for (final text in texts) {
      for (var start = 0; start < 8; start++) {
        for (final end in <int?>[null, 0, 1, 2, 3, 5, 9]) {
          final expected = _viaSplit(text, start, end);
          final actual = linkLinesFromText(text, start, end);
          expect(actual, expected, reason: '$text start=$start end=$end');
        }
      }
    }
  });

  test('התחלה שלילית זורקת כמו sublist', () {
    expect(() => linkLinesFromText('a\nb', -1, null), throwsRangeError);
  });

  test('שורה מוקדמת בספר גדול לא סורקת את כל הטקסט (מהיר מפיצול)', () {
    final text = List.generate(30000, (i) => 'שורה $i ' * 20).join('\n');
    const reps = 100;
    final split = Stopwatch()..start();
    for (var i = 0; i < reps; i++) {
      _viaSplit(text, 10, null);
    }
    split.stop();
    final direct = Stopwatch()..start();
    for (var i = 0; i < reps; i++) {
      linkLinesFromText(text, 10, null);
    }
    direct.stop();
    expect(
      direct.elapsedMicroseconds * 5,
      lessThan(split.elapsedMicroseconds),
    );
  });
}
