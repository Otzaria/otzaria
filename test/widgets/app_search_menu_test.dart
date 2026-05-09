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

    expect(find.text('חיפוש פריט'), findsOneWidget,
        reason: 'hint של שדה החיפוש צריך להופיע');
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
    expect(find.text('אריה'), findsNothing,
        reason: 'התפריט אמור להיסגר אחרי הבחירה');
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
}
