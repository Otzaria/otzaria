/// המסלולים המלאים של המנוע: התורה כולה, ספר תנ"ך בודד, הפטרה וקריאת מועד.
/// פורט של `loadAndProcessAll`, `loadAndDisplayTanachBook`,
/// `loadAndDisplayHaftarah` ו-`loadAndDisplayTorahReading` (navigation.js)
/// בלי ה-IO וה-DOM — קלט טקסט גולמי, פלט שורות מעומדות.
library;

import 'dart:math' as math;

import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/aliyot_annotator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/decalogue_taam.dart';
import 'package:otzaria/tools/tikkun_korim/engine/line_paginator.dart';
import 'package:otzaria/tools/tikkun_korim/engine/official_pages_builder.dart';
import 'package:otzaria/tools/tikkun_korim/engine/raw_text_cleaner.dart';
import 'package:otzaria/tools/tikkun_korim/engine/special_sections_marker.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/engine/verse_range_slicer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';

/// אסימוני ספר בודד: ניקוי, פירוק, בחירת הפרשיות לפי [tradition] וסימון
/// הקטעים המיוחדים שלו.
List<TikkunToken> tokenizeBook(
  String rawText,
  String hebrewBookName, {
  TikkunTradition tradition = TikkunTradition.ashkenazSephard,
  TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
}) => markSpecialSections(
  applyDecalogueTaam(
    filterByTradition(tokenizeText(cleanRawText(rawText)), tradition),
    hebrewBookName,
    decalogueTaam,
  ),
  hebrewBookName,
);

/// עיבוד מלא של חמשת החומשים כרצף אחד, כולל סימון פרשות ועליות.
/// המפתחות ב-[rawByBookId]: bereshit/shemot/vayikra/bamidbar/devarim.
/// [methodId] קובע את עוגני העמודים; בכל עוגן נכפית תחילת שורה.
ProcessedTorah processTorah(
  Map<String, String> rawByBookId,
  StamWidthModel widths, {
  TikkunTradition tradition = TikkunTradition.ashkenazSephard,
  TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
  String methodId = '',
}) {
  final raw = <TikkunToken>[];
  final order = TikkunData.booksOrder;

  for (var i = 0; i < order.length; i++) {
    final bookId = order[i];
    final book = TikkunData.torahBooks[bookId];
    final text = rawByBookId[bookId];
    if (book == null || text == null) continue;
    if (i > 0) raw.add(const TikkunToken(type: TikkunTokenType.bookBreak));
    raw.addAll(
      tokenizeBook(
        text,
        book.name,
        tradition: tradition,
        decalogueTaam: decalogueTaam,
      ),
    );
  }

  final anchored = insertPageBreaks(
    raw,
    resolveWordRefs(raw, TikkunData.torahPageAnchors(methodId)),
  );
  final tokens = anchored.tokens;
  final bookStartTokenIdx = computeBookStartIndices(tokens);
  final pageStarts = anchored.pageStarts;
  final factors = pageWidthFactors(tokens, pageStarts);
  double pageFactor(List<double> perToken, int p) =>
      perToken[p == 0 ? 0 : pageStarts[p]!];
  final isShira = [
    for (var p = 0; p < pageStarts.length; p++)
      pageStarts[p] != null && pageFactor(factors, p) != 1,
  ];
  // השיטה התימנית נוהגת כרמב"ם גם בצורות הפתוחה והסתומה.
  final rambamParashaForms = tradition == TikkunTradition.yemen;
  final linesPerPage = TikkunData.torahLayouts[methodId]?.linesPerPage;
  if (linesPerPage != null) {
    _fitPageBudgets(
      tokens,
      pageStarts,
      factors,
      widths,
      linesPerPage,
      rambamParashaForms: rambamParashaForms,
    );
  }
  final allLines = paginateAllTokens(
    tokens,
    widths,
    widthFactors: factors,
    rambamParashaForms: rambamParashaForms,
  );
  // לפי העמודים עצמם: שורת שירה שחוצה עמוד נפתחת לפני מילת העוגן.
  if (pageStarts.isNotEmpty) {
    final pages = buildOfficialPages(allLines, pageStarts, pageStarts.length);
    final pageBudgets = [
      for (var p = 0; p < pages.length; p++)
        pageStarts[p] == null ? 1.0 : pageFactor(factors, p),
    ];
    double budgetOf(TikkunLine line, int p) =>
        line.startTokenIdx >= 0 ? factors[line.startTokenIdx] : pageBudgets[p];
    // כל דף רגיל ברוחב אחד. לא הרחב שבתקציבים — דפים בודדים צפופים בהרבה
    // מהשאר והיו מרווחים את כל הספר; הם מכווצים בתצוגה, והשאר נסגר ברווחים.
    final budgets = <double>[];
    for (var p = 0; p < pages.length; p++) {
      if (isShira[p]) continue;
      var budget = 0.0;
      for (final line in pages[p].lines) {
        budget = math.max(budget, budgetOf(line, p));
      }
      if (budget > 0) budgets.add(budget);
    }
    budgets.sort();
    final regularWidth = budgets.isEmpty
        ? 1.0
        : budgets[((budgets.length - 1) * _kRegularWidthPercentile).round()];
    final display = [
      for (var p = 0; p < pages.length; p++)
        isShira[p] ? pageBudgets[p] : regularWidth,
    ];
    // דפי שירה סמוכים ברוחב אחד: הרחב שבתקציביהם, ולפחות זה שבו כל חצאי
    // השיטין נכנסים — מניין שורות השירה אינו תלוי ברוחב.
    for (var p = 0; p < display.length; p++) {
      if (!isShira[p]) continue;
      var end = p;
      while (end + 1 < display.length && isShira[end + 1]) {
        end++;
      }
      var shared = regularWidth;
      var cells = 0.0;
      var gaps = 0;
      var prose = 0.0;
      for (var k = p; k <= end; k++) {
        prose = math.max(prose, display[k]);
        for (final line in pages[k].lines) {
          final row = tikkunManualCellsEm(line, widths);
          if (row == null) continue;
          cells = math.max(cells, row.cells);
          gaps = math.max(gaps, row.gaps);
        }
      }
      final gapEm = widths.setumaGapEm * gaps;
      // הפרוזה שבדף השירה נדחסת כמו השירה; שירה שהמנוע אינו יודע את מידתה
      // נשארת ברוחב שהעימוד נתן לה.
      shared = math.max(
        shared,
        cells > 0 ? prose * kTikkunShiraMinCondense : prose,
      );
      shared = math.max(
        shared,
        (cells * kTikkunShiraMinCondense + gapEm * kTikkunShiraMinGapFactor) /
            widths.lineWidthEm,
      );
      // הרווח נקבע לפי השורה הרחבה: מתכווץ כשצריך, ואז נדחסות האותיות; מתרחב
      // כשיש מקום, כדי שהעודף לא ייפול בין המילים.
      final gapFactor = gapEm == 0
          ? 1.0
          : ((shared * widths.lineWidthEm - cells) / gapEm).clamp(
              kTikkunShiraMinGapFactor,
              kTikkunShiraMaxGapFactor,
            );
      for (var k = p; k <= end; k++) {
        for (final line in pages[k].lines) {
          line.cellGapFactor = gapFactor;
        }
      }
      display.fillRange(p, end + 1, shared);
      p = end;
    }
    for (var p = 0; p < pages.length; p++) {
      for (final line in pages[p].lines) {
        line
          ..widthFactor = display[p]
          ..budgetFactor = budgetOf(line, p);
      }
    }
  }
  annotateAliyotOnLines(tokens, allLines, bookStartTokenIdx);
  annotateCombinedAliyotOnLines(tokens, allLines, bookStartTokenIdx);

  return ProcessedTorah(
    tokens: tokens,
    allLines: allLines,
    bookStartTokenIdx: bookStartTokenIdx,
    pageStartTokenIdx: anchored.pageStarts,
  );
}

/// רוחב שורת תאים ב-em: [cells] — בשורה מיושרת התא הרחב מנורמל לשורה שלמה,
/// ובאריחי שירה סך הכתב; [gaps] — מספר הרווחים שבשיעור סתומה.
({double cells, int gaps})? tikkunManualCellsEm(
  TikkunLine line,
  StamWidthModel widths,
) {
  final cells = line.manualCells;
  if (cells == null || line.cssClasses.contains('flex-cells')) return null;
  final justify = line.cssClasses.contains('justify-cells');
  if (justify && cells.length < 2) return null;
  var widest = 0.0;
  var total = 0.0;
  for (final cell in cells) {
    if (cell.width <= 0) continue;
    var natural = widths.wordGapEm * (cell.words.length - 1);
    for (final word in cell.words) {
      natural += widths.wordWidthEm(word.stam);
    }
    total += natural;
    widest = math.max(widest, (natural + widths.wordGapEm) * 100 / cell.width);
  }
  // באריחים הרווחים שבשורה נמדדים כרווח אחד: שיעור סתומה (קסת הסופר טז, א).
  return justify
      ? (cells: widest, gaps: cells.length - 1)
      : (cells: total, gaps: 1);
}

/// כמה מותר לצמצם את הרווח שבין טורי השירה, ולדחוס את אותיותיה ואת הפרוזה
/// שבדפיה, לפני שהדף מתרחב — כדי שהשירה תקרב לרוחב הדפים הרגילים.
const double kTikkunShiraMinGapFactor = 0.5;
const double kTikkunShiraMinCondense = 0.85;

/// עד כמה מתרחב הרווח שבין טורי השירה בדף רחב ממנה.
const double kTikkunShiraMaxGapFactor = 1.5;

/// האחוזון של תקציבי הדפים הרגילים שקובע את רוחב הטור המשותף.
const double _kRegularWidthPercentile = 0.95;

/// תחום החיפוש של תקציב דף, ביחס לתקציב הבסיסי — גבול טכני לחיפוש בלבד.
const double _kMinPageBudget = 0.8;
const double _kMinShiraPageFactor = 1;
const double _kMaxPageBudget = 2.5;

/// דיוק החיפוש: תקציב רחב בשבריר כזה מהצר ביותר אינו ניכר בשורה.
const double _kBudgetTolerance = 0.002;
const double _kBudgetFirstStep = 0.02;
const int _kMaxBudgetPasses = 40;

/// סריקת הגיבוי לדף שהחיתוך לשניים לא השלים את מניינו.
const double _kSplitScanRange = 0.06;
const double _kSplitScanStep = 0.004;
const int _kSplitScanPoints = 10;

/// סריקת התקציב של העמוד האחרון: השורה האחרונה מתקצרת ככל שהתקציב גדל,
/// עד שהיא נבלעת בקודמתה — טווח שרוחבו אלפיות ספורות בלבד.
const double _kLastLineScanRange = 0.1;
const double _kLastLineScanStep = 0.001;

/// מכייל את תקציב כל דף ב-[factors] לצר ביותר שבו הדף אינו עולה על
/// [linesPerPage] — כך שורתו האחרונה מלאה ככל האפשר ואינה נותרת במילה יתומה.
void _fitPageBudgets(
  List<TikkunToken> tokens,
  List<int?> pageStarts,
  List<double> factors,
  StamWidthModel widths,
  int linesPerPage, {
  required bool rambamParashaForms,
}) {
  final starts = [for (final s in pageStarts) ?s];
  if (starts.isEmpty) return;
  final pages = [
    for (var p = 0; p < starts.length; p++)
      (
        from: p == 0 ? 0 : starts[p],
        to: p + 1 < starts.length ? starts[p + 1] : tokens.length,
      ),
  ];

  // שבירת העמוד מחייבת תחילת שורה, ולכן כל דף נעמד לבדו — מלבד דף שנפתח
  // באמצע קטע מיוחד (שירה), שמצטרף לקודמו.
  final openAt = List<bool>.filled(tokens.length, false);
  var open = false;
  for (var i = 0; i < tokens.length; i++) {
    openAt[i] = open;
    if (tokens[i].type == TikkunTokenType.specialStart) open = true;
    if (tokens[i].type == TikkunTokenType.specialEnd) open = false;
  }
  final groups = <List<int>>[];
  for (var k = 0; k < pages.length; k++) {
    if (k > 0 && openAt[pages[k].from]) {
      groups.last.add(k);
    } else {
      groups.add([k]);
    }
  }

  final counts = List<int>.filled(pages.length, 0);
  void countGroup(List<int> group, List<double> budgets) {
    final from = pages[group.first].from;
    final sub = tokens.sublist(from, pages[group.last].to);
    final perToken = List<double>.filled(sub.length, 1);
    for (final k in group) {
      perToken.fillRange(pages[k].from - from, pages[k].to - from, budgets[k]);
    }
    final lines = paginateAllTokens(
      sub,
      widths,
      widthFactors: perToken,
      rambamParashaForms: rambamParashaForms,
    );
    // אותו כלל כמו buildOfficialPages: העמוד נפתח בשורה שמכילה את העוגן.
    final lookup = LineIndexLookup(lines);
    for (var j = 0; j < group.length; j++) {
      final first = j == 0 ? 0 : lookup.find(pages[group[j]].from - from);
      final next = j + 1 < group.length
          ? lookup.find(pages[group[j + 1]].from - from)
          : lines.length;
      counts[group[j]] = next - first;
    }
  }

  final nominal = [for (final page in pages) factors[page.from]];
  for (final group in groups) {
    countGroup(group, nominal);
  }
  // גבול תחתון ידוע (עולה על המניין) ועליון ידוע (אינו עולה); בלי אחד מהם
  // מתרחקים בצעדים מוכפלים, ואחר כך חוצים.
  final lo = List<double?>.filled(pages.length, null);
  final hi = List<double?>.filled(pages.length, null);
  final countAtHi = List<int>.filled(pages.length, 0);
  final step = List<double>.filled(pages.length, _kBudgetFirstStep);
  for (var k = 0; k < pages.length; k++) {
    if (counts[k] > linesPerPage) {
      lo[k] = nominal[k];
    } else {
      hi[k] = nominal[k];
      countAtHi[k] = counts[k];
    }
  }
  double? candidate(int k) {
    final (l, h) = (lo[k], hi[k]);
    if (l != null && h != null) {
      return h - l <= _kBudgetTolerance ? null : (l + h) / 2;
    }
    final floor = nominal[k] == 1 ? _kMinPageBudget : _kMinShiraPageFactor;
    if (h == null) {
      return l! >= _kMaxPageBudget
          ? null
          : math.min(l + step[k], _kMaxPageBudget);
    }
    return h <= floor ? null : math.max(h - step[k], floor);
  }

  for (var pass = 0; pass < _kMaxBudgetPasses; pass++) {
    final trial = [for (var k = 0; k < pages.length; k++) hi[k] ?? lo[k]!];
    final active = <int>{};
    for (var k = 0; k < pages.length; k++) {
      final c = candidate(k);
      if (c == null) continue;
      trial[k] = c;
      active.add(k);
    }
    if (active.isEmpty) break;
    for (final group in groups) {
      if (group.any(active.contains)) countGroup(group, trial);
    }
    for (final k in active) {
      if (lo[k] == null || hi[k] == null) step[k] *= 2;
      if (counts[k] <= linesPerPage) {
        hi[k] = trial[k];
        countAtHi[k] = counts[k];
      } else {
        lo[k] = trial[k];
      }
    }
  }
  // פרשיות חוזרות (הנשיאים, המשכן) עוברות את הסף יחד, והדף קופץ מעל המניין
  // אל מתחתיו; אז ראשו נחתך ברוחב שמעל הסף וסופו ברוחב שמתחתיו.
  final split = <int>{};
  for (final group in groups) {
    if (group.length != 1) continue;
    final k = group.single;
    final (l, h) = (lo[k], hi[k]);
    if (l == null || h == null) continue;
    if (nominal[k] != 1 || countAtHi[k] == linesPerPage) continue;
    final (from, to) = (pages[k].from, pages[k].to);
    final sub = tokens.sublist(from, to);
    int countSplit(int at) => paginateAllTokens(
      sub,
      widths,
      widthFactors: [for (var i = 0; i < sub.length; i++) i < at ? h : l],
      rambamParashaForms: rambamParashaForms,
    ).length;
    var (left, right) = (0, sub.length);
    while (right - left > 1) {
      final mid = (left + right) ~/ 2;
      final c = countSplit(mid);
      if (c == linesPerPage) {
        factors
          ..fillRange(from, from + mid, h)
          ..fillRange(from + mid, to, l);
        split.add(k);
        break;
      }
      if (c > linesPerPage) {
        left = mid;
      } else {
        right = mid;
      }
    }
    if (split.contains(k)) continue;
    // גם הזזת אסימון אחד מקפיצה שתי שורות: סורקים נקודות חיתוך ורוחבי סוף.
    search:
    for (var y = l - _kSplitScanRange; y < h; y += _kSplitScanStep) {
      for (var f = 1; f < _kSplitScanPoints; f++) {
        final at = sub.length * f ~/ _kSplitScanPoints;
        final count = paginateAllTokens(
          sub,
          widths,
          widthFactors: [for (var i = 0; i < sub.length; i++) i < at ? h : y],
          rambamParashaForms: rambamParashaForms,
        ).length;
        if (count != linesPerPage) continue;
        factors
          ..fillRange(from, from + at, h)
          ..fillRange(from + at, to, y);
        split.add(k);
        break search;
      }
    }
  }
  for (var k = 0; k < pages.length; k++) {
    if (split.contains(k)) continue;
    // דף שאף תקציב אינו מוריד אל המניין נשאר ברחב שבתחום.
    var budget = hi[k] ?? _kMaxPageBudget;
    if (k == pages.length - 1 && countAtHi[k] == linesPerPage) {
      budget = _midLineEnding(
        tokens.sublist(pages[k].from, pages[k].to),
        widths,
        linesPerPage,
        budget,
        rambamParashaForms: rambamParashaForms,
      );
    }
    if (budget != nominal[k]) {
      factors.fillRange(pages[k].from, pages[k].to, budget);
    }
  }
}

/// הספר נגמר באמצע השיטה האחרונה של העמוד: מבין התקציבים שמעל [from]
/// ששומרים על [linesPerPage], זה שבו השורה האחרונה קרובה ביותר לחצייה.
double _midLineEnding(
  List<TikkunToken> tokens,
  StamWidthModel widths,
  int linesPerPage,
  double from, {
  required bool rambamParashaForms,
}) {
  var best = from;
  var bestDistance = double.infinity;
  for (var b = from; b <= from + _kLastLineScanRange; b += _kLastLineScanStep) {
    final lines = paginateAllTokens(
      tokens,
      widths,
      widthFactors: List.filled(tokens.length, b),
      rambamParashaForms: rambamParashaForms,
    );
    if (lines.length != linesPerPage) break;
    final words = [
      for (final w in lines.last.words)
        if (!w.isGap && !w.isBigGap) w,
    ];
    var used = widths.wordGapEm * (words.length - 1);
    for (final w in words) {
      used += widths.wordWidthEm(w.stam);
    }
    final distance = (used / (widths.lineWidthEm * b) - 0.5).abs();
    if (distance < bestDistance) {
      best = b;
      bestDistance = distance;
    }
  }
  return best;
}

/// חלוקה לעמודים לפי השיטה. 'single_page' = עמוד אחד ארוך.
List<TikkunPage> buildPages(ProcessedTorah processed, String methodId) {
  if (methodId == 'single_page') {
    return [
      TikkunPage(
        startLineIdx: 0,
        endLineIdx: processed.allLines.length,
        lines: processed.allLines,
      ),
    ];
  }
  final layout = TikkunData.torahLayouts[methodId];
  if (layout == null) return const [];
  return buildOfficialPages(
    processed.allLines,
    processed.pageStartTokenIdx,
    layout.pages.length,
  );
}

/// עיבוד ספר בודד (נביא/כתוב, או חומש לצורך הפטרה/קריאה).
ProcessedBook processBook(
  String rawText,
  String hebrewBookName,
  StamWidthModel widths, {
  TikkunTradition tradition = TikkunTradition.ashkenazSephard,
  TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
}) {
  final tokens = tokenizeBook(
    rawText,
    hebrewBookName,
    tradition: tradition,
    decalogueTaam: decalogueTaam,
  );
  final allLines = paginateAllTokens(tokens, widths);

  final chapterToLineIdx = <int, int>{};
  for (var i = 0; i < allLines.length; i++) {
    final ch = allLines[i].firstChapterNum;
    if (ch != null) chapterToLineIdx.putIfAbsent(ch, () => i);
  }

  return ProcessedBook(
    tokens: tokens,
    allLines: allLines,
    chapterToLineIdx: chapterToLineIdx,
  );
}

/// שמות הספרים שיש לטעון כדי להציג את [haftarah] בנוסח [nusach].
List<String> haftarahBooks(Haftarah haftarah, String nusach) => [
  for (final seg in getHaftarahSegments(haftarah, nusach)) seg.book,
];

/// שמות הספרים שיש לטעון כדי להציג את [reading].
List<String> readingBooks(TorahReading reading) => [
  for (final a in reading.aliyot) a.range.book,
];

/// שורות ההפטרה: כל מקטע נחתך מהספר שלו, עם הפסק בין המקטעים.
/// [tokensByBook] — אסימוני הספרים לפי שמם העברי (ראה [tokenizeBook]).
List<TikkunLine> buildHaftarahLines(
  Haftarah haftarah,
  String nusach,
  Map<String, List<TikkunToken>> tokensByBook,
  StamWidthModel widths,
) {
  final segs = getHaftarahSegments(haftarah, nusach);
  final combined = <TikkunToken>[];

  for (var i = 0; i < segs.length; i++) {
    final seg = segs[i];
    final tokens = tokensByBook[seg.book];
    if (tokens == null) continue;
    final slice = sliceTokensByVerseRange(
      tokens,
      seg.fromCh,
      seg.fromVs,
      seg.toCh,
      seg.toVs,
    );
    final afterSetuma = precededBySetuma(tokens, seg.fromCh, seg.fromVs);
    if (i == 0) {
      if (afterSetuma) {
        combined.add(const TikkunToken(type: TikkunTokenType.leadingSetuma));
      }
    } else {
      combined.add(
        TikkunToken(
          type: afterSetuma
              ? TikkunTokenType.leadingSetuma
              : TikkunTokenType.petucha,
        ),
      );
    }
    combined.addAll(slice);
  }

  final lines = paginateAllTokens(combined, widths);
  // שורת קטע מיוחד מחזיקה את תוכנה בתאים ולא ב-`words`; סימונה כפתוחה
  // היה מחזיר אותה למסלול השורה הרגילה, והיא הייתה מתרוקנת.
  if (lines.isNotEmpty && !lines.last.isSpecial) {
    lines.last.layout = LineLayout.petucha;
  }
  return lines;
}

/// שורות קריאת המועד, כולל סימון שם העליה בשורה שבה היא מתחילה.
List<TikkunLine> buildTorahReadingLines(
  TorahReading reading,
  Map<String, List<TikkunToken>> tokensByBook,
  StamWidthModel widths,
) {
  final combined = <TikkunToken>[];
  final markers = <({int tokenIdx, String label, String? scrollLabel})>[];
  String? lastAliyaKey;
  ({String book, int ch, int vs})? lastTo;
  var scrollIdx = 0;

  for (var i = 0; i < reading.aliyot.length; i++) {
    final aliya = reading.aliyot[i];
    final range = aliya.range;
    final tokens = tokensByBook[range.book];
    if (tokens == null) continue;
    final slice = sliceTokensByVerseRange(
      tokens,
      range.fromCh,
      range.fromVs,
      range.toCh,
      range.toVs,
    );
    final afterSetuma = precededBySetuma(tokens, range.fromCh, range.fromVs);
    if (i == 0 && afterSetuma) {
      combined.add(const TikkunToken(type: TikkunTokenType.leadingSetuma));
    }

    final isNewAliya = aliya.aliya != lastAliyaKey;
    String? scrollLabel;
    if (isNewAliya && lastTo != null) {
      final sameBook = range.book == lastTo.book;
      final isAdjacent =
          sameBook &&
          ((range.fromCh == lastTo.ch && range.fromVs == lastTo.vs + 1) ||
              (range.fromCh == lastTo.ch + 1 && range.fromVs == 1));
      final isOverlap =
          sameBook &&
          compareVerse(range.fromCh, range.fromVs, lastTo.ch, lastTo.vs) <= 0;
      if (!isAdjacent && !isOverlap) {
        combined.add(
          TikkunToken(
            type: afterSetuma
                ? TikkunTokenType.leadingSetuma
                : TikkunTokenType.petucha,
          ),
        );
        // מעבר לספר אחר = ספר תורה נוסף; באותו חומש רק אחרי שכבר הוחלף
        // ספר, שאם לא כן דילוג פנימי (תענית ציבור) ייחשב בטעות כהחלפה.
        if (!sameBook || scrollIdx > 0) {
          scrollIdx++;
          scrollLabel = torahScrollLabel(scrollIdx);
        }
      }
    }
    if (isNewAliya) {
      markers.add((
        tokenIdx: combined.length,
        label: aliya.aliyaLabel,
        scrollLabel: scrollLabel,
      ));
    }
    combined.addAll(slice);
    lastAliyaKey = aliya.aliya;
    lastTo = (book: range.book, ch: range.toCh, vs: range.toVs);
  }

  final lines = paginateAllTokens(combined, widths);
  annotateReadingAliyaMarkers(lines, combined, markers);
  if (lines.isNotEmpty && !lines.last.isSpecial) {
    lines.last.layout = LineLayout.petucha;
  }
  return lines;
}

/// מסמן את שם העליה בשורה שמכילה את מילתה הראשונה — גם כשהמילה נכנסה
/// לסוף שורה של העליה הקודמת.
void annotateReadingAliyaMarkers(
  List<TikkunLine> lines,
  List<TikkunToken> tokens,
  List<({int tokenIdx, String label, String? scrollLabel})> markers,
) {
  for (final marker in markers) {
    var firstWordIdx = -1;
    for (var j = marker.tokenIdx; j < tokens.length; j++) {
      if (tokens[j].isWord) {
        firstWordIdx = j;
        break;
      }
    }
    if (firstWordIdx < 0) continue;
    for (var i = 0; i < lines.length; i++) {
      final nextStart = i + 1 < lines.length
          ? lines[i + 1].startTokenIdx
          : 0x7fffffff;
      if (lines[i].startTokenIdx >= 0 &&
          lines[i].startTokenIdx <= firstWordIdx &&
          firstWordIdx < nextStart) {
        if (marker.label == kMaftirAliyaName) {
          lines[i].maftirName ??= marker.label;
        } else {
          lines[i].aliyaName ??= marker.label;
        }
        lines[i].torahScrollLabel ??= marker.scrollLabel;
        break;
      }
    }
  }
}
