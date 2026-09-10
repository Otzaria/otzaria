/// סימון תחילת פרשה ועליה על השורות. פורט של `annotateAliyotOnLines`,
/// `annotateCombinedAliyotOnLines` (navigation.js) ו-`findParashaStart`
/// (parasha_index.js).
library;

import 'package:otzaria/tools/tikkun_korim/data/tikkun_data.dart';
import 'package:otzaria/tools/tikkun_korim/engine/official_pages_builder.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

final RegExp _kqMarks = RegExp('[\u{E010}-\u{E012}]');
final RegExp _nikudAndMaqaf = RegExp('[֑-ׇ־]');
final RegExp _zeiraRabati = RegExp('[\u{E020}-\u{E023}]');
final RegExp _maskedName = RegExp('יקוק');

/// תוויות שלוש ההפסקות של קריאת שני וחמישי, לפי סדרן.
const List<String> kWeekdayAliyaLabels = ['כהן', 'לוי', 'ישראל'];

/// נרמול מילה לצורך השוואה: בלי ניקוד, מקף וסימוני PUA; שם השם המוסתר
/// מוחזר לצורתו כדי שהתאמת מילות הפתיחה תעבוד בשני הכיוונים.
String normalizeForMatch(String s) => s
    .replaceAll(_kqMarks, '')
    .replaceAll(_nikudAndMaqaf, '')
    .replaceAll(_zeiraRabati, '')
    .replaceAll(_maskedName, 'יהוה');

String normalizeParashaName(String uiName) =>
    TikkunData.normalizeParashaName(uiName);

/// אינדקס האסימון שבו מתחילה [parashaName], או ‎-1.
int findParashaStart(
  List<TikkunToken> tokens,
  String parashaName, [
  int startFromIdx = 0,
]) {
  final opening = TikkunData.parashaOpenings[parashaName];
  if (opening == null) return -1;
  final normOpening = opening.map(normalizeForMatch).toList(growable: false);

  for (var i = startFromIdx; i < tokens.length - opening.length; i++) {
    if (tokens[i].type != TikkunTokenType.word) continue;
    var opIdx = 0;
    var tIdx = i;
    var matched = true;
    while (opIdx < normOpening.length && tIdx < tokens.length) {
      final tok = tokens[tIdx];
      if (tok.type != TikkunTokenType.word) {
        tIdx++;
        continue;
      }
      final nv = normalizeForMatch(tok.value!);
      if (nv.isEmpty) {
        tIdx++;
        continue;
      }
      if (nv != normOpening[opIdx]) {
        matched = false;
        break;
      }
      opIdx++;
      tIdx++;
    }
    if (matched && opIdx == normOpening.length) return i;
  }
  return -1;
}

/// אינדקס האסימון שממנו מתחיל רצף [words], או ‎-1. מילת חיפוש יכולה
/// להתפרס על כמה אסימונים שהיו מחוברים במקף במקור.
int findWordSequence(
  List<TikkunToken> tokens,
  List<String> words,
  int fromIdx,
) {
  final normWords = words.map(normalizeForMatch).toList(growable: false);
  for (var i = fromIdx; i < tokens.length - words.length; i++) {
    if (tokens[i].type != TikkunTokenType.word) continue;
    var wIdx = 0;
    var tIdx = i;
    var ok = true;
    while (wIdx < normWords.length && tIdx < tokens.length) {
      final tok = tokens[tIdx];
      if (tok.type != TikkunTokenType.word) {
        tIdx++;
        continue;
      }
      final searchWord = normWords[wIdx];
      final tokenWord = normalizeForMatch(tok.value!);
      if (tokenWord.isEmpty) {
        tIdx++;
        continue;
      }
      if (tokenWord == searchWord) {
        wIdx++;
        tIdx++;
      } else if (searchWord.startsWith(tokenWord)) {
        var built = tokenWord;
        tIdx++;
        while (built.length < searchWord.length && tIdx < tokens.length) {
          final next = tokens[tIdx];
          if (next.type != TikkunTokenType.word) {
            tIdx++;
            continue;
          }
          built += normalizeForMatch(next.value!);
          tIdx++;
          if (built == searchWord) break;
          if (!searchWord.startsWith(built)) break;
        }
        if (built == searchWord) {
          wIdx++;
        } else {
          ok = false;
          break;
        }
      } else {
        ok = false;
        break;
      }
    }
    if (ok && wIdx == normWords.length) return i;
  }
  return -1;
}

/// אינדקס פסוקים בטווח אסימונים של חומש אחד: (פרק, פסוק) → אינדקס
/// המילה הראשונה של הפסוק.
class BookVerseIndex {
  final Map<int, int> _byKey;

  BookVerseIndex._(this._byKey);

  static int _key(int ch, int vs) => ch * 1000 + vs;

  /// [from] עד [to] (לא כולל) הם גבולות החומש ברצף האסימונים המלא.
  factory BookVerseIndex(List<TikkunToken> tokens, int from, int to) {
    final byKey = <int, int>{};
    int? curCh;
    int? curVs;
    for (var i = from; i < to && i < tokens.length; i++) {
      final tok = tokens[i];
      switch (tok.type) {
        case TikkunTokenType.chapterBreak:
          curCh = tok.chapterNum;
          // כמו בפאגינטור: פסוק א' של פרק אינו חייב לשאת סמן פסוק.
          curVs = 1;
        case TikkunTokenType.verseBreak:
          curVs = tok.verseNum;
        case TikkunTokenType.word:
          if (curCh != null && curVs != null) {
            byKey.putIfAbsent(_key(curCh, curVs), () => i);
          }
        default:
          break;
      }
    }
    return BookVerseIndex._(byKey);
  }

  /// אינדקס האסימון של המילה הראשונה בפסוק, או ‎-1.
  int wordIdx(int ch, int vs) => _byKey[_key(ch, vs)] ?? -1;
}

/// גבולות האסימונים של כל חומש: מזהה החומש → (התחלה, סוף לא כולל).
Map<String, (int, int)> bookTokenRanges(
  List<TikkunToken> tokens,
  Map<String, int> bookStartTokenIdx,
) {
  final order = TikkunData.booksOrder;
  final out = <String, (int, int)>{};
  for (var i = 0; i < order.length; i++) {
    final start = bookStartTokenIdx[order[i]];
    if (start == null) continue;
    final next = i + 1 < order.length ? bookStartTokenIdx[order[i + 1]] : null;
    out[order[i]] = (start, next ?? tokens.length);
  }
  return out;
}

String _hebRange(ParashaAliya a) =>
    '${toHebrewNumeral(a.altFrom!.$1)},${toHebrewNumeral(a.altFrom!.$2)}–'
    '${toHebrewNumeral(a.altTo!.$1)},${toHebrewNumeral(a.altTo!.$2)}';

/// מסמן `parashaName` ו-`aliyaName` על שורות תחילת הפרשה והעליות.
/// העליה נקבעת לפי פסוק הפתיחה שלה — מילות פתיחה כמו "וידבר ה' אל משה
/// לאמר" חוזרות עשרות פעמים ואינן מזהות עליה.
void annotateAliyotOnLines(
  List<TikkunToken> tokens,
  List<TikkunLine> allLines,
  Map<String, int> bookStartTokenIdx,
) {
  final lookup = LineIndexLookup(allLines);
  final ranges = bookTokenRanges(tokens, bookStartTokenIdx);

  for (final bookId in TikkunData.booksOrder) {
    final book = TikkunData.torahBooks[bookId];
    if (book == null) continue;
    final range = ranges[bookId];
    if (range == null) continue;
    final verses = BookVerseIndex(tokens, range.$1, range.$2);

    var searchFrom = range.$1;
    for (final parashaName in book.parashot) {
      final normalized = normalizeParashaName(parashaName);
      final parashaTokenIdx = findParashaStart(tokens, normalized, searchFrom);
      final parashaStart = parashaTokenIdx >= 0 ? parashaTokenIdx : searchFrom;

      final parashaLineIdx = lookup.find(parashaStart);
      if (parashaLineIdx >= 0 && allLines[parashaLineIdx].parashaName == null) {
        allLines[parashaLineIdx].parashaName = parashaName;
      }

      final byBook = TikkunData.aliyotIndex[book.name] ?? const {};
      final aliyot =
          byBook[parashaName] ?? byBook[normalized] ?? const <ParashaAliya>[];
      for (var ai = 0; ai < aliyot.length; ai++) {
        final a = aliyot[ai];
        final tokenIdx = verses.wordIdx(a.fromCh, a.fromVs);
        if (tokenIdx < 0) continue;
        final lineIdx = lookup.find(tokenIdx);
        if (lineIdx < 0) continue;
        final line = allLines[lineIdx];
        final label = TikkunData.aliyaDisplayNames[a.aliya] ?? a.aliya;
        if (a.aliya == kMaftirAliyaName) {
          line.maftirName ??= label;
          line.maftirIdx ??= ai;
          continue;
        }
        if (line.aliyaName != null) continue;
        line.aliyaName = label;
        line.aliyaIdx = ai;
        if (a.hasAlternative) line.aliyaAlternative = _hebRange(a);
      }

      final weekday =
          TikkunData.weekdayAliyotIndex[book.name]?[parashaName] ??
          TikkunData.weekdayAliyotIndex[book.name]?[normalized] ??
          const <ParashaAliya>[];
      for (
        var wi = 0;
        wi < weekday.length && wi < kWeekdayAliyaLabels.length;
        wi++
      ) {
        final tokenIdx = verses.wordIdx(weekday[wi].fromCh, weekday[wi].fromVs);
        if (tokenIdx < 0) continue;
        final lineIdx = lookup.find(tokenIdx);
        if (lineIdx < 0) continue;
        allLines[lineIdx].weekdayAliyaName ??= kWeekdayAliyaLabels[wi];
      }

      searchFrom = parashaStart + 1;
    }
  }
}

/// מסמן `combinedAliyaName` — העליות של הפרשה המחוברת.
void annotateCombinedAliyotOnLines(
  List<TikkunToken> tokens,
  List<TikkunLine> allLines,
  Map<String, int> bookStartTokenIdx,
) {
  final lookup = LineIndexLookup(allLines);
  final ranges = bookTokenRanges(tokens, bookStartTokenIdx);
  final done = <String>{};

  for (final bookId in TikkunData.booksOrder) {
    final book = TikkunData.torahBooks[bookId];
    final range = ranges[bookId];
    if (book == null || range == null) continue;
    final verses = BookVerseIndex(tokens, range.$1, range.$2);

    for (final parashaName in book.parashot) {
      final normalized = normalizeParashaName(parashaName);
      final rawInfo =
          TikkunData.combinedParashaMap[parashaName] ??
          TikkunData.combinedParashaMap[normalized];
      if (rawInfo == null) continue;
      final info = (rawInfo as Map).cast<String, Object?>();
      final combined = info['combined'] as String;
      if (!done.add(combined)) continue;

      final aliyot =
          TikkunData.aliyotIndex[book.name]?[combined] ??
          const <ParashaAliya>[];
      for (final a in aliyot) {
        final tokenIdx = verses.wordIdx(a.fromCh, a.fromVs);
        if (tokenIdx < 0) continue;
        final lineIdx = lookup.find(tokenIdx);
        if (lineIdx >= 0) {
          final label = TikkunData.aliyaDisplayNames[a.aliya] ?? a.aliya;
          final line = allLines[lineIdx];
          if (line.combinedAliyaName == null &&
              label != line.aliyaName &&
              label != line.maftirName) {
            line.combinedAliyaName = label;
          }
        }
      }
    }
  }
}
