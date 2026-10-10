import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:pdfrx/pdfrx.dart';

/// Stub פשוט של PdfOutlineNode לטסטים, ללא תלות במסמך אמיתי.
class _FakeOutlineNode implements PdfOutlineNode {
  @override
  final String title;
  final int? page;
  @override
  final List<PdfOutlineNode> children;

  _FakeOutlineNode({
    required this.title,
    this.page,
    this.children = const [],
  });

  @override
  PdfDest? get dest =>
      page == null ? null : PdfDest(page!, PdfDestCommand.fitB, null);
}

void main() {
  group('buildPdfPageLabels', () {
    test('outline ריק מחזיר מפה ריקה', () {
      expect(buildPdfPageLabels([]), isEmpty);
    });

    test('node ברמה ראשונה ממופה לעמוד שלו', () {
      final outline = [
        _FakeOutlineNode(title: 'דף ב.', page: 2),
        _FakeOutlineNode(title: 'דף ג.', page: 3),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels[2], 'דף ב.');
      expect(labels[3], 'דף ג.');
    });

    test('עוברת רקורסיבית על children', () {
      final outline = [
        _FakeOutlineNode(
          title: 'פרק ראשון',
          page: 1,
          children: [
            _FakeOutlineNode(title: 'משנה א', page: 5),
            _FakeOutlineNode(title: 'משנה ב', page: 8),
          ],
        ),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels[1], 'פרק ראשון');
      expect(labels[5], 'משנה א');
      expect(labels[8], 'משנה ב');
    });

    test('כשיש שני nodes על אותו עמוד נשמרת רק התווית הראשונה', () {
      final outline = [
        _FakeOutlineNode(title: 'ראשון', page: 7),
        _FakeOutlineNode(title: 'שני', page: 7),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels[7], 'ראשון');
    });

    test('מתעלם מ-nodes ללא dest', () {
      final outline = [
        _FakeOutlineNode(title: 'אין dest'), // page=null
        _FakeOutlineNode(title: 'יש dest', page: 4),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels.containsKey(4), isTrue);
      expect(labels.length, 1);
    });

    test('מתעלם מ-nodes עם title ריק', () {
      final outline = [
        _FakeOutlineNode(title: '', page: 4),
        _FakeOutlineNode(title: 'תקין', page: 5),
      ];
      final labels = buildPdfPageLabels(outline);
      expect(labels.containsKey(4), isFalse);
      expect(labels[5], 'תקין');
    });
  });

  group('labelForPdfPage', () {
    test('מחזיר את התווית כשהעמוד קיים במפה', () {
      final labels = {2: 'דף ב.', 3: 'דף ג.'};
      expect(labelForPdfPage(labels, 2), 'דף ב.');
      expect(labelForPdfPage(labels, 3), 'דף ג.');
    });

    test('מחזיר את מספר העמוד כשאין תווית', () {
      final labels = {2: 'דף ב.'};
      expect(labelForPdfPage(labels, 5), '5');
    });

    test('מחזיר מספר עבור מפה ריקה', () {
      expect(labelForPdfPage(<int, String>{}, 1), '1');
      expect(labelForPdfPage(<int, String>{}, 100), '100');
    });
  });

  group('computePdfPrintEndPage', () {
    test('מחזיר null כשלא במצב PDF', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: false,
          pdfEndPage: 50,
          totalPdfPages: 100,
        ),
        isNull,
      );
    });

    test('מחזיר null כש-pdfEndPage הוא 0 (לא נקבע)', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 0,
          totalPdfPages: 100,
        ),
        isNull,
      );
    });

    test('מחזיר null כש-pdfEndPage שלילי', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: -3,
          totalPdfPages: 100,
        ),
        isNull,
      );
    });

    test('מחזיר את pdfEndPage כשהוא בתוך טווח המסמך', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 36,
          totalPdfPages: 125,
        ),
        36,
      );
    });

    test('מחזיר את pdfEndPage כשהוא שווה ל-totalPdfPages (העמוד האחרון)', () {
      // הבאג שתוקן: <= במקום <
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 125,
          totalPdfPages: 125,
        ),
        125,
      );
    });

    test('מחזיר null כש-pdfEndPage חורג מ-totalPdfPages', () {
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 200,
          totalPdfPages: 125,
        ),
        isNull,
      );
    });

    test('סומך על pdfEndPage כש-totalPdfPages עדיין 0 (טרם נטען המסמך)', () {
      // נדרש כדי שה-render הראשון ב-initState יצליח לפני שהמסמך נפתח.
      expect(
        computePdfPrintEndPage(
          isPdfMode: true,
          pdfEndPage: 36,
          totalPdfPages: 0,
        ),
        36,
      );
    });
  });

  group('findLastHeaderIndexAtOrBefore', () {
    // helper לבניית רשימת כותרות עם שורות בלבד (level/text אינם משנים פה)
    List<TocEntry> headers(List<int> lineIndices) =>
        lineIndices.map((i) => TocEntry(text: 'h$i', index: i)).toList();

    test('רשימה ריקה מחזירה 0', () {
      expect(findLastHeaderIndexAtOrBefore(const [], 50), 0);
    });

    test('שורה לפני הכותרת הראשונה מחזירה 0', () {
      // כל הכותרות אחרי השורה - fallback לאינדקס 0
      final h = headers([10, 20, 30]);
      expect(findLastHeaderIndexAtOrBefore(h, 5), 0);
    });

    test('שורה בדיוק על כותרת מחזירה את האינדקס שלה', () {
      final h = headers([10, 20, 30]);
      expect(findLastHeaderIndexAtOrBefore(h, 10), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 20), 1);
      expect(findLastHeaderIndexAtOrBefore(h, 30), 2);
    });

    test('שורה באמצע סעיף מחזירה את הכותרת שמעליה', () {
      final h = headers([10, 20, 30]);
      expect(findLastHeaderIndexAtOrBefore(h, 15), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 25), 1);
      expect(findLastHeaderIndexAtOrBefore(h, 100), 2);
    });

    test('כותרת יחידה — תמיד מחזירה 0', () {
      final h = headers([42]);
      expect(findLastHeaderIndexAtOrBefore(h, 0), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 42), 0);
      expect(findLastHeaderIndexAtOrBefore(h, 999), 0);
    });
  });

  group('headerSectionEndLine — סוף סעיף הכותרת כולל את תתי-הכותרות', () {
    // רשימה שטוחה בסדר המסמך, כמו שמסך ההדפסה בונה מעץ תוכן העניינים.
    List<TocEntry> flat(List<(int line, int level)> entries) => [
      for (final (line, level) in entries)
        TocEntry(text: 'h$line', index: line, level: level),
    ];

    test('שורש שם הספר (רמה 0 מהמסד) מכסה את כל הספר', () {
      final h = flat([(0, 0), (1, 1), (16, 1), (36, 1)]);
      expect(headerSectionEndLine(h, 0, 2875), 2875);
    });

    test('פרק עם דפים מסתיים בפרק הבא, לא בדף הראשון שלו', () {
      final h = flat([(1, 1), (2, 2), (10, 2), (30, 1), (31, 2)]);
      expect(headerSectionEndLine(h, 0, 50), 30);
    });

    test('כותרת עלה מסתיימת בכותרת הבאה', () {
      final h = flat([(1, 1), (2, 2), (10, 2), (30, 1), (31, 2)]);
      expect(headerSectionEndLine(h, 1, 50), 10);
      expect(headerSectionEndLine(h, 2, 50), 30);
    });

    test('הכותרת האחרונה מסתיימת בסוף הספר', () {
      final h = flat([(1, 1), (30, 1), (31, 2)]);
      expect(headerSectionEndLine(h, 2, 50), 50);
      expect(headerSectionEndLine(h, 1, 50), 50);
    });
  });

  group('headerSectionEndLine — כותרות משנה מקוננות', () {
    // "הלכות" ברמה 1 וסימניהן ברמה 2; ההורה והסימן הראשון פותחים באותה שורה.
    final alt = [
      TocEntry(text: 'הלכות א', index: 5, level: 1),
      TocEntry(text: 'סימן א', index: 5, level: 2),
      TocEntry(text: 'סימן ב', index: 8, level: 2),
      TocEntry(text: 'הלכות ב', index: 12, level: 1),
      TocEntry(text: 'סימן ג', index: 12, level: 2),
    ];

    test('טווח ה"הלכות" מכסה את כל הסימנים עד ה"הלכות" הבאות', () {
      expect(headerSectionEndLine(alt, 0, 20), 12);
      expect(headerSectionEndLine(alt, 3, 20), 20);
    });

    test('טווח סימן מסתיים בסימן הבא או ב"הלכות" הבאות', () {
      expect(headerSectionEndLine(alt, 1, 20), 8);
      expect(headerSectionEndLine(alt, 2, 20), 12);
    });

    test('buildAltHeaderEntries שומר רמות ומקדים הורה לילד באותה שורה', () {
      final headers = buildAltHeaderEntries([
        (id: 1, parentId: 2, level: 2, lineIndex: 5, text: 'סימן א'),
        (id: 2, parentId: null, level: 1, lineIndex: 5, text: 'הלכות א'),
        (id: 3, parentId: 2, level: 2, lineIndex: 8, text: 'סימן ב'),
      ]);

      expect(
        [for (final h in headers) (h.index, h.level)],
        [
          (5, 1),
          (5, 2),
          (8, 2),
        ],
      );
      expect(headerSectionEndLine(headers, 0, 20), 20);
    });

    test('מבנה שטוח — כל ערך מסתיים בערך הבא', () {
      final flatAlt = [
        TocEntry(text: 'a', index: 0),
        TocEntry(text: 'b', index: 4),
        TocEntry(text: 'c', index: 9),
      ];
      expect(headerSectionEndLine(flatAlt, 0, 20), 4);
      expect(headerSectionEndLine(flatAlt, 2, 20), 20);
    });
  });

  group('hasPdfPageRange', () {
    test('startPage=1 ו-endPage=null → אין טווח', () {
      expect(hasPdfPageRange(startPage: 1, endPage: null), isFalse);
    });

    test('startPage>1 → יש טווח', () {
      expect(hasPdfPageRange(startPage: 2, endPage: null), isTrue);
      expect(hasPdfPageRange(startPage: 100, endPage: null), isTrue);
    });

    test('endPage מוגדר → יש טווח', () {
      expect(hasPdfPageRange(startPage: 1, endPage: 50), isTrue);
    });

    test('שניהם מוגדרים → יש טווח', () {
      expect(hasPdfPageRange(startPage: 30, endPage: 50), isTrue);
    });

    test('טווח עד העמוד האחרון במסמך → אין טווח (issue #1369)', () {
      expect(
        hasPdfPageRange(startPage: 1, endPage: 125, totalPages: 125),
        isFalse,
      );
    });

    test('טווח שנגמר לפני העמוד האחרון → יש טווח', () {
      expect(
        hasPdfPageRange(startPage: 1, endPage: 124, totalPages: 125),
        isTrue,
      );
      expect(
        hasPdfPageRange(startPage: 2, endPage: 125, totalPages: 125),
        isTrue,
      );
    });
  });

  group('pdfPageRangeSummary', () {
    test('עמוד אחד בגיליון — בלי תוספת גיליונות', () {
      expect(
        pdfPageRangeSummary(
          startPage: 1,
          endPage: 4,
          totalPages: 4,
          pagesPerSheet: 1,
        ),
        '4 עמודים מתוך 4',
      );
    });

    test('2 בגיליון — מציג את מספר הגיליונות בפועל (issue #817)', () {
      expect(
        pdfPageRangeSummary(
          startPage: 1,
          endPage: 4,
          totalPages: 4,
          pagesPerSheet: 2,
        ),
        '4 עמודים מתוך 4 (2 גיליונות)',
      );
    });

    test('טווח שאינו מתחלק — מעגל כלפי מעלה', () {
      expect(
        pdfPageRangeSummary(
          startPage: 1,
          endPage: 3,
          totalPages: 4,
          pagesPerSheet: 2,
        ),
        '3 עמודים מתוך 4 (2 גיליונות)',
      );
    });

    test('כל הטווח נכנס בגיליון אחד — לשון יחיד', () {
      expect(
        pdfPageRangeSummary(
          startPage: 3,
          endPage: 4,
          totalPages: 4,
          pagesPerSheet: 4,
        ),
        '2 עמודים מתוך 4 (גיליון אחד)',
      );
    });
  });

  group('buildAltHeaderEntries', () {
    test('דף שחוזר בכמה כרכים מקבל את נתיב האבות, לפי סדר השורות', () {
      final entries = buildAltHeaderEntries([
        (id: 1, parentId: null, level: 0, lineIndex: null, text: 'כרך א'),
        (id: 2, parentId: 1, level: 1, lineIndex: 0, text: 'הקדמה'),
        (id: 3, parentId: 2, level: 2, lineIndex: 0, text: 'דף א.'),
        (id: 4, parentId: null, level: 0, lineIndex: null, text: 'כרך ב'),
        (id: 5, parentId: 4, level: 1, lineIndex: null, text: 'שמות'),
        (id: 6, parentId: 5, level: 2, lineIndex: 90, text: 'דף א.'),
        (id: 7, parentId: 2, level: 2, lineIndex: 40, text: 'דף א:'),
      ]);

      expect(entries.map((e) => e.fullText), [
        'כרך א, הקדמה',
        'כרך א, הקדמה, דף א.',
        'כרך א, הקדמה, דף א:',
        'כרך ב, שמות, דף א.',
      ]);
      expect(entries.map((e) => e.index), [0, 0, 40, 90]);
    });
  });

  group('matchHeaderRange — טווח מתוסף מוצג כבחירת כותרות', () {
    // ספר: כותרת ספר (רמה 1), פרקים (רמה 2), ובפרק א גם כותרות פסוקים (רמה 3)
    final h = [
      TocEntry(text: 'תהילים', index: 0, level: 1),
      TocEntry(text: 'פרק א', index: 1, level: 2),
      TocEntry(text: '{א}', index: 2, level: 3),
      TocEntry(text: '{ב}', index: 4, level: 3),
      TocEntry(text: 'פרק ב', index: 7, level: 2),
      TocEntry(text: 'פרק ג', index: 12, level: 2),
    ];

    test('טווח של פרקים שלמים — מפרק עד פרק', () {
      final m = matchHeaderRange(h, 1, 12, 20);
      expect(m.start, 1);
      expect(m.end, 4); // פרק ב
    });

    test('פרק אחד — אותה כותרת בהתחלה ובסוף, ולא כותרת פסוק', () {
      final m = matchHeaderRange(h, 1, 7, 20);
      expect(m.start, 1);
      expect(m.end, 1);
    });

    test('הפרק האחרון מסתיים בסוף הספר', () {
      final m = matchHeaderRange(h, 12, 20, 20);
      expect(m.start, 5);
      expect(m.end, 5);
    });

    test('גבולות שאינם כותרות — null, והמסך נשאר בעוגני שורות', () {
      final m = matchHeaderRange(h, 3, 9, 20);
      expect(m.start, isNull);
      expect(m.end, isNull);
    });

    test('בלי כותרות — null', () {
      final m = matchHeaderRange(const [], 0, 5, 10);
      expect(m.start, isNull);
      expect(m.end, isNull);
    });
  });

  group('LineCountCache', () {
    test('זהה ל-split(newline).length', () {
      final cache = LineCountCache();
      for (final text in ['', 'א', 'א\nב', '\n', 'א\n\nב\n', '\r\nא']) {
        expect(cache.of(text), text.split('\n').length, reason: text);
      }
    });

    test('מחשב מחדש כשהטקסט מתחלף', () {
      final cache = LineCountCache();
      expect(cache.of('א\nב'), 2);
      expect(cache.of('א\nב\nג'), 3);
      expect(cache.of('א'), 1);
    });

    test('קריאה חוזרת על אותו טקסט אינה מפצלת אותו שוב', () {
      var computations = 0;
      final cache = LineCountCache((text) {
        computations++;
        return text.split('\n').length;
      });
      final text = List.filled(1000, 'בראשית ברא אלהים').join('\n');
      for (var i = 0; i < 100; i++) {
        expect(cache.of(text), 1000);
      }
      expect(computations, 1);
    });
  });
}
