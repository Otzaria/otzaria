import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/range_edit/text_range_edit.dart';

const _paragraphs = ['אחת שתים שלוש', '', 'ארבע חמש', 'שש שבע שמונה'];

TextRangeEdit _edit({
  required TextPoint start,
  required TextPoint end,
  TextRangeUnit unit = TextRangeUnit.words,
  bool cross = true,
}) => TextRangeEdit(
  paragraphCount: _paragraphs.length,
  paragraphAt: (i) => _paragraphs[i],
  start: start,
  end: end,
  unit: unit,
  crossParagraphs: cross,
);

TextPoint _at(int paragraph, String word, {bool end = false}) {
  final offset = _paragraphs[paragraph].indexOf(word);
  return (paragraph: paragraph, offset: end ? offset + word.length : offset);
}

void main() {
  test('מילים: הקצוות זזים במילים ואינם חוצים זה את זה', () {
    final edit = _edit(start: _at(0, 'שתים'), end: _at(0, 'שתים', end: true));
    expect(edit.text, 'שתים');
    expect(edit.canShrinkStart, isFalse);
    expect(edit.canShrinkEnd, isFalse);

    edit
      ..growStart()
      ..growEnd();
    expect(edit.text, 'אחת שתים שלוש');
    expect(edit.wordSpan, (first: 0, last: 2));
    expect(edit.changed, isTrue);

    edit.reset();
    expect(edit.text, 'שתים');
    expect(edit.changed, isFalse);
  });

  test('מילים: עם crossParagraphs הסוף עובר לפסקה הבאה ומדלג על ריקה', () {
    final edit = _edit(start: _at(0, 'שלוש'), end: _at(0, 'שלוש', end: true));
    edit.growEnd();
    expect(edit.end, _at(2, 'ארבע', end: true));
    expect(edit.isSingleParagraph, isFalse);
    edit.shrinkEnd();
    expect(edit.end, _at(0, 'שלוש', end: true));
  });

  test('מילים: בלי crossParagraphs נשארים בפסקה, ועוברים בה בשלמותה', () {
    final edit = _edit(
      start: _at(0, 'שלוש'),
      end: _at(0, 'שלוש', end: true),
      cross: false,
    );
    expect(edit.canGrowEnd, isFalse);
    edit.goToParagraph(3);
    expect(edit.text, 'שש שבע שמונה');
  });

  test('הזזת הטווח כולו שומרת על אורכו', () {
    final edit = _edit(start: _at(3, 'שש'), end: _at(3, 'שבע', end: true));
    edit.moveLater();
    expect(edit.text, 'שבע שמונה');
    expect(edit.canMoveLater, isFalse);
    edit.moveEarlier();
    expect(edit.text, 'שש שבע');

    final single = _edit(start: _at(3, 'שבע'), end: _at(3, 'שבע', end: true));
    single.moveEarlier();
    expect(single.text, 'שש');
  });

  test('פסקאות: הרחבה, הזזה ומעבר ממילים לפסקאות ובחזרה', () {
    final edit = _edit(start: _at(2, 'חמש'), end: _at(2, 'חמש', end: true));
    edit.unit = TextRangeUnit.paragraphs;
    expect(edit.start, (paragraph: 2, offset: 0));
    expect(edit.end, (paragraph: 2, offset: _paragraphs[2].length));

    edit.growEnd();
    expect(edit.end.paragraph, 3);
    expect(edit.canGrowEnd, isFalse);
    edit.moveEarlier();
    expect((edit.start.paragraph, edit.end.paragraph), (1, 2));

    edit.unit = TextRangeUnit.words;
    expect(edit.start, _at(2, 'ארבע'));
    expect(edit.end, _at(2, 'חמש', end: true));
  });

  test('טווח שאינו תקין מתכווץ לפסקה שבה הוא מתחיל', () {
    final edit = _edit(
      start: (paragraph: 3, offset: 5),
      end: (paragraph: 3, offset: 2),
    );
    expect(edit.text, 'שש שבע שמונה');
  });
}
