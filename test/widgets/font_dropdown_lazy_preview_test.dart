import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/misc/font_dropdown_field.dart';

void main() {
  const fontCount = 200;

  setUp(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.debugSystemFontsHebrewCache = [
      for (var i = 0; i < fontCount; i++)
        FontInfo(value: 'TestSystemFont$i', label: 'גופן בדיקה $i'),
    ];
  });

  tearDown(() {
    AppFonts.debugResetSystemFontsCache();
  });

  for (final selected in [AppFonts.defaultFont, 'TestSystemFont180']) {
    testWidgets('רק שורות נראות משתמשות בגופן התצוגה המקדימה: $selected', (
      tester,
    ) async {
      AppFonts.debugWarmUpFuture = Future.value();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 320,
                child: FontDropdownField(
                  value: selected,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(FontDropdownField));
      await tester.pumpAndSettle();

      void expectOnlyVisibleRowsBuilt() {
        final viewport = tester.getRect(find.byType(Viewport));
        var previews = 0;
        var placeholders = 0;
        for (final font in AppFonts.availableFonts) {
          final name = find.descendant(
            of: find.byType(Scrollable).last,
            matching: find.text(font.label, skipOffstage: false),
            skipOffstage: false,
          );
          if (name.evaluate().isEmpty) continue;
          final row = find.ancestor(
            of: name,
            matching: find.byType(InkWell, skipOffstage: false),
          );
          final isVisible = tester.getRect(row).overlaps(viewport);
          final texts = tester.widgetList<Text>(
            find.descendant(
              of: row,
              matching: find.byType(Text, skipOffstage: false),
              skipOffstage: false,
            ),
          );
          // שמות ודוגמאות נשארים במטמון לצורך מיקוד ונגישות, בגופן זול.
          expect(texts.length, 2);
          for (final text in texts) {
            expect(
              text.style?.fontFamily,
              isVisible ? AppFonts.renderFontFamily(font.value) : isNull,
              reason: '${font.label}: תצוגה מקדימה רק בחפיפה לתחום הציור',
            );
          }
          isVisible ? previews++ : placeholders++;
        }
        expect(previews, greaterThan(0));
        expect(placeholders, greaterThan(0));
      }

      expectOnlyVisibleRowsBuilt();
      expect(
        find.text(
          AppFonts.availableFonts
              .firstWhere((font) => font.value == selected)
              .label,
        ),
        findsNWidgets(2),
      );

      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expectOnlyVisibleRowsBuilt();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      position.jumpTo(
        (position.pixels - 13).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expectOnlyVisibleRowsBuilt();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
