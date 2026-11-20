// עיגול בחירת צבע משותף (פריט 27, theme-dark-05 / CC-21): הנבחר מסומן בוי
// ובשם ומצב לקורא מסך, לא בצבע בלבד.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/controls/app_color_swatch.dart';

Widget _app(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: Center(child: child)),
  ),
);

AppColorSwatch _swatch({
  Color? color = Colors.white,
  bool selected = false,
  String label = 'לבן',
  VoidCallback? onTap,
}) => AppColorSwatch(
  color: color,
  selected: selected,
  label: label,
  onTap: onTap ?? () {},
);

Finder get _check => find.byIcon(FluentIcons.checkmark_24_regular);

BoxDecoration _circle(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppColorSwatch),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 40,
      ),
    ),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('נבחר: וי על העיגול ו-Semantics selected עם שם הצבע', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_swatch(selected: true)));

    expect(_check, findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AppColorSwatch)),
      isSemantics(
        label: 'לבן',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('לא נבחר: בלי וי, Semantics לא נבחר, ומסגרת דקה שנראית', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(_swatch()));

    expect(_check, findsNothing);
    expect(
      tester.getSemantics(find.byType(AppColorSwatch)),
      isSemantics(label: 'לבן', isButton: true, isSelected: false),
    );
    final border = _circle(tester).border! as Border;
    expect(border.top.width, 1);
    expect(border.top.color, ThemeData().colorScheme.outline);
    semantics.dispose();
  });

  testWidgets('"ללא צבע": עיגול ריק עם קו, ווי כשנבחר', (tester) async {
    await tester.pumpWidget(_app(_swatch(color: null, label: 'ללא צבע')));
    expect(
      find.byIcon(FluentIcons.line_horizontal_1_24_regular),
      findsOneWidget,
    );
    expect(_check, findsNothing);

    await tester.pumpWidget(
      _app(_swatch(color: null, label: 'ללא צבע', selected: true)),
    );
    expect(_check, findsOneWidget);
  });

  testWidgets('הווי קריא על עיגול בהיר וכהה: שחור על צהוב, לבן על כחול כהה', (
    tester,
  ) async {
    for (final (color, expected) in [
      (const Color(0xFFFFEB3B), Colors.black),
      (const Color(0xFF001A33), Colors.white),
    ]) {
      await tester.pumpWidget(_app(_swatch(color: color, selected: true)));
      expect(tester.widget<Icon>(_check).color, expected, reason: '$color');
    }
  });

  testWidgets('נלחץ בעכבר ובמקלדת (Enter ורווח)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(_swatch(onTap: () => taps++)));
    await tester.tap(find.byType(AppColorSwatch));
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 3);
  });

  testWidgets('שטח לחיצה של 48 לפחות סביב עיגול של 40', (tester) async {
    await tester.pumpWidget(_app(_swatch()));
    final size = tester.getSize(find.byType(AppColorSwatch));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
