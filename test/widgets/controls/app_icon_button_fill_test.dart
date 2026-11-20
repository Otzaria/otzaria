import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/misc/exit_fullscreen_button.dart';
import 'package:otzaria/widgets/text/otzaria_search_field_button.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  ButtonStyle styleOf(WidgetTester tester) =>
      tester.widget<IconButton>(find.byType(IconButton)).style!;

  Color? resolved(WidgetStateProperty<Color?>? property) =>
      property?.resolve(<WidgetState>{});

  ColorScheme schemeOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(IconButton))).colorScheme;

  testWidgets('בלי רקע: פינות 8 ולא עיגול (DD-04), בלי צבע רקע', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AppIconButton(
          icon: const Icon(Icons.add),
          tooltip: 'הוסף',
          onPressed: () {},
        ),
      ),
    );

    final style = styleOf(tester);
    expect(style.shape?.resolve({}), AppTokens.roundedShape);
    expect(style.shape?.resolve({}), isNot(isA<CircleBorder>()));
    expect(resolved(style.backgroundColor), isNull);
  });

  testWidgets('tonal: secondaryContainer, פינות 8', (tester) async {
    await tester.pumpWidget(
      host(
        AppIconButton(
          icon: const Icon(Icons.add),
          tooltip: 'הוסף',
          fill: AppIconButtonFill.tonal,
          onPressed: () {},
        ),
      ),
    );

    final style = styleOf(tester);
    final cs = schemeOf(tester);
    expect(resolved(style.backgroundColor), cs.secondaryContainer);
    expect(resolved(style.foregroundColor), cs.onSecondaryContainer);
    expect(style.shape?.resolve({}), AppTokens.roundedShape);
  });

  testWidgets('neutral: surfaceContainerHighest', (tester) async {
    await tester.pumpWidget(
      host(
        AppIconButton(
          icon: const Icon(Icons.add),
          tooltip: 'הוסף',
          fill: AppIconButtonFill.neutral,
          onPressed: () {},
        ),
      ),
    );

    final style = styleOf(tester);
    final cs = schemeOf(tester);
    expect(resolved(style.backgroundColor), cs.surfaceContainerHighest);
    expect(resolved(style.foregroundColor), cs.onSurface);
    expect(style.shape?.resolve({}), AppTokens.roundedShape);
  });

  testWidgets('צבעים מפורשים גוברים על fill, והצורה אותה צורה, פינות 8', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AppIconButton(
          icon: const Icon(Icons.add),
          tooltip: 'הוסף',
          fill: AppIconButtonFill.tonal,
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );

    final style = styleOf(tester);
    expect(resolved(style.backgroundColor), Colors.red);
    expect(resolved(style.foregroundColor), Colors.white);
    expect(style.shape?.resolve({}), AppTokens.roundedShape);
  });

  testWidgets('extent קובע את צלע הכפתור', (tester) async {
    await tester.pumpWidget(
      host(
        AppIconButton(
          icon: const Icon(Icons.add),
          tooltip: 'הוסף',
          size: AppIconButtonSize.small,
          extent: 24,
          fill: AppIconButtonFill.tonal,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () {},
        ),
      ),
    );

    final box = tester.getSize(find.byType(IconButton));
    expect(box, const Size(24, 24));
  });

  testWidgets('selectedIcon מוצג במצב נבחר', (tester) async {
    await tester.pumpWidget(
      host(
        AppIconButton(
          icon: const Icon(Icons.visibility_off),
          selectedIcon: const Icon(Icons.visibility),
          isSelected: true,
          tooltip: 'הצג',
          onPressed: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);
  });

  testWidgets('כפתור היציאה ממסך מלא: AppIconButton עם רקע נייטרלי', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ExitFullscreenButton()));

    final button = tester.widget<AppIconButton>(find.byType(AppIconButton));
    expect(button.fill, AppIconButtonFill.neutral);
  });

  testWidgets('כפתור מתג בשדה חיפוש במצב נבחר: רקע סימון הסרגל', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        OtzariaSearchFieldButton(
          icon: Icons.text_fields,
          tooltip: 'התאמה מלאה',
          selected: true,
          onPressed: () {},
        ),
      ),
    );

    final cs = schemeOf(tester);
    final style = styleOf(tester);
    expect(resolved(style.backgroundColor), AppSurfaces.barButtonSelected(cs));
    expect(style.shape?.resolve({}), AppTokens.roundedShape);
  });

  testWidgets('כפתור מתג בשדה חיפוש כבוי: בלי רקע', (tester) async {
    await tester.pumpWidget(
      host(
        OtzariaSearchFieldButton(
          icon: Icons.text_fields,
          tooltip: 'התאמה מלאה',
          onPressed: () {},
        ),
      ),
    );

    expect(resolved(styleOf(tester).backgroundColor), isNull);
  });
}
