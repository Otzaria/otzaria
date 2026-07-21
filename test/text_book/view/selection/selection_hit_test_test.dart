import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selection_hit_test.dart';

void main() {
  test('לחיצה כפולה מאתרת מילה לפי שורת ה-pointer ולא לפי המופע הראשון', () {
    final result = locateSingleLineSelectionAtPointer(
      renderedLines: const ['מילה בשורה הראשונה', 'כאן מילה מסומנת'],
      sourceIndices: const [10, 11],
      selectedText: 'מילה',
      pointerLineIndex: 11,
      pointerColumn: 5,
    );

    expect(result, (lineIndex: 11, column: 4));
  });

  test('לחיצה כפולה מבדילה בין שני מופעים באותה שורה לפי העמודה', () {
    final result = locateSingleLineSelectionAtPointer(
      renderedLines: const ['מילה ועוד מילה'],
      sourceIndices: const [7],
      selectedText: 'מילה',
      pointerLineIndex: 7,
      pointerColumn: 12,
    );

    expect(result, (lineIndex: 7, column: 10));
  });

  // RichText רחב בשורה אחת: "AAAA BBBB" — "AAAA" בחצי השמאלי, "BBBB" בימני.
  Future<RenderParagraph> pumpRichText(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            // ללא רוחב קבוע — הפסקה מתכווצת לרוחב הטקסט, כך שהמרכז על הזכוכיות.
            child: Text(
              'AAAA BBBB',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderParagraph>(find.byType(RichText));
  }

  testWidgets('edge.full: לחיצה במרכז הטקסט נחשבת על הבחירה', (tester) async {
    final paragraph = await pumpRichText(tester);

    final result = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: tester.getCenter(find.byType(RichText)),
      selectedSegment: 'AAAA BBBB',
      edge: SelectionSegmentEdge.full,
    );

    expect(result, isTrue);
  });

  testWidgets('edge.substring: לחיצה על הקטע המסומן בלבד', (tester) async {
    final paragraph = await pumpRichText(tester);
    final topLeft = tester.getTopLeft(find.byType(RichText));
    final size = tester.getSize(find.byType(RichText));
    final centerY = topLeft.dy + size.height / 2;

    // "AAAA" נמצא ברבע השמאלי — לחיצה שם על הבחירה.
    final onSelection = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.1, centerY),
      selectedSegment: 'AAAA',
      edge: SelectionSegmentEdge.substring,
    );
    expect(
      onSelection,
      isTrue,
      reason: 'לחיצה על "AAAA" המסומן צריכה להיחשב על הבחירה',
    );

    // "BBBB" ברבע הימני — לחיצה שם מחוץ לבחירה ("AAAA" בלבד מסומן).
    final offSelection = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.9, centerY),
      selectedSegment: 'AAAA',
      edge: SelectionSegmentEdge.substring,
    );
    expect(
      offSelection,
      isFalse,
      reason: 'לחיצה על "BBBB" הלא-מסומן צריכה להיחשב מחוץ לבחירה',
    );
  });

  testWidgets('לחיצה מחוץ לכל פסקה מחזירה null (לא הוכרע)', (tester) async {
    final paragraph = await pumpRichText(tester);

    final result = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: const Offset(5, 5), // הפינה — מחוץ לפסקה הממורכזת
      selectedSegment: 'AAAA BBBB',
      edge: SelectionSegmentEdge.full,
    );

    expect(result, isNull);
  });

  testWidgets('edge.substring: קטע שמופיע פעמיים מחזיר null (אי-בהירות)', (
    tester,
  ) async {
    // "BB" מופיע גם ב-"ABBA" וגם ב-"BB" — לא ניתן לדעת על איזה מופע מדובר,
    // ולכן הבדיקה נסוגה לסלחני (null) במקום לבדוק מול המופע השגוי.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'ABBA xx BB',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );

    final result = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: tester.getCenter(find.byType(RichText)),
      selectedSegment: 'BB',
      edge: SelectionSegmentEdge.substring,
    );

    expect(
      result,
      isNull,
      reason: 'מופע כפול ללא רמז — לא ניתן להכריע, חוזרים לסלחני',
    );
  });

  testWidgets('right-click position resolves the second repeated occurrence', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'word xx word',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    final secondBox = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 8, extentOffset: 12),
        )
        .single
        .toRect();

    final start = renderedSelectionStartAtPosition(
      root: paragraph,
      globalPosition: paragraph.localToGlobal(secondBox.center),
      selectedSegment: 'word',
    );

    expect(start, 8);
  });

  testWidgets('edge.substring: רמז מיקום בוחר את המופע הנכון בטקסט חוזר', (
    tester,
  ) async {
    // "BB BB" — שני מופעים. הרמז מצביע על המופע השני (אינדקס 3), והלחיצה על
    // המופע השני (ימני) צריכה להיחשב על הבחירה; על הראשון (שמאלי) — מחוצה לה.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'BB BB',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    final topLeft = tester.getTopLeft(find.byType(RichText));
    final size = tester.getSize(find.byType(RichText));
    final centerY = topLeft.dy + size.height / 2;

    // לחיצה על המופע השני (ימני) — תואם לרמז 3 → על הבחירה.
    final onSecond = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.9, centerY),
      selectedSegment: 'BB',
      edge: SelectionSegmentEdge.substring,
      segmentStartHint: 3,
    );
    expect(
      onSecond,
      isTrue,
      reason: 'הרמז מצביע על המופע השני — לחיצה עליו על הבחירה',
    );

    // לחיצה על המופע הראשון (שמאלי) — מחוץ למופע הנבחר (השני) → מבטל.
    final onFirst = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.1, centerY),
      selectedSegment: 'BB',
      edge: SelectionSegmentEdge.substring,
      segmentStartHint: 3,
    );
    expect(
      onFirst,
      isFalse,
      reason: 'לחיצה על המופע הלא-נבחר (הראשון) צריכה להיחשב מחוץ לבחירה',
    );
  });

  testWidgets('edge.substring: קטע שלא קיים בטקסט מחזיר null', (tester) async {
    final paragraph = await pumpRichText(tester);

    final result = clickIsOnRenderedSelection(
      root: paragraph,
      globalPosition: tester.getCenter(find.byType(RichText)),
      selectedSegment: 'ZZZZ',
      edge: SelectionSegmentEdge.substring,
    );

    expect(
      result,
      isNull,
      reason: 'כשהקטע לא נמצא בפסקה — לא ניתן להכריע, והמתקשר יחזור לסלחני',
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  // clickIsOnSelectionWithinArea — וריאנט פאנל/כרטסיית מפרשים (SelectionArea
  // יחיד, ללא מעקב פר-שורה): מחשב את קטע הבחירה ישירות מתוך הטקסט הנבחר השטוח.
  // ───────────────────────────────────────────────────────────────────────

  testWidgets('within-area: פסקה שכולה בתוך הבחירה — לחיצה במרכז על הבחירה', (
    tester,
  ) async {
    final paragraph = await pumpRichText(tester);

    // הטקסט הנבחר מכיל את כל הפסקה (פסקת ביניים בבחירה רב-פסקתית).
    final result = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: tester.getCenter(find.byType(RichText)),
      selectedText: 'xx AAAA BBBB yy',
    );

    expect(result, isTrue);
  });

  testWidgets('within-area: בחירת קטע בודד — על הקטע true, מחוצה לו false', (
    tester,
  ) async {
    final paragraph = await pumpRichText(tester);
    final topLeft = tester.getTopLeft(find.byType(RichText));
    final size = tester.getSize(find.byType(RichText));
    final centerY = topLeft.dy + size.height / 2;

    final onSelection = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.1, centerY),
      selectedText: 'AAAA',
    );
    expect(onSelection, isTrue, reason: 'לחיצה על "AAAA" המסומן');

    final offSelection = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.9, centerY),
      selectedText: 'AAAA',
    );
    expect(offSelection, isFalse, reason: 'לחיצה על "BBBB" הלא-מסומן');
  });

  testWidgets('within-area: הבחירה מתחילה בפסקה (סיומת) — סיומת מסומנת', (
    tester,
  ) async {
    final paragraph = await pumpRichText(tester);
    final topLeft = tester.getTopLeft(find.byType(RichText));
    final size = tester.getSize(find.byType(RichText));
    final centerY = topLeft.dy + size.height / 2;

    // הבחירה מתחילה ב-"BBBB" בפסקה זו וממשיכה לפסקה הבאה ("CCCC").
    final onSuffix = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.9, centerY),
      selectedText: 'BBBB CCCC',
    );
    expect(onSuffix, isTrue, reason: 'הסיומת "BBBB" מסומנת');

    final offPrefix = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.1, centerY),
      selectedText: 'BBBB CCCC',
    );
    expect(offPrefix, isFalse, reason: '"AAAA" שלפני תחילת הבחירה לא מסומן');
  });

  testWidgets('within-area: הבחירה מסתיימת בפסקה (תחילית) — תחילית מסומנת', (
    tester,
  ) async {
    final paragraph = await pumpRichText(tester);
    final topLeft = tester.getTopLeft(find.byType(RichText));
    final size = tester.getSize(find.byType(RichText));
    final centerY = topLeft.dy + size.height / 2;

    // הבחירה מסתיימת ב-"AAAA" בפסקה זו (התחילה בפסקה קודמת — "ZZZZ").
    final onPrefix = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.1, centerY),
      selectedText: 'ZZZZ AAAA',
    );
    expect(onPrefix, isTrue, reason: 'התחילית "AAAA" מסומנת');

    final offSuffix = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: Offset(topLeft.dx + size.width * 0.9, centerY),
      selectedText: 'ZZZZ AAAA',
    );
    expect(offSuffix, isFalse, reason: '"BBBB" שאחרי סוף הבחירה לא מסומן');
  });

  testWidgets('within-area: לחיצה מחוץ לכל פסקה מחזירה null', (tester) async {
    final paragraph = await pumpRichText(tester);

    final result = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: const Offset(5, 5),
      selectedText: 'AAAA BBBB',
    );

    expect(result, isNull);
  });

  testWidgets('within-area: טקסט נבחר ריק מחזיר false', (tester) async {
    final paragraph = await pumpRichText(tester);

    final result = clickIsOnSelectionWithinArea(
      root: paragraph,
      globalPosition: tester.getCenter(find.byType(RichText)),
      selectedText: '',
    );

    expect(result, isFalse);
  });
}
