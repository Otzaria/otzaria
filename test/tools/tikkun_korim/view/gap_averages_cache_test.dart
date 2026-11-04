import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

import '../support/tikkun_fixtures.dart';

const TikkunSettings _settings = TikkunSettings();

List<TikkunLine> _book(String id) => processBook(
  readFixture(id),
  fixtureBookNames[id]!,
  const StamWidthModel.uniform(),
).allLines;

TikkunGapAverages _averages(List<TikkunLine> lines, double width) {
  final metrics = TikkunRenderMetrics.forWidth(
    width,
    _settings,
    lineWidthEm: kTestLineWidthEm,
  );
  return computeTikkunGapAverages(
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

  group('רווח ממוצע לפי מקטע', () {
    test('מחושב רק למקטע של השורה המבוקשת, פעם אחת', () {
      final lines = _book('esther');
      final requested = <List<TikkunLine>>[];
      final gaps = TikkunSegmentGapAverages(lines, (segment) {
        requested.add(segment);
        return TikkunGapAverages.none;
      });

      gaps.forLine(kTikkunGapSegmentLines + 3);
      gaps.forLine(kTikkunGapSegmentLines * 2 - 1);

      expect(requested, hasLength(1));
      expect(
        requested.single,
        lines.sublist(kTikkunGapSegmentLines, kTikkunGapSegmentLines * 2),
      );
    });

    test('השארית מצטרפת למקטע האחרון', () {
      const count = kTikkunGapSegmentLines * 2 + 9;
      expect(tikkunGapSegmentCount(count), 2);
      expect(tikkunGapSegmentRange(1, count), (kTikkunGapSegmentLines, count));
      // עמוד של שיטה בת 51 שורות נשאר מקטע אחד.
      expect(tikkunGapSegmentCount(51), 1);
      expect(tikkunGapSegmentRange(0, 51), (0, 51));
      expect(tikkunGapSegmentCount(5), 1);
    });

    test('הממוצע של מקטע שווה לחישוב על שורותיו בלבד', () {
      final lines = _book('esther');
      final gaps = TikkunSegmentGapAverages(
        lines,
        (segment) => _averages(segment, 1100),
      );
      final last = tikkunGapSegmentCount(lines.length) - 1;
      final (start, end) = tikkunGapSegmentRange(last, lines.length);
      final expected = _averages(lines.sublist(start, end), 1100);

      final actual = gaps.forLine(lines.length - 1);

      expect(actual.stam, isNotNull);
      expect(actual.stam, expected.stam);
      expect(actual.nikud, expected.nikud);
    });

    testWidgets('עמוד של ספר שלם מודד רק את המקטעים המוצגים', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final lines = _book('shemot');
      // גודל גופן שלא נמדד בבדיקה אחרת — כל גידול במטמון הוא מדידה חדשה.
      final beforeWhole = tikkunWordWidthCacheSize;
      _averages(lines, 870);
      final wholeBook = tikkunWordWidthCacheSize - beforeWhole;

      final beforePage = tikkunWordWidthCacheSize;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ReaderPage(
                lineWidthEm: kTestLineWidthEm,
                lines: lines,
                settings: _settings,
                hideStam: false,
                hideNikud: false,
              ),
            ),
          ),
        ),
      );
      final page = tikkunWordWidthCacheSize - beforePage;

      expect(page, greaterThan(0));
      expect(page, lessThan(wholeBook ~/ 10));
    });
  });
}
