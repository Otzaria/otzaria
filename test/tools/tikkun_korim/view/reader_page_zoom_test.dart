/// הזום של עמוד התיקון: הגדלה בלבד, בלי שינוי בפריסה, עם גלילה לרוחב.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';

import '../support/tikkun_fixtures.dart';

List<TikkunLine> _lines() => [
  for (var i = 0; i < 6; i++)
    TikkunLine(
      words: [
        for (var w = 0; w < 5; w++) LayoutWord(stam: 'אבגד', nikud: 'אָבְגָד'),
      ],
      startTokenIdx: i,
    ),
];

Future<void> _pump(
  WidgetTester tester,
  TikkunSettings settings, {
  void Function(double)? onZoomChanged,
  double width = 1200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 800,
              child: ReaderPage(
                lineWidthEm: kTestLineWidthEm,
                lines: _lines(),
                settings: settings,
                hideStam: false,
                hideNikud: false,
                onZoomChanged: onZoomChanged,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// גודל הגופן שבו השורות מצוירות בפועל.
double _renderedFontSize(WidgetTester tester) {
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    final size = rt.text.style?.fontSize;
    if (size != null && size > 0) return size;
  }
  fail('לא נמצא טקסט מצויר');
}

void main() {
  testWidgets('הזום מגדיל את הכתב ביחס ישר', (tester) async {
    await _pump(tester, const TikkunSettings());
    final base = _renderedFontSize(tester);

    await _pump(tester, const TikkunSettings(zoom: 1.5));
    expect(_renderedFontSize(tester), closeTo(base * 1.5, 0.01));

    await _pump(tester, const TikkunSettings(zoom: 0.5));
    expect(_renderedFontSize(tester), closeTo(base * 0.5, 0.01));
  });

  testWidgets('הפריסה אינה משתנה עם הזום', (tester) async {
    // רוחב השורה ביחידות em הוא מה שקובע את חיתוך השורות, והוא אינו תלוי בזום.
    const settings = TikkunSettings();
    final plain = TikkunRenderMetrics.forWidth(
      kTikkunReferenceWidth,
      settings,
      lineWidthEm: kTestLineWidthEm,
    );
    for (final zoom in [0.5, 1.0, 2.0, 3.0]) {
      final zoomed = TikkunRenderMetrics.forWidth(
        kTikkunReferenceWidth,
        settings,
        zoom: zoom,
        lineWidthEm: kTestLineWidthEm,
      );
      expect(zoomed.scale, closeTo(plain.scale * zoom, 1e-9));
      expect(
        zoomed.markersWidth / zoomed.stamFontSize,
        closeTo(plain.markersWidth / plain.stamFontSize, 1e-9),
        reason: 'כל המידות נשארות באותו יחס ל-em',
      );
    }
  });

  testWidgets('עמוד רחב מהחלון נגלל לרוחב', (tester) async {
    await _pump(tester, const TikkunSettings(), width: 1200);
    expect(find.byType(Scrollbar), findsNothing);

    await _pump(tester, const TikkunSettings(zoom: 2), width: 1200);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
  });

  testWidgets('גרירה בעכבר גוללת את העמוד בשני הצירים', (tester) async {
    await _pump(tester, const TikkunSettings(zoom: 2), width: 600);
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final before = horizontal.controller!.offset;

    // ב-RTL העמוד מתחיל בקצה הימני, כך שגרירה ימינה היא זו שמקדמת אותו.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(120, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      horizontal.controller!.offset,
      isNot(before),
      reason: 'גרירה אופקית בעכבר מזיזה את העמוד',
    );
  });

  testWidgets('Ctrl+גלגלת מקפיצה מדרגת זום, בלי Ctrl לא', (tester) async {
    final changes = <double>[];
    await _pump(
      tester,
      const TikkunSettings(),
      onZoomChanged: changes.add,
    );

    final center = tester.getCenter(find.byType(ReaderPage));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
    expect(changes, isEmpty, reason: 'גלגלת בלי Ctrl גוללת ולא מזימה');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(changes, [1.1, 0.9], reason: 'מדרגה אחת מעל 1.0 ואחת מתחתיה');
  });
}
