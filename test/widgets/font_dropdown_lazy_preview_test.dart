// גופן פגום תוקע את DirectWrite בפריסה (#4505), לכן בבורר הגופנים נפרסות
// רק שורות שעל המסך — לא גם שורות במטמון הגלילה מעבר לגבולותיו.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/misc/font_dropdown_field.dart';

void main() {
  const fontCount = 200;

  setUp(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.debugWarmUpFuture = Future.value();
    AppFonts.debugSystemFontsHebrewCache = [
      for (var i = 0; i < fontCount; i++)
        FontInfo(value: 'TestSystemFont$i', label: 'גופן בדיקה $i'),
    ];
  });

  tearDown(() {
    AppFonts.debugResetSystemFontsCache();
  });

  testWidgets('פתיחת בורר הגופנים בונה תצוגה מקדימה רק לשורות הנראות', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 320,
              child: FontDropdownField(
                value: AppFonts.defaultFont,
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
      final built = <String>[];
      final visible = <String>[];
      for (final font in AppFonts.availableFonts) {
        // הגופן הנבחר מוצג גם בשדה הסגור.
        if (font.value == AppFonts.defaultFont) continue;
        if (find.text(font.label, skipOffstage: false).evaluate().isNotEmpty) {
          built.add(font.label);
        }
        if (find.text(font.label).evaluate().isNotEmpty) {
          visible.add(font.label);
        }
      }
      expect(visible, isNotEmpty);
      expect(built, visible, reason: 'שורות מחוץ לתצוגה לא ייבנו ולא ייפרסו');
    }

    expectOnlyVisibleRowsBuilt();

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expectOnlyVisibleRowsBuilt();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
