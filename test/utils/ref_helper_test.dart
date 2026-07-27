import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// בונה TocEntry עם ילדים. עוזר לקיצור הטסטים של closestTocEntryIndex.
TocEntry _entry(String text, int index, int level, {List<TocEntry>? children}) {
  final e = TocEntry(text: text, index: index, level: level);
  if (children != null) {
    for (final c in children) {
      e.children.add(c);
    }
  }
  return e;
}

void main() {
  group('closestTocEntryIndex', () {
    // הפונקציה הזו מחושבת *פעם אחת* בכל emit של TextBookBloc ב-TocViewer
    // (commit 5ca70f2). אם מישהו ישבור את האלגוריתם, ה-active item
    // יוצג שגוי בכל הספרים — ולכן חשוב לכסות את הקצוות.

    test('רשימה ריקה מחזירה null', () {
      expect(closestTocEntryIndex(const [], 0), isNull);
      expect(closestTocEntryIndex(const [], 999), isNull);
    });

    test('כל הערכים אחרי היעד - מחזיר null', () {
      final entries = [
        _entry('a', 10, 1),
        _entry('b', 20, 1),
      ];
      expect(closestTocEntryIndex(entries, 5), isNull);
    });

    test('יעד שווה לאינדקס - מחזיר אותו אינדקס', () {
      final entries = [
        _entry('a', 0, 1),
        _entry('b', 5, 1),
        _entry('c', 10, 1),
      ];
      expect(closestTocEntryIndex(entries, 5), 5);
    });

    test('בוחר את האחרון שאינדקסו <= target ברמה אחת', () {
      final entries = [
        _entry('a', 0, 1),
        _entry('b', 5, 1),
        _entry('c', 10, 1),
        _entry('d', 15, 1),
      ];
      expect(closestTocEntryIndex(entries, 7), 5);
      expect(closestTocEntryIndex(entries, 9), 5);
      expect(closestTocEntryIndex(entries, 10), 10);
      expect(closestTocEntryIndex(entries, 11), 10);
      expect(closestTocEntryIndex(entries, 100), 15);
    });

    test('יורד לעומק בעץ - מוצא ילד עם אינדקס גבוה מההורה', () {
      // הורה ב-0, ילדים ב-1,2,3 — היעד 2 צריך להחזיר את הילד (2), לא ההורה
      final entries = [
        _entry(
          'parent',
          0,
          1,
          children: [
            _entry('c1', 1, 2),
            _entry('c2', 2, 2),
            _entry('c3', 3, 2),
          ],
        ),
        _entry('next', 10, 1),
      ];
      expect(closestTocEntryIndex(entries, 2), 2);
      expect(closestTocEntryIndex(entries, 4), 3);
    });

    test('יעד בין שני אבות - לא יורד לעץ של האב הרחוק', () {
      // ההגנה החשובה: כשאב נמצא אחרי היעד, האלגוריתם לא יורד לילדיו
      // כי אינדקסיהם בהכרח גבוהים יותר. זה התנאי `if (entry.index <= target)`.
      final entries = [
        _entry(
          'p1',
          0,
          1,
          children: [
            _entry('p1c', 1, 2),
          ],
        ),
        _entry(
          'p2',
          10,
          1,
          children: [
            _entry('p2c', 11, 2),
          ],
        ),
      ];
      expect(closestTocEntryIndex(entries, 5), 1);
    });

    test('היררכיה עמוקה - בוחר את האינדקס המקסימלי בכל הרמות', () {
      final entries = [
        _entry(
          'A',
          0,
          1,
          children: [
            _entry(
              'A1',
              1,
              2,
              children: [
                _entry('A1a', 2, 3),
                _entry('A1b', 3, 3),
              ],
            ),
            _entry(
              'A2',
              4,
              2,
              children: [
                _entry('A2a', 5, 3),
              ],
            ),
          ],
        ),
      ];
      expect(closestTocEntryIndex(entries, 5), 5);
      expect(closestTocEntryIndex(entries, 4), 4);
      expect(closestTocEntryIndex(entries, 3), 3);
      expect(closestTocEntryIndex(entries, 0), 0);
    });

    test('יעד שלילי - מחזיר null אם אין אינדקסים שליליים', () {
      final entries = [
        _entry('a', 0, 1),
        _entry('b', 5, 1),
      ];
      expect(closestTocEntryIndex(entries, -1), isNull);
    });

    test('יציב לאינדקסים זהים בעלים שונים - מחזיר את אחד מהם', () {
      // קצה לא טיפוסי, אבל יציבות חשובה אם זה קורה בנתונים אמיתיים
      final entries = [
        _entry('a', 5, 1),
        _entry('b', 5, 1),
      ];
      expect(closestTocEntryIndex(entries, 5), 5);
    });

    test('עץ גדול (8000 ערכים) - תוצאה נכונה במבנה מציאותי', () {
      // מבנה דמוי-ספר אמיתי: siman_s מתחיל באינדקס s*100, ילדיו ב-s*100+1..+99.
      // לא טסט ביצועים, אבל מוודא שאין רגרסיה לעצירה בלולאה אינסופית.
      final simanim = List.generate(80, (s) {
        final base = s * 100;
        final children = List.generate(
          99,
          (i) => _entry('seif$i', base + 1 + i, 2),
        );
        return _entry('siman$s', base, 1, children: children);
      });
      expect(closestTocEntryIndex(simanim, 99), 99);
      // ערך באמצע: siman40 מתחיל ב-4000, ילדים ב-4001..4099
      expect(closestTocEntryIndex(simanim, 4050), 4050);
      // יעד בדיוק על siman - לא בורר אחד מהילדים
      expect(closestTocEntryIndex(simanim, 4000), 4000);
    });
  });

  group('refFromIndex', () {
    // רגרסיה: "מחנה אפרים חלק א - ב" — חלק א מתחיל ברמה 2 (אין כותרת חלק
    // ברמה 1), ולכן הכותרת הראשונה ("הלכות שבועות") נתקעה באינדקס 0
    // והודבקה לכל כתובת בחלק א (ראה הבאג: "הלכות שבועות, הלכות צדקה, סימן יב").

    test('TOC שמתחיל ברמה 2 - לא מדביק את הכותרת הראשונה לכל כתובת', () async {
      final toc = [
        _entry(
          'הלכות שבועות',
          2,
          2,
          children: [
            _entry('סימן א', 3, 3),
            _entry('סימן ב', 14, 3),
          ],
        ),
        _entry(
          'הלכות צדקה',
          183,
          2,
          children: [
            _entry('סימן א', 184, 3),
            _entry('סימן יב', 226, 3),
          ],
        ),
      ];

      // סימן יב תחת הלכות צדקה - לא אמור לכלול "הלכות שבועות"
      expect(await refFromIndex(226, Future.value(toc)), 'הלכות צדקה, סימן יב');
      // סימן ב תחת הלכות שבועות - הכתובת הנכונה שלו
      expect(await refFromIndex(14, Future.value(toc)), 'הלכות שבועות, סימן ב');
    });

    test('TOC עם רמה 1 תקין - שומר על כל ההיררכיה', () async {
      final toc = [
        _entry(
          'מחנה אפרים חלק ב',
          1216,
          1,
          children: [
            _entry(
              'הלכות שכירות פועלים',
              1218,
              2,
              children: [
                _entry('סימן א', 1219, 3),
              ],
            ),
            _entry(
              'הלכות ערב',
              1460,
              2,
              children: [
                _entry('סימן ב', 1468, 3),
              ],
            ),
          ],
        ),
      ];

      expect(
        await refFromIndex(1468, Future.value(toc)),
        'מחנה אפרים חלק ב, הלכות ערב, סימן ב',
      );
    });

    test('דילוג על רמה (1 ואז 3) - לא משאיר מקטעים ריקים', () async {
      final toc = [
        _entry(
          'חלק',
          0,
          1,
          children: [
            _entry('סעיף', 5, 3),
          ],
        ),
      ];

      expect(await refFromIndex(5, Future.value(toc)), 'חלק, סעיף');
    });

    test('אינדקס לפני הכותרת הראשונה - מחזיר מחרוזת ריקה', () async {
      final toc = [
        _entry('הלכות שבועות', 2, 2),
      ];

      expect(await refFromIndex(0, Future.value(toc)), '');
    });

    test('refFromTocList (סינכרוני) מחזיר זהה ל-refFromIndex', () async {
      final toc = [
        _entry(
          'מחנה אפרים חלק ב',
          1216,
          1,
          children: [
            _entry(
              'הלכות ערב',
              1460,
              2,
              children: [
                _entry('סימן ב', 1468, 3),
              ],
            ),
          ],
        ),
      ];

      expect(
        refFromTocList(1468, toc),
        await refFromIndex(1468, Future.value(toc)),
      );
    });
  });

  group('formatDisplayReference', () {
    test('adds the book title when resolved reference omits it', () {
      expect(
        formatDisplayReference(
          bookTitle: 'בראשית',
          resolvedRef: 'פרק א',
          fallbackRef: 'א',
        ),
        'בראשית, פרק א',
      );
    });

    test('keeps the resolved reference when it already starts with title', () {
      expect(
        formatDisplayReference(
          bookTitle: 'בראשית',
          resolvedRef: 'בראשית, פרק א',
          fallbackRef: 'פרק א',
        ),
        'בראשית, פרק א',
      );
    });

    test('removes adjacent duplicate toc segments', () {
      expect(
        formatDisplayReference(
          bookTitle: 'לבני מחולקת על כרכות',
          resolvedRef: 'לבני מחולקת על כרכות, לבני מחולקת על כרכות, כרכות',
        ),
        'לבני מחולקת על כרכות, כרכות',
      );
    });

    test(
      'falls back to the existing link reference when TOC ref is unavailable',
      () {
        expect(
          formatDisplayReference(
            bookTitle: 'בראשית',
            fallbackRef: 'פרק א',
          ),
          'בראשית, פרק א',
        );
      },
    );

    test('returns only the book title when no reference is available', () {
      expect(
        formatDisplayReference(
          bookTitle: 'בראשית',
        ),
        'בראשית',
      );
    });

    test('normalizes whitespace and keeps only adjacent unique segments', () {
      expect(
        formatDisplayReference(
          bookTitle: 'בראשית',
          resolvedRef: '  פרק א  ,   פרק א , פסוק ב  ',
        ),
        'בראשית, פרק א, פסוק ב',
      );
    });

    test('prefers fallback reference when it is more specific than TOC', () {
      expect(
        formatDisplayReference(
          bookTitle: 'כמלכל',
          resolvedRef: 'פרק ו',
          fallbackRef: 'פרק ו, פסוק ג',
        ),
        'כמלכל, פרק ו, פסוק ג',
      );
    });

    // רגרסיה: ה-TOC של "משנה אבות" נעצר בפרק, וכתובת השורה ("א, ג") היא
    // היחידה שנושאת את מספר המשנה. הניקוד לבדו העדיף את הכתובת הקצרה.
    test('מעדיף את כתובת השורה כשהיא עמוקה מכתובת ה-TOC', () {
      expect(
        formatDisplayReference(
          bookTitle: 'משנה אבות',
          resolvedRef: 'פרק א',
          fallbackRef: 'משנה אבות א, ג',
        ),
        'משנה אבות א, ג',
      );
    });

    test('נשאר בכתובת ה-TOC כשהיא עמוקה מכתובת השורה', () {
      expect(
        formatDisplayReference(
          bookTitle: 'ברכות',
          resolvedRef: 'דף ב, עמוד א',
          fallbackRef: 'ברכות ב א',
        ),
        'ברכות, דף ב, עמוד א',
      );
    });

    test('כתובת שורה שהיא רק שם הספר אינה דוחקת את כתובת ה-TOC', () {
      expect(
        formatDisplayReference(
          bookTitle: 'משנה אבות',
          resolvedRef: 'פרק א',
          fallbackRef: 'משנה אבות',
        ),
        'משנה אבות, פרק א',
      );
    });

    test('עומק שווה — הניקוד ממשיך להכריע לטובת כתובת ה-TOC', () {
      expect(
        formatDisplayReference(
          bookTitle: 'בראשית',
          resolvedRef: 'פרק א',
          fallbackRef: 'א',
        ),
        'בראשית, פרק א',
      );
    });
  });

  group('addBookTitleToRef', () {
    test('לא מוסיף קידומת כשהכותרת כבר מתחילה בשם הספר', () {
      expect(addBookTitleToRef('בכורות, דף ב', 'בכורות'), 'בכורות, דף ב');
    });

    test('מוסיף שם ספר כשהכותרת אינה קשורה', () {
      expect(addBookTitleToRef('דף ב', 'בכורות'), 'בכורות, דף ב');
    });

    test('מחזיר רק שם ספר כשהכותרת ריקה', () {
      expect(addBookTitleToRef('', 'בכורות'), 'בכורות');
      expect(addBookTitleToRef('  ', 'בכורות'), 'בכורות');
    });

    // רגרסיה: "חברותא על בכורות" + ערך TOC "חברותא - בכורות" = כפילות
    test('לא מוסיף קידומת כשמילות הספר המשמעותיות כלולות בכותרת', () {
      expect(
        addBookTitleToRef('חברותא - בכורות', 'חברותא על בכורות'),
        'חברותא - בכורות',
      );
    });

    test('לא מוסיף קידומת כשהכותרת כוללת ספר + פרק עם מילות הספר', () {
      expect(
        addBookTitleToRef(
          'חברותא - בכורות, פרק ראשון - הלוקח',
          'חברותא על בכורות',
        ),
        'חברותא - בכורות, פרק ראשון - הלוקח',
      );
    });

    test('מוסיף קידומת כששם הספר ארוך ממה שמופיע בכותרת', () {
      // "שלחן ערוך" לא מופיע ב-"אורח חיים"
      expect(
        addBookTitleToRef('אורח חיים', 'שלחן ערוך אורח חיים'),
        'שלחן ערוך אורח חיים, אורח חיים',
      );
    });

    // רגרסיה: השם במסד נשמר בלי גרשיים ("מהרם") מול ערך TOC עם גרשיים ("מהר"ם")
    test('לא מוסיף קידומת כשההבדל היחיד הוא גרשיים', () {
      expect(
        addBookTitleToRef('מהר"ם שיק תרי"ג מצות', 'מהרם שיק תריג מצות'),
        'מהר"ם שיק תרי"ג מצות',
      );
      expect(
        addBookTitleToRef('ספר השרשים לרד"ק', 'ספר השרשים לרדק'),
        'ספר השרשים לרד"ק',
      );
    });

    test('לא מוסיף קידומת כשההבדל היחיד הוא ניקוד', () {
      expect(addBookTitleToRef('לְכָה דוֹדִי', 'לכה דודי'), 'לְכָה דוֹדִי');
    });

    test('לא מוסיף קידומת כשההבדל הוא מקף עברי מול רווח', () {
      expect(
        addBookTitleToRef('מגדל עז או תמת ישרים', 'מגדל־עז או תמת ישרים'),
        'מגדל עז או תמת ישרים',
      );
    });

    // כותרת מקוצרת מהשם + מילה מובילה זהה → מחזיר את השם המלא (בלי כפילות)
    test('מחזיר את שם הספר כשהכותרת מקוצרת ממנו וחולקת מילה מובילה', () {
      expect(
        addBookTitleToRef(
          'בית מאיר אורח חיים',
          'בית מאיר על שולחן ערוך אורח חיים',
        ),
        'בית מאיר על שולחן ערוך אורח חיים',
      );
    });

    // מילה מובילה שונה = הפניית-מיקום (תת-חלק), לא ניסוח מקוצר → כן מוסיף קידומת
    test('מוסיף קידומת כשהכותרת תת-קבוצה אך מילתה המובילה שונה', () {
      expect(
        addBookTitleToRef('חלק ראשון', 'ימי מוהרנת חלק ראשון'),
        'ימי מוהרנת חלק ראשון, חלק ראשון',
      );
    });
  });
}
