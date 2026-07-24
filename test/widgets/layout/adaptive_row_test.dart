import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_row.dart';

void main() {
  // עוטף את הווידג'ט ברוחב קבוע כדי לשלוט בצד שבו LayoutBuilder בוחר.
  Future<void> pumpAtWidth(
    WidgetTester tester, {
    required double width,
    required Widget child,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );
  }

  AdaptiveRow buildRow({
    bool equalHeight = false,
    CrossAxisAlignment wideCrossAxisAlignment = CrossAxisAlignment.start,
  }) {
    return AdaptiveRow(
      breakpoint: 400,
      spacing: 10,
      equalHeight: equalHeight,
      wideCrossAxisAlignment: wideCrossAxisAlignment,
      children: const [
        SizedBox(height: 20, child: Text('a')),
        SizedBox(height: 60, child: Text('b')),
      ],
    );
  }

  group('AdaptiveRow — בחירת פריסה לפי הרוחב', () {
    testWidgets('מתחת ל-breakpoint מציג Column ולא Row/Expanded', (
      tester,
    ) async {
      await pumpAtWidth(tester, width: 300, child: buildRow());

      expect(find.byType(Column), findsOneWidget);
      expect(find.byType(Row), findsNothing);
      expect(find.byType(Expanded), findsNothing);
      expect(find.byType(IntrinsicHeight), findsNothing);
    });

    testWidgets('מעל ל-breakpoint מציג Row עם Expanded לכל ילד', (
      tester,
    ) async {
      await pumpAtWidth(tester, width: 600, child: buildRow());

      expect(find.byType(Row), findsOneWidget);
      expect(find.byType(Expanded), findsNWidgets(2));
    });
  });

  group('AdaptiveRow — equalHeight', () {
    testWidgets(
      'equalHeight=false: ללא IntrinsicHeight ובמיושר ה-wide שהוגדר',
      (tester) async {
        await pumpAtWidth(
          tester,
          width: 600,
          child: buildRow(wideCrossAxisAlignment: CrossAxisAlignment.center),
        );

        expect(find.byType(IntrinsicHeight), findsNothing);
        final row = tester.widget<Row>(find.byType(Row));
        expect(row.crossAxisAlignment, CrossAxisAlignment.center);
      },
    );

    // שומר על התיקון: equalHeight חייב לכפות stretch, אחרת IntrinsicHeight
    // עוטף לחינם והכרטיסים לא נמתחים לגובה אחיד.
    testWidgets('equalHeight=true: עוטף ב-IntrinsicHeight וכופה stretch', (
      tester,
    ) async {
      await pumpAtWidth(
        tester,
        width: 600,
        child: buildRow(equalHeight: true),
      );

      expect(find.byType(IntrinsicHeight), findsOneWidget);
      final row = tester.widget<Row>(
        find.descendant(
          of: find.byType(IntrinsicHeight),
          matching: find.byType(Row),
        ),
      );
      expect(row.crossAxisAlignment, CrossAxisAlignment.stretch);
    });
  });
}
