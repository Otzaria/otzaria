import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/markers_column.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/special_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

import '../support/tikkun_fakes.dart';

import '../support/tikkun_fixtures.dart';

const Size _surface = Size(1200, 400);
const TikkunSettings _settings = TikkunSettings();

Future<void> _pump(WidgetTester tester, TikkunLine line) async {
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final metrics = TikkunRenderMetrics.forWidth(
    _surface.width,
    _settings,
    lineWidthEm: kTestLineWidthEm,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SpecialRow(
            line: line,
            metrics: metrics,
            settings: _settings,
            hideStam: false,
            hideNikud: false,
            markers: MarkersColumn(metrics: metrics),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('הרווח בין טורי השירה הוא שיעור הפרשה, לפי הכתב', (tester) async {
    await _pump(
      tester,
      TikkunLine(
        layout: LineLayout.shiraZigzag,
        zigzagRow: ZigzagRow.manual,
        cssClass: 'justify-cells',
        manualCells: [
          ManualCell(width: 50, words: [word('אחת'), word('שתים')]),
          ManualCell(width: 50, words: [word('שלוש'), word('ארבע')]),
        ],
      ),
    );

    final metrics = TikkunRenderMetrics.forWidth(
      _surface.width,
      _settings,
      lineWidthEm: kTestLineWidthEm,
    );
    final expected = tikkunSetumaGapWidth(metrics.stamStyle());
    final rows = tester.widgetList<Row>(find.byType(Row));
    expect(
      rows.any((r) => ((r.spacing) - expected).abs() < 0.01),
      isTrue,
      reason: 'הרווח נגזר מרוחב "אשר" בגופן ולא מגופן השורה',
    );
  });

  testWidgets('שירה מקבילה: בלוק ימני, רווח ובלוק שמאלי', (tester) async {
    await _pump(
      tester,
      TikkunLine(
        layout: LineLayout.shiraParallel,
        rightWords: [word('אחת'), word('שתים')],
        leftWords: [word('שלוש')],
      ),
    );

    // שלוש מילים בכל טור — סת"ם ומנוקד.
    expect(find.byType(StamWord), findsNWidgets(3));
    final wraps = tester.widgetList<Wrap>(find.byType(Wrap));
    expect(
      wraps.where((w) => w.alignment == WrapAlignment.start),
      isNotEmpty,
    );
    expect(wraps.where((w) => w.alignment == WrapAlignment.end), isNotEmpty);
  });

  testWidgets('זיגזג משולש: 25/50/25 מרוחב הטור', (tester) async {
    await _pump(
      tester,
      TikkunLine(
        layout: LineLayout.shiraZigzag,
        zigzagRow: ZigzagRow.triple,
        rightWords: [word('ימין')],
        centerWords: [word('מרכז')],
        leftWords: [word('שמאל')],
      ),
    );

    final metrics = TikkunRenderMetrics.forWidth(
      _surface.width,
      _settings,
      lineWidthEm: kTestLineWidthEm,
    );
    final columnWidth =
        (_surface.width - metrics.markersWidth - metrics.columnGap * 2) / 2;
    final contentWidth = columnWidth - metrics.em(0.5) * 2;
    final widths = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .map((b) => b.width)
        .whereType<double>();
    expect(
      widths.any((w) => (w - contentWidth * 0.25).abs() < 0.5),
      isTrue,
    );
    expect(widths.any((w) => (w - contentWidth * 0.5).abs() < 0.5), isTrue);
  });

  testWidgets('רשימה ריבועית מציגה ארבעה תאים בשני זוגות', (tester) async {
    await _pump(
      tester,
      TikkunLine(
        layout: LineLayout.listQuad,
        cells: [
          [word('א')],
          [word('ב')],
          [word('ג')],
          [word('ד')],
        ],
      ),
    );

    expect(find.byType(StamWord), findsNWidgets(4));
  });

  testWidgets('אריחי שירה: הכתב צמוד לצדדים והרווח שביניהם מצטמצם', (
    tester,
  ) async {
    Future<double> gapOf(List<LayoutWord> right) async {
      await _pump(
        tester,
        TikkunLine(
          layout: LineLayout.shiraZigzag,
          zigzagRow: ZigzagRow.manual,
          manualCells: [
            ManualCell(width: 40, words: right),
            ManualCell(width: 60, words: [word('שמאל')]),
          ],
        ),
      );
      Rect rectOf(String text) {
        final box =
            tester
                    .elementList(find.widgetWithText(StamWord, text))
                    .first
                    .renderObject!
                as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }

      // ימין-לשמאל: התא הראשון ימני, ולכן הרווח הוא עד קצהו השמאלי.
      return rectOf(right.last.stam).left - rectOf('שמאל').right;
    }

    final narrow = await gapOf([word('ימין')]);
    final wide = await gapOf([word('ימין'), word('והמצולות')]);
    expect(narrow, greaterThan(0));
    expect(wide, lessThan(narrow));
  });

  testWidgets('קטע compact נכתב בגודל מלא כשהוא נכנס ברוחבו', (tester) async {
    await _pump(
      tester,
      TikkunLine(
        layout: LineLayout.listPairs,
        cssClass: 'compact',
        rightWords: [word('שם')],
        leftWords: [word('אחד')],
      ),
    );

    final metrics = TikkunRenderMetrics.forWidth(
      _surface.width,
      _settings,
      lineWidthEm: kTestLineWidthEm,
    );
    final stam = tester.widgetList<StamWord>(find.byType(StamWord)).first;
    expect(stam.style.fontSize, closeTo(metrics.stamFontSize, 0.01));
  });

  testWidgets('תא צפוף מצמצם את כתב השורה כולה ואינו גולש לשורה שנייה', (
    tester,
  ) async {
    final crowded = [for (var i = 0; i < 2; i++) word('והמצולות')];
    await _pump(
      tester,
      TikkunLine(
        layout: LineLayout.shiraZigzag,
        zigzagRow: ZigzagRow.manual,
        manualCells: [
          ManualCell(width: 25, words: crowded),
          ManualCell(width: 50, words: [word('אחת')]),
          ManualCell(width: 25, words: [word('שתים')]),
        ],
      ),
    );

    final stamWords = tester.widgetList<StamWord>(find.byType(StamWord));
    final fontSizes = stamWords.map((w) => w.style.fontSize).toSet();
    expect(fontSizes, hasLength(1), reason: 'כתב אחיד לכל השורה');
    final condensed = stamWords.map((w) => w.condense).toSet();
    final base = TikkunRenderMetrics.forWidth(
      _surface.width,
      _settings,
      lineWidthEm: kTestLineWidthEm,
    ).stamStyle().fontSize!;
    expect(
      fontSizes.single! < base || condensed.single < 1,
      isTrue,
      reason: 'הכתב הוקטן או נדחס',
    );

    final tops = tester
        .elementList(find.widgetWithText(StamWord, 'והמצולות'))
        .map((e) => (e.renderObject as RenderBox).localToGlobal(Offset.zero).dy)
        .toSet();
    expect(tops, hasLength(1), reason: 'התא הצפוף נשאר בשורה אחת');
  });
}
