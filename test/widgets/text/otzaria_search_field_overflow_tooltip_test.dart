import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// issue #4608 — בשדה צר השאילתה נחתכת; בריחוף מוצג הטקסט המלא.
void main() {
  const longQuery = 'את שמע ישראל ה׳ אלהינו ה׳ אחד ואהבת את ה׳ אלהיך';

  Future<(TextEditingController, FocusNode)> pumpField(
    WidgetTester tester,
    String text, {
    double width = 160,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: OtzariaSearchField(
                  controller: controller,
                  focusNode: focusNode,
                  hintText: 'חפש כאן...',
                  onClear: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, focusNode);
  }

  Future<void> hoverField(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(EditableText)));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  for (final (name, seed, brightness) in [
    ('בהיר', AppSeedColors.defaultLight, Brightness.light),
    ('כהה', AppSeedColors.defaultDark, Brightness.dark),
    ('לבן', AppSeedColors.white, Brightness.light),
  ]) {
    for (final width in [360.0, 800.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('טולטיפ ב־RTL: $name, רוחב $width, טקסט $scale', (
          tester,
        ) async {
          final theme = AppThemeData.light(
            AppThemeData.createColorScheme(seed, brightness),
            compactMenuMode: false,
            variant: AppThemeVariant.ofSeed(seed),
          );
          final query = List.filled(4, longQuery).join(' ');
          await pumpField(
            tester,
            query,
            width: width,
            textScale: scale,
            theme: theme,
          );
          await hoverField(tester);
          expect(find.byTooltip(query), findsOneWidget);
          expect(find.text(query), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('טקסט שנחתך מוצג בטולטיפ בריחוף', (tester) async {
    await pumpField(tester, longQuery);
    await hoverField(tester);

    expect(find.byTooltip(longQuery), findsOneWidget);
    expect(find.text(longQuery), findsNWidgets(2));
  });

  testWidgets('טקסט שנכנס בשדה אינו מקבל טולטיפ', (tester) async {
    await pumpField(tester, 'שמע');

    expect(find.byTooltip('שמע'), findsNothing);
  });

  testWidgets('בעריכה אין טולטיפ, והפוקוס נשמר במעבר', (tester) async {
    final (_, focusNode) = await pumpField(tester, longQuery);
    expect(find.byTooltip(longQuery), findsOneWidget);

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(find.byTooltip(longQuery), findsNothing);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('שינוי שאילתה מעדכן טולטיפ ושומר פוקוס ובחירה', (tester) async {
    final (controller, focusNode) = await pumpField(tester, longQuery);
    for (final text in ['שמע', '', longQuery]) {
      controller.text = text;
      controller.selection = TextSelection.collapsed(offset: text.length);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(longQuery),
        text == longQuery ? findsOneWidget : findsNothing,
      );
      expect(focusNode.hasFocus, isFalse);
      expect(controller.selection.baseOffset, text.length);
    }
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 4);
    controller.text = '$longQuery א';
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pumpAndSettle();
    expect(find.byTooltip(controller.text), findsNothing);
    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('שינוי רוחב הורה מעדכן טולטיפ בלי לאבד בחירה', (tester) async {
    const query = 'שמע ישראל ה׳ אלהינו ה׳ אחד';
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(160, 600);
    final (controller, focusNode) = await pumpField(
      tester,
      query,
      width: 800,
    );
    controller.selection = const TextSelection.collapsed(offset: 5);
    expect(find.byTooltip(query), findsOneWidget);
    for (final width in [800.0, 160.0]) {
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(query),
        width == 160 ? findsOneWidget : findsNothing,
      );
      expect(controller.selection.baseOffset, 5);
      expect(focusNode.hasFocus, isFalse);
    }
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 5);
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(controller.selection.baseOffset, 5);
    expect(focusNode.hasFocus, isTrue);
    expect(find.byTooltip(query), findsNothing);
  });

  testWidgets('ריחוף על כפתור בשדה מציג רק את הטולטיפ של הכפתור', (
    tester,
  ) async {
    await pumpField(tester, longQuery);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byTooltip('נקה')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('נקה'), findsOneWidget);
    expect(find.text(longQuery), findsOneWidget);
  });
}
