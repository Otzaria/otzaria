import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';

void main() {
  const searchInAramaic = 'חפש "מילה" בארמית';
  const searchInHebrew = 'חפש בעברית';
  const copyWithResult = 'העתק את הערך עם התוצאה';
  const copyEntry = 'העתק את הערך';
  const copyMeaning = 'העתק פירוש';

  final searches = <(String, bool)>[];

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool queryIsAramaic,
    double width = 1100,
  }) async {
    searches.clear();
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: AramaicResultCard(
                aramaic: 'מילה',
                hebrew: 'פירוש ראשון ארוך מאוד שממשיך לכמה מילים *** פירוש שני',
                query: queryIsAramaic ? 'מילה' : 'פירוש',
                queryIsAramaic: queryIsAramaic,
                onSearch: (text, {required hebrewToAramaic}) =>
                    searches.add((text, hebrewToAramaic)),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AramaicResultCard)));
    await tester.pumpAndSettle();
  }

  for (final width in [1100.0, 360.0]) {
    testWidgets('חיפוש ארמי ($width): חיפוש בעברית בכל פירוש, לצד שני ההעתקות', (
      tester,
    ) async {
      await pumpCard(tester, queryIsAramaic: true, width: width);

      // הכותרת: העתקה עם התוצאה והעתקת הערך; אין חיפוש בכותרת.
      expect(find.byTooltip(searchInAramaic), findsNothing);
      expect(find.byTooltip(copyWithResult), findsOneWidget);
      expect(find.byTooltip(copyEntry), findsOneWidget);
      // כל שורת פירוש: חיפוש בעברית והעתקת הפירוש.
      expect(find.byTooltip(searchInHebrew), findsNWidgets(2));
      expect(find.byTooltip(copyMeaning), findsNWidgets(2));

      final header = tester.getCenter(find.byTooltip(copyEntry)).dy;
      expect(tester.getCenter(find.byTooltip(copyWithResult)).dy, header);
      // RTL: הראשון בשורה הוא הימני ביותר.
      expect(
        tester.getCenter(find.byTooltip(copyWithResult)).dx,
        greaterThan(tester.getCenter(find.byTooltip(copyEntry)).dx),
      );
      final row = tester.getCenter(find.byTooltip(searchInHebrew).first);
      expect(row.dy, tester.getCenter(find.byTooltip(copyMeaning).first).dy);
      expect(row.dx, greaterThan(tester.getCenter(find.byTooltip(copyMeaning).first).dx));

      await tester.tap(find.byTooltip(searchInHebrew).first);
      await tester.pump();
      expect(searches, [('פירוש ראשון ארוך מאוד שממשיך לכמה מילים', true)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('חיפוש עברי ($width): חיפוש בארמית בכותרת, לצד שני ההעתקות', (
      tester,
    ) async {
      await pumpCard(tester, queryIsAramaic: false, width: width);

      // הכותרת: חיפוש בארמית והעתקת הערך; אין חיפוש בעברית בשורות.
      expect(find.byTooltip(searchInAramaic), findsOneWidget);
      expect(find.byTooltip(copyEntry), findsOneWidget);
      expect(find.byTooltip(searchInHebrew), findsNothing);
      // כל שורת פירוש: העתקה עם הערך והעתקת הפירוש.
      expect(find.byTooltip(copyWithResult), findsNWidgets(2));
      expect(find.byTooltip(copyMeaning), findsNWidgets(2));

      final header = tester.getCenter(find.byTooltip(copyEntry)).dy;
      expect(tester.getCenter(find.byTooltip(searchInAramaic)).dy, header);
      expect(
        tester.getCenter(find.byTooltip(searchInAramaic)).dx,
        greaterThan(tester.getCenter(find.byTooltip(copyEntry)).dx),
      );
      final row = tester.getCenter(find.byTooltip(copyWithResult).first);
      expect(row.dy, tester.getCenter(find.byTooltip(copyMeaning).first).dy);
      expect(row.dx, greaterThan(tester.getCenter(find.byTooltip(copyMeaning).first).dx));

      await tester.tap(find.byTooltip(searchInAramaic));
      await tester.pump();
      expect(searches, [('מילה', false)]);
      expect(tester.takeException(), isNull);
    });
  }
}
