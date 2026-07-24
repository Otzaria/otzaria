import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

ItemPosition _pos(int index) =>
    ItemPosition(index: index, itemLeadingEdge: 0, itemTrailingEdge: 0);

void main() {
  group('topmostVisibleIndex', () {
    test('מחזיר 0 כשהקולקציה ריקה', () {
      expect(topmostVisibleIndex(const <ItemPosition>[]), 0);
    });

    test('מחזיר את האינדקס היחיד כשיש פריט אחד', () {
      expect(topmostVisibleIndex([_pos(42)]), 42);
    });

    test('מחזיר מינימום כשהפריטים בסדר עולה', () {
      expect(
        topmostVisibleIndex([_pos(10), _pos(11), _pos(12)]),
        10,
      );
    });

    test('מחזיר מינימום גם כשסדר האיטרציה הפוך לאינדקס (הבאג של .first)', () {
      // מדמה את התרחיש הבעייתי: itemPositions הוא Set שסדר ההכנסה שלו
      // אינו תואם לאינדקס. ב-.first נקבל 12, אבל הפריט העליון הוא 10.
      expect(
        topmostVisibleIndex([_pos(12), _pos(11), _pos(10)]),
        10,
      );
    });

    test('מחזיר מינימום בסדר ערבוב כללי', () {
      expect(
        topmostVisibleIndex([_pos(50), _pos(20), _pos(80), _pos(35)]),
        20,
      );
    });

    test('עובד עם אינדקסים שליליים (קצה תיאורטי)', () {
      expect(topmostVisibleIndex([_pos(-1), _pos(0), _pos(1)]), -1);
    });
  });

  group('bottommostVisibleIndex', () {
    test('מחזיר 0 כשהקולקציה ריקה', () {
      expect(bottommostVisibleIndex(const <ItemPosition>[]), 0);
    });

    test('מחזיר את האינדקס היחיד כשיש פריט אחד', () {
      expect(bottommostVisibleIndex([_pos(42)]), 42);
    });

    test('מחזיר מקסימום כשהפריטים בסדר עולה', () {
      expect(
        bottommostVisibleIndex([_pos(10), _pos(11), _pos(12)]),
        12,
      );
    });

    test('מחזיר מקסימום גם כשסדר האיטרציה לא תואם לאינדקס', () {
      // .last יחזיר 10, אבל הפריט התחתון הוא 12.
      expect(
        bottommostVisibleIndex([_pos(12), _pos(11), _pos(10)]),
        12,
      );
    });

    test('מחזיר מקסימום בסדר ערבוב כללי', () {
      expect(
        bottommostVisibleIndex([_pos(50), _pos(20), _pos(80), _pos(35)]),
        80,
      );
    });
  });

  group('עקביות עם ValueNotifier של ItemPositionsListener', () {
    test('עובד על ה-Iterable שמוחזר מ-ItemPositionsListener', () {
      final listener = ItemPositionsListener.create();
      (listener.itemPositions as dynamic).value = [
        _pos(7),
        _pos(5),
        _pos(9),
      ];

      expect(topmostVisibleIndex(listener.itemPositions.value), 5);
      expect(bottommostVisibleIndex(listener.itemPositions.value), 9);
    });
  });

  // ─── תרגום segmentIndex ⇄ source line — קריטי לסימניות, TOC, PDF, deep-links ───
  group('resolveTopmostSourceLine', () {
    test('מצב רגיל — מחזיר את ה-itemIndex המינימלי (זהה לשורת מקור)', () {
      // segments[i].startLineIndex == i במצב הרגיל.
      final segments = buildReadingSegments([
        'א',
        'ב',
        'ג',
        'ד',
      ], continuous: false);
      expect(
        resolveTopmostSourceLine(
          positions: [_pos(2), _pos(3)],
          continuousReadingMode: false,
          readingSegments: segments,
        ),
        2,
      );
    });

    test('מצב רצף — מתרגם segmentIndex לשורת מקור הראשונה של הפסקה', () {
      // ['<h1>x</h1>', 'a', 'b', 'c', 'd'] במצב רצף:
      //   segment 0 = header (line 0)
      //   segment 1 = paragraph (lines 1-4)
      final segments = buildReadingSegments(
        ['<h1>x</h1>', 'a', 'b', 'c', 'd'],
        continuous: true,
      );
      // segmentIndex 1 → startLineIndex = 1 (לא 1 בכל מקרה - כאן זה צירוף מקרים).
      expect(
        resolveTopmostSourceLine(
          positions: [_pos(1)],
          continuousReadingMode: true,
          readingSegments: segments,
        ),
        1,
      );
    });

    test('מצב רצף עם פסקאות נפרדות — segmentIndex≠sourceLineIndex', () {
      // ['<h1>x</h1>', 'a', '<h1>y</h1>', 'b', 'c']
      //   seg 0 = header (line 0)
      //   seg 1 = 'a' (line 1)
      //   seg 2 = header (line 2)
      //   seg 3 = paragraph (lines 3-4)
      final segments = buildReadingSegments(
        ['<h1>x</h1>', 'a', '<h1>y</h1>', 'b', 'c'],
        continuous: true,
      );
      // segmentIndex 3 → startLineIndex = 3.
      expect(
        resolveTopmostSourceLine(
          positions: [_pos(3)],
          continuousReadingMode: true,
          readingSegments: segments,
        ),
        3,
      );
    });

    test('positions ריק → 0', () {
      expect(
        resolveTopmostSourceLine(
          positions: const <ItemPosition>[],
          continuousReadingMode: true,
          readingSegments: const [],
        ),
        0,
      );
    });

    test('continuous=true אבל segments ריק → fallback להתנהגות הרגילה', () {
      // הגנה: אם השדה לא חושב עדיין, לא רוצים לחזור 0 בטעות.
      expect(
        resolveTopmostSourceLine(
          positions: [_pos(5)],
          continuousReadingMode: true,
          readingSegments: const [],
        ),
        5,
      );
    });

    test('segmentIndex מחוץ לטווח של segments → 0 (הגנה)', () {
      final segments = buildReadingSegments(['א'], continuous: true);
      expect(
        resolveTopmostSourceLine(
          positions: [_pos(99)],
          continuousReadingMode: true,
          readingSegments: segments,
        ),
        0,
      );
    });

    test('positions לא ממוין — בוחר את ה-segmentIndex המינימלי', () {
      // הבאג של .first: ב-itemPositions הוא Set שסדר ההכנסה שלו לא בהכרח
      // מסכים עם האינדקס. בלי .reduce(min), קוראים סגמנט שגוי.
      final segments = buildReadingSegments(
        ['<h1>x</h1>', 'a', 'b', 'c'],
        continuous: true,
      );
      expect(
        resolveTopmostSourceLine(
          positions: [_pos(1), _pos(0)],
          continuousReadingMode: true,
          readingSegments: segments,
        ),
        0,
      );
    });
  });

  group('resolveBottommostSourceLine', () {
    test('מצב רגיל — מחזיר את ה-itemIndex המקסימלי', () {
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: false);
      expect(
        resolveBottommostSourceLine(
          positions: [_pos(0), _pos(1), _pos(2)],
          continuousReadingMode: false,
          readingSegments: segments,
        ),
        2,
      );
    });

    test('מצב רצף — מחזיר את שורת המקור האחרונה של הפסקה האחרונה הנראית', () {
      // ['a', 'b', 'c'] במצב רצף → פסקה אחת [0,1,2].
      // segmentIndex 0 → sourceLineIndices.last = 2.
      final segments = buildReadingSegments(['a', 'b', 'c'], continuous: true);
      expect(
        resolveBottommostSourceLine(
          positions: [_pos(0)],
          continuousReadingMode: true,
          readingSegments: segments,
        ),
        2,
      );
    });

    test('positions ריק → 0', () {
      expect(
        resolveBottommostSourceLine(
          positions: const <ItemPosition>[],
          continuousReadingMode: true,
          readingSegments: const [],
        ),
        0,
      );
    });
  });

  group('resolveItemIndexForSourceLine', () {
    test('segments ריק → מחזיר את שורת המקור (אין מה לתרגם)', () {
      expect(
        resolveItemIndexForSourceLine(
          lineIndex: 7,
          readingSegments: const [],
        ),
        7,
      );
    });

    test('מצב רגיל — שורה N היא segmentIndex N', () {
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: false);
      expect(
        resolveItemIndexForSourceLine(
          lineIndex: 1,
          readingSegments: segments,
        ),
        1,
      );
    });

    test('מצב רצף — שורות בפסקה מתרגמות לאותו segmentIndex', () {
      // ['<h1>x</h1>', 'a', 'b', 'c']
      //   seg 0 = header (line 0)
      //   seg 1 = paragraph (lines 1, 2, 3)
      final segments = buildReadingSegments(
        ['<h1>x</h1>', 'a', 'b', 'c'],
        continuous: true,
      );
      expect(
        resolveItemIndexForSourceLine(lineIndex: 1, readingSegments: segments),
        1,
      );
      expect(
        resolveItemIndexForSourceLine(lineIndex: 2, readingSegments: segments),
        1,
      );
      expect(
        resolveItemIndexForSourceLine(lineIndex: 3, readingSegments: segments),
        1,
      );
    });

    test('שורה שתואמת כותרת — מקבלת את segmentIndex של הכותרת', () {
      final segments = buildReadingSegments(
        ['<h1>x</h1>', 'a', 'b'],
        continuous: true,
      );
      expect(
        resolveItemIndexForSourceLine(lineIndex: 0, readingSegments: segments),
        0,
      );
    });
  });
}
