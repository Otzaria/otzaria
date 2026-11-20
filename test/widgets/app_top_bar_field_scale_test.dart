// סעיף 30 (הערת הבעלים): AppTopBarField מגביל שדה בסרגל ל-1.6, גבוה מהכותרת.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

Future<double> _textHeight(
  WidgetTester tester, {
  required Widget Function(Widget text) wrap,
  required double scale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 400,
            child: AppTopBar(
              center: wrap(
                const Text('שדה', style: TextStyle(fontSize: 20)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.text('שדה')).height;
}

void main() {
  test('התקרה של שדות גבוהה מזו של הכותרת, ו-1.6 בדיוק', () {
    expect(AppTopBar.maxFieldTextScale, 1.6);
    expect(AppTopBar.maxFieldTextScale, greaterThan(AppTopBar.maxTextScale));
  });

  Widget field(Widget text) => AppTopBarField(child: text);
  Widget title(Widget text) => AppTopBarTitle(child: text);

  testWidgets('1.0 ו-1.5 גדלים כרגיל', (tester) async {
    final base = await _textHeight(tester, wrap: field, scale: 1.0);
    final mid = await _textHeight(tester, wrap: field, scale: 1.5);
    expect(mid, greaterThan(base));
    expect(mid, closeTo(base * 1.5, 1.0));
  });

  for (final scale in [1.8, 2.0]) {
    testWidgets('$scale נעצר בגובה של 1.6', (tester) async {
      final capped = await _textHeight(tester, wrap: field, scale: 1.6);
      final big = await _textHeight(tester, wrap: field, scale: scale);
      expect(big, closeTo(capped, 0.01));
    });
  }

  testWidgets('התקרה של שדה גבוהה מזו של כותרת (1.5: שדה גדול מכותרת)', (
    tester,
  ) async {
    final asTitle = await _textHeight(tester, wrap: title, scale: 1.5);
    final asField = await _textHeight(tester, wrap: field, scale: 1.5);
    expect(asField, greaterThan(asTitle + 1));
  });
}
