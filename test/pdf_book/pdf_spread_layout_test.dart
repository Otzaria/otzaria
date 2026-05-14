import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_spread_layout.dart';

void main() {
  group('pdfSpreadStartPage', () {
    test('עמוד 1 עומד לבדו', () {
      expect(pdfSpreadStartPage(1), 1);
    });

    test('עמוד 0 או שלילי ממופה ל-1', () {
      expect(pdfSpreadStartPage(0), 1);
      expect(pdfSpreadStartPage(-5), 1);
    });

    test('עמוד זוגי מחזיר את עצמו', () {
      expect(pdfSpreadStartPage(2), 2);
      expect(pdfSpreadStartPage(4), 4);
      expect(pdfSpreadStartPage(10), 10);
    });

    test('עמוד אי-זוגי (>1) מחזיר את העמוד הזוגי שלפניו', () {
      expect(pdfSpreadStartPage(3), 2);
      expect(pdfSpreadStartPage(5), 4);
      expect(pdfSpreadStartPage(11), 10);
    });
  });

  group('pdfSpreadPageRange — תצוגה רגילה', () {
    test('תמיד מחזיר עמוד יחיד', () {
      for (final page in [1, 2, 3, 4, 5, 50]) {
        final range = pdfSpreadPageRange(page, bookView: false);
        expect(range.startPage, page,
            reason: 'startPage should equal page for $page');
        expect(range.endPageExclusive, page + 1,
            reason: 'endPageExclusive should be page+1 for $page');
      }
    });
  });

  group('pdfSpreadPageRange — תצוגת ספר', () {
    test('עמוד 1 עומד לבדו (כריכה)', () {
      final range = pdfSpreadPageRange(1, bookView: true);
      expect(range.startPage, 1);
      expect(range.endPageExclusive, 2);
    });

    test('עמודים 2 ו-3 הם ספירייד אחד', () {
      expect(pdfSpreadPageRange(2, bookView: true),
          (startPage: 2, endPageExclusive: 4));
      expect(pdfSpreadPageRange(3, bookView: true),
          (startPage: 2, endPageExclusive: 4));
    });

    test('עמודים 4 ו-5 הם ספירייד אחד', () {
      expect(pdfSpreadPageRange(4, bookView: true),
          (startPage: 4, endPageExclusive: 6));
      expect(pdfSpreadPageRange(5, bookView: true),
          (startPage: 4, endPageExclusive: 6));
    });

    test('הטווח תמיד מכסה שני עמודים אחרי עמוד 1', () {
      for (final page in [2, 3, 10, 11, 100, 101]) {
        final range = pdfSpreadPageRange(page, bookView: true);
        expect(range.endPageExclusive - range.startPage, 2,
            reason: 'spread for page $page should span 2 pages');
      }
    });
  });

  group('pdfSpreadPageRange — חיתוך לפי totalPages', () {
    test('עמוד אחרון זוגי במסמך עם מספר עמודים זוגי עומד לבדו', () {
      // 10 עמודים: 1, 2+3, 4+5, 6+7, 8+9, 10 (לבדו — אין עמוד 11)
      final range = pdfSpreadPageRange(10, bookView: true, totalPages: 10);
      expect(range.startPage, 10);
      expect(range.endPageExclusive, 11,
          reason: 'must not extend past totalPages');
    });

    test('עמוד 9 ב-9 עמודים מציג ספירייד מלא 8+9', () {
      // 9 עמודים: 1, 2+3, 4+5, 6+7, 8+9
      final range = pdfSpreadPageRange(9, bookView: true, totalPages: 9);
      expect(range.startPage, 8);
      expect(range.endPageExclusive, 10);
    });

    test('עמוד אמצעי לא מושפע מ-totalPages', () {
      final range = pdfSpreadPageRange(4, bookView: true, totalPages: 100);
      expect(range, (startPage: 4, endPageExclusive: 6));
    });

    test('תצוגה רגילה: עמוד אחרון לא חורג מ-totalPages', () {
      final range = pdfSpreadPageRange(10, bookView: false, totalPages: 10);
      expect(range.startPage, 10);
      expect(range.endPageExclusive, 11);
    });

    test('ללא totalPages: התנהגות המקור (ללא חיתוך)', () {
      final range = pdfSpreadPageRange(10, bookView: true);
      expect(range, (startPage: 10, endPageExclusive: 12));
    });
  });

  group('pdfCombineSpreadTitles', () {
    test('שתי כותרות שונות משולבות עם מקף ארוך', () {
      expect(pdfCombineSpreadTitles('פרק א', 'פרק ב'), 'פרק א — פרק ב');
    });

    test('כותרות זהות מחזירות אחת', () {
      expect(pdfCombineSpreadTitles('פרק א', 'פרק א'), 'פרק א');
    });

    test('כותרת ראשונה ריקה — מחזיר את השנייה', () {
      expect(pdfCombineSpreadTitles('', 'פרק ב'), 'פרק ב');
    });

    test('כותרת שנייה ריקה — מחזיר את הראשונה', () {
      expect(pdfCombineSpreadTitles('פרק א', ''), 'פרק א');
    });

    test('שתי כותרות ריקות — מחזיר ריק', () {
      expect(pdfCombineSpreadTitles('', ''), '');
    });
  });
}
