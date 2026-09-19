/// פתוחה שנופלת בשיטה כמעט מלאה: שתי התיבות האחרונות יורדות, כדי שיישאר אחריהן
/// שיעור פרשה — כמו הכלל של הסתומה. בשיטה התימנית מניחים שיטה פנויה במקומו.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

const StamWidthModel _widths = StamWidthModel.uniform();

final double _wordEm = _widths.wordWidthEm('אבג') + _widths.wordGapEm;

/// כמה תיבות ממלאות שיטה — נגזר מהתקציב, כדי שהבדיקה לא תיקשר לרוחב הטור.
final int _wordsPerLine = (_widths.lineWidthEm / _wordEm).floor();

/// תיבות שונות זו מזו באותו רוחב, כדי לזהות את סדרן אחרי ההורדה.
List<TikkunToken> _words(int count) => [
  for (var i = 0; i < count; i++)
    TikkunToken.word('אב${String.fromCharCode(0x05D0 + i % 22)}'),
];

const TikkunToken _petucha = TikkunToken(type: TikkunTokenType.petucha);

double _remainingEm(TikkunLine line) {
  var used = 0.0;
  for (final word in line.words) {
    used += _widths.itemWidthEm(word);
  }
  return _widths.lineWidthEm - used;
}

List<String> _allWords(List<TikkunLine> lines) => [
  for (final line in lines)
    for (final word in line.words) word.stam,
];

void main() {
  test('המבחן בנוי על שיטה שנשאר בה פחות משיעור פרשה', () {
    expect(
      _widths.lineWidthEm - _wordsPerLine * _wordEm,
      lessThan(_widths.setumaGapEm),
    );
  });

  test('בשיטה מלאה שתי תיבות יורדות ונשאר אחריהן שיעור פרשה', () {
    final tokens = [..._words(_wordsPerLine), _petucha, ..._words(3)];
    final lines = paginateAllTokens(tokens, _widths);

    final petucha = lines.firstWhere((l) => l.layout == LineLayout.petucha);
    expect(_remainingEm(petucha), greaterThanOrEqualTo(_widths.setumaGapEm));
    expect(lines.first.layout, LineLayout.regular);
    expect(lines.first.words, hasLength(_wordsPerLine - 2));
    expect(petucha.words, hasLength(2));
    expect(lines.where((l) => l.isEmpty), isEmpty);
    expect(_allWords(lines), [
      for (final t in tokens)
        if (t.isWord) t.value,
    ]);
  });

  test('העודף מתחלק על כל שיטות הקטע ולא נשאר בשיטה שלפני הפתוחה', () {
    // תיבות באורכים שבהם הזזת תיבה בין זוג שיטות סמוכות נתקעת; חיתוך הקטע
    // כולו מחדש מביא את הרווחים לשוויון כמעט מלא.
    const lengths = [
      3,
      2,
      5,
      6,
      6,
      4,
      2,
      3,
      3,
      3,
      3,
      2,
      3,
      6,
      5,
      2,
      2,
      3,
      3,
      6,
    ];
    const more = [3, 5, 4, 2, 4, 6, 3, 1, 2, 1];
    final lines = paginateAllTokens([
      for (final n in [...lengths, ...more]) TikkunToken.word('א' * n),
      _petucha,
      ..._words(3),
    ], _widths);
    final petuchaIdx = lines.indexWhere((l) => l.layout == LineLayout.petucha);
    final gaps = [
      for (final l in lines.take(petuchaIdx))
        _remainingEm(l) / (l.words.length - 1),
    ];
    expect(gaps.length, greaterThan(2));
    final spread =
        gaps.reduce((a, b) => a > b ? a : b) -
        gaps.reduce((a, b) => a < b ? a : b);
    expect(spread, lessThan(0.5));
  });

  test('ריוח סתומה אינו יורד לראש השיטה יחד עם התיבות', () {
    final lines = paginateAllTokens([
      ..._words(_wordsPerLine - 3),
      const TikkunToken(type: TikkunTokenType.setuma),
      ..._words(1),
      _petucha,
      ..._words(3),
    ], _widths);
    final petucha = lines.firstWhere((l) => l.layout == LineLayout.petucha);
    expect(petucha.words.first.isGap, isFalse);
    expect(lines.every((l) => l.words.isEmpty || !l.words.first.isGap), isTrue);
  });

  test('פתוחה באמצע השיטה נשארת במקומה', () {
    final lines = paginateAllTokens([
      ..._words(3),
      _petucha,
      ..._words(3),
    ], _widths);
    expect(lines.first.layout, LineLayout.petucha);
    expect(lines.first.words, hasLength(3));
  });

  test('בשיטה התימנית אין הורדה — מניחים שיטה פנויה', () {
    final lines = paginateAllTokens(
      [..._words(_wordsPerLine), _petucha, ..._words(3)],
      _widths,
      rambamParashaForms: true,
    );
    expect(lines.first.words, hasLength(_wordsPerLine));
    expect(lines[1].layout, LineLayout.empty);
  });

  test('לפני מעבר חומש אין הורדה — השיטין הפנויות מראות את ההפסק', () {
    final lines = paginateAllTokens([
      ..._words(_wordsPerLine),
      _petucha,
      const TikkunToken(type: TikkunTokenType.bookBreak),
      ..._words(3),
    ], _widths);
    expect(lines.first.words, hasLength(_wordsPerLine));
    expect(lines.first.layout, LineLayout.petucha);
  });
}
