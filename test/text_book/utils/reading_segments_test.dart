import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

void main() {
  group('isReadingHeaderLine', () {
    test('מזהה תגי כותרת h1–h6', () {
      for (final tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']) {
        expect(
          isReadingHeaderLine('<$tag>title</$tag>'),
          isTrue,
          reason: 'תג $tag צריך להיחשב ככותרת',
        );
      }
    });

    test('סובלני לרווחים מובילים ול-case-insensitive', () {
      expect(isReadingHeaderLine('  <H2 class="x">פרק</H2>'), isTrue);
    });

    test('שורה רגילה אינה כותרת', () {
      expect(isReadingHeaderLine('בראשית ברא אלהים'), isFalse);
      expect(isReadingHeaderLine('<p>פסקה</p>'), isFalse);
      expect(isReadingHeaderLine('<h7>not a header</h7>'), isFalse);
    });
  });

  group('buildReadingSegments — non-continuous', () {
    test('שורה אחת לכל סגמנט במצב הרגיל', () {
      final lines = ['<h1>פתיחה</h1>', 'שורה א', 'שורה ב', 'שורה ג'];
      final segments = buildReadingSegments(lines, continuous: false);

      expect(segments, hasLength(4));
      for (var i = 0; i < segments.length; i++) {
        expect(segments[i].sourceLineIndices, [i]);
        expect(segments[i].text, lines[i]);
      }
      expect(segments[0].isHeader, isTrue);
      expect(segments[1].isHeader, isFalse);
    });

    test('lineRanges במצב רגיל מכסים את כל השורה', () {
      final lines = ['שורה ראשונה', 'שניה'];
      final segments = buildReadingSegments(lines, continuous: false);

      expect(segments[0].lineRanges, hasLength(1));
      expect(segments[0].lineRanges.first.start, 0);
      expect(segments[0].lineRanges.first.end, lines[0].length);
    });
  });

  group('buildReadingSegments — continuous', () {
    test('שורות לא־כותרת עוקבות מתמזגות לפסקה אחת', () {
      final lines = ['<h1>פרק א</h1>', 'אחת', 'שתיים', 'שלוש'];
      final segments = buildReadingSegments(lines, continuous: true);

      // כותרת בנפרד + פסקה אחת מאוחדת
      expect(segments, hasLength(2));
      expect(segments[0].isHeader, isTrue);
      expect(segments[0].sourceLineIndices, [0]);

      expect(segments[1].isHeader, isFalse);
      expect(segments[1].sourceLineIndices, [1, 2, 3]);
      expect(segments[1].text, 'אחת שתיים שלוש');
    });

    test('כותרת שוברת פסקה רציפה', () {
      final lines = [
        'שורה לפני',
        '<h2>כותרת</h2>',
        'שורה אחרי',
      ];
      final segments = buildReadingSegments(lines, continuous: true);

      expect(segments, hasLength(3));
      expect(segments[0].sourceLineIndices, [0]);
      expect(segments[1].isHeader, isTrue);
      expect(segments[1].sourceLineIndices, [1]);
      expect(segments[2].sourceLineIndices, [2]);
    });

    test('lineRanges פסקאיים מצביעים על מיקום מדויק בטקסט המאוחד', () {
      final lines = ['אאא', 'בבב'];
      final segments = buildReadingSegments(lines, continuous: true);

      expect(segments, hasLength(1));
      final segment = segments.first;
      expect(segment.text, 'אאא בבב');
      // השורה הראשונה היא 0..3, ואז רווח, ואז השורה השניה ב-4..7
      expect(segment.lineRanges[0].start, 0);
      expect(segment.lineRanges[0].end, 3);
      expect(segment.lineRanges[1].start, 4);
      expect(segment.lineRanges[1].end, 7);
    });

    test('שורות ריקות נשמרות כאינדקסים אך מתמזגות', () {
      final lines = ['א', '', 'ג'];
      final segments = buildReadingSegments(lines, continuous: true);

      expect(segments, hasLength(1));
      expect(segments.first.sourceLineIndices, [0, 1, 2]);
    });

    test('שורות לא-טעונות שוברת פסקה ואינן מתמזגות עם תוכן טעון', () {
      final lines = ['', '', 'א', 'ב'];
      final segments = buildReadingSegments(
        lines,
        continuous: true,
        loadedLineFlags: const [false, false, true, true],
      );

      expect(segments, hasLength(2));
      expect(segments[0].isLoaded, isFalse);
      expect(segments[0].sourceLineIndices, [0, 1]);
      expect(segments[1].isLoaded, isTrue);
      expect(segments[1].sourceLineIndices, [2, 3]);
      expect(segments[1].text, 'א ב');
    });

    test('רשימה ריקה לא נופלת', () {
      expect(buildReadingSegments(const [], continuous: true), isEmpty);
      expect(buildReadingSegments(const [], continuous: false), isEmpty);
    });
  });

  group('caching by identity (Expando)', () {
    test('שני קריאות עם אותה רשימה מחזירות את אותו אובייקט', () {
      final lines = ['אחת', 'שתיים'];
      final first = buildReadingSegments(lines, continuous: false);
      final second = buildReadingSegments(lines, continuous: false);
      expect(identical(first, second), isTrue);
    });

    test('cache נפרד בין מצב רציף לרגיל', () {
      final lines = ['אחת', 'שתיים'];
      final lineMode = buildReadingSegments(lines, continuous: false);
      final continuousMode = buildReadingSegments(lines, continuous: true);
      expect(identical(lineMode, continuousMode), isFalse);
      expect(lineMode, hasLength(2));
      expect(continuousMode, hasLength(1));
    });

    test('רשימה חדשה (זהות שונה) מקבלת חישוב חדש', () {
      final a = ['x'];
      final b = ['x'];
      final fromA = buildReadingSegments(a, continuous: false);
      final fromB = buildReadingSegments(b, continuous: false);
      expect(identical(fromA, fromB), isFalse);
    });

    test('loadedLineFlags שונים לא מחזירים cache ישן עבור אותה רשימה', () {
      final lines = ['', 'טעון'];
      final unloaded = buildReadingSegments(
        lines,
        continuous: true,
        loadedLineFlags: const [false, true],
      );
      final loaded = buildReadingSegments(
        lines,
        continuous: true,
        loadedLineFlags: const [true, true],
      );

      expect(unloaded, isNot(same(loaded)));
      expect(unloaded.first.isLoaded, isFalse);
      expect(loaded.first.isLoaded, isTrue);
    });
  });

  group('updateReadingSegmentsForRange', () {
    test('במצב רגיל מעדכן רק את הטווח שנוסף', () {
      final initialLines = ['א', '', ''];
      final initialSegments = buildReadingSegments(
        initialLines,
        continuous: false,
        loadedLineFlags: const [true, false, false],
      );

      final updated = updateReadingSegmentsForRange(
        initialSegments,
        ['א', 'ב', ''],
        loadedLineFlags: const [true, true, false],
        continuous: false,
        startLine: 1,
        endLine: 1,
      );

      expect(updated, hasLength(3));
      expect(updated[0].text, 'א');
      expect(updated[1].text, 'ב');
      expect(updated[2].isLoaded, isFalse);
    });

    test('במצב רציף ממזג מחדש רק את הגבול המקומי סביב הטווח החדש', () {
      final initialSegments = buildReadingSegments(
        ['', '', 'א', 'ב'],
        continuous: true,
        loadedLineFlags: const [false, false, true, true],
      );

      final updated = updateReadingSegmentsForRange(
        initialSegments,
        ['', 'קודם', 'א', 'ב'],
        loadedLineFlags: const [false, true, true, true],
        continuous: true,
        startLine: 1,
        endLine: 1,
      );

      expect(updated, hasLength(2));
      expect(updated[0].isLoaded, isFalse);
      expect(updated[0].sourceLineIndices, [0]);
      expect(updated[1].sourceLineIndices, [1, 2, 3]);
      expect(updated[1].text, 'קודם א ב');
    });

    test('append קדימה במצב רציף שומר סגמנטים קיימים במסלול ללא חפיפה', () {
      final initialSegments = buildReadingSegments(
        ['<h1>כותרת</h1>'],
        continuous: true,
        loadedLineFlags: const [true],
      );

      final updated = updateReadingSegmentsForRange(
        initialSegments,
        ['<h1>כותרת</h1>', 'ג', 'ד'],
        loadedLineFlags: const [true, true, true],
        continuous: true,
        startLine: 1,
        endLine: 2,
      );

      expect(updated, hasLength(2));
      expect(identical(updated.first, initialSegments.first), isTrue);
      expect(updated.last.sourceLineIndices, [1, 2]);
      expect(updated.last.text, 'ג ד');
    });

    test('backfill אחורה במצב רציף שומר prefix unloaded מקומי בלבד', () {
      final initialSegments = buildReadingSegments(
        ['', '', '', '', '', 'א', 'ב'],
        continuous: true,
        loadedLineFlags: const [false, false, false, false, false, true, true],
      );

      final updated = updateReadingSegmentsForRange(
        initialSegments,
        ['', '', '', 'קודם', 'אמצע', 'א', 'ב'],
        loadedLineFlags: const [false, false, false, true, true, true, true],
        continuous: true,
        startLine: 3,
        endLine: 4,
      );

      expect(updated, hasLength(2));
      expect(updated.first.isLoaded, isFalse);
      expect(updated.first.sourceLineIndices, [0, 1, 2]);
      expect(updated.last.isLoaded, isTrue);
      expect(updated.last.sourceLineIndices, [3, 4, 5, 6]);
      expect(updated.last.text, 'קודם אמצע א ב');
    });
  });

  group('segmentIndexForLine', () {
    test('שורה שנמצאת בסגמנט מחזירה את האינדקס שלו', () {
      // continuous: כל שורה לא-כותרת באותה פסקה
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: true);
      // פסקה אחת לכל השורות
      expect(segmentIndexForLine(segments, 0), 0);
      expect(segmentIndexForLine(segments, 1), 0);
      expect(segmentIndexForLine(segments, 2), 0);
    });

    test('עם כותרת — מחזירה סגמנטים שונים', () {
      final segments = buildReadingSegments(
        ['<h1>כותרת</h1>', 'א', 'ב'],
        continuous: true,
      );
      // [header(0), paragraph(1,2)]
      expect(segmentIndexForLine(segments, 0), 0);
      expect(segmentIndexForLine(segments, 1), 1);
      expect(segmentIndexForLine(segments, 2), 1);
    });

    test('שורה לפני הסגמנט הראשון מחזירה 0', () {
      final segments = buildReadingSegments(['א', 'ב'], continuous: false);
      expect(segmentIndexForLine(segments, -5), 0);
    });

    test('שורה מעבר לסוף מחזירה את האחרון', () {
      final segments = buildReadingSegments(['א', 'ב'], continuous: false);
      expect(segmentIndexForLine(segments, 100), 1);
    });

    test('רשימה ריקה — מחזיר 0', () {
      expect(segmentIndexForLine(const [], 5), 0);
    });
  });

  group('lineFractionWithinSegment', () {
    test('שורה ראשונה בפסקה — fraction = 0', () {
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: true);
      expect(lineFractionWithinSegment(segments.first, 0), 0);
    });

    test('שורה אמצעית בפסקה — fraction באמצע', () {
      final segments = buildReadingSegments([
        'א',
        'ב',
        'ג',
        'ד',
      ], continuous: true);
      // הטקסט הממוזג 'א ב ג ד' (7 תווים), שורה 2 מתחילה בתו 4 → 4/7.
      expect(
        lineFractionWithinSegment(segments.first, 2),
        closeTo(4 / 7, 1e-9),
      );
    });

    test('משקל שורה מתעלם מגוף הערת inline ומניקוד', () {
      const noteLine =
          'קצר<sup class="footnote-marker">א</sup>'
          '<i class="footnote">גוף הערה ארוך מאוד שמוסר לחלוטין ברינדור</i>';
      final segments = buildReadingSegments(
        ['אָאָאָאָ', noteLine, 'סוף'],
        continuous: true,
      );
      // תצוגה: 'אָאָאָאָ'=4 graphemes, noteLine='קצרא'=4, ורווח אחרי כל שורה
      // → שורה 2 מתחילה ב-10 מתוך 13.
      expect(
        lineFractionWithinSegment(segments.first, 2),
        closeTo(10 / 13, 1e-9),
      );
    });

    test('שקלול לפי אורך טקסט — שורה ארוכה מזיזה את השורות שאחריה', () {
      final segments = buildReadingSegments(
        ['אאאאאאאאאא', 'ב', 'ג'],
        continuous: true,
      );
      // 'אאאאאאאאאא ב ג' (14 תווים): שורה 1 מתחילה בתו 11 → 11/14,
      // הרבה אחרי 1/3 של חלוקה שווה.
      expect(
        lineFractionWithinSegment(segments.first, 1),
        closeTo(11 / 14, 1e-9),
      );
    });

    test('סגמנט שורה אחת מחזיר 0', () {
      final segments = buildReadingSegments(['א'], continuous: false);
      expect(lineFractionWithinSegment(segments.first, 0), 0);
    });

    test('intraLineFraction בסגמנט שורה אחת — מיקום ההתאמה בפסקה', () {
      final segments = buildReadingSegments(['א'], continuous: false);
      expect(
        lineFractionWithinSegment(segments.first, 0, intraLineFraction: 0.5),
        0.5,
      );
    });

    test('intraLineFraction בפסקה רב-שורתית משוקלל לפי אורך הטקסט', () {
      final segments = buildReadingSegments([
        'א',
        'ב',
        'ג',
        'ד',
      ], continuous: true);
      // 'א ב ג ד' (7 תווים): שורה 2 מתחילה בתו 4, רוחבה (כולל רווח מפריד)
      // 2 תווים, + חצי פנימה → (4 + 1)/7.
      expect(
        lineFractionWithinSegment(segments.first, 2, intraLineFraction: 0.5),
        closeTo(5 / 7, 1e-9),
      );
    });
  });

  group('sourceLineIndicesForSegmentViewports', () {
    test('סגמנט שורה אחת מחזיר את שורת המקור שלו', () {
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: false);
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 1,
            leadingEdge: 0,
            trailingEdge: 0.5,
          ),
        ],
      );
      expect(result, [1]);
    });

    test('סגמנט כותרת — תמיד מחזיר את שורת הכותרת בלי חישוב fraction', () {
      final segments = buildReadingSegments(
        ['<h1>title</h1>', 'a', 'b'],
        continuous: true,
      );
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: -100, // ערכים לא הגיוניים, צריך להתעלם
            trailingEdge: 100,
          ),
        ],
      );
      expect(result, [0]);
    });

    test('סגמנט unloaded גדול מחזיר רק פרוסה מייצגת קטנה', () {
      final segments = buildReadingSegments(
        List<String>.filled(1000, ''),
        continuous: true,
        loadedLineFlags: List<bool>.filled(1000, false),
      );

      final result = sourceLineIndicesForSegmentViewports(
        segments,
        const [
          ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: -10,
            trailingEdge: 10,
          ),
        ],
      );

      expect(result.length, lessThanOrEqualTo(3));
      expect(result.first, greaterThan(0));
      expect(result.last, lessThan(999));
    });

    test('סגמנט רב-שורתי — חישוב fraction מחזיר תת-קבוצה של שורות', () {
      // 4 שורות בפסקה אחת.
      final segments = buildReadingSegments([
        'a',
        'b',
        'c',
        'd',
      ], continuous: true);

      // viewport שמתחיל מעט לפני הסגמנט, מסתיים באמצעו:
      // leadingEdge=0, trailingEdge=1 → extent=1, startFraction=0, endFraction=1
      // → כל השורות צריכות להופיע.
      final all = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
        ],
      );
      expect(all, [0, 1, 2, 3]);
    });

    test('extent לא תקין — נופל ל-startLineIndex', () {
      final segments = buildReadingSegments(['a', 'b', 'c'], continuous: true);
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: 0.5,
            trailingEdge: 0.5, // extent = 0
          ),
        ],
      );
      expect(result, [0]);
    });

    test('אינדקסים מחוץ לטווח מתעלמים בשקט', () {
      final segments = buildReadingSegments(['a'], continuous: false);
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: -1,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
          const ReadingSegmentViewport(
            segmentIndex: 99,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test('isLineRemnant מסנן שורות שנגמרות בקו העוגן בתוך סגמנט ממוזג', () {
      // 10 שורות בפסקה ממוזגת אחת. ניווט לשורה 5 מיישר אותה לקו העוגן
      // (0.05) לפי אותו שקלול שהניווט משתמש בו: הסגמנט תופס extent=1.0.
      final segments = buildReadingSegments(
        List<String>.generate(10, (i) => 'line$i'),
        continuous: true,
      );

      final targetFraction = lineFractionWithinSegment(segments.first, 5);
      final viewport = ReadingSegmentViewport(
        segmentIndex: 0,
        leadingEdge: 0.05 - targetFraction,
        trailingEdge: 0.05 - targetFraction + 1.0,
      );

      // בלי הסינון - שורות שמעל קו העוגן (כולל ריפוד) נכללות ראשונות.
      final unfiltered = sourceLineIndicesForSegmentViewports(segments, [
        viewport,
      ]);
      expect(unfiltered.first, lessThan(5));

      // עם הסינון - השורה שאליה ניווטו היא הראשונה.
      final filtered = sourceLineIndicesForSegmentViewports(
        segments,
        [viewport],
        isLineRemnant: isRemnantAbovePositionAnchor,
      );
      expect(filtered.first, 5);
      expect(filtered, contains(6));
    });

    test('viewports ממספר סגמנטים מחוברים יחד וממוינים', () {
      // 5 שורות: 0=header, 1-2 פסקה ראשונה, 3=header, 4 פסקה שניה
      final segments = buildReadingSegments(
        ['<h1>a</h1>', 'b', 'c', '<h1>d</h1>', 'e'],
        continuous: true,
      );
      // segments: [h(0), p(1,2), h(3), p(4)]
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 1,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
          const ReadingSegmentViewport(
            segmentIndex: 3,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
        ],
      );
      expect(result, [1, 2, 4]);
    });
  });
}
