/// צורות הפתוחה והסתומה כלשון הרמב"ם (הל' ספר תורה ח,א–ב) בשיטה התימנית.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

const StamWidthModel _widths = StamWidthModel.uniform();

List<TikkunToken> _words(int count) => [
  for (var i = 0; i < count; i++) const TikkunToken.word('אבג'),
];

List<TikkunLine> _paginate(List<TikkunToken> tokens, {required bool rambam}) =>
    paginateAllTokens(tokens, _widths, rambamParashaForms: rambam);

void main() {
  test('פתוחה אחרי שיטה כמעט מלאה מניחה שיטה שנייה פנויה', () {
    final tokens = [
      ..._words(9),
      const TikkunToken(type: TikkunTokenType.petucha),
      ..._words(3),
    ];
    final rambam = _paginate(tokens, rambam: true);
    expect(rambam.map((l) => l.layout).take(3), [
      LineLayout.petucha,
      LineLayout.empty,
      isNot(LineLayout.empty),
    ]);
    final other = _paginate(tokens, rambam: false);
    expect(other.where((l) => l.isEmpty), isEmpty);
  });

  test('פתוחה באמצע השיטה אינה מוסיפה שיטה פנויה', () {
    final tokens = [
      ..._words(3),
      const TikkunToken(type: TikkunTokenType.petucha),
      ..._words(3),
    ];
    expect(_paginate(tokens, rambam: true).where((l) => l.isEmpty), isEmpty);
  });

  test(
    'סתומה בלי מקום לריוח ולתיבה — שאר השיטה פנוי ומעט ריוח בראש השנייה',
    () {
      final tokens = [
        ..._words(7),
        const TikkunToken(type: TikkunTokenType.setuma),
        ..._words(5),
      ];
      final lines = _paginate(tokens, rambam: true);
      expect(lines.first.words, hasLength(7), reason: 'אף תיבה לא ירדה');
      expect(lines.first.layout, LineLayout.petucha);
      final lead = lines[1].words.first;
      expect(lead.isGap, isTrue);
      expect(lead.gapFraction, inExclusiveRange(0, 1));
      expect(
        _widths.setumaGapEm * lead.gapFraction,
        greaterThanOrEqualTo(_widths.wordGapEm),
      );
    },
  );

  test('סתומה באמצע השיטה — ריוח שלם, כמו בשאר השיטות', () {
    final tokens = [
      ..._words(2),
      const TikkunToken(type: TikkunTokenType.setuma),
      ..._words(2),
    ];
    for (final rambam in [true, false]) {
      final gap = _paginate(
        tokens,
        rambam: rambam,
      ).first.words.firstWhere((w) => w.isGap);
      expect(gap.gapFraction, 1);
    }
  });
}
