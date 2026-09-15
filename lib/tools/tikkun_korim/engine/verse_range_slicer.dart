/// חיתוך רצף האסימונים לפי טווח פסוקים, לצורך הפטרות וקריאות למועדים.
/// פורט של `sliceTokensByVerseRange`, `precededBySetuma`, `compareVerse`,
/// `computeContinuousSegments` ו-`getHaftarahSegments` (navigation.js).
library;

import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// השוואת מיקומים: שלילי אם (ch1,vs1) קודם ל-(ch2,vs2).
int compareVerse(int ch1, int vs1, int ch2, int vs2) {
  if (ch1 != ch2) return ch1 - ch2;
  return vs1 - vs2;
}

/// תת-רצף האסימונים של הטווח, עם `chapter_break` מקדים כדי שהעימוד יידע
/// באיזה פרק הוא מתחיל. רשימה ריקה כשהטווח אינו נמצא.
List<TikkunToken> sliceTokensByVerseRange(
  List<TikkunToken> tokens,
  int fromCh,
  int fromVs,
  int toCh,
  int toVs,
) {
  int? curCh;
  int? curVs;
  var startIdx = -1;
  var endIdx = -1;

  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok.type == TikkunTokenType.chapterBreak) {
      curCh = tok.chapterNum;
      curVs = null;
      continue;
    }
    if (tok.type != TikkunTokenType.verseBreak) continue;
    curVs = tok.verseNum;
    if (curCh == null) continue;

    if (startIdx == -1 && compareVerse(curCh, curVs!, fromCh, fromVs) >= 0) {
      startIdx = i;
    }
    if (startIdx != -1 && compareVerse(curCh, curVs!, toCh, toVs) > 0) {
      endIdx = i;
      break;
    }
  }

  if (startIdx == -1) return const [];
  if (endIdx == -1) endIdx = tokens.length;

  return [
    TikkunToken(type: TikkunTokenType.chapterBreak, chapterNum: fromCh),
    ...tokens.sublist(startIdx, endIdx),
  ];
}

/// האם הפסוק הפותח בא במקור מיד אחרי פרשה סתומה — אז השורה הראשונה תוזח.
bool precededBySetuma(List<TikkunToken> tokens, int fromCh, int fromVs) {
  int? curCh;
  int? curVs;
  var startIdx = -1;

  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok.type == TikkunTokenType.chapterBreak) {
      curCh = tok.chapterNum;
      curVs = null;
      continue;
    }
    if (tok.type != TikkunTokenType.verseBreak) continue;
    curVs = tok.verseNum;
    if (curCh == null) continue;
    if (compareVerse(curCh, curVs!, fromCh, fromVs) >= 0) {
      startIdx = i;
      break;
    }
  }

  if (startIdx <= 0) return false;
  for (var j = startIdx - 1; j >= 0; j--) {
    final type = tokens[j].type;
    if (type == TikkunTokenType.verseBreak ||
        type == TikkunTokenType.chapterBreak ||
        type == TikkunTokenType.segmentBreak) {
      continue;
    }
    return type == TikkunTokenType.setuma;
  }
  return false;
}

/// מקטעי ההפטרה לפי הנוסח; אשכנז הוא הגיבוי כשאין קטעים לנוסח המבוקש.
List<VerseRange> getHaftarahSegments(Haftarah haftarah, String nusach) =>
    haftarah.forNusach(nusach);

/// מיזוג עליות עוקבות או חופפות מאותו ספר לטווחים רציפים — לכותרת הקריאה.
List<VerseRange> computeContinuousSegments(List<ReadingAliya> aliyot) {
  if (aliyot.isEmpty) return const [];

  final segs = <VerseRange>[];
  var cur = aliyot.first.range;

  for (var i = 1; i < aliyot.length; i++) {
    final a = aliyot[i].range;
    final sameBook = a.book == cur.book;
    final isAdjacent =
        sameBook &&
        ((a.fromCh == cur.toCh && a.fromVs == cur.toVs + 1) ||
            (a.fromCh == cur.toCh + 1 && a.fromVs == 1));
    final isOverlap =
        sameBook && compareVerse(a.fromCh, a.fromVs, cur.toCh, cur.toVs) <= 0;

    if (isAdjacent || isOverlap) {
      if (compareVerse(a.toCh, a.toVs, cur.toCh, cur.toVs) > 0) {
        cur = VerseRange(
          book: cur.book,
          fromCh: cur.fromCh,
          fromVs: cur.fromVs,
          toCh: a.toCh,
          toVs: a.toVs,
        );
      }
    } else {
      segs.add(cur);
      cur = a;
    }
  }
  segs.add(cur);
  return segs;
}
