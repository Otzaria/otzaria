import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/font_dropdown_field.dart';

void main() {
  setUp(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.debugWarmUpFuture = Future.value();
    AppFonts.debugSystemFontsHebrewCache = [
      for (var i = 0; i < 100; i++)
        FontInfo(value: 'TestSystemFont$i', label: 'גופן בדיקה $i'),
    ];
  });

  tearDown(AppFonts.debugResetSystemFontsCache);

  for (final fontMenu in [false, true]) {
    testWidgets('Tab ו־Shift+Tab גוללים בין כל הפריטים: font=$fontMenu', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final labels = fontMenu
            ? AppFonts.availableFonts.map((font) => font.label).toList()
            : [for (var i = 0; i < 100; i++) 'פריט $i'];
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 320,
                    child: fontMenu
                        ? FontDropdownField(
                            value: AppFonts.availableFonts.first.value,
                            onChanged: (value) => selected = value,
                          )
                        : AppDropdownField<int>(
                            value: 0,
                            enableSearch: true,
                            entries: [
                              for (var i = 0; i < 100; i++)
                                AppMenuEntry(value: i, label: labels[i]),
                            ],
                            onSelected: (value) => selected = '$value',
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is AppDropdownField),
        );
        await tester.pumpAndSettle();
        List<String> focusedLabels() {
          final context = FocusManager.instance.primaryFocus!.context!;
          return tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byElementPredicate(
                    (element) => identical(element, context),
                  ),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data ?? '')
              .toList();
        }

        Future<void> tab({bool reverse = false}) async {
          if (reverse) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          if (reverse) {
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.pumpAndSettle();
        }

        for (var i = 0; i < 8 && !focusedLabels().contains(labels.first); i++) {
          await tab();
        }
        expect(focusedLabels(), contains(labels.first));
        for (var i = 0; i < 29; i++) {
          await tab();
        }
        expect(focusedLabels(), contains(labels[29]));
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).last,
        );
        expect(scrollable.position.pixels, greaterThan(400));
        var previousIndex = 29;
        for (var i = 0; i < 100 && previousIndex > 9; i++) {
          await tab(reverse: true);
          final focused = focusedLabels();
          final index = labels.indexWhere(focused.contains);
          if (index < 0) continue;
          expect(index, previousIndex - 1);
          previousIndex = index;
        }
        expect(focusedLabels(), contains(labels[9]));
        expect(
          tester.getSemantics(find.text(labels[9])).label,
          contains(labels[9]),
        );
        if (fontMenu) {
          final row = find.ancestor(
            of: find.text(labels[9]),
            matching: find.byType(InkWell),
          );
          expect(
            find.descendant(of: row, matching: find.text('אבגד הוזח')),
            findsOneWidget,
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selected, fontMenu ? AppFonts.availableFonts[9].value : '9');
      } finally {
        semantics.dispose();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
