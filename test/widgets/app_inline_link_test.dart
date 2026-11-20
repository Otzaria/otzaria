import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/app_inline_link.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('קישור: צבע primary, קו תחתון באותו צבע, והקשה מפעילה', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(AppInlineLink(text: 'פתח', onTap: () => taps++)),
    );

    final primary = Theme.of(
      tester.element(find.text('פתח')),
    ).colorScheme.primary;
    final style = tester.widget<Text>(find.text('פתח')).style!;
    expect(style.color, primary);
    expect(style.decoration, TextDecoration.underline);
    expect(style.decorationColor, primary);

    await tester.tap(find.text('פתח'));
    expect(taps, 1);
  });

  testWidgets('בלי onTap: טקסט רגיל בסגנון שהועבר, בלי קו תחתון ובלי לחיצה', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const AppInlineLink(
          text: 'נתיב',
          onTap: null,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );

    final style = tester.widget<Text>(find.text('נתיב')).style!;
    expect(style.color, Colors.grey);
    expect(style.decoration, isNull);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('הסגנון הבסיסי נשמר: גודל ומשקל', (tester) async {
    await tester.pumpWidget(
      host(
        AppInlineLink(
          text: 'קישור',
          onTap: () {},
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );

    final style = tester.widget<Text>(find.text('קישור')).style!;
    expect(style.fontSize, 12);
    expect(style.fontWeight, FontWeight.bold);
    expect(style.decoration, TextDecoration.underline);
  });

  testWidgets('מקלדת: Tab מגיע לקישור ו-Enter מפעיל אותו', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(AppInlineLink(text: 'פתח', onTap: () => taps++)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('tooltip מוצג רק כשנתון', (tester) async {
    await tester.pumpWidget(
      host(AppInlineLink(text: 'פתח', onTap: () {}, tooltip: 'פתיחה בדפדפן')),
    );
    expect(find.byTooltip('פתיחה בדפדפן'), findsOneWidget);

    await tester.pumpWidget(host(AppInlineLink(text: 'פתח', onTap: () {})));
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('styleOf: לקישור בתוך משפט', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            style = AppInlineLink.styleOf(
              context,
              const TextStyle(fontWeight: FontWeight.w600),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    final primary = ThemeData().colorScheme.primary;
    expect(style.color, primary);
    expect(style.decoration, TextDecoration.underline);
    expect(style.decorationColor, primary);
    expect(style.fontWeight, FontWeight.w600);
  });
}
