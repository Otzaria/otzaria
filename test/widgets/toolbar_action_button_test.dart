import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ToolbarActionButton — השבתה', () {
    testWidgets('onPressed=null מרנדר IconButton מושבת', (tester) async {
      await tester.pumpWidget(wrap(const ToolbarActionButton(
        tooltip: 'הצג תצוגה מקדימה',
        icon: FluentIcons.eye_24_regular,
        onPressed: null,
      )));

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('onPressed לא-null מרנדר כפתור פעיל', (tester) async {
      await tester.pumpWidget(wrap(ToolbarActionButton(
        tooltip: 'הצג תצוגה מקדימה',
        icon: FluentIcons.eye_24_regular,
        onPressed: () {},
      )));

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('onPressed=null צובע את האייקון בצבע מושבת', (tester) async {
      late final Color disabledColor;
      await tester.pumpWidget(wrap(Builder(
        builder: (context) {
          disabledColor = Theme.of(context).disabledColor;
          return const ToolbarActionButton(
            tooltip: 'הצג תצוגה מקדימה',
            icon: FluentIcons.eye_24_regular,
            onPressed: null,
          );
        },
      )));

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, disabledColor);
    });
  });
}
