import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/font_dropdown_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  setUp(() {
    AppFonts.debugResetSystemFontsCache();
    AppFonts.debugSystemFontsHebrewCache = [
      for (var i = 0; i < 200; i++)
        FontInfo(
          value: 'TestSystemFont$i',
          label: 'גופן בדיקה $i',
          category: i.isEven ? FontCategory.serif : FontCategory.sansSerif,
        ),
    ];
  });

  tearDown(AppFonts.debugResetSystemFontsCache);

  Widget field({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 320,
              child: FontDropdownField(value: value, onChanged: onChanged),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('search from a distant selected font resets the visible range', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      field(value: 'TestSystemFont180', onChanged: (value) => picked = value),
    );
    await tester.tap(find.byType(FontDropdownField));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    expect(scrollable.position.pixels, greaterThan(2000));

    // The previous scroll offset is well past the new one-row result set.
    await tester.enterText(find.byType(RtlTextField), 'גופן בדיקה 181');
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, 0);
    final label = find.descendant(
      of: find.byType(SliverFixedExtentList),
      matching: find.text('גופן בדיקה 181'),
    );
    expect(label, findsOneWidget);
    expect(
      tester.widget<Text>(label).style?.fontFamily,
      AppFonts.renderFontFamily('TestSystemFont181'),
    );
    final row = find.ancestor(of: label, matching: find.byType(InkWell));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('אבגד הוזח')),
      findsOneWidget,
    );

    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(picked, 'TestSystemFont181');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Serif/Sans filtering and an empty search do not retain rows', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      field(value: AppFonts.defaultFont, onChanged: (value) => picked = value),
    );
    await tester.tap(find.byType(FontDropdownField));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sans'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(RtlTextField), 'גופן בדיקה 19');
    await tester.pumpAndSettle();

    expect(find.text('גופן בדיקה 191'), findsOneWidget);
    expect(find.text('גופן בדיקה 190'), findsNothing);

    await tester.enterText(find.byType(RtlTextField), 'לא קיים');
    await tester.pumpAndSettle();
    expect(find.byType(SliverFixedExtentList), findsNothing);

    await tester.enterText(find.byType(RtlTextField), 'גופן בדיקה 18');
    await tester.pumpAndSettle();
    expect(find.text('גופן בדיקה 181'), findsOneWidget);
    expect(find.text('גופן בדיקה 180'), findsNothing);

    await tester.tap(find.text('Serif'));
    await tester.pumpAndSettle();
    expect(find.text('גופן בדיקה 180'), findsOneWidget);
    expect(find.text('גופן בדיקה 181'), findsNothing);

    await tester.tap(find.text('גופן בדיקה 180'));
    await tester.pumpAndSettle();
    expect(picked, 'TestSystemFont180');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('fast jumps preserve visible preview fonts at larger row sizes', (
    tester,
  ) async {
    final metrics = AppMenuMetrics.create(
      compactMenus: false,
    ).copyWith(itemHeight: 52, fontSize: 21);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [metrics]),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
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
      ),
    );
    await tester.tap(find.byType(FontDropdownField));
    await tester.pumpAndSettle();

    final listFinder = find.byType(SliverFixedExtentList);
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );

    for (final target in [3500.0, 0.0, 6200.0, 950.0]) {
      scrollable.position.jumpTo(
        target.clamp(0.0, scrollable.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SliverFixedExtentList>(listFinder).itemExtent, 52);

      final viewport = tester.getRect(find.byType(Viewport));
      var visible = 0;
      var cached = 0;
      for (final font in AppFonts.availableFonts) {
        final label = find.descendant(
          of: find.byType(Scrollable).last,
          matching: find.text(font.label, skipOffstage: false),
          skipOffstage: false,
        );
        if (label.evaluate().isEmpty) continue;
        final row = find.ancestor(
          of: label,
          matching: find.byType(InkWell, skipOffstage: false),
        );
        final intersects = tester.getRect(row).overlaps(viewport);
        final texts = tester
            .widgetList<Text>(
              find.descendant(
                of: row,
                matching: find.byType(Text, skipOffstage: false),
                skipOffstage: false,
              ),
            )
            .toList();
        expect(texts, hasLength(2));
        for (final text in texts) {
          expect(
            text.style?.fontFamily,
            intersects ? AppFonts.renderFontFamily(font.value) : isNull,
            reason: 'font ${font.value}, scroll to $target',
          );
        }
        if (intersects) {
          visible++;
        } else {
          cached++;
        }
      }
      expect(visible, greaterThan(0));
      expect(cached, greaterThan(0));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
