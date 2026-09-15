/// חיתוך רצף האסימונים לשורות, לפי רוחב המילים בגופן הסת"ם (יחידות em).
library;

import 'dart:math' as math;

import 'package:otzaria/tools/tikkun_korim/engine/special_lines_builder.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

final RegExp _kqPattern = RegExp(
  '\u{E010}([\\s\\S]*?)\u{E011}([\\s\\S]*?)\u{E012}',
);

RegExpMatch? _kqMatch(String word) =>
    word.contains('\u{E010}') ? _kqPattern.firstMatch(word) : null;

/// כיול העמודים מעמד את התורה פעמים רבות; כל מילה מופשטת פעם אחת.
String _stamOf(String word) => _stamCache[word] ??= stripNikud(word);
final Map<String, String> _stamCache = {};

/// תקציב רוחב מותאם לסגמנט, כדי שהשורה האחרונה לא תישאר ריקה למחצה.
double computeBalancedLineWidthEm(
  List<TikkunToken> tokens,
  StamWidthModel widths, [
  double? maxWidthEm,
]) {
  final baseWidthEm = maxWidthEm ?? widths.lineWidthEm;
  var total = 0.0;
  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.word) {
      total += widths.wordWidthEm(stripNikud(tok.value!)) + widths.wordGapEm;
    } else if (tok.type == TikkunTokenType.setuma) {
      total += widths.setumaGapEm;
    }
  }
  if (total <= baseWidthEm) return baseWidthEm;

  final linesAtBase = (total / baseWidthEm).ceil();
  final lastLineSize = total - (linesAtBase - 1) * baseWidthEm;
  if (lastLineSize < baseWidthEm * 0.5) return total / linesAtBase;
  return baseWidthEm;
}

/// רוחב אסימון מילה בשורה, לפי אותם כללים של העימוד;
/// `null` למילה שריקה בסת"ם ונדבקת לקודמת.
double? _tokenWidthEm(TikkunToken token, StamWidthModel widths) {
  final value = token.value!;
  final kq = _kqMatch(value);
  if (kq != null) {
    final ketiv = stripNikud(kq[1]!);
    final qere = stripNikud(kq[2]!);
    if (ketiv.isEmpty && qere.isEmpty) return null;
    return widths.wordWidthEm(ketiv.isNotEmpty ? ketiv : qere) +
        widths.wordGapEm;
  }
  final stam = _stamOf(value);
  if (stam.isEmpty) return null;
  return widths.wordWidthEm(stam) + widths.wordGapEm;
}

/// האם סתומה כלשהי בסגמנט תיפול בלי מקום לרווח ולהמשך, בתקציב [widthEm].
bool _setumaStarved(
  List<TikkunToken> tokens,
  StamWidthModel widths,
  double widthEm,
) {
  var lineWidth = 0.0;
  for (final tok in tokens) {
    if (tok.type == TikkunTokenType.setuma) {
      if (widthEm - lineWidth < widths.minAfterSetumaEm) return true;
      lineWidth += widths.setumaGapEm;
      if (lineWidth >= widthEm) lineWidth = 0;
      continue;
    }
    if (tok.type != TikkunTokenType.word) continue;
    final wordWidth = _tokenWidthEm(tok, widths);
    if (wordWidth == null) continue;
    if (lineWidth > 0 && lineWidth + wordWidth > widthEm) lineWidth = 0;
    lineWidth += wordWidth;
  }
  return false;
}

/// התקציב של כל אסימון, לפי הסגמנט שהוא שייך אליו. סגמנט שבו סתומה
/// נופלת בלי מקום מצומצם מעט, כדי שהחסר יתפרש על כל שורותיו.
List<double> _segmentWidths(
  List<TikkunToken> tokens,
  StamWidthModel widths,
  double maxWidthEm,
  List<double>? widthFactors, {
  required bool narrowForSetuma,
}) {
  const boundaries = {
    TikkunTokenType.petucha,
    TikkunTokenType.leadingSetuma,
    TikkunTokenType.bookBreak,
    TikkunTokenType.aliyaBreak,
    TikkunTokenType.specialStart,
    TikkunTokenType.specialEnd,
    TikkunTokenType.segmentBreak,
    TikkunTokenType.pageBreak,
  };
  const minFactor = 0.96;
  const step = 0.01;

  final result = [
    for (var i = 0; i < tokens.length; i++)
      maxWidthEm * (widthFactors?[i] ?? 1),
  ];
  var start = 0;
  void close(int end) {
    if (end <= start) return;
    final segment = tokens.sublist(start, end);
    if (!narrowForSetuma ||
        !segment.any((t) => t.type == TikkunTokenType.setuma)) {
      return;
    }
    // עמוד רחב נפתח בגבול סגמנט, ולכן התקציב אחיד בכל הסגמנט.
    final baseWidthEm = result[start];
    // כשאף צמצום לא עוזר, עדיף התקציב המלא מעל הצר שבהם.
    var width = baseWidthEm;
    for (var factor = 1.0; factor >= minFactor; factor -= step) {
      final candidate = baseWidthEm * factor;
      if (_setumaStarved(segment, widths, candidate)) continue;
      width = candidate;
      break;
    }
    // יחס ולא ערך: דף שנחתך בשני רוחבות שומר על החיתוך גם בתוך הסגמנט.
    final ratio = width / baseWidthEm;
    for (var i = start; i < end; i++) {
      result[i] *= ratio;
    }
  }

  for (var i = 0; i < tokens.length; i++) {
    if (!boundaries.contains(tokens[i].type)) continue;
    close(i);
    start = i + 1;
  }
  close(tokens.length);
  return result;
}

/// מקור המילה בשורה: אינדקס האסימון והסימונים שנפתחו בה. בלעדיו העברת
/// מילה בין שורות הייתה מזיזה את מספרי הפרק והפסוק בשוליים.
class _WordMeta {
  final int tokenIdx;
  final int? chapterNum;
  final int? verseNum;
  const _WordMeta(this.tokenIdx, this.chapterNum, this.verseNum);
}

/// העודף שיתחלק בין מילות השורה ביישור לרוחב מלא.
/// תקרת מעברי האיזון — הוא מתכנס תוך מעברים ספורים, והתקרה מונעת לולאה
/// אינסופית אם שתי הזזות יבטלו זו את זו.
const int _kMaxBalancePasses = 8;

/// עלות הריווח של שיטה — ריבוע הרווח העודף, כדי ששיטה אחת חריגה תשקול
/// יותר משתי שיטין בינוניות.
double _gapCostEm(
  List<LayoutWord> words,
  StamWidthModel widths,
  double widthEm,
) {
  final gap = _extraGapEm(words, widths, widthEm);
  return gap <= 0 ? 0 : gap * gap;
}

double _extraGapEm(
  List<LayoutWord> words,
  StamWidthModel widths,
  double widthEm,
) {
  final slots = words.length - 1;
  if (slots <= 0) return 0;
  var used = 0.0;
  for (final w in words) {
    used += widths.itemWidthEm(w);
  }
  return (widthEm - used) / slots;
}

/// האם בין שני האסימונים עומד גבול מבני שאסור להעביר מילה מעליו.
bool _breakBetween(List<TikkunToken> tokens, int from, int to) {
  const boundaries = {
    TikkunTokenType.petucha,
    TikkunTokenType.leadingSetuma,
    TikkunTokenType.bookBreak,
    TikkunTokenType.aliyaBreak,
    TikkunTokenType.specialStart,
    TikkunTokenType.specialEnd,
    TikkunTokenType.segmentBreak,
    TikkunTokenType.setuma,
    TikkunTokenType.pageBreak,
  };
  for (var i = from + 1; i < to && i < tokens.length; i++) {
    if (boundaries.contains(tokens[i].type)) return true;
  }
  return false;
}

/// רוחב התיבה שאחרי [i] — בסתומה כרמב"ם צריך מקום לתיבה אחת אחרי הריוח.
double _nextWordWidthEm(
  List<TikkunToken> tokens,
  int i,
  StamWidthModel widths,
) {
  for (var j = i + 1; j < tokens.length; j++) {
    if (tokens[j].type != TikkunTokenType.word) continue;
    final width = _tokenWidthEm(tokens[j], widths);
    if (width != null) return width;
  }
  return 0;
}

/// חיתוך כל האסימונים לשורות, כולל טיפול בקטעים מיוחדים. [widthFactors] — רוחב
/// הדף של כל אסימון; [rambamParashaForms] — פתוחות וסתומות כרמב"ם (ח,א–ב).
List<TikkunLine> paginateAllTokens(
  List<TikkunToken> tokens,
  StamWidthModel widths, {
  double? maxWidthEm,
  List<double>? widthFactors,
  bool rambamParashaForms = false,
}) {
  final maxLineWidthEm = maxWidthEm ?? widths.lineWidthEm;
  // מתחת למלאות הזו יישור לרוחב מלא מותח את השורה בצורה צורמנית.
  const partialFill = 0.65;
  final segmentWidths = _segmentWidths(
    tokens,
    widths,
    maxLineWidthEm,
    widthFactors,
    narrowForSetuma: !rambamParashaForms,
  );
  var lineWidthEm = maxLineWidthEm;
  final lines = <TikkunLine>[];
  final lineMeta = <List<_WordMeta>?>[];
  var currentLine = <LayoutWord>[];
  var currentMeta = <_WordMeta>[];
  var currentLineStartTokenIdx = -1;
  var lineWidth = 0.0;
  var lineLayout = LineLayout.regular;
  int? pendingChapterNum;
  int? pendingVerseNum;
  int? currentLineFirstVerse;
  int? currentLineFirstChapter;

  void flushLine() {
    if (currentLine.isNotEmpty) {
      lines.add(
        TikkunLine(
          words: currentLine,
          layout: lineLayout,
          startTokenIdx: currentLineStartTokenIdx,
          firstVerseNum: currentLineFirstVerse,
          firstChapterNum: currentLineFirstChapter,
        ),
      );
      lineMeta.add(currentMeta);
    }
    currentLine = [];
    currentMeta = [];
    currentLineStartTokenIdx = -1;
    lineWidth = 0;
    lineLayout = LineLayout.regular;
    currentLineFirstVerse = null;
    currentLineFirstChapter = null;
  }

  _WordMeta consumePendingMarkers(int tokenIdx) {
    final meta = _WordMeta(tokenIdx, pendingChapterNum, pendingVerseNum);
    if (pendingChapterNum != null && currentLineFirstChapter == null) {
      currentLineFirstChapter = pendingChapterNum;
    }
    if (pendingVerseNum != null && currentLineFirstVerse == null) {
      currentLineFirstVerse = pendingVerseNum;
    }
    pendingChapterNum = null;
    pendingVerseNum = null;
    return meta;
  }

  /// חישוב מחדש של סימוני השוליים אחרי שמילה עזבה את השורה או הצטרפה אליה.
  void recomputeMarkers(int lineIdx) {
    final metas = lineMeta[lineIdx];
    if (metas == null) return;
    final line = lines[lineIdx];
    line.firstChapterNum = null;
    line.firstVerseNum = null;
    for (final m in metas) {
      line.firstChapterNum ??= m.chapterNum;
      line.firstVerseNum ??= m.verseNum;
    }
    line.startTokenIdx = metas.isEmpty
        ? line.startTokenIdx
        : metas.first.tokenIdx;
  }

  /// מוריד את המילה האחרונה של השיטה שמעל [k] אליה, אם הריווח משתפר.
  /// [squaredCost] משקלל את שתי השיטין יחד; בלעדיו נשקל הרווח הגדול שבהן.
  bool tryMoveWordDown(int k, {required bool squaredCost}) {
    final donor = lines[k - 1];
    final target = lines[k];
    final donorMeta = lineMeta[k - 1];
    final targetMeta = lineMeta[k];
    if (donorMeta == null || targetMeta == null) return false;
    if (donor.layout != LineLayout.regular) return false;
    if (target.layout != LineLayout.regular) return false;
    if (donor.words.length < 2 || donorMeta.length != donor.words.length) {
      return false;
    }
    final moved = donor.words.last;
    if (moved.isGap || moved.isBigGap) return false;
    final movedMeta = donorMeta.last;
    if (_breakBetween(tokens, movedMeta.tokenIdx, target.startTokenIdx)) {
      return false;
    }
    final donorWidth =
        segmentWidths[donor.startTokenIdx.clamp(0, segmentWidths.length - 1)];
    final targetWidth =
        segmentWidths[target.startTokenIdx.clamp(0, segmentWidths.length - 1)];
    final newDonorWords = donor.words.sublist(0, donor.words.length - 1);
    final newTargetWords = [moved, ...target.words];
    var targetUsed = 0.0;
    for (final w in newTargetWords) {
      targetUsed += widths.itemWidthEm(w);
    }
    if (targetUsed > targetWidth) return false;

    final double before;
    final double after;
    if (squaredCost) {
      before =
          _gapCostEm(donor.words, widths, donorWidth) +
          _gapCostEm(target.words, widths, targetWidth);
      after =
          _gapCostEm(newDonorWords, widths, donorWidth) +
          _gapCostEm(newTargetWords, widths, targetWidth);
    } else {
      before = math.max(
        _extraGapEm(donor.words, widths, donorWidth),
        _extraGapEm(target.words, widths, targetWidth),
      );
      after = math.max(
        _extraGapEm(newDonorWords, widths, donorWidth),
        _extraGapEm(newTargetWords, widths, targetWidth),
      );
    }
    if (after >= before) return false;

    donor.words = newDonorWords;
    donorMeta.removeLast();
    target.words = newTargetWords;
    targetMeta.insert(0, movedMeta);
    recomputeMarkers(k - 1);
    recomputeMarkers(k);
    return true;
  }

  // אחרי שסתומה משכה מילה למטה השורה שמעליה נשארת דלילה ונמתחת; מורידים
  // אליה מילה מקודמתה כל עוד הרווח הגדול משתי השורות מצטמצם.
  void borrowUpward() {
    for (var k = lines.length - 1; k > 0; k--) {
      if (!tryMoveWordDown(k, squaredCost: false)) return;
    }
  }

  // המעמד חמדני וממלא כל שיטה עד הסוף, ולכן שיטה דחוסה משאירה את זו שאחריה
  // דלילה. כאן מוזזת מילה למטה כל עוד סכום עלויות הריווח של השתיים יורד.
  void balanceRegularLines() {
    for (var pass = 0; pass < _kMaxBalancePasses; pass++) {
      var changed = false;
      for (var k = 1; k < lines.length; k++) {
        if (tryMoveWordDown(k, squaredCost: true)) changed = true;
      }
      if (!changed) return;
    }
  }

  // שורה קצרה לפני גבול סגמנט מתמתחת מכוער ב-space-between; ממזגים אותה
  // לקודמת כשהאיחוד עדיין נכנס בחריגה של עד 20%.
  void rebalanceLastSegmentBeforeBoundary() {
    if (currentLine.isEmpty) return;
    var curWidth = 0.0;
    for (final w in currentLine) {
      curWidth += widths.itemWidthEm(w);
    }
    if (curWidth >= lineWidthEm * 0.4 || lines.isEmpty) {
      flushLine();
      return;
    }
    final prev = lines.last;
    if (prev.layout != LineLayout.regular &&
        prev.layout != LineLayout.partial) {
      flushLine();
      return;
    }
    final allWords = [...prev.words, ...currentLine];
    var totalWidth = 0.0;
    for (final w in allWords) {
      totalWidth += widths.itemWidthEm(w);
    }
    if (totalWidth <= lineWidthEm * 1.20) {
      prev.words = allWords;
      prev.layout = LineLayout.regular;
      final prevMeta = lineMeta.last;
      if (prevMeta == null) {
        lineMeta[lineMeta.length - 1] = null;
      } else {
        prevMeta.addAll(currentMeta);
      }
      currentLine = [];
      currentMeta = [];
      currentLineStartTokenIdx = -1;
      lineWidth = 0;
      lineLayout = LineLayout.regular;
      currentLineFirstVerse = null;
      currentLineFirstChapter = null;
      return;
    }
    flushLine();
  }

  void appendEmptyLine(int tokenIdx) {
    if (lines.isNotEmpty && lines.last.layout == LineLayout.empty) return;
    lines.add(TikkunLine(layout: LineLayout.empty, startTokenIdx: tokenIdx));
    lineMeta.add(null);
  }

  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    lineWidthEm = segmentWidths[i];

    if (tok.type == TikkunTokenType.specialStart) {
      rebalanceLastSegmentBeforeBoundary();

      final sectionTokens = <TikkunToken>[];
      var j = i + 1;
      while (j < tokens.length &&
          tokens[j].type != TikkunTokenType.specialEnd) {
        sectionTokens.add(tokens[j]);
        j++;
      }

      for (final st in sectionTokens) {
        if (st.type == TikkunTokenType.chapterBreak) {
          pendingChapterNum = st.chapterNum;
          pendingVerseNum ??= 1;
        } else if (st.type == TikkunTokenType.verseBreak) {
          pendingVerseNum = st.verseNum;
        }
      }

      final section = tok.section;
      final specialLines = section == null
          ? <TikkunLine>[]
          : buildSpecialLines(
              sectionTokens,
              i + 1,
              section,
              openingChapter: tok.openingChapter,
              openingVerse: tok.openingVerse,
            );

      if (specialLines.isNotEmpty) {
        final startCh = tok.openingChapter ?? section?.fromCh;
        if (startCh != null && specialLines.first.firstChapterNum == null) {
          specialLines.first.firstChapterNum = startCh;
        }
        if (section != null && section.justifyLineBefore && lines.isNotEmpty) {
          final last = lines.last;
          if (last.layout == LineLayout.petucha ||
              last.layout == LineLayout.partial) {
            last.layout = LineLayout.regular;
          }
        }

        var lastKnownStart = i;
        for (final line in specialLines) {
          final firstIdx = firstTokenIdxOfLine(line);
          if (firstIdx >= 0) lastKnownStart = firstIdx;
          line.startTokenIdx = lastKnownStart;
          if (section?.cssClass != null) line.cssClass = section!.cssClass;
        }
        pendingChapterNum = null;
        pendingVerseNum = null;
        // בשיטת הרמב"ם האזינו נפתחת בלי שיטה פנויה לפניה.
        final blankBefore =
            (section?.blankLineBefore ?? false) &&
            !(rambamParashaForms && section!.id == 'shirat_haazinu');
        if (blankBefore) appendEmptyLine(i);
        lines.addAll(specialLines);
        lineMeta.addAll(
          List<List<_WordMeta>?>.filled(specialLines.length, null),
        );
        if (section?.blankLineAfter ?? false) appendEmptyLine(i);
      }

      i = j;
      continue;
    }

    if (tok.type == TikkunTokenType.specialEnd) continue;
    if (tok.type == TikkunTokenType.segmentBreak) continue;

    if (tok.type == TikkunTokenType.leadingSetuma) {
      if (currentLine.isNotEmpty) {
        lineLayout = LineLayout.petucha;
        flushLine();
      }
      currentLine.add(const LayoutWord(stam: kBigGapWord, nikud: kBigGapWord));
      currentMeta.add(_WordMeta(i, null, null));
      lineWidth += widths.bigGapEm * (widthFactors?[i] ?? 1);
      lineLayout = LineLayout.setumaStart;
      continue;
    }

    if (tok.type == TikkunTokenType.petucha) {
      // ח,א: נשאר בשיטה פחות מתשע אותיות, או שגמר בסופה — שיטה שנייה פנויה.
      final blankLine =
          rambamParashaForms &&
          (currentLine.isNotEmpty
              ? lineWidthEm - lineWidth < widths.setumaGapEm
              : lines.isNotEmpty && lines.last.layout == LineLayout.regular);
      if (currentLine.isNotEmpty) {
        lineLayout = LineLayout.petucha;
        flushLine();
      } else if (lines.isNotEmpty && lines.last.layout != LineLayout.empty) {
        lines.last.layout = LineLayout.petucha;
      }
      if (blankLine) appendEmptyLine(i);
      continue;
    }

    // השיטה שלפני עמוד חדש נשארת מיושרת; האיזון מפזר את החוסר על שורות העמוד.
    if (tok.type == TikkunTokenType.pageBreak) {
      if (currentLine.isNotEmpty) flushLine();
      continue;
    }

    if (tok.type == TikkunTokenType.aliyaBreak) {
      if (currentLine.isNotEmpty) flushLine();
      continue;
    }

    if (tok.type == TikkunTokenType.bookBreak) {
      if (currentLine.isNotEmpty) {
        lineLayout = LineLayout.petucha;
        flushLine();
      }
      // ד' שיטין פנויות בדיוק — שיטה פנויה שכבר הוזרקה בפתוחה שקדמה נספרת בהן.
      var blank = 0;
      for (var k = lines.length - 1; k >= 0; k--) {
        if (lines[k].layout != LineLayout.empty) break;
        blank++;
      }
      for (var k = blank; k < 4; k++) {
        lines.add(TikkunLine(layout: LineLayout.empty, startTokenIdx: i));
        lineMeta.add(null);
      }
      continue;
    }

    if (tok.type == TikkunTokenType.chapterBreak) {
      pendingChapterNum = tok.chapterNum;
      pendingVerseNum ??= 1;
      continue;
    }

    if (tok.type == TikkunTokenType.verseBreak) {
      pendingVerseNum = tok.verseNum;
      continue;
    }

    if (tok.type == TikkunTokenType.setuma && rambamParashaForms) {
      final remaining = lineWidthEm - lineWidth;
      if (currentLine.isEmpty ||
          remaining <
              widths.setumaGapEm + _nextWordWidthEm(tokens, i, widths)) {
        // ח,ב: אין מקום לריוח ולתיבה — שאר השיטה פנוי, ובראש השנייה השלמה
        // לשיעור, ולפחות מלא אות קטנה ("מעט רוח").
        final left = currentLine.isEmpty ? 0.0 : remaining;
        if (currentLine.isNotEmpty) {
          lineLayout = LineLayout.petucha;
          flushLine();
        }
        final lead = math.max(widths.setumaGapEm - left, widths.wordGapEm);
        currentLineStartTokenIdx = i;
        currentLine.add(
          LayoutWord(
            stam: kGapWord,
            nikud: kGapWord,
            gapFraction: lead / widths.setumaGapEm,
          ),
        );
        currentMeta.add(_WordMeta(i, null, null));
        lineLayout = LineLayout.setuma;
        lineWidth = lead;
        continue;
      }
    }

    if (tok.type == TikkunTokenType.setuma) {
      if (!rambamParashaForms &&
          lineWidthEm - lineWidth < widths.minAfterSetumaEm &&
          currentLine.length >= 2) {
        final lastWord = currentLine.removeLast();
        final lastMeta = currentMeta.removeLast();
        final lastWidth = widths.itemWidthEm(lastWord);
        lineWidth -= lastWidth;
        flushLine();
        borrowUpward();
        currentLineStartTokenIdx = lastMeta.tokenIdx;
        currentLineFirstChapter = lastMeta.chapterNum;
        currentLineFirstVerse = lastMeta.verseNum;
        currentLine.add(lastWord);
        currentMeta.add(lastMeta);
        lineWidth = lastWidth;
      }
      if (currentLineStartTokenIdx < 0) currentLineStartTokenIdx = i;
      currentLine.add(const LayoutWord(stam: kGapWord, nikud: kGapWord));
      currentMeta.add(_WordMeta(i, null, null));
      lineLayout = LineLayout.setuma;
      lineWidth += widths.setumaGapEm;
      if (lineWidth >= lineWidthEm) flushLine();
      continue;
    }

    final word = tok.value!;
    final kq = _kqMatch(word);
    if (kq != null) {
      final ketiv = kq[1]!;
      final qere = kq[2]!;
      final ketivStam = stripNikud(ketiv);
      final qereStam = stripNikud(qere);
      if (ketivStam.isEmpty && qereStam.isEmpty) continue;
      final baseWidth =
          widths.wordWidthEm(ketivStam.isNotEmpty ? ketivStam : qereStam) +
          widths.wordGapEm;
      final onlyLeadingGap = currentLine.length == 1 && currentLine[0].isBigGap;
      if (currentLine.isNotEmpty &&
          !onlyLeadingGap &&
          lineWidth + baseWidth > lineWidthEm) {
        if (lineLayout == LineLayout.regular &&
            lineWidth < lineWidthEm * partialFill) {
          lineLayout = LineLayout.partial;
        }
        flushLine();
      }
      if (currentLineStartTokenIdx < 0) currentLineStartTokenIdx = i;
      currentMeta.add(consumePendingMarkers(i));
      currentLine.add(LayoutWord(stam: ketivStam, nikud: qere));
      lineWidth += baseWidth;
      continue;
    }

    final wordStam = _stamOf(word);

    // מילה שריקה בסת"ם (פסק/סוף פסוק בודדים) נדבקת לקודמת בטור המנוקד.
    if (wordStam.isEmpty) {
      if (currentLine.isNotEmpty) {
        final prev = currentLine.last;
        currentLine[currentLine.length - 1] = prev.copyWith(
          nikud: '${prev.nikud} $word',
        );
      }
      continue;
    }

    final wordWidth = widths.wordWidthEm(wordStam) + widths.wordGapEm;
    final onlyLeadingGap = currentLine.length == 1 && currentLine[0].isBigGap;
    if (currentLine.isNotEmpty &&
        !onlyLeadingGap &&
        lineWidth + wordWidth > lineWidthEm) {
      if (lineLayout == LineLayout.regular &&
          lineWidth < lineWidthEm * partialFill) {
        lineLayout = LineLayout.partial;
      }
      flushLine();
    }
    if (currentLineStartTokenIdx < 0) currentLineStartTokenIdx = i;
    currentMeta.add(consumePendingMarkers(i));
    currentLine.add(LayoutWord(stam: wordStam, nikud: word));
    lineWidth += wordWidth;
  }

  // השורה האחרונה בטקסט לעולם לא נמתחת לרוחב מלא, גם כשהיא כמעט מלאה.
  if (currentLine.isNotEmpty) {
    if (lineLayout == LineLayout.regular) lineLayout = LineLayout.partial;
    flushLine();
  }

  balanceRegularLines();

  return lines;
}
