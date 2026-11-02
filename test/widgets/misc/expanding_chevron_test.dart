import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';

void main() {
  Future<double> turnsOf(
    WidgetTester tester, {
    required bool expanded,
    required ExpandingChevronStyle style,
    TextDirection direction = TextDirection.rtl,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: ExpandingChevron(isExpanded: expanded, style: style),
      ),
    );
    return tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;
  }

  testWidgets('אקורדיון: למטה כשסגור, למעלה כשפתוח', (tester) async {
    expect(
      await turnsOf(
        tester,
        expanded: false,
        style: ExpandingChevronStyle.accordion,
      ),
      0.0,
    );
    expect(
      await turnsOf(
        tester,
        expanded: true,
        style: ExpandingChevronStyle.accordion,
      ),
      0.5,
    );
  });

  // החץ הבסיסי מצביע למטה; רבע סיבוב עם השעון מפנה אותו שמאלה.
  testWidgets('עץ: לכיוון הקריאה כשסגור, למטה כשפתוח', (tester) async {
    expect(
      await turnsOf(tester, expanded: false, style: ExpandingChevronStyle.tree),
      0.25,
    );
    expect(
      await turnsOf(
        tester,
        expanded: false,
        style: ExpandingChevronStyle.tree,
        direction: TextDirection.ltr,
      ),
      -0.25,
    );
    expect(
      await turnsOf(tester, expanded: true, style: ExpandingChevronStyle.tree),
      0.0,
    );
  });

  testWidgets('מכריז על מצב ההרחבה לקורא מסך', (tester) async {
    final handle = tester.ensureSemantics();
    for (final expanded in [false, true]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: ExpandingChevron(isExpanded: expanded),
        ),
      );
      expect(
        tester.getSemantics(find.byType(ExpandingChevron)),
        matchesSemantics(hasExpandedState: true, isExpanded: expanded),
      );
    }
    handle.dispose();
  });

  testWidgets('בלי תוכן לא מוצג חץ', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: ExpandingChevron(isExpanded: false, hasContent: false),
      ),
    );
    expect(find.byType(AnimatedRotation), findsNothing);
  });
}
