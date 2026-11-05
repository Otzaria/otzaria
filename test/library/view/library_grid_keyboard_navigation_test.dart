import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_browser.dart';

Category _category(String title) => Category(
  title: title,
  description: 'תיאור מלא לכפתור המידע',
  shortDescription: 'תיאור קצר',
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

void main() {
  group('ניווט חיצים ברשת הספרייה', () {
    late List<FocusNode> nodes;
    late int exitTopCount;

    tearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });

    /// רוחב 600 → שתי עמודות (600 ~/ 250); שישה כרטיסים = שלוש שורות.
    Widget buildGrid() {
      nodes = List.generate(6, (i) => FocusNode(debugLabel: 'card$i'));
      exitTopCount = 0;
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: Center(
              child: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: MyGridView(
                    onExitTop: () => exitTopCount++,
                    items: [
                      for (var i = 0; i < 6; i++)
                        CategoryGridItem(
                          category: _category('פריט $i'),
                          onCategoryClickCallback: () {},
                          focusNode: nodes[i],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    int? focusedIndex() {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].hasPrimaryFocus) return i;
      }
      return null;
    }

    testWidgets('חיצי צד עוברים ברצף בין הכרטיסים בלבד', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[0].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focusedIndex(), 1);
    });

    testWidgets('חיצי צד ממשיכים ברצף גם במעבר בין שורות', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[1].requestFocus();
      await tester.pump();

      // מסוף השורה הראשונה לתחילת השנייה — בלי לברוח לרכיב צדדי.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 2);
    });

    testWidgets('מעלה ומטה נעים בין שורות באותו טור', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[0].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedIndex(), 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedIndex(), 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedIndex(), 2);
    });

    testWidgets('בקצה הרשת הפוקוס נשאר על הכרטיס ולא בורח החוצה', (
      tester,
    ) async {
      await tester.pumpWidget(buildGrid());
      nodes[5].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedIndex(), 5);
    });

    testWidgets('חץ מעלה מהשורה הראשונה מפעיל onExitTop', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[1].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(exitTopCount, 1);
    });

    testWidgets('כפתור המידע שבכרטיס מוחרג ממסלול ה-Tab', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[0].requestFocus();
      await tester.pump();

      // בלי ההחרגה Tab היה עוצר על ה-IconButton של המידע בתוך הכרטיס.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedIndex(), 1);
    });
  });

  group('רשת גוללת ארוכה', () {
    const count = 300;
    late List<FocusNode> nodes;
    late int exitTopCount;

    tearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });

    /// 600×600 → שתי עמודות; 300 כרטיסים = 150 שורות, רובן מחוץ לתצוגה.
    Widget buildGrid({required bool scrollable}) {
      nodes = List.generate(count, (i) => FocusNode(debugLabel: 'card$i'));
      exitTopCount = 0;
      final grid = MyGridView(
        scrollable: scrollable,
        onExitTop: () => exitTopCount++,
        items: [
          for (var i = 0; i < count; i++)
            CategoryGridItem(
              category: _category('פריט $i'),
              onCategoryClickCallback: () {},
              focusNode: nodes[i],
            ),
        ],
      );
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: Center(
              child: SizedBox(
                width: 600,
                height: 600,
                child: scrollable ? grid : SingleChildScrollView(child: grid),
              ),
            ),
          ),
        ),
      );
    }

    int? focusedIndex() {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].hasPrimaryFocus) return i;
      }
      return null;
    }

    testWidgets('רשת גוללת בונה רק את הכרטיסים שבתצוגה', (tester) async {
      await tester.pumpWidget(buildGrid(scrollable: true));
      final built = find.byType(CategoryGridItem).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(count ~/ 5));
    });

    for (final scrollable in [false, true]) {
      testWidgets(
        'מטה עובר את כל השורות ומעלה חוזר לחיפוש (scrollable: $scrollable)',
        (tester) async {
          await tester.pumpWidget(buildGrid(scrollable: scrollable));
          nodes[1].requestFocus();
          await tester.pump();

          for (var row = 1; row < count ~/ 2; row++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            expect(focusedIndex(), row * 2 + 1);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          expect(focusedIndex(), count - 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(focusedIndex(), count - 2);

          for (var row = count ~/ 2 - 2; row >= 0; row--) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await tester.pump();
            expect(focusedIndex(), row * 2);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(exitTopCount, 1);
        },
      );
    }
  });

  // רשת הפסים (q12 Q8): שלוש תיקיות בשתי עמודות, כך ששורת התיקיות השנייה
  // חלקית, והספרים מתחילים בשורה חדשה. מעלה/מטה הולכים לשורה הסמוכה בפועל,
  // לכרטיס הקרוב ביותר אופקית, ולא לאינדקס ועוד מספר העמודות.
  for (final direction in TextDirection.values) {
    group('ניווט מעלה/מטה ברשת הפסים (${direction.name})', () {
      const folders = 3;
      const books = 4;
      late List<FocusNode> nodes;
      late int exitTopCount;

      tearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });

      /// רוחב 600 → שתי עמודות; 0–2 תיקיות (שורות 1–2), 3–6 ספרים (שורות 3–4).
      Widget buildGrid({int leadingCategoryCount = folders}) {
        nodes = List.generate(
          folders + books,
          (i) => FocusNode(debugLabel: 'card$i'),
        );
        exitTopCount = 0;
        return MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Material(
              child: Center(
                child: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                    child: MyGridView(
                      leadingCategoryCount: leadingCategoryCount,
                      onExitTop: () => exitTopCount++,
                      items: [
                        for (var i = 0; i < folders + books; i++)
                          CategoryGridItem(
                            category: _category('פריט $i'),
                            onCategoryClickCallback: () {},
                            focusNode: nodes[i],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      int? focusedIndex() {
        for (var i = 0; i < nodes.length; i++) {
          if (nodes[i].hasPrimaryFocus) return i;
        }
        return null;
      }

      Future<int?> press(
        WidgetTester tester,
        int from,
        LogicalKeyboardKey key,
      ) async {
        nodes[from].requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pump();
        return focusedIndex();
      }

      Rect rectOf(WidgetTester tester, int i) =>
          tester.getRect(find.byType(CategoryGridItem).at(i));

      testWidgets('הפריסה: התיקייה השלישית לבדה בשורה, והספר הראשון בשורה '
          'חדשה באותו טור', (tester) async {
        await tester.pumpWidget(buildGrid());
        // הטור הראשון בכיוון הקריאה: ימין ב-RTL, שמאל ב-LTR.
        expect(rectOf(tester, 2).left, closeTo(rectOf(tester, 0).left, 0.5));
        expect(rectOf(tester, 3).left, closeTo(rectOf(tester, 0).left, 0.5));
        expect(rectOf(tester, 3).top, greaterThan(rectOf(tester, 2).bottom));
        // פס התיקיות נמוך מהספרים — אחרת זו לא רשת הפסים.
        expect(
          rectOf(tester, 0).height,
          lessThan(rectOf(tester, 3).height - 1),
        );
      });

      testWidgets('מטה מכל תיקייה', (tester) async {
        await tester.pumpWidget(buildGrid());
        // תיקייה 1 (טור ראשון) → תיקייה 3 שמתחתיה.
        expect(await press(tester, 0, LogicalKeyboardKey.arrowDown), 2);
        // תיקייה 2 (טור שני) → תיקייה 3, השורה הבאה; לא מדלגים לספר 1.
        expect(await press(tester, 1, LogicalKeyboardKey.arrowDown), 2);
        // תיקייה 3 (טור ראשון) → ספר 1 שמתחתיה, ולא ספר 2 שבטור השני.
        expect(await press(tester, 2, LogicalKeyboardKey.arrowDown), 3);
      });

      testWidgets('מעלה מכל תיקייה ומשורת הספרים הראשונה', (tester) async {
        await tester.pumpWidget(buildGrid());
        expect(await press(tester, 2, LogicalKeyboardKey.arrowUp), 0);
        // ספר 1 (טור ראשון) → תיקייה 3 שמעליו, ולא תיקייה 2.
        expect(await press(tester, 3, LogicalKeyboardKey.arrowUp), 2);
        // ספר 2 (טור שני) → תיקייה 3, הכרטיס היחיד בשורה שמעליו.
        expect(await press(tester, 4, LogicalKeyboardKey.arrowUp), 2);
        // ספר 3 → ספר 1, באותו טור.
        expect(await press(tester, 5, LogicalKeyboardKey.arrowUp), 3);

        expect(await press(tester, 0, LogicalKeyboardKey.arrowUp), 0);
        expect(exitTopCount, 1);
        expect(await press(tester, 1, LogicalKeyboardKey.arrowUp), 1);
        expect(exitTopCount, 2);
      });

      testWidgets('הספרים נעים באותו טור, ובסוף הרשת הפוקוס נשאר', (
        tester,
      ) async {
        await tester.pumpWidget(buildGrid());
        expect(await press(tester, 3, LogicalKeyboardKey.arrowDown), 5);
        expect(await press(tester, 4, LogicalKeyboardKey.arrowDown), 6);
        expect(await press(tester, 5, LogicalKeyboardKey.arrowDown), 5);
        expect(await press(tester, 6, LogicalKeyboardKey.arrowDown), 6);
      });

      testWidgets('חיצי צד לא השתנו: ברצף לפי סדר הקריאה', (tester) async {
        await tester.pumpWidget(buildGrid());
        final next = direction == TextDirection.rtl
            ? LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowRight;
        final previous = direction == TextDirection.rtl
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft;
        expect(await press(tester, 2, next), 3);
        expect(await press(tester, 3, previous), 2);
        expect(await press(tester, 1, next), 2);
      });

      // הרשת האחידה (בלי פס תיקיות), אותם שבעה כרטיסים: שורה = שני אינדקסים,
      // והשורה האחרונה החלקית מתנהגת כמו קודם.
      testWidgets('רשת אחידה: מעלה/מטה כמו קודם (אינדקס ± מספר העמודות)', (
        tester,
      ) async {
        await tester.pumpWidget(buildGrid(leadingCategoryCount: 0));
        expect(
          rectOf(tester, 0).height,
          closeTo(rectOf(tester, 3).height, 0.5),
        );
        for (var i = 0; i < folders + books; i++) {
          final down = i + 2 < folders + books ? i + 2 : i;
          expect(
            await press(tester, i, LogicalKeyboardKey.arrowDown),
            down,
            reason: 'מטה מ-$i',
          );
          final up = i >= 2 ? i - 2 : i;
          expect(
            await press(tester, i, LogicalKeyboardKey.arrowUp),
            up,
            reason: 'מעלה מ-$i',
          );
        }
        // מהשורה הראשונה מעלה יוצא לחיפוש (פעמיים: מ-0 ומ-1).
        expect(exitTopCount, 2);
      });
    });
  }

  group('resolveLibraryBackspaceAction', () {
    test('בשדה החיפוש הריק של הספרייה — עולים תיקייה', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: true,
          isLibrarySearchFocused: true,
          isSearchTextEmpty: true,
        ),
        LibraryBackspaceAction.navigateUp,
      );
    });

    test('בשדה החיפוש עם טקסט — המקש נשאר מחיקת תו', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: true,
          isLibrarySearchFocused: true,
          isSearchTextEmpty: false,
        ),
        LibraryBackspaceAction.none,
      );
    });

    test('בשדה טקסט אחר — המקש נשאר מחיקת תו גם כשהוא ריק', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: true,
          isLibrarySearchFocused: false,
          isSearchTextEmpty: true,
        ),
        LibraryBackspaceAction.none,
      );
    });

    test('פוקוס על כרטיס בלי חיפוש פעיל — עולים תיקייה', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: false,
          isLibrarySearchFocused: false,
          isSearchTextEmpty: true,
        ),
        LibraryBackspaceAction.navigateUp,
      );
    });

    test('פוקוס על כרטיס בזמן חיפוש פעיל — ניקוי החיפוש תחילה', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: false,
          isLibrarySearchFocused: false,
          isSearchTextEmpty: false,
        ),
        LibraryBackspaceAction.clearSearch,
      );
    });
  });
}
