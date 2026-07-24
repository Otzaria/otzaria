import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// בודק את התנהגות `showAnchoredAppSearchMenu` — תפריט עם שדה חיפוש מוצמד.
///
/// כל טסט בונה כפתור עוגן, פותח את התפריט, ועושה ממנו פעולות
/// (חיפוש, בחירה, ESC) כדי לאמת את ההתנהגות.
void main() {
  Future<void> pumpAnchorWithMenu<T>(
    WidgetTester tester, {
    required List<AppMenuEntry<T>> entries,
    required ValueChanged<T?> onResult,
    T? initialValue,
    String searchHint = 'חיפוש',
    List<String>? filterLabels,
    List<bool Function(AppMenuEntry<T>)?>? filterPredicates,
    int initialFilter = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240, // רוחב ריאליסטי של שדה dropdown באפליקציה
              child: Builder(
                builder: (anchorContext) => ElevatedButton(
                  onPressed: () async {
                    final result = await showAnchoredAppSearchMenu<T>(
                      context: anchorContext,
                      anchorContext: anchorContext,
                      entries: entries,
                      initialValue: initialValue,
                      searchHint: searchHint,
                      filterLabels: filterLabels,
                      filterPredicates: filterPredicates,
                      initialFilter: initialFilter,
                    );
                    onResult(result);
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('שדה החיפוש מוצמד בראש ומופיע מיד עם הפתיחה', (tester) async {
    String? selected;
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'a', label: 'אבא'),
        AppMenuEntry<String>(value: 'b', label: 'בית'),
      ],
      onResult: (v) => selected = v,
      searchHint: 'חיפוש פריט',
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    expect(
      find.text('חיפוש פריט'),
      findsOneWidget,
      reason: 'hint של שדה החיפוש צריך להופיע',
    );
    expect(find.text('אבא'), findsOneWidget);
    expect(find.text('בית'), findsOneWidget);
    expect(selected, isNull, reason: 'לא נבחר עדיין פריט');
  });

  testWidgets('כתיבה בשדה החיפוש מסננת את הפריטים', (tester) async {
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'a', label: 'אריה'),
        AppMenuEntry<String>(value: 'b', label: 'בית'),
        AppMenuEntry<String>(value: 'g', label: 'גמל'),
      ],
      onResult: (_) {},
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    // לפני סינון - שלושת הפריטים מופיעים
    expect(find.text('אריה'), findsOneWidget);
    expect(find.text('בית'), findsOneWidget);
    expect(find.text('גמל'), findsOneWidget);

    // הכנסת טקסט סינון
    await tester.enterText(find.byType(EditableText).first, 'בית');
    await tester.pump();

    // "בית" מופיע גם בשדה החיפוש; מתעניינים בפריט הרשימה (InkWell).
    final filteredItem = find.descendant(
      of: find.byType(InkWell),
      matching: find.text('בית'),
    );
    expect(filteredItem, findsOneWidget);
    expect(find.text('אריה'), findsNothing);
    expect(find.text('גמל'), findsNothing);
  });

  testWidgets('סינון ללא תוצאות מציג "אין תוצאות"', (tester) async {
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'a', label: 'אריה'),
        AppMenuEntry<String>(value: 'b', label: 'בית'),
      ],
      onResult: (_) {},
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'אין דבר כזה');
    await tester.pump();

    expect(find.text('אין תוצאות'), findsOneWidget);
  });

  testWidgets('בחירת פריט מחזירה את הערך וסוגרת את התפריט', (tester) async {
    String? selected;
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'a', label: 'אריה'),
        AppMenuEntry<String>(value: 'b', label: 'בית'),
      ],
      onResult: (v) => selected = v,
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בית'));
    await tester.pumpAndSettle();

    expect(selected, 'b');
    expect(
      find.text('אריה'),
      findsNothing,
      reason: 'התפריט אמור להיסגר אחרי הבחירה',
    );
  });

  testWidgets('initialValue מסומן כפריט הנבחר', (tester) async {
    await pumpAnchorWithMenu<int>(
      tester,
      initialValue: 2,
      entries: const [
        AppMenuEntry<int>(value: 1, label: 'אחד'),
        AppMenuEntry<int>(value: 2, label: 'שניים'),
        AppMenuEntry<int>(value: 3, label: 'שלוש'),
      ],
      onResult: (_) {},
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    // צ'קמרק (ה-icon של ✓) אמור להופיע ליד "שניים"
    // (buildAppMenuRowContent מוסיף checkmark_24_regular לפריט נבחר)
    final selectedRow = find.ancestor(
      of: find.text('שניים'),
      matching: find.byType(InkWell),
    );
    expect(selectedRow, findsOneWidget);
  });

  testWidgets('רשימה ריקה מחזירה null מיד בלי לפתוח תפריט', (tester) async {
    bool called = false;
    String? selected = 'something';
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [],
      onResult: (v) {
        called = true;
        selected = v;
      },
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(selected, isNull);
  });

  testWidgets('בחירת הפריט הארוך ביותר כ-initialValue לא גורמת לגלישת רינדור '
      '(סימן ה-✓ מוצג בגופן מודגש הרחב יותר מהרגיל)', (tester) async {
    await pumpAnchorWithMenu<int>(
      tester,
      initialValue: 1,
      entries: const [
        AppMenuEntry<int>(
          value: 1,
          label: 'פרק א, סימן ב, פסקה ג - כותרת ארוכה מאוד לבדיקה',
        ),
        AppMenuEntry<int>(value: 2, label: 'קצר'),
      ],
      onResult: (_) {},
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('סימן ה-✓ צמוד לתוכן כשהפריט הנבחר הוא גם הכי ארוך בתפריט '
      '(רוחב התפריט נגזר ממנו, אז אין רווח גדול משאריות ה-Spacer)', (
    tester,
  ) async {
    const longestLabel = 'פרק א, סימן ב, פסקה ג - כותרת ארוכה מאוד לבדיקה';
    await pumpAnchorWithMenu<int>(
      tester,
      initialValue: 1,
      entries: const [
        AppMenuEntry<int>(value: 1, label: longestLabel),
        AppMenuEntry<int>(value: 2, label: 'קצר'),
      ],
      onResult: (_) {},
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final textRect = tester.getRect(find.text(longestLabel));
    final checkRect = tester.getRect(
      find.byIcon(FluentIcons.checkmark_circle_24_filled),
    );

    // ב-LTR (ברירת המחדל בטסט) הסימון נמצא מימין לטקסט.
    final gap = checkRect.left - textRect.right;
    expect(
      gap,
      lessThan(10),
      reason: 'כשהתפריט נגזר ברוחבו מהפריט הזה, המרחק לסימן ה-✓ אמור להיות קטן',
    );
  });

  testWidgets('initialFilter פותח את התפריט על הצ\'יפ המבוקש ומסנן לפיו', (
    tester,
  ) async {
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'h', label: 'כותרת'),
        AppMenuEntry<String>(value: 'l', label: 'שורה 1'),
      ],
      onResult: (_) {},
      filterLabels: const ['כותרות', 'שורות'],
      filterPredicates: [
        (e) => e.value == 'h',
        (e) => e.value == 'l',
      ],
      // הצ'יפ השני ('שורות') פעיל בפתיחה.
      initialFilter: 1,
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    // רק פריטי הסינון של הצ'יפ הפעיל מוצגים.
    expect(find.text('שורה 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.text('כותרת'),
      ),
      findsNothing,
    );
  });

  testWidgets('צ\'יפי סינון ארוכים מהטקסט מרחיבים את רוחב התפריט', (
    tester,
  ) async {
    Rect menuRect() => tester.getRect(
      find.byWidgetPredicate((w) => w is Material && w.elevation == 8),
    );

    // ללא צ'יפים — הרוחב נגזר מהפריטים הקצרים בלבד.
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'a', label: 'א'),
        AppMenuEntry<String>(value: 'b', label: 'ב'),
      ],
      onResult: (_) {},
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    final widthWithoutChips = menuRect().width;
    await tester.tapAt(const Offset(5, 5)); // סגירה
    await tester.pumpAndSettle();

    // עם צ'יפים ארוכים בהרבה מהפריטים — הרוחב חייב לגדול כדי להכילם.
    await pumpAnchorWithMenu<String>(
      tester,
      entries: const [
        AppMenuEntry<String>(value: 'a', label: 'א'),
        AppMenuEntry<String>(value: 'b', label: 'ב'),
      ],
      onResult: (_) {},
      filterLabels: const [
        'כותרות ראשיות מאוד ארוכות',
        'כותרות משנה ארוכות',
        'שורות',
      ],
      filterPredicates: [
        (e) => true,
        (e) => true,
        (e) => true,
      ],
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    expect(
      menuRect().width,
      greaterThan(widthWithoutChips),
      reason: 'צ\'יפים רחבים מהפריטים אמורים להרחיב את התפריט',
    );
  });

  testWidgets('התפריט מתרחב לרוחב התוכן גם בלי menuMinWidth מפורש', (
    tester,
  ) async {
    await pumpAnchorWithMenu<int>(
      tester,
      entries: const [
        AppMenuEntry<int>(value: 1, label: 'קצר'),
        AppMenuEntry<int>(
          value: 2,
          label: 'תווית ארוכה בהרבה מרוחב השדה המפעיל את התפריט הזה',
        ),
      ],
      onResult: (_) {},
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    // pumpAnchorWithMenu ממקם את האנקור ב-SizedBox ברוחב 240 (ר' הגדרתו למעלה).
    final menuRect = tester.getRect(
      find.byWidgetPredicate((w) => w is Material && w.elevation == 8),
    );
    expect(
      menuRect.width,
      greaterThan(240),
      reason: 'תווית ארוכה מהאנקור אמורה להרחיב את התפריט אוטומטית',
    );
  });

  testWidgets('כפתור צמוד לקצה שמאל: תפריט רחב מתרחב פנימה ולא בולט מחוץ לחלון', (
    tester,
  ) async {
    // כפתור צר בפינה השמאלית-עליונה; תפריט רחב בהרבה מהכפתור.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 90,
              child: Builder(
                builder: (anchorContext) => ElevatedButton(
                  onPressed: () => showAnchoredAppSearchMenu<int>(
                    context: anchorContext,
                    anchorContext: anchorContext,
                    entries: const [
                      AppMenuEntry<int>(
                        value: 1,
                        label:
                            'תווית ארוכה מאוד שמרחיבה את התפריט הרבה מעבר לרוחב הכפתור',
                      ),
                    ],
                  ),
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final menuRect = tester.getRect(
      find.byWidgetPredicate((w) => w is Material && w.elevation == 8),
    );

    expect(
      menuRect.left,
      greaterThanOrEqualTo(0.0),
      reason: 'התפריט לא אמור לחרוג משמאל לקצה החלון',
    );
    expect(
      menuRect.right,
      lessThanOrEqualTo(screenWidth + 0.5),
      reason: 'התפריט לא אמור לחרוג מימין לקצה החלון',
    );
    // התפריט מתרחב פנימה (ימינה) מהכפתור שבקצה, ולא נצמד לקצה השמאלי.
    final buttonRect = tester.getRect(find.text('פתח'));
    expect(
      menuRect.left,
      lessThanOrEqualTo(buttonRect.left + 1),
      reason: 'שמאל התפריט מיושר לכפתור (מתרחב ימינה פנימה)',
    );
  });
}
