import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

ItemPosition _pos(int index, double leading, double trailing) => ItemPosition(
  index: index,
  itemLeadingEdge: leading,
  itemTrailingEdge: trailing,
);

void main() {
  final normal = buildReadingSegments(
    List.generate(100, (i) => 'שורה $i'),
    continuous: false,
  );
  // פסקה אחת של 10 שורות שוות אורך בין שתי כותרות.
  final paragraph = buildReadingSegments(
    [
      '<h2>א</h2>',
      for (var i = 1; i <= 10; i++) 'שורה מספר ${i.toString().padLeft(2, '0')}',
      '<h2>ב</h2>',
    ],
    continuous: true,
  );

  test('פריט שנגלל כולו מעל החלון אינו המיקום (issue #1358)', () {
    final position = readingPositionFromItems(normal, [
      _pos(0, -2.0, -1.2),
      _pos(37, -0.1, 0.4),
      _pos(38, 0.4, 0.9),
    ]);
    expect(position?.topLine, 37);
  });

  test('שייר הקטע הקודם מעל קו העוגן אינו המיקום (#1974)', () {
    final position = readingPositionFromItems(normal, [
      _pos(9, -0.2, kReadingAnchorAlignment),
      _pos(10, kReadingAnchorAlignment, 0.4),
      _pos(11, 0.4, 0.9),
    ]);
    expect(position?.topLine, 10);
    expect(position?.visibleLines, [10, 11]);
  });

  test('בראש הספר שורה שמעל קו העוגן היא המיקום', () {
    final position = readingPositionFromItems(normal, [
      _pos(0, 0, 0.03),
      _pos(1, 0.03, 0.06),
      _pos(2, 0.06, 0.09),
    ]);
    expect(position?.topLine, 0);
  });

  test('באמצע פסקה המיקום הוא השורה שעל קו העוגן, עם החלק שעבר אותו', () {
    // הפסקה (פריט 1) גבוהה פי 2 מהתצוגה; השורה הרביעית מתחילה בקו העוגן פחות
    // רבע שורה.
    const extent = 2.0;
    const lineExtent = extent / 10;
    const leading = kReadingAnchorAlignment - 3.25 * lineExtent;
    final position = readingPositionFromItems(paragraph, [
      _pos(1, leading, leading + extent),
    ])!;
    expect(position.topLine, 4);
    expect(position.intraLineFraction, closeTo(0.25, 0.05));
  });

  test('העוגן משחזר את אותה נקודה בטקסט', () {
    const extent = 2.0;
    const leading = kReadingAnchorAlignment - 0.65;
    final anchor = readingAnchorFromItems(paragraph, [
      _pos(1, leading, leading + extent),
    ])!;
    expect(anchor.line, 4);
    expect(anchor.alignment, kReadingAnchorAlignment);
    expect(anchor.intraLineFraction, closeTo(0.25, 0.05));
  });

  test('שורה בודדת נמדדת בלי באנר או כרטיס שמגדילים את הפריט', () {
    final single = buildReadingSegments(['פסקה'], continuous: false);
    ({double top, double bottom})? measure(int item, int line) =>
        (top: 0.2, bottom: 0.6);
    final position = _pos(0, -0.55, 1.45);
    final edges = lineEdgesInViewport(single, 0, position, measure: measure);
    expect(edges.leading, closeTo(-0.15, 1e-8));
    expect(edges.trailing, closeTo(0.65, 1e-8));
    final anchor = readingAnchorFromItems(single, [
      position,
    ], measure: measure)!;
    expect(anchor.line, 0);
    expect(anchor.intraLineFraction, closeTo(0.25, 1e-8));
    expect(
      lineFractionInItem(
        single,
        0,
        0,
        intraLineFraction: 0.25,
        measure: measure,
      ),
      closeTo(0.3, 1e-8),
    );
  });

  test('כרטיס מעל שורת טקסט גלויה אינו מחזיק את המיקום בשורה הקודמת', () {
    ({double top, double bottom})? measure(int item, int line) =>
        (top: 0, bottom: item == 1 ? 1 / 6 : 1);
    final positions = [_pos(1, -0.45, 0.15), _pos(2, 0.15, 0.8)];
    final position = readingPositionFromItems(
      normal,
      positions,
      measure: measure,
    )!;
    expect(position.topLine, 2);
    expect(position.visibleLines, [2]);
    expect(
      readingPositionFromItems(normal, [
        positions.first,
      ], measure: measure)!.topLine,
      1,
      reason: 'כשהמסך כולו כרטיס נשמר ההקשר של שורת המקור שלו',
    );
  });

  test('חלון הטעינה כולל פריט בשולי התצוגה שסונן מהשורות הגלויות', () {
    final position = readingPositionFromItems(paragraph, [
      _pos(0, -0.02, 0.02),
      _pos(1, 0.02, 0.98),
      _pos(2, 0.99, 1.2),
    ])!;
    expect(position.visibleLines, isNot(contains(11)));
    expect(position.windowFirstLine, 0);
    expect(position.windowLastLine, 11);
  });
  group('lineCrossingViewportFraction (#4798)', () {
    const line = 1 / 3;

    test('שתי פסקאות ארוכות: נבחרת השנייה כשהיא חוצה את שליש המסך', () {
      final position = lineCrossingViewportFraction(normal, [
        _pos(5, -0.6, 0.3),
        _pos(6, 0.3, 1.4),
      ], line);
      expect(position, 6);
    });

    test('פסקאות קצרות: נבחרת זו שבשליש ולא לפי מספר הגלויות', () {
      // לפי ספירה (שליש מ-8 גלויות) הייתה נבחרת 22.
      final position = lineCrossingViewportFraction(normal, [
        for (var i = 0; i < 6; i++) _pos(20 + i, i * 0.05, (i + 1) * 0.05),
        _pos(26, 0.3, 0.5),
        _pos(27, 0.5, 1),
      ], line);
      expect(position, 26);
    });

    test('פריט שמסתיים בדיוק על הקו אינו חוצה אותו; זה שמתחיל בו — כן', () {
      final position = lineCrossingViewportFraction(normal, [
        _pos(7, 0, line),
        _pos(8, line, 0.9),
      ], line);
      expect(position, 8);
    });

    test('בקריאה רציפה נבחרת שורת המקור שבתוך הפסקה', () {
      // פריט 1 מכסה את שורות 1..10 בשווה: שליש התצוגה נופל בשורה הרביעית.
      final position = lineCrossingViewportFraction(paragraph, [
        _pos(1, 0, 1),
      ], line);
      expect(position, 4);
    });

    test('אין פריט שחוצה את הקו', () {
      expect(
        lineCrossingViewportFraction(normal, [_pos(0, 0, 0.2)], line),
        isNull,
      );
    });
  });
}
