// כפתור "הוסף אירוע" בתא היום נשמר כאותו מופע בין בנייה לבנייה, כדי
// שבחירת יום (בנייה מחדש של 42 תאים) לא תעדכן 42 כפתורים. הוא גלוי רק
// בריחוף על התא, בנגיעה בו או במיקוד מקלדת.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

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
                  // כמו התא האמיתי: התוכן נבדק בלחיצה (hit test).
                  builder: (isHovered) => const SizedBox.expand(
                    child: ColoredBox(color: Colors.transparent),
                  ),
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

  testWidgets('הכפתור הוא AppIconButton עם tooltip, וצבעיו מערכת הנושא', (
    tester,
  ) async {
    await pumpCell(tester);
    expect(find.byType(AppIconButton), findsOneWidget);
    expect(addButton(tester).tooltip, 'הוסף אירוע');

    rebuildParent(
      () => scheme = ColorScheme.fromSeed(seedColor: Colors.green),
    );
    await tester.pumpAndSettle();

    final iconColor = IconTheme.of(
      tester.element(find.byIcon(FluentIcons.add_24_regular)),
    ).color;
    expect(iconColor, scheme.onSurfaceVariant);
  });

  double addOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byType(AppIconButton),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('הכפתור מוסתר ואינו לחיץ עד ריחוף על התא, ונעלם כשהעכבר יוצא', (
    tester,
  ) async {
    var calls = 0;
    onAdd = () => calls++;
    await pumpCell(tester);

    expect(addOpacity(tester), 0.0);
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    expect(calls, 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getTopLeft(find.byType(HoverableDayCell)) + const Offset(4, 90),
    );
    await tester.pumpAndSettle();
    expect(addOpacity(tester), 1.0);

    await tester.tap(find.byType(IconButton));
    expect(calls, 1);

    await gesture.moveTo(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(addOpacity(tester), 0.0);
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    expect(calls, 1);
  });

  testWidgets('בריחוף על הכפתור עצמו מקבל מילוי עגול', (tester) async {
    await pumpCell(tester);
    BoxDecoration fill() =>
        tester
                .widget<AnimatedContainer>(
                  find.ancestor(
                    of: find.byType(AppIconButton),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(fill().shape, BoxShape.circle);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getTopLeft(find.byType(HoverableDayCell)) + const Offset(4, 90),
    );
    await tester.pumpAndSettle();
    expect(fill().color, Colors.transparent);

    await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
    await tester.pumpAndSettle();
    expect(fill().color, scheme.surfaceContainerHighest);
  });

  testWidgets('מעבר מקלדת (Tab) לכפתור מציג אותו, ו-Enter מוסיף אירוע', (
    tester,
  ) async {
    var calls = 0;
    onAdd = () => calls++;
    await pumpCell(tester);
    expect(addOpacity(tester), 0.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(addOpacity(tester), 1.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 1);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(addOpacity(tester), 0.0);
  });

  testWidgets('במגע: נגיעה בתא מציגה את הכפתור, ונגיעה בו מוסיפה אירוע', (
    tester,
  ) async {
    var calls = 0;
    onAdd = () => calls++;
    await pumpCell(tester);
    expect(addOpacity(tester), 0.0);

    await tester.tapAt(
      tester.getTopLeft(find.byType(HoverableDayCell)) + const Offset(4, 90),
    );
    await tester.pumpAndSettle();
    expect(addOpacity(tester), 1.0);
    expect(calls, 0);

    await tester.tap(find.byType(IconButton));
    expect(calls, 1);
  });
}
