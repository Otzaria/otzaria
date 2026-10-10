import 'dart:math';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:otzaria/text_book/utils/reading_segments.dart';

/// אינדקס הפריט העליון הנראה.
///
/// `ItemPositionsListener.itemPositions.value` מוחזק כ-`Set` שסדר האיטרציה
/// שלו תואם לסדר ההכנסה (ולא לאינדקס). אחרי גלילות, `.first.index` עלול
/// להחזיר את הפריט התחתון. לכן יש לחשב את המינימום מפורשות.
///
/// אם הקולקציה ריקה מוחזר 0 (פריט "ראשון" סביר כשאין מה לראות).
int topmostVisibleIndex(Iterable<ItemPosition> positions) {
  if (positions.isEmpty) return 0;
  // הרשימה מדווחת גם פריטים שנגללו כולם מעל החלון (ב-cache); בחירתם הקפיצה
  // את "הקטע הקודם" לתחילת הספר (issue #1358). קודם הפריטים הנראים בפועל.
  final visible = positions.where((p) => p.itemTrailingEdge > 0);
  final candidates = visible.isEmpty ? positions : visible;
  return candidates.map((p) => p.index).reduce(min);
}

/// **תמיד מחזיר שורת מקור**, גם במצב רצף שבו ה-itemIndex של ה-
/// `ScrollablePositionedList` הוא segmentIndex (פסקה) ולא שורה.
///
/// צרכנים שעובדים מול ה-TOC, סימניות, deep links או PDF דורשים שורת מקור.
/// צרכני גלילה (`scrollToPreviousSegment` וכו') ממשיכים להשתמש ב-
/// [topmostVisibleIndex] הגולמי, כי "הסעיף הקודם" = "הפסקה הקודמת" במצב רצף.
int resolveTopmostSourceLine({
  required Iterable<ItemPosition> positions,
  required bool continuousReadingMode,
  required List<ReadingSegment> readingSegments,
}) {
  if (positions.isEmpty) return 0;
  final topmost = topmostVisibleIndex(positions);
  if (!continuousReadingMode || readingSegments.isEmpty) {
    return topmost;
  }
  if (topmost < 0 || topmost >= readingSegments.length) return 0;
  return readingSegments[topmost].startLineIndex;
}

/// השורה שהכותרת מציגה: [visibleIndices] (שורות מקור) כבר מסוננים משארית
/// הקטע הקודם בראש החלון, שאחרת מעבירה ל-PDF עמוד אחד אחורה (#1974).
int displayedSourceLine(List<int> visibleIndices, int topmostSourceLine) =>
    visibleIndices.isNotEmpty ? visibleIndices.first : topmostSourceLine;

/// ממיר שורת מקור ל-itemIndex של ה-`ScrollablePositionedList`.
/// במצב הרגיל זה זהות; במצב רצף זה segmentIndex של הפסקה שמכילה את השורה.
int resolveItemIndexForSourceLine({
  required int lineIndex,
  required List<ReadingSegment> readingSegments,
}) {
  if (readingSegments.isEmpty) return lineIndex;
  return segmentIndexForLine(readingSegments, lineIndex);
}
