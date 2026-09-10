/// מודל רוחב הסת"ם: גזירת תקציב השורה מגאומטריית הטור, וחישוב רוחב מילה.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

const StamWidthModel _model = StamWidthModel(
  id: 'test',
  advances: {0x05D0: 0.8, 0x05D9: 0.2},
  fallbackAdvance: 0.5,
);

void main() {
  test('תקציב השורה שווה לרוחב תוכן הטור ברוחב הייחוס, ביחידות em', () {
    const settings = TikkunSettings();
    final metrics = TikkunRenderMetrics.forWidth(
      kTikkunReferenceWidth,
      settings,
    );
    final rowWidth =
        kTikkunReferenceWidth - 2 * metrics.em(kTikkunRowPaddingEm);
    final contentWidth = tikkunColumnContentWidth(
      rowWidth: rowWidth,
      metrics: metrics,
      settings: settings,
      isStam: true,
      hideNikud: false,
    );

    expect(
      contentWidth / metrics.stamFontSize,
      closeTo(kTikkunLineWidthEm, 0.05),
    );
  });

  test('רוחב מילה = סכום ה-advance, עם נפילה לרוחב הברירה', () {
    expect(_model.wordWidthEm('אא'), closeTo(1.6, 1e-9));
    expect(_model.wordWidthEm('אי'), closeTo(1.0, 1e-9));
    expect(_model.wordWidthEm('בב'), closeTo(1.0, 1e-9));
  });

  test('ניקוד, טעמים וסימוני PUA אינם מוסיפים רוחב', () {
    final plain = _model.wordWidthEm('אא');
    expect(_model.wordWidthEm('אָ֥א'), closeTo(plain, 1e-9));
    expect(
      _model.wordWidthEm(
        '${String.fromCharCode(kKetivQereStart)}אא'
        '${String.fromCharCode(kKetivQereEnd)}',
      ),
      closeTo(plain, 1e-9),
    );
  });

  test('זעירא מצמצמת ורבתי מרחיבה את הרוחב לפי המקדמים', () {
    final zeira =
        '${String.fromCharCode(kZeiraStart)}א'
        '${String.fromCharCode(kZeiraEnd)}א';
    final rabati =
        '${String.fromCharCode(kRabatiStart)}א'
        '${String.fromCharCode(kRabatiEnd)}א';

    expect(
      _model.wordWidthEm(zeira),
      closeTo(0.8 * kTikkunZeiraFactor + 0.8, 1e-9),
    );
    expect(
      _model.wordWidthEm(rabati),
      closeTo(0.8 * kTikkunRabatiFactor + 0.8, 1e-9),
    );
  });

  test('שיעור הפרשה נגזר משלוש פעמים "אשר" ולא ממספר תווים', () {
    // 'אשר' = 0.8 + 0.5 + 0.5 במודל הבדיקה; ועוד שני רווחי מילה שביניהן.
    expect(
      _model.setumaGapEm,
      closeTo(3 * 1.8 + 2 * kTikkunWordGapAllowanceEm, 1e-9),
    );
    expect(
      _model.minAfterSetumaEm,
      closeTo(_model.setumaGapEm * kTikkunMinAfterSetumaRatio, 1e-9),
    );
  });

  test('רווח הפתיחה זהה לזה שהמרנדר מצייר', () {
    expect(
      _model.bigGapEm,
      closeTo(kTikkunLineWidthEm * kTikkunBigGapFraction, 1e-9),
    );
  });
}
