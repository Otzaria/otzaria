/// שם עליה ארוך בעמודת המסמנים אינו מרווח את השורה.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/markers_column.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

const Size _surface = Size(1200, 400);
const TikkunSettings _settings = TikkunSettings();

Future<double> _rowHeight(
  WidgetTester tester,
  TikkunLine line, {
  required MarkersColumn Function(TikkunRenderMetrics metrics) markers,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final metrics = TikkunRenderMetrics.forWidth(_surface.width, _settings);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ReaderRow(
            line: line,
            metrics: metrics,
            settings: _settings,
            hideStam: false,
            hideNikud: false,
            markers: markers(metrics),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(ReaderRow)).height;
}

void main() {
  testWidgets('מסמנים מרובי שורות אינם מגדילים את גובה השורה', (tester) async {
    final line = TikkunLine(
      words: [const LayoutWord(stam: 'א', nikud: 'אָ')],
    );

    final plain = await _rowHeight(
      tester,
      line,
      markers: (metrics) => MarkersColumn(metrics: metrics, verseNum: 1),
    );
    final crowded = await _rowHeight(
      tester,
      line,
      markers: (metrics) => MarkersColumn(
        metrics: metrics,
        aliyaName: 'שלישי',
        combinedAliyaName: 'ויקהל פקודי',
        chapterNum: 12,
        verseNum: 21,
      ),
    );

    expect(crowded, plain);
  });
}
