import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

import '../support/tikkun_fixtures.dart';

const TikkunSettings _twoColumns = TikkunSettings();
const TikkunSettings _singleCentered = TikkunSettings(
  hideStam: true,
  centerSingleColumn: true,
);

/// רוחב הטור בעמוד ברוחב [pageWidth] — אחרי ריפוד הרשימה משני הצדדים.
double _columnWidthAt(double pageWidth, TikkunSettings settings) {
  final metrics = TikkunRenderMetrics.forWidth(
    pageWidth,
    settings,
    lineWidthEm: kTestLineWidthEm,
  );
  final rowWidth = pageWidth - 2 * metrics.em(kTikkunRowPaddingEm);
  return tikkunColumnWidth(rowWidth, metrics, settings);
}

void main() {
  test('רוחב הייחוס של טור יחיד ממורכז צר מזה של שני טורים', () {
    expect(
      TikkunRenderMetrics.referenceWidthFor(_singleCentered),
      kTikkunSingleColumnReferenceWidth,
    );
    expect(
      TikkunRenderMetrics.referenceWidthFor(_twoColumns),
      kTikkunReferenceWidth,
    );
    expect(
      kTikkunSingleColumnReferenceWidth,
      lessThan(kTikkunReferenceWidth),
    );
  });

  test(
    'טור יחיד ברוחב הייחוס שלו — אותו גופן ואותו רוחב טור כמו בשני טורים',
    () {
      final two = TikkunRenderMetrics.forWidth(
        kTikkunReferenceWidth,
        _twoColumns,
        lineWidthEm: kTestLineWidthEm,
      );
      final single = TikkunRenderMetrics.forWidth(
        kTikkunSingleColumnReferenceWidth,
        _singleCentered,
        lineWidthEm: kTestLineWidthEm,
      );

      expect(single.scale, closeTo(two.scale, 0.001));
      expect(
        _columnWidthAt(kTikkunSingleColumnReferenceWidth, _singleCentered),
        closeTo(_columnWidthAt(kTikkunReferenceWidth, _twoColumns), 4),
      );
    },
  );

  test('במסך צר טור יחיד ממורכז גדול מטור אחד מתוך שניים', () {
    const width = 600.0;
    final single = TikkunRenderMetrics.forWidth(
      width,
      _singleCentered,
      lineWidthEm: kTestLineWidthEm,
    );
    final two = TikkunRenderMetrics.forWidth(
      width,
      _twoColumns,
      lineWidthEm: kTestLineWidthEm,
    );

    expect(single.scale, greaterThan(two.scale));
    expect(
      _columnWidthAt(width, _singleCentered),
      greaterThan(1.5 * _columnWidthAt(width, _twoColumns)),
    );
  });

  group('דף רחב', () {
    // כמו בתצוגה: קנה המידה לפי רוחב דף רגיל, והדף הרחב עד רוחב החלון.
    TikkunRenderMetrics at(double width, double factor) =>
        TikkunRenderMetrics.forWidth(
          width.clamp(0.0, kTikkunReferenceWidth),
          _twoColumns,
          lineWidthEm: kTestLineWidthEm,
          pageWidthFactor: factor,
          maxPageWidth: width,
        );

    test('כשיש מקום בשוליים — אותו כתב, והדף מתרחב אליהם', () {
      final regular = at(3000, 1);
      final wide = at(3000, 1.5);
      expect(wide.stamFontSize, closeTo(regular.stamFontSize, 0.001));
      expect(wide.scale, regular.scale);
      expect(wide.pageWidth, greaterThan(regular.pageWidth * 1.3));
    });

    test('כשאין די מקום — הדף ממלא את הרוחב והכתב מוקטן רק בשיעור החסר', () {
      final regular = at(1700, 1);
      final wide = at(1700, 1.5);
      expect(wide.pageWidth, 1700);
      expect(wide.scale, regular.scale);
      expect(wide.stamFontSize, lessThan(regular.stamFontSize));
      expect(
        wide.stamFontSize,
        greaterThan(at(kTikkunReferenceWidth, 1.5).stamFontSize),
      );
    });
  });

  test('קנה המידה נשאר בתחום גם ברוחב קיצוני', () {
    expect(
      TikkunRenderMetrics.forWidth(
        100,
        _singleCentered,
        lineWidthEm: kTestLineWidthEm,
      ).scale,
      kTikkunMinScale,
    );
    expect(
      TikkunRenderMetrics.forWidth(
        5000,
        _singleCentered,
        lineWidthEm: kTestLineWidthEm,
      ).scale,
      1.0,
    );
  });
}
