import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/markers_column.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/special_row.dart';

import '../support/tikkun_fakes.dart';

const TikkunSettings _settings = TikkunSettings();
const List<String> _words = ['שלום', 'עולם', 'אחד', 'שנים'];

late TikkunRenderMetrics _metrics;
late TextStyle _style;
late double _minGap;
late double _threshold;
late double _used;

double _petuchaGap({required double contentWidth, double? averageGap}) {
  final row =
      buildTikkunWordsRow(
            words: _words.map(word).toList(),
            layout: LineLayout.petucha,
            metrics: _metrics,
            contentWidth: contentWidth,
            isStam: true,
            maskDivineName: false,
            averageGap: averageGap,
          )
          as Row;
  return row.spacing;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _metrics = TikkunRenderMetrics.forWidth(1200, _settings);
    _style = _metrics.stamStyle();
    _minGap = _metrics.em(kTikkunPetuchaMinGapEm);
    _threshold = tikkunSetumaGapWidth(_style);
    _used = tikkunLineItemWidths(
      words: _words.map(word).toList(),
      style: _style,
      contentWidth: 600,
      isStam: true,
      maskDivineName: false,
    ).fold(0.0, (a, b) => a + b);
  });

  test('שורת פתוחה מתרווחת לרווח הממוצע כשיש מקום', () {
    final average = _minGap * 4;
    final gap = _petuchaGap(contentWidth: 900, averageGap: average);

    expect(gap, closeTo(average, 0.01));
  });

  test('כשאין מקום מלא — הרווח קטן והחלל הפתוח נשמר', () {
    final average = _minGap * 8;
    final slots = _words.length - 1;
    final contentWidth = _used + _threshold + slots * _minGap * 2;
    final gap = _petuchaGap(contentWidth: contentWidth, averageGap: average);

    expect(gap, lessThan(average));
    expect(gap, greaterThan(_minGap));
    final open = contentWidth - _used - gap * slots;
    expect(open, greaterThanOrEqualTo(_threshold - 0.01));
  });

  test('בלי מקום כלל הרווח נשאר המזערי', () {
    final gap = _petuchaGap(
      contentWidth: _used + _threshold * 0.5,
      averageGap: _minGap * 8,
    );

    expect(gap, closeTo(_minGap, 0.01));
  });

  test('שורה מיושרת שומרת על הרווח הבסיסי', () {
    final row =
        buildTikkunWordsRow(
              words: _words.map(word).toList(),
              layout: LineLayout.regular,
              metrics: _metrics,
              contentWidth: 900,
              isStam: true,
              maskDivineName: false,
              averageGap: _minGap * 8,
            )
            as Row;

    expect(row.mainAxisAlignment, MainAxisAlignment.spaceBetween);
    expect(row.spacing, 0);
  });

  test('הממוצע נגזר מהשורות המיושרות בלבד', () {
    final lines = [
      textLine(_words),
      textLine(_words),
      textLine(['שלום'], layout: LineLayout.petucha),
    ];
    final averages = computeTikkunGapAverages(
      lines: lines,
      metrics: _metrics,
      settings: _settings,
      rowWidth: 1200,
      hideNikud: false,
    );
    final contentWidth = tikkunColumnContentWidth(
      rowWidth: 1200,
      metrics: _metrics,
      settings: _settings,
      isStam: true,
      hideNikud: false,
    );
    final used = tikkunLineItemWidths(
      words: _words.map(word).toList(),
      style: _style,
      contentWidth: contentWidth,
      isStam: true,
      maskDivineName: false,
    ).fold(0.0, (a, b) => a + b);

    expect(
      averages.stam,
      closeTo((contentWidth - used) / (_words.length - 1), 0.01),
    );
    expect(averages.nikud, isNotNull);
  });

  testWidgets('בעמוד — שורת הפתוחה רחבה מהמינימום', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ReaderPage(
              lines: [
                textLine(_words, chapter: 1, verse: 1),
                textLine(_words, chapter: 1, verse: 2),
                textLine(
                  [
                    'שלום',
                    'עולם',
                  ],
                  layout: LineLayout.petucha,
                  chapter: 1,
                  verse: 3,
                ),
              ],
              settings: _settings,
              hideStam: false,
              hideNikud: false,
            ),
          ),
        ),
      ),
    );

    final petuchaRows = tester
        .widgetList<Row>(find.byType(Row))
        .where(
          (r) =>
              r.mainAxisAlignment == MainAxisAlignment.start &&
              r.spacing > 0 &&
              r.children.length == 2,
        );
    expect(petuchaRows, isNotEmpty);
    expect(
      petuchaRows.every((r) => r.spacing > _metrics.em(kTikkunPetuchaMinGapEm)),
      isTrue,
    );
  });

  group('שורות מיוחדות אינן חורגות', () {
    final specialLines = <String, TikkunLine>{
      'שירה מקבילה': TikkunLine(
        layout: LineLayout.shiraParallel,
        rightWords: [word('שלום'), word('עולם')],
        leftWords: [word('אחד'), word('שנים')],
      ),
      'זיגזג משולש': TikkunLine(
        layout: LineLayout.shiraZigzag,
        zigzagRow: ZigzagRow.triple,
        rightWords: [word('שלום'), word('עולם')],
        centerWords: [word('אחד'), word('שנים')],
        leftWords: [word('שלוש')],
      ),
      'זיגזג יחיד': TikkunLine(
        layout: LineLayout.shiraZigzag,
        zigzagRow: ZigzagRow.single,
        centerWords: [word('שלום'), word('עולם')],
      ),
      'רשימה ריבועית': TikkunLine(
        layout: LineLayout.listQuad,
        cells: [
          [word('דן')],
          [word('גד')],
          [word('אב')],
          [word('שם')],
        ],
      ),
      'פריסה ידנית': TikkunLine(
        layout: LineLayout.shiraZigzag,
        zigzagRow: ZigzagRow.manual,
        manualCells: [
          ManualCell(width: 40, words: [word('שלום'), word('עולם')]),
          ManualCell(width: 60, words: [word('אחד'), word('שנים')]),
        ],
      ),
    };

    for (final width in [600.0, 900.0, 1200.0]) {
      for (final entry in specialLines.entries) {
        testWidgets('${entry.key} ברוחב $width', (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final metrics = TikkunRenderMetrics.forWidth(width, _settings);

          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('he', 'IL'),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SpecialRow(
                    line: entry.value,
                    metrics: metrics,
                    settings: _settings,
                    hideStam: false,
                    hideNikud: false,
                    markers: MarkersColumn(metrics: metrics),
                    gaps: TikkunGapAverages(
                      stam: metrics.em(2),
                      nikud: metrics.em(2),
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
