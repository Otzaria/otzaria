import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';

void main() {
  // בגופן הבדיקות כל תו רוחבו כגודל הגופן: 10 תווים × 10 = 100px.
  const title = 'אבגדהוזחטי';

  Future<void> pumpTitle(WidgetTester tester, double width) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 10),
            child: Center(
              child: SizedBox(
                width: width,
                child: Builder(
                  builder: (context) => buildFadedTabTitle(context, title),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('כותרת שנכנסת במלואה אינה נדהית גם כשהיא מגיעה לקצה (#1933)', (
    tester,
  ) async {
    await pumpTitle(tester, 100);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('כותרת שנחתכת נדהית בקצה הסוף', (tester) async {
    await pumpTitle(tester, 60);
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}
