// סעיף 30: הטקסט בסרגל העליון גדל עד פי 1.3 ועוצר שם.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

Widget _app({
  required double width,
  Widget? center,
  double textScale = 1.0,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: AppTopBar(center: center),
        ),
      ),
    ),
  );
}

void main() {
  group('AppTopBar: הגדלת טקסט עד פי 1.3', () {
    Future<double> titleHeight(WidgetTester tester, double scale) async {
      await tester.pumpWidget(
        _app(
          width: 400,
          textScale: scale,
          center: const AppTopBarTitle(
            child: Text('כותרת', style: TextStyle(fontSize: 20)),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.text('כותרת')).height;
    }

    testWidgets('1.0 ו-1.15 גדלים כרגיל', (tester) async {
      final base = await titleHeight(tester, 1.0);
      final mid = await titleHeight(tester, 1.15);
      expect(mid, greaterThan(base));
    });

    for (final scale in [1.5, 2.0]) {
      testWidgets('$scale נעצר בגובה של 1.3', (tester) async {
        final capped = await titleHeight(tester, 1.3);
        final big = await titleHeight(tester, scale);
        expect(big, closeTo(capped, 0.01));
        expect(capped, greaterThan(await titleHeight(tester, 1.0)));
      });
    }
  });
}
