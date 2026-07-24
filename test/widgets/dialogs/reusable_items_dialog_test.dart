import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/reusable_items_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AppCustomContentDialog משתמש ב-MediaQuery.of(context).size כדי לחשב את הרוחב.
  // בטסטים `setSurfaceSize` לא תמיד מתפשט ל-MediaQuery של דיאלוגים, לכן עוטפים
  // ידנית ב-MediaQuery עם הגודל הרצוי. הקונטיינר הפנימי של הדיאלוג הוא היחיד
  // עם padding אנכי של 16 בלבד (horizontal מנוהל דרך Padding פנימי לכל שורה).
  Container findInnerContainer() {
    return find
        .descendant(
          of: find.byType(AppCustomContentDialog),
          matching: find.byType(Container),
        )
        .evaluate()
        .map((e) => e.widget as Container)
        .singleWhere(
          (c) => c.padding == const EdgeInsets.symmetric(vertical: 16),
        );
  }

  Future<void> pumpDialog(
    WidgetTester tester,
    Size mediaSize, {
    String title = 'כותרת',
    bool scrollable = true,
    Widget child = const SizedBox.shrink(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: mediaSize),
          child: Material(
            child: AppCustomContentDialog(
              title: title,
              scrollable: scrollable,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('AppCustomContentDialog — רוחב רספונסיבי', () {
    testWidgets('מסך רחב: הדיאלוג מבקש רוחב של 50% מהמסך', (tester) async {
      await pumpDialog(tester, const Size(1200, 800));

      final requested = findInnerContainer().constraints!.maxWidth;
      expect(
        requested,
        closeTo(600, 0.5),
        reason: '1200 * 0.5 = 600 — שמירה על ההתנהגות במסך רחב',
      );
    });

    testWidgets('מסך צר: הדיאלוג מבקש רוחב של 95% מהמסך', (tester) async {
      await pumpDialog(tester, const Size(400, 800));

      final requested = findInnerContainer().constraints!.maxWidth;
      expect(
        requested,
        closeTo(380, 0.5),
        reason:
            '400 * 0.95 = 380 — בלי תיקון היה 200 (50%) והטקסט היה קורס לתו-לשורה',
      );
    });

    testWidgets('הכותרת מוצגת', (tester) async {
      await pumpDialog(tester, const Size(800, 600));
      expect(find.text('כותרת'), findsOneWidget);
    });
  });

  group('AppCustomContentDialog — כותרת רספונסיבית', () {
    testWidgets('הכותרת עטופה ב-FittedBox עם BoxFit.scaleDown', (tester) async {
      await pumpDialog(tester, const Size(800, 600));

      final fittedBoxes = tester
          .widgetList<FittedBox>(find.byType(FittedBox))
          .where((fb) => fb.fit == BoxFit.scaleDown)
          .toList();
      expect(
        fittedBoxes,
        isNotEmpty,
        reason: 'חייב להיות לפחות FittedBox אחד עם scaleDown לכותרת',
      );
    });

    testWidgets('ה-Text של הכותרת מוגבל לשורה אחת', (tester) async {
      await pumpDialog(tester, const Size(800, 600));

      final titleText = tester.widget<Text>(find.text('כותרת'));
      expect(titleText.maxLines, 1);
    });

    testWidgets('כותרת ארוכה לא גולשת מהשורה גם במסך צר', (tester) async {
      const longTitle = 'כותרת ארוכה מאוד שעשויה לגלוש בתצוגה רגילה';
      await pumpDialog(tester, const Size(350, 700), title: longTitle);

      expect(find.text(longTitle), findsOneWidget);

      final fittedBox = tester
          .widgetList<FittedBox>(find.byType(FittedBox))
          .firstWhere((fb) => fb.fit == BoxFit.scaleDown);
      expect(fittedBox.fit, BoxFit.scaleDown);
    });
  });

  group('AppCustomContentDialog — מיקום Scrollbar בתוך ה-padding הקיים', () {
    testWidgets(
      'ה-SingleChildScrollView מכיל padding אופקי של 16px בדיוק — ללא padding נוסף',
      (tester) async {
        await pumpDialog(tester, const Size(800, 600), scrollable: true);

        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        expect(
          scrollView.padding,
          equals(const EdgeInsets.symmetric(horizontal: 16)),
          reason:
              'padding 16px הסטנדרטי בלבד — הScrollbar ממוקם בתוך ה-16px הקיים ולא מוסיף רווח',
        );
      },
    );

    testWidgets(
      'התוכן מוצב בדיוק ב-16px מקצה ה-Scrollbar — הScrollbar לא חופף לתוכן',
      (tester) async {
        const childKey = Key('dialog-content');
        await pumpDialog(
          tester,
          const Size(800, 600),
          scrollable: true,
          child: const SizedBox(key: childKey, height: 10),
        );

        final scrollbarRect = tester.getRect(find.byType(Scrollbar));
        final contentRect = tester.getRect(find.byKey(childKey));

        // התוכן מתחיל ב-16px מקצה ה-Scrollbar widget (padding הסטנדרטי בלבד).
        // אם היה padding נוסף, המרחק היה גדול מ-16px.
        expect(
          contentRect.left - scrollbarRect.left,
          closeTo(16.0, 0.5),
          reason:
              'אין padding נוסף: המרחק מקצה אזור הגלילה לתוכן הוא 16px (ה-Scrollbar יושב בתוך הרווח הזה)',
        );
      },
    );

    testWidgets("ה-Scrollbar ממוקם ע\"י הווידג'ט עצמו — קיים ב-scrollable=true", (
      tester,
    ) async {
      await pumpDialog(tester, const Size(800, 600), scrollable: true);

      expect(
        find.byType(Scrollbar),
        findsOneWidget,
        reason: 'AppCustomContentDialog מגדיר ומציב את ה-Scrollbar',
      );
      expect(
        find.byType(ScrollbarTheme),
        findsOneWidget,
        reason:
            'ScrollbarTheme מגדיר crossAxisMargin=2 — זהה ל-adaptive_side_pane, צמוד לגבול',
      );
    });

    testWidgets('ללא scrollable — אין Scrollbar ואין SingleChildScrollView', (
      tester,
    ) async {
      await pumpDialog(tester, const Size(800, 600), scrollable: false);

      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets(
      'ללא scrollable — התוכן מוצב ב-16px בדיוק (אותו מרווח כמו scrollable)',
      (tester) async {
        const childKey = Key('dialog-content');

        // scrollable: false — תוכן עם Padding ישיר
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(800, 600)),
              child: Material(
                child: AppCustomContentDialog(
                  title: 'כותרת',
                  scrollable: false,
                  child: const Padding(
                    // Padding wrapper so getRect returns the inner widget's position
                    padding: EdgeInsets.zero,
                    child: SizedBox(key: childKey, height: 10),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Container הפנימי (vertical padding בלבד) — קצהו השמאלי = גבול אזור התוכן
        final containerFinder = find
            .descendant(
              of: find.byType(AppCustomContentDialog),
              matching: find.byType(Container),
            )
            .evaluate()
            .where(
              (e) =>
                  (e.widget as Container).padding ==
                  const EdgeInsets.symmetric(vertical: 16),
            )
            .first;
        final containerRect = tester.getRect(
          find.byElementPredicate(
            (el) => el == containerFinder,
            description: 'inner container',
          ),
        );
        final contentRect = tester.getRect(find.byKey(childKey));

        expect(
          contentRect.left - containerRect.left,
          closeTo(16.0, 0.5),
          reason:
              'ב-scrollable=false המרחק מקצה ה-Container לתוכן הוא 16px — זהה לאופן הפעולה עם גלילה',
        );
      },
    );
  });
}
