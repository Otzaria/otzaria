/// חיתוך השורות לפי רוחב: אותיות צרות מכניסות יותר מילים לשורה, הרווח בין
/// השורות אחיד יותר מחיתוך לפי מניין תווים, והכללים המבניים נשמרים.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_width_measurer.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

import '../support/tikkun_fixtures.dart';

const String _stamFamily = 'AshkenaziStam';
const String _stamFontFile = 'fonts/tikkun_korim/Ashkenazi-Stam.ttf';

/// גופני הסת"ם המוטמעים — שיעור הסתומה נמדד בכולם.
const Map<String, String> _stamFontFiles = {
  'AshkenaziStam': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'SefardiStam': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
};

/// חיתוך לפי מניין תווים הוא בדיוק מודל רוחב אחיד: כל תו באותו advance,
/// והתקציב מכיל 36 יחידות כאלה.
const StamWidthModel _charCountModel = StamWidthModel.uniform(
  id: 'char-count',
  advance: kTikkunWordGapAllowanceEm,
);

/// רוחב הפריטים בשורה, בלי הקצאת הרווח — כמו `tikkunLineItemWidths` במרנדר.
List<double> _itemWidths(TikkunLine line, StamWidthModel widths) => [
  for (final w in line.words)
    if (w.isGap)
      widths.setumaGapEm
    else if (w.isBigGap)
      widths.bigGapEm
    else if (w.stam.isNotEmpty)
      widths.wordWidthEm(w.stam),
];

/// הרווח שיתקבל בין המילים בשורה מיושרת, ביחידות em.
List<double> _justifiedGaps(List<TikkunLine> lines, StamWidthModel widths) {
  final gaps = <double>[];
  for (final line in lines) {
    if (line.isSpecial || line.isEmpty) continue;
    if (line.layout == LineLayout.petucha ||
        line.layout == LineLayout.partial) {
      continue;
    }
    final items = _itemWidths(line, widths);
    if (items.length < 2) continue;
    final used = items.fold(0.0, (a, b) => a + b);
    gaps.add((kTikkunLineWidthEm - used) / (items.length - 1));
  }
  return gaps;
}

double _stdDev(List<double> values) {
  if (values.length < 2) return 0;
  final mean = values.fold(0.0, (a, b) => a + b) / values.length;
  final variance =
      values.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / values.length;
  return math.sqrt(variance);
}

List<TikkunToken> _wordTokens(String word, int count) => [
  for (var i = 0; i < count; i++) TikkunToken.word(word),
];

void main() {
  late StamWidthModel widths;
  late List<TikkunToken> bereshit;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await File(_stamFontFile).readAsBytes();
    await (FontLoader(
      _stamFamily,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    widths = measureStamWidthModel(_stamFamily);
    bereshit = tokenizeBook(readFixture('bereshit'), 'בראשית');
  });

  test('שורה של אותיות צרות מכילה יותר מילים משורה של אותיות רחבות', () {
    final narrow = paginateAllTokens(_wordTokens('ווו', 400), widths);
    final wide = paginateAllTokens(_wordTokens('ששש', 400), widths);

    expect(widths.wordWidthEm('ווו'), lessThan(widths.wordWidthEm('ששש')));
    expect(narrow.first.words.length, greaterThan(wide.first.words.length));
  });

  test('הרווח בין השורות אחיד יותר מחיתוך לפי מניין תווים', () {
    final byWidth = _justifiedGaps(
      paginateAllTokens(bereshit, widths),
      widths,
    );
    final byChars = _justifiedGaps(
      paginateAllTokens(bereshit, _charCountModel),
      widths,
    );

    final widthDev = _stdDev(byWidth);
    final charDev = _stdDev(byChars);
    // ignore: avoid_print
    print('gap std-dev (em): width=$widthDev chars=$charDev');

    expect(byWidth.length, greaterThan(1000));
    expect(widthDev, lessThan(charDev * 0.70));
  });

  test('אף שורה מיושרת אינה חורגת מהתקציב', () {
    for (final line in paginateAllTokens(bereshit, widths)) {
      if (line.isSpecial || line.isEmpty) continue;
      final items = _itemWidths(line, widths);
      if (items.length < 2) continue;
      // מיזוג שורה קצרה לפני גבול סגמנט מתיר חריגה של עד 20%.
      expect(
        items.fold(0.0, (a, b) => a + b),
        lessThanOrEqualTo(kTikkunLineWidthEm * 1.20),
      );
    }
  });

  test('כללי הסתומה, הפתוחה והשורה החלקית נשמרים', () {
    final lines = paginateAllTokens(bereshit, widths);

    expect(
      lines.where((l) => l.layout == LineLayout.setuma),
      isNotEmpty,
    );
    expect(
      lines.where((l) => l.layout == LineLayout.petucha),
      isNotEmpty,
    );

    for (final line in lines) {
      if (line.layout == LineLayout.setuma) {
        expect(line.words.any((w) => w.isGap), isTrue);
      }
      if (line.layout == LineLayout.setumaStart) {
        expect(line.words.first.isBigGap, isTrue);
      }
      if (line.layout == LineLayout.partial) {
        final used = _itemWidths(
          line,
          widths,
        ).fold(0.0, (a, b) => a + b);
        expect(used, lessThan(kTikkunLineWidthEm * 0.65));
      }
    }
  });

  test('אחרי סתומה נשאר מרחב מזערי בשורה', () {
    for (final line in paginateAllTokens(bereshit, widths)) {
      final gapIdx = line.words.indexWhere((w) => w.isGap);
      if (gapIdx < 0 || gapIdx == line.words.length - 1) continue;
      final before = line.words
          .take(gapIdx + 1)
          .fold(0.0, (a, w) => a + widths.itemWidthEm(w));
      expect(
        kTikkunLineWidthEm - before,
        greaterThan(-widths.minAfterSetumaEm),
      );
    }
  });

  test('שיעור הפרשה תופס חלק דומה מהשורה בכל גופני הסת"ם', () async {
    final shares = <String, double>{};
    for (final entry in _stamFontFiles.entries) {
      final bytes = await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      shares[entry.key] =
          measureStamWidthModel(entry.key).setumaGapEm / kTikkunLineWidthEm;
    }

    // המידה נמדדת מן הכתב (3×"אשר"), ולכן היא נשמרת גם כשהאותיות צרות יותר.
    for (final share in shares.values) {
      expect(share, inInclusiveRange(0.15, 0.4), reason: shares.toString());
    }
    final spread =
        shares.values.reduce(math.max) - shares.values.reduce(math.min);
    expect(spread, lessThan(0.1), reason: shares.toString());
  });

  test('דטרמיניזם — אותו קלט ואותו מודל מחזירים אותן שורות', () {
    final first = paginateAllTokens(bereshit, widths);
    final second = paginateAllTokens(bereshit, widths);

    expect(first.length, second.length);
    for (var i = 0; i < first.length; i++) {
      expect(first[i].words, second[i].words);
      expect(first[i].layout, second[i].layout);
    }
  });

  test('רוחב המילה במודל קרוב לרוחב המרונדר', () {
    const fontSize = 200.0;
    const style = TextStyle(fontFamily: _stamFamily, fontSize: fontSize);
    final seen = <String>{};
    final errors = <double>[];

    for (final tok in bereshit) {
      if (!tok.isWord) continue;
      final stam = stripNikud(tok.value!);
      if (stam.isEmpty || !seen.add(stam)) continue;
      final rendered = tikkunWordWidth(stam, style);
      if (rendered <= 0) continue;
      errors.add(
        (widths.wordWidthEm(stam) * fontSize - rendered).abs() / rendered,
      );
      if (seen.length >= 2000) break;
    }

    errors.sort();
    final median = errors[errors.length ~/ 2];
    final worst = errors.last;
    // ignore: avoid_print
    print('word width error: median=$median worst=$worst n=${errors.length}');

    expect(median, lessThan(0.02));
  });
}
