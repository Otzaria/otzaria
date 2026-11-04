import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

import '../support/tikkun_fixtures.dart';

const TikkunSettings _settings = TikkunSettings();

List<TikkunLine> _book(String id) => processBook(
  readFixture(id),
  fixtureBookNames[id]!,
  const StamWidthModel.uniform(),
).allLines;

void _averages(List<TikkunLine> lines, double width) {
  final metrics = TikkunRenderMetrics.forWidth(
    width,
    _settings,
    lineWidthEm: kTestLineWidthEm,
  );
  computeTikkunGapAverages(
    lines: lines,
    metrics: metrics,
    settings: _settings,
    rowWidth: metrics.pageWidth,
    hideNikud: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ספר שלם בגודל חדש, כשהמטמון כבר מלא בגודל קודם.
  test('חישוב חוזר של רווח ספר שלם באותו גודל אינו מודד מחדש', () {
    for (final id in ['yeshayahu', 'shmuel_b', 'devarim']) {
      _averages(_book(id), 1000);
    }
    final bereshit = _book('bereshit');
    _averages(bereshit, 1200);
    final afterFirst = tikkunWordWidthCacheSize;

    _averages(bereshit, 1200);

    expect(tikkunWordWidthCacheSize, afterFirst);
  });
}
