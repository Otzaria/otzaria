/// שיטות פנויות: פתוחה שנגמרה בסוף שיטה, מעבר חומש, וסביב השירות.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

const StamWidthModel _widths = StamWidthModel.uniform(advance: 0.55);

/// מילה בת שלוש אותיות — עשר כאלה ממלאות שיטה ומשאירות פחות משיעור פרשה.
List<TikkunToken> _words(int count) => [
  for (var i = 0; i < count; i++) const TikkunToken.word('אבג'),
];

const TikkunToken _petucha = TikkunToken(type: TikkunTokenType.petucha);
const TikkunToken _bookBreak = TikkunToken(type: TikkunTokenType.bookBreak);

const SpecialSection _shira = SpecialSection(
  id: 'shirat_hayam',
  name: 'שירת הים',
  book: 'shemot',
  fromCh: 15,
  fromVs: 1,
  toCh: 15,
  toVs: 19,
  layout: 'shira_parallel',
  blankLineBefore: true,
  blankLineAfter: true,
);

List<TikkunToken> _withSection(int before, int inside, int after) => [
  ..._words(before),
  const TikkunToken(
    type: TikkunTokenType.specialStart,
    section: _shira,
    openingChapter: 15,
    openingVerse: 1,
  ),
  ..._words(inside),
  const TikkunToken(type: TikkunTokenType.specialEnd),
  ..._words(after),
];

int _emptyRunAt(List<TikkunLine> lines, int from) {
  var count = 0;
  for (var i = from; i < lines.length; i++) {
    if (lines[i].layout != LineLayout.empty) break;
    count++;
  }
  return count;
}

void main() {
  test('מעבר חומש — בדיוק ד" שיטין פנויות', () {
    for (final wordsBefore in [3, 10]) {
      final lines = paginateAllTokens([
        ..._words(wordsBefore),
        _petucha,
        _bookBreak,
        ..._words(3),
      ], _widths);

      expect(_emptyRunAt(lines, 1), 4, reason: 'לפני המעבר $wordsBefore מילים');
      expect(lines[5].layout, isNot(LineLayout.empty));
    }
  });

  test('שיטה פנויה לפני השירה ואחריה', () {
    final lines = paginateAllTokens(_withSection(3, 4, 3), _widths);
    final shiraIdx = lines.indexWhere(
      (l) => l.layout == LineLayout.shiraParallel,
    );

    expect(shiraIdx, greaterThan(0));
    expect(lines[shiraIdx - 1].layout, LineLayout.empty);
    expect(lines[shiraIdx + 1].layout, LineLayout.empty);
  });

  test('פתוחה לפני השירה אינה מכפילה את השיטה הפנויה', () {
    final tokens = [..._words(10), _petucha, ..._withSection(0, 4, 3)];
    final lines = paginateAllTokens(tokens, _widths);
    final shiraIdx = lines.indexWhere(
      (l) => l.layout == LineLayout.shiraParallel,
    );

    expect(_emptyRunAt(lines, shiraIdx - 1), 1);
  });

  test('השירות מסומנות בנתונים כמניחות שיטה פנויה לפניהן ואחריהן', () {
    final byId = {for (final s in TikkunData.specialSections) s.id: s};

    for (final id in ['shirat_hayam', 'shirat_haazinu']) {
      expect(byId[id]?.blankLineBefore, isTrue, reason: id);
      expect(byId[id]?.blankLineAfter, isTrue, reason: id);
    }
    expect(byId['shirat_devorah']?.blankLineBefore, isFalse);
  });
}
