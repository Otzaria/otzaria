// review-r3, q-bottom-bar: תווית לכל יעד בסרגל התחתון, ורק כשהתווית הארוכה
// לא נכנסת ברוחב של יעד — תווית רק ליעד הנבחר. ההחלטה נמדדת (TextPainter
// בסגנון התווית ובגודל הטקסט), ולכן כאן הרוחב נגזר מהמדידה עצמה.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/bottom_nav_labels.dart';

const _labels = ['ספרייה', 'איתור', 'עיון', 'חיפוש', 'כלים', 'הגדרות'];
const _style = TextStyle(fontSize: 12);

/// רוחב התווית הארוכה, כמו שהסרגל מצייר אותה.
double _longest({double scale = 1}) {
  var max = 0.0;
  for (final l in _labels) {
    final p = TextPainter(
      text: TextSpan(text: l, style: _style),
      textDirection: TextDirection.rtl,
      textScaler: TextScaler.linear(scale),
    )..layout();
    if (p.maxIntrinsicWidth > max) max = p.maxIntrinsicWidth;
    p.dispose();
  }
  return max;
}

Future<NavigationDestinationLabelBehavior> _pump(
  WidgetTester tester, {
  required double width,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        navigationBarTheme: const NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(_style),
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 600),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            bottomNavigationBar: LayoutBuilder(
              builder: (context, constraints) => NavigationBar(
                labelBehavior: BottomNavLabels.behaviorFor(
                  context,
                  barWidth: constraints.maxWidth,
                  labels: _labels,
                ),
                destinations: [
                  for (final l in _labels)
                    NavigationDestination(
                      icon: const Icon(Icons.abc),
                      label: l,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<NavigationBar>(find.byType(NavigationBar))
      .labelBehavior!;
}

/// שקיפות התווית של יעד: 1 גלויה, 0 מוסתרת.
double _opacity(WidgetTester tester, String label) => tester
    .widget<FadeTransition>(
      find
          .ancestor(of: find.text(label), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

void main() {
  testWidgets('התוויות נכנסות: תווית לכל יעד', (tester) async {
    final width = _longest() * _labels.length + 6;
    expect(
      await _pump(tester, width: width),
      NavigationDestinationLabelBehavior.alwaysShow,
    );
    expect(_opacity(tester, 'הגדרות'), 1);
    expect(_opacity(tester, 'ספרייה'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('התוויות לא נכנסות: תווית רק ליעד הנבחר', (tester) async {
    final width = _longest() * _labels.length - 6;
    expect(
      await _pump(tester, width: width),
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
    // היעד הנבחר (הראשון) עם תווית, והשאר בלי.
    expect(_opacity(tester, 'ספרייה'), 1);
    expect(_opacity(tester, 'הגדרות'), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('גודל טקסט גדול: אותו רוחב, והתוויות כבר לא נכנסות', (
    tester,
  ) async {
    final width = _longest() * _labels.length + 6;
    expect(
      await _pump(tester, width: width, scale: 1.3),
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
  });

  testWidgets('גודל הטקסט נמדד עד התקרה של הסרגל (1.3), לא מעבר לה', (
    tester,
  ) async {
    // ב־1.3 נכנס, ולכן גם ב־2.0: הסרגל מצייר את התווית ב־1.3 לכל היותר.
    final width =
        _longest(scale: BottomNavLabels.maxLabelTextScale) * _labels.length + 6;
    expect(
      await _pump(tester, width: width, scale: 2),
      NavigationDestinationLabelBehavior.alwaysShow,
    );
  });
}
