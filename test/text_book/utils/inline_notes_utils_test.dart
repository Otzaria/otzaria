import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';

void main() {
  group('addInlineNotePreviewLinks', () {
    test('מחליף את הסמן הצמוד בקישור להערה', () {
      const line =
          'גוף<sup class="footnote-marker">א</sup>'
          '<i class="footnote">תוכן</i>';

      final result = addInlineNotePreviewLinks(line, lineIndex: 7);

      expect(result, contains('href="otzaria://book-note?line=7&note=0"'));
      expect(result, contains('>א</a><i class="footnote">תוכן</i>'));
    });

    test('מחלץ את ההערה לפי כתובת הריחוף', () {
      const content = [
        'גוף<sup class="footnote-marker">א</sup>'
            '<i class="footnote">ראשונה</i>'
            '<sup class="footnote-marker">ב</sup>'
            '<i class="footnote">שנייה</i>',
      ];

      expect(
        inlineNoteFromPreviewUrl(
          content,
          'otzaria://book-note?line=0&note=1',
        ),
        contains('שנייה'),
      );
    });
  });

  group('stripInlineNotes', () {
    test('מסיר <i class="footnote"> מהשורה ומשאיר את <sup>', () {
      const input =
          'גוף הטקסט<sup class="footnote-marker">א</sup><i class="footnote">תוכן ההערה</i>. המשך';
      final result = stripInlineNotes(input);
      expect(result, contains('גוף הטקסט'));
      expect(result, contains('<sup class="footnote-marker">א</sup>'));
      expect(result, contains('. המשך'));
      expect(result, isNot(contains('<i')));
      expect(result, isNot(contains('תוכן ההערה')));
    });

    test('מטפל במספר הערות באותה שורה', () {
      const input =
          'א<sup>1</sup><i class="footnote">ראשונה</i>, ב<sup>2</sup><i class="footnote">שנייה</i>.';
      final result = stripInlineNotes(input);
      expect(result, isNot(contains('ראשונה')));
      expect(result, isNot(contains('שנייה')));
      expect(result, contains('<sup>1</sup>'));
      expect(result, contains('<sup>2</sup>'));
    });

    test('משאיר שורות ללא הערות ללא שינוי', () {
      const input = 'שורה פשוטה ללא הערה';
      expect(stripInlineNotes(input), input);
    });

    test('מטפל ב-<i> שאינו footnote ולא נוגע בו', () {
      const input =
          'טקסט עם <i>italic רגיל</i> והערה <i class="footnote">הערה</i>';
      final result = stripInlineNotes(input);
      expect(result, contains('<i>italic רגיל</i>'));
      expect(result, isNot(contains('הערה</i>')));
    });
  });

  group('stripInlineNotesForSearch', () {
    test('מסיר גם את אות ההפניה (<sup>) וגם את גוף ההערה', () {
      const input =
          'גוף הטקסט<sup class="footnote-marker">א</sup><i class="footnote">תוכן ההערה</i>. המשך';
      final result = stripInlineNotesForSearch(input);
      expect(result, contains('גוף הטקסט'));
      expect(result, contains('. המשך'));
      expect(result, isNot(contains('<sup')));
      expect(result, isNot(contains('<i')));
      // האות א של ה-marker וגם תוכן ההערה הוסרו לגמרי
      expect(result, isNot(contains('תוכן ההערה')));
      expect(result, 'גוף הטקסט. המשך');
    });

    test('מטפל במספר הערות באותה שורה', () {
      const input =
          'א<sup class="footnote-marker">1</sup><i class="footnote">ראשונה</i>, '
          'ב<sup class="footnote-marker">2</sup><i class="footnote">שנייה</i>.';
      final result = stripInlineNotesForSearch(input);
      expect(result, isNot(contains('<sup')));
      expect(result, isNot(contains('ראשונה')));
      expect(result, isNot(contains('שנייה')));
      expect(result, 'א, ב.');
    });

    test('משאיר שורות ללא הערות ללא שינוי', () {
      const input = 'שורה פשוטה ללא הערה';
      expect(stripInlineNotesForSearch(input), input);
    });

    test('לא נוגע ב-<sup> שאינו footnote-marker', () {
      const input = 'טקסט עם <sup>מעריך</sup> רגיל';
      expect(stripInlineNotesForSearch(input), input);
    });
  });

  group('hasInlineNotes', () {
    test('מחזיר true כשיש לפחות שורה אחת עם <i class="footnote">', () {
      final content = [
        'שורה רגילה',
        'שורה<sup>1</sup><i class="footnote">הערה</i>',
        'שורה אחרונה',
      ];
      expect(hasInlineNotes(content), isTrue);
    });

    test('מחזיר false כשאין הערות בשום שורה', () {
      final content = ['א', 'ב', 'ג'];
      expect(hasInlineNotes(content), isFalse);
    });

    test('מחזיר false לרשימה ריקה', () {
      expect(hasInlineNotes(const []), isFalse);
    });
  });

  group('notesForLines', () {
    test('מחזיר את ה-marker והגוף עבור הערה צמודה ל-<sup>', () {
      final content = [
        'גוף<sup class="footnote-marker">א</sup><i class="footnote">תוכן</i>.',
      ];
      final result = notesForLines(content, [0]);
      expect(result.length, 1);
      expect(result.first, contains('<sup class="footnote-marker">א</sup>'));
      expect(result.first, contains('תוכן'));
    });

    test('מחלץ מספר הערות באותה שורה — כל הערה רק עם ה-<sup> הצמוד שלה', () {
      final content = [
        'א<sup>1</sup><i class="footnote">ראשונה</i> ב<sup>2</sup><i class="footnote">שנייה</i>.',
      ];
      final result = notesForLines(content, [0]);
      expect(result.length, 2);
      expect(result[0], contains('<sup>1</sup>'));
      expect(result[0], contains('ראשונה'));
      expect(result[0], isNot(contains('<sup>2</sup>')));
      expect(result[0], isNot(contains('שנייה')));

      expect(result[1], contains('<sup>2</sup>'));
      expect(result[1], contains('שנייה'));
      // regression: אסור שהערה שנייה תכיל את ה-marker או הגוף של הראשונה
      expect(result[1], isNot(contains('<sup>1</sup>')));
      expect(result[1], isNot(contains('ראשונה')));
    });

    test('מחלץ 4 הערות עם markers אותיות עבריות שונות (Beit Yaakov pattern)', () {
      final content = [
        'גוף<sup class="footnote-marker">א</sup><i class="footnote">A</i>'
            '. עוד<sup class="footnote-marker">ב</sup><i class="footnote">B</i>'
            '. עוד<sup class="footnote-marker">ג</sup><i class="footnote">C</i>'
            '. עוד<sup class="footnote-marker">ד</sup><i class="footnote">D</i>',
      ];
      final result = notesForLines(content, [0]);
      expect(result.length, 4);
      expect(result[0], contains('>א</sup>'));
      expect(result[0], contains('A'));
      expect(result[1], contains('>ב</sup>'));
      expect(result[1], contains('B'));
      expect(result[1], isNot(contains('>א</sup>')));
      expect(result[2], contains('>ג</sup>'));
      expect(result[2], isNot(contains('>ב</sup>')));
      expect(result[3], contains('>ד</sup>'));
      expect(result[3], isNot(contains('>ג</sup>')));
    });

    test('מסנן אינדקסים מחוץ לתחום', () {
      final content = ['<sup>1</sup><i class="footnote">תוכן</i>'];
      expect(notesForLines(content, [-1, 5]), isEmpty);
    });

    test('מחזיר רק את ההערות של האינדקסים המבוקשים', () {
      final content = [
        '<sup>1</sup><i class="footnote">הראשונה</i>',
        '<sup>2</sup><i class="footnote">השנייה</i>',
        '<sup>3</sup><i class="footnote">השלישית</i>',
      ];
      final result = notesForLines(content, [1]);
      expect(result.length, 1);
      expect(result.first, contains('השנייה'));
      expect(result.first, isNot(contains('הראשונה')));
      expect(result.first, isNot(contains('השלישית')));
    });

    test('מחלץ הערה ללא <sup> צמוד (orphan)', () {
      final content = ['טקסט <i class="footnote">הערה יתומה</i>.'];
      final result = notesForLines(content, [0]);
      expect(result.length, 1);
      expect(result.first, 'הערה יתומה');
    });

    test('מתעלם משורות ללא הערות', () {
      final content = ['שורה רגילה', 'שורה אחרת'];
      expect(notesForLines(content, [0, 1]), isEmpty);
    });
  });
}
