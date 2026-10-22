/// מצב קריאה רציף לספרי מקרא: פרקים ופסוקים בגליון, חיתוך רק בפתוחה ובשם ספר.
/// הנתונים סינתטיים (אותיות מדומות), במבנה השורות של המסד.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/mikra_citation.dart';
import 'package:otzaria/text_book/utils/mikra_structure.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';

const String _pe = '<span class="mam-spi-pe">{פ}</span><br>';
const String _samekh = '<span class="mam-spi-samekh">{ס}</span><br>';

List<String> _book() => [
  '<h1>ספר</h1>', // 0
  '<h2>פרק א</h2>', // 1
  '(א) אבג דהו', // 2
  '(ב) זחט יכל $_samekh', // 3
  '(ג) מנס עפצ $_pe', // 4
  '(ד) קרש תאב', // 5
  '<h2>פרק ב</h2>', // 6
  '(א) גדה וזח', // 7
  '(ב) טיכ למנ $_pe', // 8
  '(ג) סעפ צקר', // 9
];

void main() {
  group('parseHebrewNumeral', () {
    test('אותיות לערך', () {
      expect(parseHebrewNumeral('א'), 1);
      expect(parseHebrewNumeral('יא'), 11);
      expect(parseHebrewNumeral('טו'), 15);
      expect(parseHebrewNumeral("ט״ז"), 16);
      expect(parseHebrewNumeral('קנ'), 150);
    });
  });

  group('MikraStructure.parse', () {
    test('מזהה ספר, פרקים ופסוקים', () {
      final m = MikraStructure.parse(_book())!;
      expect(m.bookTitleLines, [0]);
      expect(m.kindAt(1), MikraLineKind.chapterTitle);
      expect(m.isHiddenLine(1), isTrue);
      expect(m.isHiddenLine(2), isFalse);
      expect(m.lines[5].chapter, 1);
      expect(m.lines[9].chapter, 2);
      expect(m.lines[9].verse, 3);
    });

    test('הפרק מופיע בגליון רק בפסוק הראשון בו', () {
      final m = MikraStructure.parse(_book())!;
      expect(
        m.gutterLabelAt(2),
        const MikraGutterLabel(chapter: 'א', verse: 'א'),
      );
      expect(m.gutterLabelAt(3), const MikraGutterLabel(verse: 'ב'));
      expect(
        m.gutterLabelAt(7),
        const MikraGutterLabel(chapter: 'ב', verse: 'א'),
      );
      expect(m.gutterLabelAt(1), isNull);
      expect(m.gutterLabelAt(0), isNull);
    });

    test('פתוחה חותכת פסקה; סתומה אינה', () {
      final m = MikraStructure.parse(_book())!;
      expect(m.paragraphEndLines, [4, 8]);
      expect(m.setumaAt(3), isTrue);
      expect(m.petuchaAt(3), isFalse);
    });

    test('ספר שאינו במבנה כותרת/פרק/פסוק נשאר כמות שהוא', () {
      expect(
        MikraStructure.parse(['<h1>ספר</h1>', 'שורה חופשית', 'עוד שורה']),
        isNull,
      );
      expect(MikraStructure.parse(['(א) אבג', '(ב) דהו', '(ג) זחט']), isNull);
    });
  });

  group('mikraDisplayHtml', () {
    test('מסיר את מספר הפסוק ושומר על התגיות שלפניו', () {
      expect(stripMikraVersePrefix('(יא) אבג'), 'אבג');
      expect(stripMikraVersePrefix('<b>(ב)</b> אבג'), startsWith('<b>'));
    });

    test('פתוחה: בלי שבירת שורה וסימון באפור', () {
      final html = mikraDisplayHtml('(ג) מנס $_pe');
      expect(html, isNot(contains('<br')));
      expect(html, contains('{פ}'));
      expect(html, contains(kMikraMarkColor));
      expect(html, isNot(contains('(ג)')));
    });

    test('סתומה: ריווח ברצף ובלי שבירת שורה', () {
      final html = mikraDisplayHtml('(ב) זחט $_samekh');
      expect(html, isNot(contains('<br')));
      expect(html, contains('{ס}'));
      expect(html, endsWith('    '));
    });
  });

  group('ReadingLayout', () {
    test('ללא splitAfter — כמו קודם: שורת שבירה היא פריט לבדה', () {
      final layout = ReadingLayout.continuous(
        lineCount: 10,
        breakLines: [0, 6],
      );
      expect(
        [for (var i = 0; i < layout.itemCount; i++) layout.firstLineOf(i)],
        [0, 1, 6, 7],
      );
    });

    test('מקרא: רק שם הספר שובר, והפתוחה חותכת אחריה', () {
      final m = MikraStructure.parse(_book())!;
      final layout = ReadingLayout.continuous(
        lineCount: _book().length,
        breakLines: m.bookTitleLines,
        splitAfterLines: m.paragraphEndLines,
      );
      final starts = [
        for (var i = 0; i < layout.itemCount; i++) layout.firstLineOf(i),
      ];
      // ספר | שורות 1–4 (פרק א ועד הפתוחה) | שורות 5–8 (חוצה פרק) | שורה 9
      expect(starts, [0, 1, 5, 9]);
      // כותרת פרק ב באמצע פסקה, לא שוברת אותה.
      expect(layout.itemForLine(6), layout.itemForLine(5));
    });

    test('splitAfter על השורה האחרונה אינו יוצר פריט ריק', () {
      final layout = ReadingLayout.continuous(
        lineCount: 3,
        breakLines: const [],
        splitAfterLines: const [2],
      );
      expect(layout.itemCount, 1);
    });
  });

  group('גליון', () {
    testWidgets('ציון לכל שורת תצוגה; פסוקים באותה שורה — טווח', (
      tester,
    ) async {
      const text =
          'אבג דהו זחט יכל מנס עפצ קרש תאב גדה וזח טיכ למנ סעפ צקר '
          'אבג דהו זחט יכל מנס עפצ קרש תאב גדה וזח טיכ למנ סעפ צקר';
      // שלושה פסוקים: הראשון והשני קצרים (שורה אחת), השלישי ארוך.
      const first = 'אבג דהו';
      const second = ' זחט יכל';
      const third = ' $text';
      final lines = [
        const ReaderParagraphLineData(
          lineIndex: 2,
          range: TextRange(start: 0, end: first.length),
          gutter: MikraGutterLabel(chapter: 'א', verse: 'א'),
        ),
        ReaderParagraphLineData(
          lineIndex: 3,
          range: TextRange(
            start: first.length + 1,
            end: first.length + second.length,
          ),
          gutter: const MikraGutterLabel(verse: 'ב'),
        ),
        ReaderParagraphLineData(
          lineIndex: 4,
          range: TextRange(
            start: first.length + second.length + 1,
            end: first.length + second.length + third.length,
          ),
          gutter: const MikraGutterLabel(verse: 'ג'),
        ),
      ];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 160,
              child: ReaderParagraphLines(
                lines: lines,
                gutterStyle: const TextStyle(fontSize: 10),
                child: const Text(
                  first + second + third,
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
          ),
        ),
      );
      final render = tester.renderObject<RenderReaderParagraphLines>(
        find.byType(ReaderParagraphLines),
      );
      final entries = render.gutterEntries();
      // הפסוקים א׳ וב׳ באותה שורה → ציון אחד שהוא טווח; ג׳ מתחיל באותה שורה
      // או מתחתיה, ואין שני ציונים באותו גובה.
      expect(entries.first.first.chapter, 'א');
      expect(entries.first.top, 0);
      final tops = entries.map((e) => e.top).toList();
      expect(tops.toSet().length, tops.length);
      expect(entries.length, lessThanOrEqualTo(3));
    });
  });

  group('פרשות ועליות (בראשית)', () {
    // ספר סינתטי: פרק א׳ 31 פסוקים, פרק ב׳ 25, פרק ג׳ 24 — מבנה בראשית.
    List<String> torahBook() {
      final lines = <String>['<h1>בראשית</h1>'];
      const counts = {1: 31, 2: 25, 3: 24};
      counts.forEach((chapter, verses) {
        lines.add('<h2>פרק ${toHebrewNumeral(chapter)}</h2>');
        for (var v = 1; v <= verses; v++) {
          lines.add('(${toHebrewNumeral(v)}) אבג דהו');
        }
      });
      return lines;
    }

    int lineOf(int chapter, int verse) {
      var line = 1;
      const counts = {1: 31, 2: 25, 3: 24};
      for (final entry in counts.entries) {
        line++; // כותרת פרק
        if (entry.key == chapter) return line + verse - 1;
        line += entry.value;
      }
      throw ArgumentError('אין פסוק');
    }

    test('הפרשה בעלייה הראשונה, והעליות לפי הטבלה', () {
      final m = MikraStructure.parse(torahBook(), bookTitle: 'בראשית')!;
      expect(
        m.divisionAt(lineOf(1, 1)),
        const MikraDivisionLabel(parasha: 'בראשית', aliyah: 'ראשון'),
      );
      expect(
        m.divisionAt(lineOf(2, 4)),
        const MikraDivisionLabel(aliyah: 'שני'),
      );
      expect(
        m.divisionAt(lineOf(2, 20)),
        const MikraDivisionLabel(aliyah: 'שלישי'),
      );
      expect(
        m.divisionAt(lineOf(3, 22)),
        const MikraDivisionLabel(aliyah: 'רביעי'),
      );
      expect(m.divisionAt(lineOf(1, 2)), isNull);
    });

    test('ציון מקור לשורה: הפרשה והעלייה שהיא בתוכן', () {
      final m = MikraStructure.parse(torahBook(), bookTitle: 'בראשית')!;
      expect(m.citationAt(lineOf(1, 1)), (parasha: 'בראשית', aliyah: 'ראשון'));
      expect(m.citationAt(lineOf(2, 3)), (parasha: 'בראשית', aliyah: 'ראשון'));
      expect(m.citationAt(lineOf(2, 4)), (parasha: 'בראשית', aliyah: 'שני'));
      expect(m.citationAt(lineOf(3, 21)), (parasha: 'בראשית', aliyah: 'שלישי'));
      expect(m.citationAt(lineOf(3, 24)), (parasha: 'בראשית', aliyah: 'רביעי'));
      // כותרת פרק ב׳ (באמצע עלייה א׳) — העלייה שהיא בתוכה.
      expect(m.citationAt(lineOf(2, 1) - 1)?.aliyah, 'ראשון');
      // לפני העלייה הראשונה: שם הספר וכותרת פרק א׳.
      expect(m.citationAt(0), isNull);
      expect(m.citationAt(1), isNull);
    });

    test('כותרת ציון המקור לפי ההגדרה', () {
      final m = MikraStructure.parse(torahBook(), bookTitle: 'בראשית')!;
      String? header(String style, int line) => torahCitationHeader(
        mikra: m,
        line: line,
        bookTitle: 'בראשית',
        style: style,
      );
      expect(
        header(TorahCopyCitation.bookParashaAliyah, lineOf(2, 5)),
        'בראשית, פרשת בראשית, שני',
      );
      expect(
        header(TorahCopyCitation.parashaAliyah, lineOf(2, 5)),
        'בראשית, שני',
      );
      expect(header(TorahCopyCitation.chapter, lineOf(2, 5)), isNull);
      expect(header(TorahCopyCitation.parashaAliyah, 0), isNull);
      expect(
        torahCitationHeader(
          mikra: null,
          line: 3,
          bookTitle: 'ישעיהו',
          style: TorahCopyCitation.parashaAliyah,
        ),
        isNull,
      );
    });

    test('ספר שאינו בתורה — בלי פרשות ועליות', () {
      final m = MikraStructure.parse(torahBook(), bookTitle: 'ישעיהו')!;
      expect(m.divisionAt(lineOf(1, 1)), isNull);
      final none = MikraStructure.parse(torahBook())!;
      expect(none.divisionAt(lineOf(1, 1)), isNull);
    });
  });

  group('שימור מזהי השורות', () {
    test('הפריסה מחלקת את כל שורות המקור לפריטים רצופים, בלי חפיפה', () {
      final content = _book();
      final m = MikraStructure.parse(content)!;
      final layout = ReadingLayout.continuous(
        lineCount: content.length,
        breakLines: m.bookTitleLines,
        splitAfterLines: m.paragraphEndLines,
      );
      var expected = 0;
      for (var item = 0; item < layout.itemCount; item++) {
        expect(layout.firstLineOf(item), expected);
        expected = layout.lastLineOf(item) + 1;
      }
      expect(expected, content.length);
      for (var line = 0; line < content.length; line++) {
        final item = layout.itemForLine(line);
        expect(layout.firstLineOf(item) <= line, isTrue);
        expect(line <= layout.lastLineOf(item), isTrue);
      }
    });

    test('הניתוח והתצוגה אינם משנים את שורות המקור', () {
      final content = List<String>.unmodifiable(_book());
      final before = List<String>.of(content);
      final m = MikraStructure.parse(content)!;
      for (var i = 0; i < content.length; i++) {
        mikraDisplayHtml(content[i]);
      }
      expect(content, before);
      // כותרת הפרק נשארת שורה במקומה (מוסתרת בתצוגה), לא נמחקת ולא מוזזת.
      expect(m.lines.length, content.length);
      expect(m.kindAt(1), MikraLineKind.chapterTitle);
    });
  });
}
