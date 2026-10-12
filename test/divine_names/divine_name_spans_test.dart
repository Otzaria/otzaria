import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';

/// המבנה הדחוס של מופעי השמות: חיפוש לפי שורה, סדר, וקלט פגום.
void main() {
  test('ריק — אין מופעים בשום שורה', () {
    final spans = DivineNameSpansBuilder().build();
    expect(spans.isEmpty, isTrue);
    expect(identical(spans, DivineNameSpans.empty), isTrue);
    expect(spans.spansAt(0), isEmpty);
  });

  test('המופעים של כל שורה, לפי הסדר', () {
    final builder = DivineNameSpansBuilder()
      ..add(2, 0, 4, 1)
      ..add(2, 10, 15, 5)
      ..add(7, 3, 6, 7)
      ..add(100, 1, 3, 3);
    final spans = builder.build();

    expect(spans.length, 4);
    expect(spans.spansAt(2), [
      (start: 0, end: 4, kind: 1),
      (start: 10, end: 15, kind: 5),
    ]);
    expect(spans.spansAt(7), [(start: 3, end: 6, kind: 7)]);
    expect(spans.spansAt(100), [(start: 1, end: 3, kind: 3)]);
    for (final missing in [-1, 0, 1, 3, 8, 99, 101]) {
      expect(spans.spansAt(missing), isEmpty, reason: 'line $missing');
    }
  });

  test('טווח ריק או שלילי, ושורה שחוזרת אחורה — מדולגים', () {
    final spans =
        (DivineNameSpansBuilder()
              ..add(1, 5, 5, 1)
              ..add(1, -1, 3, 1)
              ..add(3, 0, 2, 3)
              ..add(2, 0, 2, 3))
            .build();
    expect(spans.length, 1);
    expect(spans.spansAt(3), [(start: 0, end: 2, kind: 3)]);
    expect(spans.spansAt(2), isEmpty);
  });
}
