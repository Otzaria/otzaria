import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/markers_column.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/nikud_word.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

import '../support/tikkun_fakes.dart';

const Size _surface = Size(1200, 400);

Future<void> _pump(
  WidgetTester tester,
  TikkunLine line, {
  TikkunSettings settings = const TikkunSettings(),
  bool hideStam = false,
  bool hideNikud = false,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final metrics = TikkunRenderMetrics.forWidth(_surface.width, settings);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ReaderRow(
            line: line,
            metrics: metrics,
            settings: settings,
            hideStam: hideStam,
            hideNikud: hideNikud,
            markers: MarkersColumn(metrics: metrics, verseNum: 1),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('שורה רגילה מפזרת את המילים לשני הכיוונים', (tester) async {
    await _pump(tester, textLine(['אחת', 'שתים', 'שלוש']));

    expect(find.byType(StamWord), findsNWidgets(3));
    expect(find.byType(NikudWord), findsNWidgets(3));
    final rows = tester
        .widgetList<Row>(find.byType(Row))
        .where((r) => r.mainAxisAlignment == MainAxisAlignment.spaceBetween);
    expect(rows, isNotEmpty);
  });

  testWidgets('שורת פתוחה מיישרת להתחלה', (tester) async {
    await _pump(
      tester,
      textLine(['אחת', 'שתים'], layout: LineLayout.petucha),
    );

    final rows = tester
        .widgetList<Row>(find.byType(Row))
        .where(
          (r) =>
              r.mainAxisAlignment == MainAxisAlignment.start &&
              r.spacing > 0 &&
              r.children.length == 2,
        );
    expect(rows, isNotEmpty);
  });

  testWidgets('רווח סתומה תופס תשעה תווים', (tester) async {
    const settings = TikkunSettings();
    final line = TikkunLine(
      words: [
        word('אחת'),
        const LayoutWord(stam: kGapWord, nikud: kGapWord),
        word('שתים'),
      ],
      layout: LineLayout.setuma,
    );
    await _pump(tester, line, settings: settings);

    final metrics = TikkunRenderMetrics.forWidth(_surface.width, settings);
    final expected = tikkunSetumaGapWidth(metrics.stamStyle());
    // הרווח לעולם לא צר משיעור הפרשה, ובולע את עודף השורה.
    final spacers = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((b) => b.width != null && b.width! >= expected - 0.01);
    expect(spacers, isNotEmpty);
  });

  testWidgets('רווח פתיחת פרשה סתומה תופס שני שליש מהטור', (tester) async {
    final line = TikkunLine(
      words: [
        const LayoutWord(stam: kBigGapWord, nikud: kBigGapWord),
        word('אחת'),
      ],
      layout: LineLayout.setumaStart,
    );
    await _pump(tester, line);

    final wide = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((b) => b.width != null && b.width! > 200);
    expect(wide, isNotEmpty);
  });

  testWidgets('הסתרת קווי ההפרדה מבטלת את הגבול התחתון', (tester) async {
    await _pump(
      tester,
      textLine(['אחת']),
      settings: const TikkunSettings(hideRowBorders: true),
    );

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration != null);
    expect(containers, isEmpty);
  });

  testWidgets('הסתרת טור שומרת על מקומו', (tester) async {
    await _pump(tester, textLine(['אחת']), hideNikud: true);

    final hidden = find.byType(Opacity);
    expect(tester.widget<Opacity>(hidden).opacity, 0);
    expect(tester.getSize(hidden).width, greaterThan(0));
  });

  testWidgets('הסתרת שם השם מחליפה ה לק', (tester) async {
    await _pump(
      tester,
      textLine(['יְהוָה']),
      settings: const TikkunSettings(hideDivineName: true),
    );

    final stam = tester.widget<StamWord>(find.byType(StamWord));
    expect(stam.text.contains('ק'), isTrue);
    expect(stam.text.contains('ה'), isFalse);
  });

  test('טור יחיד ממורכז תופס את כל השורה חוץ מעמודת המסמנים', () {
    const settings = TikkunSettings(hideNikud: true, centerSingleColumn: true);
    final metrics = TikkunRenderMetrics.forWidth(600, settings);

    expect(
      tikkunColumnWidth(600, metrics, settings),
      600 - metrics.markersWidth - 2 * metrics.columnGap,
    );
    expect(
      tikkunColumnWidth(600, metrics, const TikkunSettings()),
      (600 - metrics.markersWidth - 2 * metrics.columnGap) / 2,
    );
  });
}
