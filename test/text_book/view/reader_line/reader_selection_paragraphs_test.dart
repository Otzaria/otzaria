import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';

void main() {
  test('כל שורה בחלון נבדקת כבלוק פעם אחת לכל היותר', () {
    final lines = [for (var i = 0; i < 50; i++) '<b>שורה</b> $i'];
    final paragraphs = readerSelectionParagraphs(
      layout: ReadingLayout.continuous(
        lineCount: lines.length,
        breakLines: const [0],
      ),
      lines: lines,
      baseIndex: 0,
    )!;

    debugReaderBlockMarkupChecks = 0;
    for (var line = 0; line < lines.length; line++) {
      paragraphs.headingAt(line);
    }
    for (var line = 0; line < lines.length - 1; line++) {
      paragraphs.joinsNext(line);
    }

    expect(debugReaderBlockMarkupChecks, lessThanOrEqualTo(lines.length));
  });

  test('חיבור שורות וכותרות בזרימה לפי מבנה הפסקה', () {
    const lines = ['<h2>פרק</h2>', 'אחת', 'שתיים', '<h3>כותרת</h3>', 'ארבע'];
    final paragraphs = readerSelectionParagraphs(
      layout: ReadingLayout.continuous(
        lineCount: lines.length,
        breakLines: const [0],
      ),
      lines: lines,
      baseIndex: 1,
      sectionHeadings: const {
        2: ['נושא', 'משנה'],
        3: ['בבלוק'],
      },
    )!;

    expect(
      [for (var i = 0; i < 4; i++) paragraphs.joinsNext(i)],
      [
        true,
        false,
        false,
        false,
      ],
    );
    expect(
      [for (var i = 0; i < 4; i++) paragraphs.headingAt(i)],
      [
        null,
        'נושא · משנה',
        null,
        null,
      ],
    );
  });
}
