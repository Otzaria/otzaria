/// בניית העמודים (הטורים) לפי טבלת השיטה. פורט של `buildOfficialPages`
/// ו-`computeBookStartIndices` (navigation.js).
library;

import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// אינדקס האסימון שבו מתחיל כל חומש (`book_break` מפריד ביניהם).
Map<String, int> computeBookStartIndices(
  List<TikkunToken> tokens, {
  List<String> order = const ['shemot', 'vayikra', 'bamidbar', 'devarim'],
  String firstBookId = 'bereshit',
}) {
  final indices = <String, int>{firstBookId: 0};
  var count = 0;
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].type == TikkunTokenType.bookBreak) {
      if (count < order.length) {
        indices[order[count]] = i + 1;
        count++;
      }
    }
  }
  return indices;
}

/// מפה מאינדקס אסימון לשורה שמכילה אותו (חיפוש בינארי על שורות תקינות).
class LineIndexLookup {
  final List<TikkunLine> _lines;
  final List<int> _validLines;

  LineIndexLookup(this._lines)
    : _validLines = [
        for (var i = 0; i < _lines.length; i++)
          if (_lines[i].startTokenIdx >= 0) i,
      ];

  /// אינדקס השורה האחרונה שה-startTokenIdx שלה ‎<= [tokenIdx]; ‎-1 כשאין.
  int find(int tokenIdx) {
    var lo = 0;
    var hi = _validLines.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_lines[_validLines[mid]].startTokenIdx <= tokenIdx) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi >= 0 ? _validLines[hi] : -1;
  }
}

/// מספר העמודים שמילתם האחרונה אינה `lastWord` שבטבלת השיטה — מדד הכיסוי
/// של גבולות העמודים, שרובם נקבעים בהתאמת `firstWord` או באינטרפולציה.
int countUnmatchedOfficialPages(
  List<TikkunPage> pages,
  List<PageDefinition> pageDefs,
) {
  var unmatched = 0;
  for (var pi = 0; pi < pages.length && pi < pageDefs.length; pi++) {
    final expected = pageDefs[pi].lastWord;
    if (expected == null) continue;
    String? actual;
    for (final line in pages[pi].lines) {
      for (final word in line.words) {
        if (word.isGap || word.isBigGap || word.stam.isEmpty) continue;
        actual = word.stam;
      }
    }
    if (actual != expected) unmatched++;
  }
  return unmatched;
}

/// מפעיל את [visit] על כל מילה בתורה עם הפניתה. החומש מתקדם בכל `bookBreak`;
/// מילה שריקה בסת"ם (פסק בודד) אינה נספרת.
void forEachTorahWord(
  List<TikkunToken> tokens,
  void Function(int tokenIdx, TikkunWordRef ref) visit,
) {
  var book = 1;
  var chapter = 0;
  var verse = 0;
  var word = 0;
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    switch (tok.type) {
      case TikkunTokenType.bookBreak:
        book++;
        chapter = 0;
        verse = 0;
        word = 0;
      case TikkunTokenType.chapterBreak:
        chapter = tok.chapterNum!;
        verse = 0;
        word = 0;
      case TikkunTokenType.verseBreak:
        verse = tok.verseNum!;
        word = 0;
      case TikkunTokenType.word:
        if (stripNikud(tok.value!).isEmpty) continue;
        word++;
        visit(i, (book: book, chapter: chapter, verse: verse, word: word));
      default:
        break;
    }
  }
}

/// אסימון המילה שכל הפניה ב-[refs] מצביעה עליה, או `null` כשאינה בטקסט.
List<int?> resolveWordRefs(
  List<TikkunToken> tokens,
  List<TikkunWordRef?> refs,
) {
  final out = List<int?>.filled(refs.length, null);
  final pageOf = <TikkunWordRef, int>{
    for (var p = 0; p < refs.length; p++)
      if (refs[p] != null) refs[p]!: p,
  };
  if (pageOf.isEmpty) return out;
  forEachTorahWord(tokens, (i, ref) {
    final p = pageOf[ref];
    if (p != null) out[p] = i;
  });
  return out;
}

/// מזריק `pageBreak` לפני כל עוגן שמחוץ לקטע מיוחד (שם השורות בנויות מתאים),
/// ומחזיר את מיקום מילת העוגן של כל עמוד ברצף החדש.
({List<TikkunToken> tokens, List<int?> pageStarts}) insertPageBreaks(
  List<TikkunToken> tokens,
  List<int?> anchors,
) {
  final breakBefore = {
    for (var p = 1; p < anchors.length; p++)
      if (anchors[p] != null) anchors[p]!,
  };
  final out = <TikkunToken>[];
  final newIdx = List<int>.filled(tokens.length, 0);
  var inSpecial = false;
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok.type == TikkunTokenType.specialStart) inSpecial = true;
    if (tok.type == TikkunTokenType.specialEnd) inSpecial = false;
    if (!inSpecial && breakBefore.contains(i)) {
      out.add(const TikkunToken(type: TikkunTokenType.pageBreak));
    }
    newIdx[i] = out.length;
    out.add(tok);
  }
  return (
    tokens: out,
    pageStarts: [for (final a in anchors) a == null ? null : newIdx[a]],
  );
}

/// רוחב פתיחה של דף שירה: ארבע אצבעות מול שש (רמב"ם הל' ספר תורה ט,י); העיבוד
/// מכייל כל דף שירה למניין השורות. ברמ"ה וברמ"ח טרם אומת מול ספר תורה.
const double kTikkunShiraPageWidthFactor = 1.5;

/// הקטעים שהדף שהם כתובים בו רחב כולו.
const Set<String> kTikkunWidePageSections = {'shirat_hayam', 'shirat_haazinu'};

/// רוחב הדף של כל אסימון ביחס לדף רגיל, לפי [pageStarts] של [insertPageBreaks].
List<double> pageWidthFactors(List<TikkunToken> tokens, List<int?> pageStarts) {
  final factors = List<double>.filled(tokens.length, 1);
  final wide = <(int, int)>[];
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok.type != TikkunTokenType.specialStart ||
        !kTikkunWidePageSections.contains(tok.section?.id)) {
      continue;
    }
    var end = i;
    while (end < tokens.length &&
        tokens[end].type != TikkunTokenType.specialEnd) {
      end++;
    }
    wide.add((i, end));
  }
  final starts = [for (final s in pageStarts) ?s];
  for (var p = 0; p < starts.length; p++) {
    final from = p == 0 ? 0 : starts[p];
    final to = p + 1 < starts.length ? starts[p + 1] : tokens.length;
    if (wide.any((w) => w.$1 < to && w.$2 >= from)) {
      factors.fillRange(from, to, kTikkunShiraPageWidthFactor);
    }
  }
  return factors;
}

/// מפתח הפסוק שבתוקף בשורה [lineIdx] של עמוד [pageIdx] — יציב בין שיטות,
/// ולכן מחזיר את הקורא לאותו מקום אחרי החלפת חלוקה.
int? tikkunVerseKeyAt(List<TikkunPage> pages, int pageIdx, int lineIdx) {
  int? key;
  _walkVerseKeys(pages, (p, i, k) {
    if (p > pageIdx || (p == pageIdx && i > lineIdx)) return false;
    key = k ?? key;
    return true;
  });
  return key;
}

/// השורה הראשונה שבה [verseKey] (מ-[tikkunVerseKeyAt]) כבר בתוקף.
({int pageIdx, int lineInPage})? tikkunLocateVerse(
  List<TikkunPage> pages,
  int verseKey,
) {
  ({int pageIdx, int lineInPage})? found;
  _walkVerseKeys(pages, (p, i, k) {
    if (k == null || k < verseKey) return true;
    found = (pageIdx: p, lineInPage: i);
    return false;
  });
  return found;
}

/// מיקום קריאה: הפסוק שבתוקף ומספר השורות מתחילתו. הפסוק מחזיר לאותו מקום
/// גם כשהעימוד השתנה; ההיסט מדייק אותו לשורה כשהעימוד זהה.
typedef TikkunPosition = ({int verseKey, int lineOffset});

/// המיקום של שורה [lineIdx] בעמוד [pageIdx], או `null` כשאין בה פסוקים.
TikkunPosition? tikkunPositionAt(
  List<TikkunPage> pages,
  int pageIdx,
  int lineIdx,
) {
  final key = tikkunVerseKeyAt(pages, pageIdx, lineIdx);
  if (key == null) return null;
  final start = tikkunLocateVerse(pages, key)!;
  var offset = lineIdx - start.lineInPage;
  for (var p = start.pageIdx; p < pageIdx; p++) {
    offset += pages[p].lines.length;
  }
  return (verseKey: key, lineOffset: offset < 0 ? 0 : offset);
}

/// השורה של [position]; ההיסט נחתך בסוף העמודים.
({int pageIdx, int lineInPage})? tikkunLocatePosition(
  List<TikkunPage> pages,
  TikkunPosition position,
) {
  final start = tikkunLocateVerse(pages, position.verseKey);
  if (start == null) return null;
  var page = start.pageIdx;
  var line = start.lineInPage + position.lineOffset;
  while (page < pages.length - 1 && line >= pages[page].lines.length) {
    line -= pages[page].lines.length;
    page++;
  }
  final last = pages[page].lines.length - 1;
  return (
    pageIdx: page,
    lineInPage: line > last ? (last < 0 ? 0 : last) : line,
  );
}

/// החומש מזוהה בירידת מספר הפרק — בשורות אין שם חומש.
void _walkVerseKeys(
  List<TikkunPage> pages,
  bool Function(int pageIdx, int lineIdx, int? key) visit,
) {
  var book = 0;
  var chapter = 0;
  var verse = 0;
  for (var p = 0; p < pages.length; p++) {
    final lines = pages[p].lines;
    for (var i = 0; i < lines.length; i++) {
      final ch = lines[i].firstChapterNum;
      if (ch != null && ch != chapter) {
        if (ch < chapter) book++;
        chapter = ch;
        verse = lines[i].firstVerseNum ?? 1;
      } else if (lines[i].firstVerseNum != null) {
        verse = lines[i].firstVerseNum!;
      }
      final key = chapter == 0 ? null : (book * 1000 + chapter) * 1000 + verse;
      if (!visit(p, i, key)) return;
    }
  }
}

/// מייצר בדיוק [pageCount] עמודים. עמוד עם עוגן נפתח בשורה שמכילה אותו;
/// עמודים בלי עוגן מתחלקים שווה בשורות בין העוגנים שמשני צידיהם.
List<TikkunPage> buildOfficialPages(
  List<TikkunLine> allLines,
  List<int?> pageStartTokenIdx,
  int pageCount,
) {
  if (pageCount <= 0) return [];
  final lookup = LineIndexLookup(allLines);
  final starts = List<int?>.filled(pageCount, null);
  starts[0] = 0;
  var prev = 0;
  for (var p = 1; p < pageCount && p < pageStartTokenIdx.length; p++) {
    final tok = pageStartTokenIdx[p];
    if (tok == null) continue;
    final line = lookup.find(tok);
    if (line <= prev) continue;
    starts[p] = line;
    prev = line;
  }

  var lo = 0;
  for (var p = 1; p <= pageCount; p++) {
    if (p < pageCount && starts[p] == null) continue;
    final loLine = starts[lo]!;
    final hiLine = p < pageCount ? starts[p]! : allLines.length;
    final gap = p - lo;
    for (var k = 1; k < gap; k++) {
      starts[lo + k] = loLine + ((hiLine - loLine) * k / gap).round();
    }
    lo = p;
  }

  return [
    for (var p = 0; p < pageCount; p++)
      () {
        final start = starts[p]!;
        final end = p + 1 < pageCount ? starts[p + 1]! : allLines.length;
        return TikkunPage(
          startLineIdx: start,
          endLineIdx: end,
          lines: allLines.sublist(start, end),
        );
      }(),
  ];
}
