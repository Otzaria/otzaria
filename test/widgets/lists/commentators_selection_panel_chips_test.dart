// שורת הצ׳יפים בפאנל בחירת המפרשים: דורות מימין, סוגי קישור משמאל.
// ציר הסוגים אופציונלי — פאנלי ה-PDF אינם מעבירים אותו כלל.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';

void main() {
  const groups = [
    CommentatorGroup(title: 'ראשונים', commentators: ['רש"י']),
    CommentatorGroup(title: 'אחרונים', commentators: ['קצות החושן']),
  ];

  Future<Set<String>?> pump(
    WidgetTester tester, {
    List<String> typeChipKeys = const [],
    Set<String> selectedTypeChips = const {},
    bool withTypeCallback = true,
  }) async {
    Set<String>? lastTypes;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CommentatorsSelectionPanel(
              groups: groups,
              selectedCommentators: const [],
              onSelectionChanged: (_) {},
              bookTitle: 'בראשית',
              typeChipKeys: typeChipKeys,
              selectedTypeChips: selectedTypeChips,
              typeChipLabelBuilder: (key) => key == 'TARGUM' ? 'תרגום' : 'מדרש',
              onTypeChipsChanged: withTypeCallback
                  ? (types) => lastTypes = types
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return lastTypes;
  }

  testWidgets('בלי מפתחות סוג — רק קבוצת הדורות (מסלול ה-PDF)', (tester) async {
    await pump(tester);

    expect(find.byKey(commentatorEraChipsGroupKey), findsOneWidget);
    expect(find.byKey(commentatorTypeChipsGroupKey), findsNothing);
    expect(find.widgetWithText(Chip, 'ראשונים'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'על בראשית'), findsOneWidget);
  });

  testWidgets('שתי הקבוצות באותה שורה — דורות מימין, סוגים משמאל', (
    tester,
  ) async {
    await pump(tester, typeChipKeys: const ['TARGUM', 'MIDRASH']);

    final eras = tester.getRect(find.byKey(commentatorEraChipsGroupKey));
    final types = tester.getRect(find.byKey(commentatorTypeChipsGroupKey));
    expect(types.right, lessThanOrEqualTo(eras.left));
    expect(eras.top, types.top);
    expect(eras.height, types.height);
  });

  testWidgets('בלי ציר סוגים אין קו מפריד', (tester) async {
    await pump(tester);

    expect(find.byKey(commentatorChipAxesDividerKey), findsNothing);
  });

  testWidgets('הקו המפריד ניצב בין שתי הקבוצות', (tester) async {
    await pump(tester, typeChipKeys: const ['TARGUM', 'MIDRASH']);

    final eras = tester.getRect(find.byKey(commentatorEraChipsGroupKey));
    final types = tester.getRect(find.byKey(commentatorTypeChipsGroupKey));
    final divider = tester.getRect(
      find.byKey(commentatorChipAxesDividerKey),
    );
    expect(divider.left, greaterThanOrEqualTo(types.right));
    expect(divider.right, lessThanOrEqualTo(eras.left));
    // חצי-חצי קבוע: לשני הצירים אותו רוחב, ולכן הקו במרכז.
    expect(eras.width, moreOrLessEquals(types.width, epsilon: 1));
  });

  testWidgets('התוויות נבנות מ-typeChipLabelBuilder', (tester) async {
    await pump(tester, typeChipKeys: const ['TARGUM', 'MIDRASH']);

    expect(find.widgetWithText(Chip, 'תרגום'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'מדרש'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'TARGUM'), findsNothing);
  });

  testWidgets('לחיצה על צ׳יפ סוג מדווחת את המפתח, לא את התווית', (
    tester,
  ) async {
    Set<String>? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CommentatorsSelectionPanel(
              groups: groups,
              selectedCommentators: const [],
              onSelectionChanged: (_) {},
              bookTitle: 'בראשית',
              typeChipKeys: const ['TARGUM', 'MIDRASH'],
              typeChipLabelBuilder: (key) => key == 'TARGUM' ? 'תרגום' : 'מדרש',
              onTypeChipsChanged: (types) => reported = types,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Chip, 'תרגום'));
    await tester.pumpAndSettle();

    expect(reported, {'TARGUM'});
  });

  testWidgets('בחירת סוג נכנסת מבחוץ ומסמנת את הצ׳יפ', (tester) async {
    await pump(
      tester,
      typeChipKeys: const ['TARGUM', 'MIDRASH'],
      selectedTypeChips: const {'MIDRASH'},
    );

    final selected = tester.widget<Chip>(find.widgetWithText(Chip, 'מדרש'));
    final unselected = tester.widget<Chip>(find.widgetWithText(Chip, 'תרגום'));
    expect(selected.backgroundColor, isNotNull);
    expect(unselected.backgroundColor, isNull);
  });

  group('צ׳יפ סוג מצמצם את רשימת המפרשים, כמו צ׳יפ דור', () {
    const byType = {
      'TARGUM': {'רש"י'},
      'MIDRASH': {'קצות החושן'},
    };

    Future<void> pumpWithTypes(
      WidgetTester tester, {
      required Set<String> selectedTypeChips,
      Map<String, Set<String>> commentatorsByType = byType,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: CommentatorsSelectionPanel(
                groups: groups,
                selectedCommentators: const [],
                onSelectionChanged: (_) {},
                bookTitle: 'בראשית',
                typeChipKeys: const ['TARGUM', 'MIDRASH'],
                selectedTypeChips: selectedTypeChips,
                typeChipLabelBuilder: (key) =>
                    key == 'TARGUM' ? 'תרגום' : 'מדרש',
                commentatorsByType: commentatorsByType,
                onTypeChipsChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('בלי בחירת סוג — כל המפרשים ברשימה', (tester) async {
      await pumpWithTypes(tester, selectedTypeChips: const {});

      expect(find.widgetWithText(CheckboxListTile, 'רש"י'), findsOneWidget);
      expect(
        find.widgetWithText(CheckboxListTile, 'קצות החושן'),
        findsOneWidget,
      );
    });

    testWidgets('בחירת "תרגום" משאירה רק את המפרש מאותו סוג', (tester) async {
      await pumpWithTypes(tester, selectedTypeChips: const {'TARGUM'});

      expect(find.widgetWithText(CheckboxListTile, 'רש"י'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'קצות החושן'), findsNothing);
    });

    testWidgets('בחירת שני סוגים = איחוד הרשימות', (tester) async {
      await pumpWithTypes(
        tester,
        selectedTypeChips: const {'TARGUM', 'MIDRASH'},
      );

      expect(find.widgetWithText(CheckboxListTile, 'רש"י'), findsOneWidget);
      expect(
        find.widgetWithText(CheckboxListTile, 'קצות החושן'),
        findsOneWidget,
      );
    });

    testWidgets('כפתור "הצג את כל" של דור שכל מפרשיו סוננו אינו מוצג', (
      tester,
    ) async {
      await pumpWithTypes(tester, selectedTypeChips: const {'TARGUM'});

      // 'רש"י' בראשונים נשאר, ולכן קצות החושן ('אחרונים') נושר עם הכפתור שלו.
      expect(
        find.widgetWithText(CheckboxListTile, 'הצג את כל הראשונים'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'הצג את כל האחרונים'),
        findsNothing,
      );
    });

    testWidgets('בלי commentatorsByType אין צמצום (מסלול ה-PDF)', (
      tester,
    ) async {
      await pumpWithTypes(
        tester,
        selectedTypeChips: const {'TARGUM'},
        commentatorsByType: const {},
      );

      expect(find.widgetWithText(CheckboxListTile, 'רש"י'), findsOneWidget);
      expect(
        find.widgetWithText(CheckboxListTile, 'קצות החושן'),
        findsOneWidget,
      );
    });

    testWidgets('שינוי הבחירה מבחוץ מעדכן את הרשימה מיד', (tester) async {
      await pumpWithTypes(tester, selectedTypeChips: const {});
      expect(
        find.widgetWithText(CheckboxListTile, 'קצות החושן'),
        findsOneWidget,
      );

      await pumpWithTypes(tester, selectedTypeChips: const {'TARGUM'});

      expect(find.widgetWithText(CheckboxListTile, 'קצות החושן'), findsNothing);
    });
  });

  testWidgets('בחירת דור אינה משפיעה על בחירת הסוגים', (tester) async {
    Set<String>? reportedTypes;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CommentatorsSelectionPanel(
              groups: groups,
              selectedCommentators: const [],
              onSelectionChanged: (_) {},
              bookTitle: 'בראשית',
              typeChipKeys: const ['TARGUM'],
              selectedTypeChips: const {'TARGUM'},
              typeChipLabelBuilder: (_) => 'תרגום',
              onTypeChipsChanged: (types) => reportedTypes = types,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Chip, 'ראשונים'));
    await tester.pumpAndSettle();

    expect(reportedTypes, isNull);
    final eraChip = tester.widget<Chip>(
      find.widgetWithText(Chip, 'ראשונים'),
    );
    expect(eraChip.backgroundColor, isNotNull);
    final typeChip = tester.widget<Chip>(find.widgetWithText(Chip, 'תרגום'));
    expect(typeChip.backgroundColor, isNotNull);
  });
}
