import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
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

    test('מרקר מספרי עובר באותו קישור מורם כמו מרקר אות', () {
      // issue #1236: ספרות-עילית יוניקוד נפלו לגופן מערכת ב-4–9.
      const line =
          'גוף<sup class="footnote-marker">3</sup>'
          '<i class="footnote">תוכן</i>';

      final result = addInlineNotePreviewLinks(line, lineIndex: 7);

      expect(result, contains('class="book-note-marker"'));
      expect(result, contains('href="otzaria://book-note?line=7&note=0"'));
      expect(result, contains('>3</a>'));
      expect(result, isNot(contains('<sup')));
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

  group('הערות מהמסד (line_note) — גוף ההערה אינו בשורה', () {
    // השורה כפי שנשמרה בסכמה 7: ה-<sup> נשאר, הגוף בטבלה.
    const stripped =
        'גוף<sup class="footnote-marker">א</sup> המשך'
        '<sup class="footnote-marker">ב</sup> סוף';
    final dbNotes =
        (BookNotesBuilder()
              ..add(4, 0, 'א', 'ראשונה')
              ..add(4, 1, null, 'נספחת')
              ..add(4, 2, 'ב', 'שנייה'))
            .build();

    test('notesForLines ו-hasInlineNotes רואים את הערות הטבלה', () {
      final content = List.filled(6, 'שורה');
      content[4] = stripped;
      expect(hasInlineNotes(content), isFalse);
      expect(hasInlineNotes(content, dbNotes: dbNotes), isTrue);
      expect(notesForLines(content, [4], dbNotes: dbNotes), [
        '<sup class="footnote-marker">א</sup> ראשונה',
        'נספחת',
        '<sup class="footnote-marker">ב</sup> שנייה',
      ]);
    });

    test('ה-<sup> ה-k-י מקושר להערה ה-k-ית שיש לה marker', () {
      final result = addInlineNotePreviewLinks(
        stripped,
        lineIndex: 4,
        dbNotes: dbNotes,
      );
      expect(result, contains('note=0">א</a>'));
      expect(result, contains('note=2">ב</a>'));
      expect(result, isNot(contains('<sup')));

      final content = List.filled(6, '');
      content[4] = stripped;
      expect(
        inlineNoteFromPreviewUrl(
          content,
          'otzaria://book-note?line=4&note=2',
          dbNotes: dbNotes,
        ),
        '<sup class="footnote-marker">ב</sup> שנייה',
      );
    });

    test('בלי הערות מהמסד — השורה ללא שינוי', () {
      expect(addInlineNotePreviewLinks(stripped, lineIndex: 4), stripped);
    });

    test('rehydrate מחזיר את הגוף אחרי ה-<sup> שלו, ואת היתר לסוף', () {
      expect(
        rehydrateInlineNotes(stripped, dbNotes.notesAt(4)),
        'גוף<sup class="footnote-marker">א</sup>'
        '<i class="footnote">ראשונה</i> המשך'
        '<sup class="footnote-marker">ב</sup>'
        '<i class="footnote">שנייה</i> סוף'
        '<i class="footnote">נספחת</i>',
      );
      expect(rehydrateInlineNotes(stripped, const []), stripped);
      expect(
        rehydrateInlineNotesInText(
          'א\n\n\n\n$stripped',
          dbNotes,
        ).split('\n')[4],
        rehydrateInlineNotes(stripped, dbNotes.notesAt(4)),
      );
    });

    test('rehydrate ואחריו notesForLines — כמו הערה inline מקורית', () {
      final line = rehydrateInlineNotes(stripped, dbNotes.notesAt(4));
      expect(notesForLines([line], [0]), [
        '<sup class="footnote-marker">א</sup> ראשונה',
        '<sup class="footnote-marker">ב</sup> שנייה',
        'נספחת',
      ]);
    });
  });

  group('line_note עם charPos ושמות קודש בגוף', () {
    // "גוף" + sup "א" — 4 תווים גלויים; "המשך" אחריהם.
    const stored = 'גוף<sup class="footnote-marker">א</sup> <b>המשך</b> סוף';

    test('כל גוף חוזר באופסט שלו — גם הערה בלי marker באמצע השורה', () {
      final notes =
          (BookNotesBuilder()
                ..add(0, 0, 'א', 'ראשונה', charPos: 4)
                ..add(0, 1, null, 'באמצע', charPos: 9))
              .build();
      expect(
        rehydrateInlineNotes(stored, notes.notesAt(0)),
        'גוף<sup class="footnote-marker">א</sup>'
        '<i class="footnote">ראשונה</i> <b>המשך</b>'
        '<i class="footnote">באמצע</i> סוף',
      );
    });

    test('ישות נספרת כתו אחד, ושתי הערות באותו מקום נשמרות בסדרן', () {
      final notes =
          (BookNotesBuilder()
                ..add(0, 0, null, 'א', charPos: 2)
                ..add(0, 1, null, 'ב', charPos: 2))
              .build();
      expect(
        rehydrateInlineNotes('x&amp;y', notes.notesAt(0)),
        'x&amp;<i class="footnote">א</i><i class="footnote">ב</i>y',
      );
    });

    test('אופסט מעבר לסוף השורה — בסוף', () {
      final notes = (BookNotesBuilder()..add(0, 0, null, 'ז', charPos: 99))
          .build();
      expect(
        rehydrateInlineNotes('קצר', notes.notesAt(0)),
        'קצר<i class="footnote">ז</i>',
      );
    });

    test('שמות הקודש בגוף ההערה מסומנים לחלונית ולריחוף', () {
      final notes =
          (BookNotesBuilder()
                ..add(0, 0, 'א', 'אמר אלהים', charPos: 4)
                ..addDivineName(0, 0, 4, 9, DivineNameKind.elohim))
              .build();
      final html = notesForLines(const [stored], [0], dbNotes: notes).single;
      expect(html, contains('data-k="${DivineNameKind.elohim}">אלהים</span>'));
      expect(
        resolveDivineNameMarkers(html, substituteOtherNames: true),
        '<sup class="footnote-marker">א</sup> אמר אלקים',
      );
    });

    test('applyStoredLineData — שמות השורה וההערה, וההערה במקומה', () {
      const line = 'ברא אלהים<sup class="footnote-marker">א</sup> סוף';
      final names =
          (DivineNameSpansBuilder()..add(0, 4, 9, DivineNameKind.elohim))
              .build();
      final notes =
          (BookNotesBuilder()
                ..add(0, 0, 'א', 'אמר אלהים', charPos: 10)
                ..addDivineName(0, 0, 4, 9, DivineNameKind.elohim))
              .build();
      expect(
        applyStoredLineData(
          line,
          0,
          names: names,
          notes: notes,
          substituteOtherNames: true,
        ),
        'ברא אלקים<sup class="footnote-marker">א</sup>'
        '<i class="footnote">אמר אלקים</i> סוף',
      );
      expect(
        applyStoredLineData(
          line,
          0,
          names: names,
          notes: notes,
          substituteOtherNames: false,
        ),
        'ברא אלהים<sup class="footnote-marker">א</sup>'
        '<i class="footnote">אמר אלהים</i> סוף',
      );
    });
  });
}
