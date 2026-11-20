// כפתור "צור אירוע" הנסתר בתא היום נשמר כאותו מופע בין בנייה לבנייה, כדי
// שבחירת יום (בנייה מחדש של 42 תאים) לא תעדכן 42 כפתורים.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';

void main() {
  late StateSetter rebuildParent;
  late VoidCallback onAdd;
  late ColorScheme scheme;

  Future<void> pumpCell(WidgetTester tester) async {
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuildParent = setState;
          return MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Scaffold(
              body: SizedBox(
                width: 120,
                height: 100,
                child: HoverableDayCell(
                  onAdd: onAdd,
                  builder: (isHovered) => const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconButton addButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.byType(IconButton));

  Future<void> hover(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(HoverableDayCell)));
    await tester.pumpAndSettle();
  }

  setUp(() {
    onAdd = () {};
    scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
  });

  testWidgets('בנייה מחדש של ההורה ורחיפה אינן בונות את הכפתור מחדש', (
    tester,
  ) async {
    await pumpCell(tester);
    final before = addButton(tester);

    rebuildParent(() => onAdd = () {});
    await tester.pump();
    expect(identical(addButton(tester), before), isTrue);

    await hover(tester);
    expect(identical(addButton(tester), before), isTrue);
  });

  testWidgets('לחיצה קוראת ל-onAdd העדכני אחרי בנייה מחדש', (tester) async {
    var oldCalls = 0;
    var newCalls = 0;
    onAdd = () => oldCalls++;
    await pumpCell(tester);

    rebuildParent(() => onAdd = () => newCalls++);
    await tester.pump();
    await hover(tester);
    await tester.tap(find.byType(IconButton));

    expect(newCalls, 1);
    expect(oldCalls, 0);
  });

  testWidgets('שינוי ערכת צבעים מעדכן את צבעי הכפתור', (tester) async {
    await pumpCell(tester);
    rebuildParent(
      () => scheme = ColorScheme.fromSeed(seedColor: Colors.green),
    );
    await tester.pumpAndSettle();

    final background = addButton(
      tester,
    ).style!.backgroundColor!.resolve(<WidgetState>{});
    expect(background, scheme.primaryContainer);
  });

  testWidgets('הכפתור מוסתר ואינו לחיץ עד לריחוף', (tester) async {
    var calls = 0;
    onAdd = () => calls++;
    await pumpCell(tester);

    final opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacity.opacity, 0.0);
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    expect(calls, 0);

    await hover(tester);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1.0,
    );
  });
}
