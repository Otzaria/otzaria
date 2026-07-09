import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('BarButton.icon — השבתה', () {
    testWidgets('onPressed=null מרנדר IconButton מושבת', (tester) async {
      await tester.pumpWidget(wrap(const BarButton.icon(
        tooltip: 'הצג תצוגה מקדימה',
        icon: FluentIcons.eye_24_regular,
        onPressed: null,
      )));

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('onPressed לא-null מרנדר כפתור פעיל', (tester) async {
      await tester.pumpWidget(wrap(BarButton.icon(
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
          return const BarButton.icon(
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

  group('BarButton.text — צבע מושבת', () {
    testWidgets('onPressed=null פותר את צבע החזית ל-disabledColor',
        (tester) async {
      late final Color disabledColor;
      late final Color enabledColor;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        final theme = Theme.of(context);
        disabledColor = theme.disabledColor;
        enabledColor = theme.colorScheme.onSurfaceVariant;
        return const BarButton.text(text: 'ט', onPressed: null);
      })));

      final ghostTheme = tester.widget<TextButtonTheme>(
        find
            .ancestor(
              of: find.byType(TextButton),
              matching: find.byType(TextButtonTheme),
            )
            .first,
      );
      final fg = ghostTheme.data.style!.foregroundColor!;
      expect(fg.resolve({WidgetState.disabled}), disabledColor);
      expect(fg.resolve(<WidgetState>{}), enabledColor);
    });
  });
}
