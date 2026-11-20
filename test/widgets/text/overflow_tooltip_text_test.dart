import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/overflow_tooltip_text.dart';

const _long = 'כף החיים על שולחן ערוך אורח חיים';
const _short = 'סימן א';

Widget _rows(double width, {int generation = 0}) => MaterialApp(
  home: Material(
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SizedBox(
          width: width,
          child: Column(
            // דור שונה = מופעי widget חדשים, כמו בנייה מחדש של הרשימה.
            key: ValueKey(generation),
            children: const [
              OverflowTooltipText(text: _long),
              OverflowTooltipText(text: _short),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('בנייה מחדש באותו רוחב אינה מודדת שוב את הטקסט', (tester) async {
    await tester.pumpWidget(_rows(150));
    final afterFirst = debugTextOverflowLayouts;
    for (var generation = 1; generation <= 5; generation++) {
      await tester.pumpWidget(_rows(150, generation: generation));
    }
    expect(debugTextOverflowLayouts, afterFirst);
  });

  testWidgets('Tooltip רק לטקסט שגולש, גם אחרי שינוי רוחב', (tester) async {
    Finder tooltipFor(String text) =>
        find.ancestor(of: find.text(text), matching: find.byType(Tooltip));

    await tester.pumpWidget(_rows(150));
    expect(tooltipFor(_long), findsOneWidget);
    expect(tooltipFor(_short), findsNothing);

    await tester.pumpWidget(_rows(790, generation: 1));
    expect(tooltipFor(_long), findsNothing);

    await tester.pumpWidget(_rows(150, generation: 2));
    expect(tooltipFor(_long), findsOneWidget);
  });

  testWidgets('שינוי בגופני המערכת מודד מחדש', (tester) async {
    await tester.pumpWidget(_rows(150));
    final before = debugTextOverflowLayouts;
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    await tester.pumpWidget(_rows(150, generation: 1));
    expect(debugTextOverflowLayouts, greaterThan(before));
  });
}
