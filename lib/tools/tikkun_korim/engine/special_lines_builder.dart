/// בניית שורות הפריסה של קטע מיוחד (שירה / רשימה). פורט של
/// `buildSpecialLines` וכל ה-`build*Lines` (special_layouts.js).
library;

import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// אתנחתא — חוצה את הפסוק לשני חצאים בפריסת `shira_parallel`.
const String kAtnachta = '֑';

final RegExp _maqafOrHyphen = RegExp('[־-]');
final RegExp _kqPattern = RegExp(
  '\u{E010}([\\s\\S]*?)\u{E011}([\\s\\S]*?)\u{E012}',
);

class _Verse {
  int? verseNum;
  List<LayoutWord> words = [];

  _Verse(this.verseNum);
}

/// מילה מתוך אסימון, בהתחשב בכתיב/קרי. `null` כשאין מה להציג.
LayoutWord? _wordFromToken(TikkunToken tok, int? verseNum, int tokenIdx) {
  final word = tok.value!;
  final kq = _kqPattern.firstMatch(word);
  if (kq != null) {
    final ketivRaw = kq[1]!;
    final qereRaw = kq[2]!;
    final ketivStam = stripNikud(ketivRaw);
    final qereStam = stripNikud(qereRaw);
    if (ketivStam.isEmpty && qereStam.isEmpty) return null;
    return LayoutWord(
      stam: ketivStam,
      nikud: qereRaw,
      verseNum: verseNum,
      tokenIdx: tokenIdx,
    );
  }
  final wordStam = stripNikud(word);
  if (wordStam.isEmpty) return null;
  return LayoutWord(
    stam: wordStam,
    nikud: word,
    verseNum: verseNum,
    tokenIdx: tokenIdx,
  );
}

/// נקודת החיתוך של פסוק לפי האתנחתא, או מחצית המילים כשאין.
int findAtnachtaSplit(List<LayoutWord> words) {
  for (var i = 0; i < words.length; i++) {
    final text = words[i].nikud.isNotEmpty ? words[i].nikud : words[i].stam;
    if (text.contains(kAtnachta)) return i + 1;
  }
  return (words.length + 1) ~/ 2;
}

List<TikkunLine> buildParallelLines(List<List<LayoutWord>> verses) {
  final lines = <TikkunLine>[];
  int? lastVerse;
  for (final verseWords in verses) {
    if (verseWords.isEmpty) continue;
    final splitAt = findAtnachtaSplit(verseWords);
    final line = TikkunLine(
      layout: LineLayout.shiraParallel,
      rightWords: verseWords.sublist(0, splitAt),
      leftWords: verseWords.sublist(splitAt),
    );
    final vn = verseWords.first.verseNum;
    if (vn != null && vn != lastVerse) {
      line.firstVerseNum = vn;
      lastVerse = vn;
    }
    lines.add(line);
  }
  return lines;
}

List<TikkunLine> buildZigzagLines(List<List<LayoutWord>> verses) {
  const cap50 = 18;
  const cap25 = 9;

  final flatWords = <LayoutWord>[for (final v in verses) ...v];
  if (flatWords.isEmpty) return [];

  int wordLen(LayoutWord w) => w.stam.length + 1;

  final lines = <TikkunLine>[];
  var wi = 0;
  var rowParity = 0;
  int? lastVerse;

  while (wi < flatWords.length) {
    int? lineFirstVerse;
    final capacities = rowParity == 0
        ? const [cap50, cap50]
        : const [cap25, cap50, cap25];
    final cells = [<LayoutWord>[], <LayoutWord>[], <LayoutWord>[]];

    for (var ci = 0; ci < capacities.length; ci++) {
      final cap = capacities[ci];
      var cellChars = 0;
      while (wi < flatWords.length) {
        final w = flatWords[wi];
        final wl = wordLen(w);
        if (cells[ci].isNotEmpty && cellChars + wl > cap) break;
        if (lineFirstVerse == null &&
            w.verseNum != null &&
            w.verseNum != lastVerse) {
          lineFirstVerse = w.verseNum;
          lastVerse = w.verseNum;
        }
        cells[ci].add(w);
        cellChars += wl;
        wi++;
      }
    }

    final line = rowParity == 0
        ? TikkunLine(
            layout: LineLayout.shiraZigzag,
            zigzagRow: ZigzagRow.double,
            rightWords: cells[0],
            leftWords: cells[1],
          )
        : TikkunLine(
            layout: LineLayout.shiraZigzag,
            zigzagRow: ZigzagRow.triple,
            rightWords: cells[0],
            centerWords: cells[1],
            leftWords: cells[2],
          );
    if (lineFirstVerse != null) line.firstVerseNum = lineFirstVerse;
    lines.add(line);
    rowParity = 1 - rowParity;
  }
  return lines;
}

/// שורות לפי טבלת חלוקה ידנית; התא האחרון בשורה האחרונה בולע את השארית.
List<TikkunLine> buildManualRowsLines(
  List<LayoutWord> flatWords,
  List<List<ManualRowSpec>> manualRows,
) {
  final lines = <TikkunLine>[];
  var wi = 0;
  int? lastVerse;
  for (var ri = 0; ri < manualRows.length; ri++) {
    final row = manualRows[ri];
    final isLastRow = ri == manualRows.length - 1;
    final cells = <ManualCell>[];
    int? lineFirstVerse;
    for (var ci = 0; ci < row.length; ci++) {
      final spec = row[ci];
      final isLastCell = isLastRow && ci == row.length - 1;
      final cellWords = <LayoutWord>[];
      final targetN = isLastCell ? flatWords.length : spec.count;
      for (var k = 0; k < targetN && wi < flatWords.length; k++) {
        final w = flatWords[wi];
        if (lineFirstVerse == null &&
            w.verseNum != null &&
            w.verseNum != lastVerse) {
          lineFirstVerse = w.verseNum;
          lastVerse = w.verseNum;
        }
        cellWords.add(w);
        wi++;
      }
      cells.add(ManualCell(width: spec.width, words: cellWords));
    }
    final line = TikkunLine(
      layout: LineLayout.shiraZigzag,
      zigzagRow: ZigzagRow.manual,
      manualCells: cells,
    );
    if (lineFirstVerse != null) line.firstVerseNum = lineFirstVerse;
    lines.add(line);
  }
  return lines;
}

/// שורות 50/50 לפי הרווחים הוויזואליים (segment_break) שבטקסט המקור.
List<TikkunLine> buildSegmentPairsLines(
  List<TikkunToken> sectionTokens,
  int baseTokenIdx, {
  int? openingVerse,
}) {
  final segments = <List<LayoutWord>>[];
  var curSeg = <LayoutWord>[];
  var curVerse = openingVerse;

  void flushSeg() {
    if (curSeg.isNotEmpty) segments.add(curSeg);
    curSeg = [];
  }

  for (var i = 0; i < sectionTokens.length; i++) {
    final tok = sectionTokens[i];
    if (tok.type == TikkunTokenType.verseBreak) {
      if (!tok.suppressFlush) flushSeg();
      curVerse = tok.verseNum;
      continue;
    }
    if (tok.type == TikkunTokenType.segmentBreak) {
      flushSeg();
      continue;
    }
    if (tok.type != TikkunTokenType.word) continue;
    final w = _wordFromToken(tok, curVerse, baseTokenIdx + i);
    if (w != null) curSeg.add(w);
  }
  flushSeg();

  final lines = <TikkunLine>[];
  int? lastVerseShown;
  for (var i = 0; i < segments.length; i += 2) {
    final right = segments[i];
    final left = i + 1 < segments.length ? segments[i + 1] : null;
    final line = TikkunLine(
      layout: LineLayout.shiraZigzag,
      zigzagRow: ZigzagRow.manual,
      manualCells: [
        ManualCell(width: 50, words: right),
        ManualCell(width: 50, words: left ?? const []),
      ],
    );
    final vn = right.first.verseNum;
    if (vn != null && vn != lastVerseShown) {
      line.firstVerseNum = vn;
      lastVerseShown = vn;
    }
    lines.add(line);
  }
  return lines;
}

List<TikkunLine> buildListPairsLines(
  List<LayoutWord> words,
  String? separator,
  String pairOrder,
) {
  bool isSep(LayoutWord w) =>
      w.stam.replaceAll(_maqafOrHyphen, '') == separator;
  final lines = <TikkunLine>[];
  var i = 0;

  void pushLine(List<LayoutWord> nameWords, LayoutWord? sepWord) {
    if (nameWords.isEmpty && sepWord == null) return;
    lines.add(
      TikkunLine(
        layout: LineLayout.listPairs,
        rightWords: nameWords,
        leftWords: sepWord == null ? <LayoutWord>[] : [sepWord],
      ),
    );
  }

  if (pairOrder == 'words_then_sep') {
    while (i < words.length) {
      final nameWords = <LayoutWord>[];
      while (i < words.length && !isSep(words[i])) {
        nameWords.add(words[i]);
        i++;
      }
      if (i < words.length && isSep(words[i])) {
        pushLine(nameWords, words[i]);
        i++;
      } else {
        pushLine(nameWords, null);
      }
    }
  } else {
    final leadingWords = <LayoutWord>[];
    while (i < words.length && !isSep(words[i])) {
      leadingWords.add(words[i]);
      i++;
    }
    if (leadingWords.isNotEmpty) pushLine(leadingWords, null);
    while (i < words.length) {
      final sepWord = words[i];
      i++;
      final nameWords = <LayoutWord>[];
      while (i < words.length && !isSep(words[i])) {
        nameWords.add(words[i]);
        i++;
      }
      pushLine(nameWords, sepWord);
    }
  }
  return lines;
}

List<TikkunLine> buildQuadLines(
  List<List<LayoutWord>> verses,
  String? separator,
) {
  bool isSep(LayoutWord w) {
    final c = w.stam.replaceAll(_maqafOrHyphen, '');
    return c == separator || c == 'ו$separator';
  }

  final lines = <TikkunLine>[];
  int? lastVerse;
  for (final verseWords in verses) {
    if (verseWords.isEmpty) continue;
    final groups = <List<LayoutWord>>[];
    var current = <LayoutWord>[];
    for (final w in verseWords) {
      if (isSep(w)) {
        if (current.isNotEmpty) groups.add(current);
        groups.add([w]);
        current = [];
      } else {
        current.add(w);
      }
    }
    if (current.isNotEmpty) groups.add(current);

    final line = TikkunLine(layout: LineLayout.listQuad, cells: groups);
    final vn = verseWords.first.verseNum;
    if (vn != null && vn != lastVerse) {
      line.firstVerseNum = vn;
      lastVerse = vn;
    }
    lines.add(line);
  }
  return lines;
}

List<TikkunLine> buildAlternatingLines(List<LayoutWord> words) {
  final lines = <TikkunLine>[];
  int? lastVerse;
  for (var i = 0; i < words.length; i += 2) {
    final rightW = words[i];
    final leftW = i + 1 < words.length ? words[i + 1] : null;
    final line = TikkunLine(
      layout: LineLayout.listAlternating,
      rightWords: [rightW],
      leftWords: leftW == null ? <LayoutWord>[] : [leftW],
    );
    // המילה השמאלית פותחת את הפסוק הבא, ולכן היא שקובעת את מספר הפסוק.
    final sourceVerse = leftW?.verseNum ?? rightW.verseNum;
    if (sourceVerse != null && sourceVerse != lastVerse) {
      line.firstVerseNum = sourceVerse;
      lastVerse = sourceVerse;
    }
    lines.add(line);
  }
  return lines;
}

/// בונה את שורות הקטע המיוחד. [baseTokenIdx] הוא האינדקס הגלובלי של
/// `sectionTokens[0]` (מחליף את `globalIdx` שהוצמד לאסימון ב-JS).
List<TikkunLine> buildSpecialLines(
  List<TikkunToken> sectionTokens,
  int baseTokenIdx,
  SpecialSection section, {
  int? openingChapter,
  int? openingVerse,
}) {
  final verses = <_Verse>[];
  var curVerse = _Verse(openingVerse);

  void flushVerse() {
    if (curVerse.words.isNotEmpty) verses.add(curVerse);
    curVerse = _Verse(null);
  }

  for (var i = 0; i < sectionTokens.length; i++) {
    final tok = sectionTokens[i];
    if (tok.type == TikkunTokenType.verseBreak) {
      flushVerse();
      curVerse.verseNum = tok.verseNum;
      continue;
    }
    if (tok.type != TikkunTokenType.word) continue;
    final w = _wordFromToken(tok, curVerse.verseNum, baseTokenIdx + i);
    if (w != null) curVerse.words.add(w);
  }
  flushVerse();

  if (verses.isEmpty) return [];

  if (section.hasTrim) {
    final n = section.trimStartKeepLast;
    if (n != null) {
      final first = verses.first.words;
      if (first.length > n) {
        verses.first.words = first.sublist(first.length - n);
      }
    }
    final m = section.trimEndKeepFirst;
    if (m != null) {
      final last = verses.last.words;
      if (last.length > m) verses.last.words = last.sublist(0, m);
    }
  }

  final flatWords = <LayoutWord>[for (final v in verses) ...v.words];
  final verseWordLists = [for (final v in verses) v.words];

  switch (section.layout) {
    case 'shira_parallel':
      return buildParallelLines(verseWordLists);
    case 'shira_zigzag':
      return buildZigzagLines(verseWordLists);
    case 'manual_zigzag':
      return buildManualRowsLines(flatWords, section.manualRows);
    case 'segment_pairs':
      return buildSegmentPairsLines(
        sectionTokens,
        baseTokenIdx,
        openingVerse: openingVerse,
      );
    case 'list_pairs':
      return buildListPairsLines(
        flatWords,
        section.pairSeparator,
        section.pairOrder,
      );
    case 'list_alternating':
      return buildAlternatingLines(flatWords);
    case 'list_quad':
      return buildQuadLines(verseWordLists, section.pairSeparator);
    default:
      return [];
  }
}

/// האינדקס הגלובלי הקטן ביותר מבין מילות השורה, או ‎-1.
int firstTokenIdxOfLine(TikkunLine line) {
  var best = -1;
  void scan(List<LayoutWord>? group) {
    if (group == null) return;
    for (final w in group) {
      final idx = w.tokenIdx;
      if (idx != null && (best < 0 || idx < best)) best = idx;
    }
  }

  scan(line.rightWords);
  scan(line.centerWords);
  scan(line.leftWords);
  if (line.manualCells != null) {
    for (final c in line.manualCells!) {
      scan(c.words);
    }
  }
  if (line.cells != null) {
    for (final c in line.cells!) {
      scan(c);
    }
  }
  scan(line.words);
  return best;
}
