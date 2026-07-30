import 'dart:ui';

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

    test('ללא עמוד שער — הזוגות הם (1,2), (3,4)', () {
      expect(pdfSpreadStartPage(1, coverPage: false), 1);
      expect(pdfSpreadStartPage(2, coverPage: false), 1);
      expect(pdfSpreadStartPage(3, coverPage: false), 3);
      expect(pdfSpreadStartPage(4, coverPage: false), 3);
      expect(pdfSpreadStartPage(10, coverPage: false), 9);
      expect(pdfSpreadStartPage(0, coverPage: false), 1);
    });
  });

  group('pdfNextSpreadFocusPage', () {
    test('מהכריכה — לעמוד 2 (הימני של הזוג הראשון)', () {
      expect(pdfNextSpreadFocusPage(1, 10), 2);
    });

    test('מזוג פנימי — לעמוד הימני של הזוג הבא, גם כשהנוכחי הוא השמאלי', () {
      expect(pdfNextSpreadFocusPage(2, 10), 4);
      expect(pdfNextSpreadFocusPage(3, 10), 4);
      expect(pdfNextSpreadFocusPage(5, 10), 6);
    });

    test('אין זוג הבא — null', () {
      expect(pdfNextSpreadFocusPage(10, 10), isNull);
      expect(pdfNextSpreadFocusPage(11, 11), isNull);
      expect(pdfNextSpreadFocusPage(10, 11), isNull);
    });

    test('זוג אחרון בעל עמוד יחיד עדיין נגיש', () {
      expect(pdfNextSpreadFocusPage(8, 10), 10);
    });

    test('ללא עמוד שער — מהזוג (1,2) לעמוד 3', () {
      expect(pdfNextSpreadFocusPage(1, 10, coverPage: false), 3);
      expect(pdfNextSpreadFocusPage(2, 10, coverPage: false), 3);
      expect(pdfNextSpreadFocusPage(4, 10, coverPage: false), 5);
      expect(pdfNextSpreadFocusPage(9, 10, coverPage: false), isNull);
    });
  });

  group('pdfPreviousSpreadFocusPage', () {
    test('מהזוג הראשון — חזרה לכריכה', () {
      expect(pdfPreviousSpreadFocusPage(2), 1);
      expect(pdfPreviousSpreadFocusPage(3), 1);
    });

    test('מזוג פנימי — לעמוד השמאלי (השני) של הזוג הקודם', () {
      expect(pdfPreviousSpreadFocusPage(4), 3);
      expect(pdfPreviousSpreadFocusPage(5), 3);
      expect(pdfPreviousSpreadFocusPage(10), 9);
    });

    test('מהכריכה — null', () {
      expect(pdfPreviousSpreadFocusPage(1), isNull);
      expect(pdfPreviousSpreadFocusPage(0), isNull);
    });

    test('ללא עמוד שער — מהזוג הראשון null, מזוג פנימי לעמוד השמאלי הקודם', () {
      expect(pdfPreviousSpreadFocusPage(1, coverPage: false), isNull);
      expect(pdfPreviousSpreadFocusPage(2, coverPage: false), isNull);
      expect(pdfPreviousSpreadFocusPage(3, coverPage: false), 2);
      expect(pdfPreviousSpreadFocusPage(6, coverPage: false), 4);
    });
  });

  group('pdfSpreadPageRange — תצוגה רגילה', () {
    test('תמיד מחזיר עמוד יחיד', () {
      for (final page in [1, 2, 3, 4, 5, 50]) {
        final range = pdfSpreadPageRange(page, bookView: false);
        expect(
          range.startPage,
          page,
          reason: 'startPage should equal page for $page',
        );
        expect(
          range.endPageExclusive,
          page + 1,
          reason: 'endPageExclusive should be page+1 for $page',
        );
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
      expect(pdfSpreadPageRange(2, bookView: true), (
        startPage: 2,
        endPageExclusive: 4,
      ));
      expect(pdfSpreadPageRange(3, bookView: true), (
        startPage: 2,
        endPageExclusive: 4,
      ));
    });

    test('עמודים 4 ו-5 הם ספירייד אחד', () {
      expect(pdfSpreadPageRange(4, bookView: true), (
        startPage: 4,
        endPageExclusive: 6,
      ));
      expect(pdfSpreadPageRange(5, bookView: true), (
        startPage: 4,
        endPageExclusive: 6,
      ));
    });

    test('הטווח תמיד מכסה שני עמודים אחרי עמוד 1', () {
      for (final page in [2, 3, 10, 11, 100, 101]) {
        final range = pdfSpreadPageRange(page, bookView: true);
        expect(
          range.endPageExclusive - range.startPage,
          2,
          reason: 'spread for page $page should span 2 pages',
        );
      }
    });

    test('ללא עמוד שער — עמודים 1 ו-2 הם ספירייד אחד', () {
      for (final page in [1, 2]) {
        expect(pdfSpreadPageRange(page, bookView: true, coverPage: false), (
          startPage: 1,
          endPageExclusive: 3,
        ));
      }
      expect(pdfSpreadPageRange(4, bookView: true, coverPage: false), (
        startPage: 3,
        endPageExclusive: 5,
      ));
    });

    test('ללא עמוד שער — עמוד אחרון אי-זוגי נחתך לגבול המסמך', () {
      final range = pdfSpreadPageRange(
        9,
        bookView: true,
        coverPage: false,
        totalPages: 9,
      );
      expect(range, (startPage: 9, endPageExclusive: 10));
    });
  });

  group('pdfSpreadPageRange — חיתוך לפי totalPages', () {
    test('עמוד אחרון זוגי במסמך עם מספר עמודים זוגי עומד לבדו', () {
      // 10 עמודים: 1, 2+3, 4+5, 6+7, 8+9, 10 (לבדו — אין עמוד 11)
      final range = pdfSpreadPageRange(10, bookView: true, totalPages: 10);
      expect(range.startPage, 10);
      expect(
        range.endPageExclusive,
        11,
        reason: 'must not extend past totalPages',
      );
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

  group('pdfTextLineRangeForPageRange — טווח הקישורים של הספירייד', () {
    Future<
      ({
        ({int startPage, int endPageExclusive}) range,
        List<int> calls,
        ({int start, int? end})? lines,
      })
    >
    resolve({
      required int page,
      required bool bookView,
      int? totalPages,
      int? Function(int page)? mapper,
      bool Function()? isActive,
    }) async {
      final range = pdfSpreadPageRange(
        page,
        bookView: bookView,
        totalPages: totalPages,
      );
      final calls = <int>[];
      final lines = await pdfTextLineRangeForPageRange(
        startPage: range.startPage,
        endPageExclusive: range.endPageExclusive,
        resolveTextIndex: (pdfPage) async {
          calls.add(pdfPage);
          return mapper == null ? pdfPage * 10 : mapper(pdfPage);
        },
        isActive: isActive,
      );
      return (range: range, calls: calls, lines: lines);
    }

    test('תצוגה רגילה בעמוד 201 ממפה עמוד אחד בלבד עד גבול 202', () async {
      final result = await resolve(page: 201, bookView: false);

      expect(result.range, (startPage: 201, endPageExclusive: 202));
      expect(result.calls, [201, 202]);
      expect(result.lines, (start: 2011, end: 2020));
    });

    test('תצוגת ספר בעמוד 201 ממפה את שני העמודים 200–201', () async {
      final result = await resolve(page: 201, bookView: true);

      expect(result.range, (startPage: 200, endPageExclusive: 202));
      expect(result.calls, [200, 202]);
      expect(result.lines, (start: 2001, end: 2020));
    });

    test('עמוד 200 ועמוד 201 מפיקים בדיוק אותו טווח שורות', () async {
      final even = await resolve(page: 200, bookView: true);
      final odd = await resolve(page: 201, bookView: true);

      expect(even.range, odd.range);
      expect(even.lines, odd.lines);
      expect(even.calls, [200, 202]);
      expect(odd.calls, [200, 202]);
    });

    test('הזוג הראשון 2–3 משתמש בגבול עמוד 4', () async {
      final result = await resolve(page: 3, bookView: true);

      expect(result.calls, [2, 4]);
      expect(result.lines, (start: 21, end: 40));
    });

    test('עמוד הכריכה 1 נשאר טווח של עמוד יחיד', () async {
      final result = await resolve(page: 1, bookView: true);

      expect(result.calls, [1, 2]);
      expect(result.lines, (start: 11, end: 20));
    });

    test('עמוד אחרון זוגי ללא בן זוג נחתך לגבול המסמך', () async {
      final result = await resolve(
        page: 202,
        bookView: true,
        totalPages: 202,
      );

      expect(result.range, (startPage: 202, endPageExclusive: 203));
      expect(result.calls, [202, 203]);
      expect(result.lines, (start: 2021, end: 2030));
    });

    test('מיפוי חסר בגבול ההתחלה מחזיר null ולא מבקש את גבול הסיום', () async {
      final result = await resolve(
        page: 201,
        bookView: true,
        mapper: (page) => page == 200 ? null : page * 10,
      );

      expect(result.calls, [200]);
      expect(result.lines, isNull);
    });

    test('מיפוי חסר בגבול הסיום שומר את ההתחלה עם end=null', () async {
      final result = await resolve(
        page: 201,
        bookView: true,
        mapper: (page) => page == 202 ? null : page * 10,
      );

      expect(result.calls, [200, 202]);
      expect(result.lines, (start: 2001, end: null));
    });

    test('מסך שנסגר אחרי מיפוי ההתחלה לא מפעיל מיפוי נוסף', () async {
      final result = await resolve(
        page: 201,
        bookView: true,
        isActive: () => false,
      );

      expect(result.calls, [200]);
      expect(result.lines, (start: 2001, end: null));
    });
  });

  group('pdfTopmostVisiblePage', () {
    // פריסה אנכית: 3 עמודים בגובה 800 עם רווח 4 ביניהם.
    final pageRects = <Rect>[
      const Rect.fromLTWH(0, 0, 500, 800), // עמוד 1: 0–800
      const Rect.fromLTWH(0, 804, 500, 800), // עמוד 2: 804–1604
      const Rect.fromLTWH(0, 1608, 500, 800), // עמוד 3: 1608–2408
    ];
    Rect viewportAt(double top) => Rect.fromLTWH(0, top, 500, 600);

    test('בראש עמוד 2 מחזיר 2 (לא את הקודם)', () {
      expect(pdfTopmostVisiblePage(viewportAt(804), pageRects), 2);
    });

    test('בתחתית עמוד 2 עדיין מחזיר 2', () {
      expect(pdfTopmostVisiblePage(viewportAt(1004), pageRects), 2);
    });

    test('בתוך הרווח שמעל עמוד 2 מחזיר 2', () {
      expect(pdfTopmostVisiblePage(viewportAt(802), pageRects), 2);
    });

    test('בתוך עמוד 1 מחזיר 1', () {
      expect(pdfTopmostVisiblePage(viewportAt(750), pageRects), 1);
    });

    test('גלילה מעל ראש המסמך מחזירה 1', () {
      expect(pdfTopmostVisiblePage(viewportAt(-50), pageRects), 1);
    });

    test('גלילה מעבר לעמוד האחרון מחזירה את העמוד האחרון', () {
      expect(pdfTopmostVisiblePage(viewportAt(5000), pageRects), 3);
    });

    test('רשימת עמודים ריקה מחזירה null', () {
      expect(pdfTopmostVisiblePage(viewportAt(0), const []), isNull);
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

  group('pdfSplitSpreadTitleByKnown', () {
    test('כותרת משולבת מפוצלת לשתי כותרות קיימות', () {
      final split = pdfSplitSpreadTitleByKnown('פרק א — פרק ב', {
        'פרק א',
        'פרק ב',
      });
      expect(split, (first: 'פרק א', second: 'פרק ב'));
    });

    test('round-trip עם pdfCombineSpreadTitles', () {
      final combined = pdfCombineSpreadTitles('ברכות ב.', 'ברכות ב:');
      final split = pdfSplitSpreadTitleByKnown(combined, {
        'ברכות ב.',
        'ברכות ב:',
      });
      expect(split, (first: 'ברכות ב.', second: 'ברכות ב:'));
    });

    test('כותרת עמוד יחיד (ללא מפריד) מחזירה null', () {
      expect(pdfSplitSpreadTitleByKnown('פרק א', {'פרק א'}), isNull);
    });

    test('כותרת חוקית שמכילה מקף — חלקיה אינם כותרות — מחזירה null', () {
      expect(pdfSplitSpreadTitleByKnown('שער — מבוא', {'שער — מבוא'}), isNull);
    });

    test('כותרת ראשונה המכילה מקף מתפצלת במקום הנכון', () {
      // "שער — מבוא" היא כותרת קיימת, "פרק א" כותרת קיימת — הספירייד ביניהן.
      final split = pdfSplitSpreadTitleByKnown('שער — מבוא — פרק א', {
        'שער — מבוא',
        'פרק א',
      });
      expect(split, (first: 'שער — מבוא', second: 'פרק א'));
    });
  });
}
