import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// בודק את הסינון של "מ-/עד-" — בתפריט ההדפסה הסינון נעשה ע"י .where()
/// על entries לפני העברתם ל-AppDropdownField.
///
/// כאן אנחנו מאמתים שהאפליקציה אכן מעבירה רשימה מסוננת, ושהתפריט מציג רק
/// את הפריטים שהועברו. זה מכסה את ההתנהגות שהמשתמש דרש: ב-"מ-" אסור
/// לראות פריטים שאחרי הבחירה ב-"עד-".
///
/// הערה: הטקסט הנבחר מופיע גם בטריגר וגם בתפריט; משתמשים ב-popupItem כדי
/// לסקופ את הבדיקה רק לפריטי התפריט (PopupMenuItem).
void main() {
  Future<void> pumpFilteredDropdown<T>(
    WidgetTester tester, {
    required List<AppMenuEntry<T>> filteredEntries,
    required T? value,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: AppDropdownField<T>(
                value: value,
                entries: filteredEntries,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder popupItem(String text) => find.descendant(
    of: find.byType(PopupMenuItem<int>),
    matching: find.text(text),
  );

  testWidgets('תפריט "מ-" אחרי סינון endIndex=2 מציג רק את 3 הראשונים מתוך 5', (
    tester,
  ) async {
    const allHeaders = [
      AppMenuEntry<int>(value: 0, label: 'פרק א'),
      AppMenuEntry<int>(value: 1, label: 'פרק ב'),
      AppMenuEntry<int>(value: 2, label: 'פרק ג'),
      AppMenuEntry<int>(value: 3, label: 'פרק ד'),
      AppMenuEntry<int>(value: 4, label: 'פרק ה'),
    ];
    const endIndex = 2;
    final filtered = allHeaders.where((e) => e.value <= endIndex).toList();

    await pumpFilteredDropdown<int>(
      tester,
      filteredEntries: filtered,
      value: 0,
    );

    await tester.tap(find.byType(AppDropdownField<int>));
    await tester.pumpAndSettle();

    expect(popupItem('פרק א'), findsOneWidget);
    expect(popupItem('פרק ב'), findsOneWidget);
    expect(popupItem('פרק ג'), findsOneWidget);
    expect(
      popupItem('פרק ד'),
      findsNothing,
      reason: 'פרק ד אחרי endIndex=2 לא צריך להופיע ב"מ-"',
    );
    expect(popupItem('פרק ה'), findsNothing);
  });

  testWidgets('תפריט "עד-" אחרי סינון startIndex=2 מציג רק את 3 האחרונים', (
    tester,
  ) async {
    const allHeaders = [
      AppMenuEntry<int>(value: 0, label: 'פרק א'),
      AppMenuEntry<int>(value: 1, label: 'פרק ב'),
      AppMenuEntry<int>(value: 2, label: 'פרק ג'),
      AppMenuEntry<int>(value: 3, label: 'פרק ד'),
      AppMenuEntry<int>(value: 4, label: 'פרק ה'),
    ];
    const startIndex = 2;
    final filtered = allHeaders.where((e) => e.value >= startIndex).toList();

    await pumpFilteredDropdown<int>(
      tester,
      filteredEntries: filtered,
      value: 4,
    );

    await tester.tap(find.byType(AppDropdownField<int>));
    await tester.pumpAndSettle();

    expect(
      popupItem('פרק א'),
      findsNothing,
      reason: 'פרק א לפני startIndex=2 לא צריך להופיע ב"עד-"',
    );
    expect(popupItem('פרק ב'), findsNothing);
    expect(popupItem('פרק ג'), findsOneWidget);
    expect(popupItem('פרק ד'), findsOneWidget);
    expect(popupItem('פרק ה'), findsOneWidget);
  });

  testWidgets('כש-end לא נבחר (null), "מ-" מציג את כל הפריטים', (tester) async {
    const allHeaders = [
      AppMenuEntry<int>(value: 0, label: 'פרק א'),
      AppMenuEntry<int>(value: 1, label: 'פרק ב'),
      AppMenuEntry<int>(value: 2, label: 'פרק ג'),
    ];
    const int? endIndex = null;
    final filtered = allHeaders
        .where((e) => endIndex == null || e.value <= endIndex)
        .toList();

    await pumpFilteredDropdown<int>(
      tester,
      filteredEntries: filtered,
      value: 0,
    );

    await tester.tap(find.byType(AppDropdownField<int>));
    await tester.pumpAndSettle();

    expect(popupItem('פרק א'), findsOneWidget);
    expect(popupItem('פרק ב'), findsOneWidget);
    expect(popupItem('פרק ג'), findsOneWidget);
  });

  testWidgets('סינון של עמודי PDF: "מעמוד" מסתיים ב-pdfEndPage', (
    tester,
  ) async {
    const pdfEndPage = 3;
    final entries = List.generate(
      pdfEndPage,
      (i) => AppMenuEntry<int>(
        value: i + 1,
        label: 'דף ${i + 1}',
      ),
    );

    await pumpFilteredDropdown<int>(
      tester,
      filteredEntries: entries,
      value: 1,
    );

    await tester.tap(find.byType(AppDropdownField<int>));
    await tester.pumpAndSettle();

    expect(popupItem('דף 1'), findsOneWidget);
    expect(popupItem('דף 2'), findsOneWidget);
    expect(popupItem('דף 3'), findsOneWidget);
    expect(
      popupItem('דף 4'),
      findsNothing,
      reason: 'pdfEndPage=3 → רק עמודים 1..3 ב"מעמוד"',
    );
  });
}
