import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

const TikkunSettings _twoColumns = TikkunSettings();
const TikkunSettings _singleCentered = TikkunSettings(
  hideStam: true,
  centerSingleColumn: true,
);

/// רוחב הטור בעמוד ברוחב [pageWidth] — אחרי ריפוד הרשימה משני הצדדים.
double _columnWidthAt(double pageWidth, TikkunSettings settings) {
  final metrics = TikkunRenderMetrics.forWidth(pageWidth, settings);
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
      );
      final single = TikkunRenderMetrics.forWidth(
        kTikkunSingleColumnReferenceWidth,
        _singleCentered,
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
    final single = TikkunRenderMetrics.forWidth(width, _singleCentered);
    final two = TikkunRenderMetrics.forWidth(width, _twoColumns);

    expect(single.scale, greaterThan(two.scale));
    expect(
      _columnWidthAt(width, _singleCentered),
      greaterThan(1.5 * _columnWidthAt(width, _twoColumns)),
    );
  });

  test('קנה המידה נשאר בתחום גם ברוחב קיצוני', () {
    expect(
      TikkunRenderMetrics.forWidth(100, _singleCentered).scale,
      kTikkunMinScale,
    );
    expect(TikkunRenderMetrics.forWidth(5000, _singleCentered).scale, 1.0);
  });
}
