// סעיף 30 (q30): רק כותרת הסרגל העליון מוגבלת ל-1.3. שדות חיפוש וכפתורים
// בסרגל גדלים עם הטקסט של המערכת.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

Widget _app({required Widget center, required double textScale}) {
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
        child: SizedBox(width: 400, child: AppTopBar(center: center)),
      ),
    ),
  );
}

const _label = 'טקסט בסרגל';

Future<double> _textHeight(
  WidgetTester tester, {
  required Widget Function(Widget text) wrap,
  required double scale,
}) async {
  await tester.pumpWidget(
    _app(
      textScale: scale,
      center: wrap(const Text(_label, style: TextStyle(fontSize: 20))),
    ),
  );
  await tester.pump();
  return tester.getSize(find.text(_label)).height;
}

void main() {
  group('AppTopBarTitle: הכותרת גדלה עד פי 1.3 ועוצרת', () {
    Widget title(Widget text) => AppTopBarTitle(child: text);

    testWidgets('1.0 ו-1.15 גדלים כרגיל', (tester) async {
      final base = await _textHeight(tester, wrap: title, scale: 1.0);
      final mid = await _textHeight(tester, wrap: title, scale: 1.15);
      expect(mid, greaterThan(base));
    });

    for (final scale in [1.5, 2.0]) {
      testWidgets('$scale נעצר בגובה של 1.3', (tester) async {
        final capped = await _textHeight(tester, wrap: title, scale: 1.3);
        final big = await _textHeight(tester, wrap: title, scale: scale);
        expect(big, closeTo(capped, 0.01));
        expect(
          capped,
          greaterThan(await _textHeight(tester, wrap: title, scale: 1.0)),
        );
      });
    }
  });

  group('שאר הסרגל: לא מוגבל ל-1.3', () {
    Widget plain(Widget text) => text;

    testWidgets('טקסט במרכז הסרגל בלי AppTopBarTitle גדל מעבר ל-1.3', (
      tester,
    ) async {
      final capped = await _textHeight(tester, wrap: plain, scale: 1.3);
      final big = await _textHeight(tester, wrap: plain, scale: 2.0);
      expect(big, greaterThan(capped + 1));
    });
  });
}
