/// המיקום הנוכחי בספר, במונחי שורות מקור בלבד.
library;

import 'package:flutter/foundation.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

/// ההגדרה היחידה של "איפה הקורא נמצא".
@immutable
class ReadingPosition {
  const ReadingPosition({
    required this.topLine,
    this.intraLineFraction = 0,
    required this.visibleLines,
    int? windowFirstLine,
    int? windowLastLine,
  }) : windowFirstLine = windowFirstLine ?? topLine,
       windowLastLine = windowLastLine ?? topLine;

  /// מיקום שנקבע בניווט ועוד לא נמדד מהמסך.
  ReadingPosition.target(int line, {double intraLineFraction = 0})
    : this(
        topLine: line,
        intraLineFraction: intraLineFraction,
        visibleLines: [line],
      );

  /// השורה הראשונה שאינה שייר של הקטע הקודם מעל קו העוגן.
  final int topLine;

  /// החלק (0..1) של [topLine] שכבר עבר את קו העוגן.
  final double intraLineFraction;

  /// השורות הגלויות אחרי סינון שיירים בשולי התצוגה, ממוינות.
  final List<int> visibleLines;

  /// טווח השורות של כל הפריטים שנוגעים בתצוגה, בלי סינון — לטעינת תוכן.
  final int windowFirstLine;
  final int windowLastLine;

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition &&
      other.topLine == topLine &&
      other.intraLineFraction == intraLineFraction &&
      other.windowFirstLine == windowFirstLine &&
      other.windowLastLine == windowLastLine &&
      listEquals(other.visibleLines, visibleLines);

  @override
  int get hashCode => Object.hash(
    topLine,
    intraLineFraction,
    windowFirstLine,
    windowLastLine,
    Object.hashAll(visibleLines),
  );

  @override
  String toString() =>
      'ReadingPosition(top: $topLine+$intraLineFraction, $visibleLines)';
}

/// נקודה בטקסט ([line] + [intraLineFraction]) והגובה שבו היא יושבת בתצוגה.
@immutable
class ReadingAnchor {
  const ReadingAnchor({
    required this.line,
    this.intraLineFraction = 0,
    this.alignment = kReadingAnchorAlignment,
  });

  final int line;
  final double intraLineFraction;
  final double alignment;

  Map<String, Object> toJson() => {
    'line': line,
    'intraLineFraction': intraLineFraction,
    'alignment': alignment,
  };

  static ReadingAnchor? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final line = value['line'];
    final fraction = value['intraLineFraction'];
    final alignment = value['alignment'];
    if (line is! int || line < 0 || fraction is! num || alignment is! num) {
      return null;
    }
    if (!fraction.isFinite || !alignment.isFinite) return null;
    return ReadingAnchor(
      line: line,
      intraLineFraction: fraction.toDouble().clamp(0, 1),
      alignment: alignment.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingAnchor &&
      other.line == line &&
      other.intraLineFraction == intraLineFraction &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(line, intraLineFraction, alignment);

  @override
  String toString() => 'ReadingAnchor($line+$intraLineFraction @ $alignment)';
}

/// מסנן שייר של הקטע הקודם מעל קו העוגן, וקטע שגלוי פחות מ-15% מגובהו
/// (או מגובה התצוגה כשהוא ארוך ממנה). סינון שמרוקן הכול מחזיר את המקור.
List<ItemPosition> filterBarelyVisiblePositions(List<ItemPosition> positions) {
  if (positions.length <= 1) return positions;
  final filtered = positions.where((p) {
    final extent = p.itemTrailingEdge - p.itemLeadingEdge;
    if (extent <= 0) return false;
    if (!_atBookStart(p) &&
        isRemnantAbovePositionAnchor(p.itemLeadingEdge, p.itemTrailingEdge)) {
      return false;
    }
    final visibleTop = p.itemLeadingEdge.clamp(0.0, 1.0);
    final visibleBottom = p.itemTrailingEdge.clamp(0.0, 1.0);
    final visiblePortion = visibleBottom - visibleTop;
    if (visiblePortion <= 0) return false;
    // קטע ארוך מהמסך נמדד מול המסך, אחרת בתחילתו ובסופו הוא נסנן (#2327).
    return visiblePortion / extent.clamp(0.0, 1.0) >= 0.15;
  }).toList();
  return filtered.isEmpty ? positions : filtered;
}

/// בראש הספר אין קטע קודם, ולכן מה שמעל קו העוגן אינו שייר שלו.
bool _atBookStart(ItemPosition p) => p.index == 0 && p.itemLeadingEdge >= 0;

ReadingSegmentViewport _viewport(ItemPosition p) => ReadingSegmentViewport(
  segmentIndex: p.index,
  leadingEdge: p.itemLeadingEdge,
  trailingEdge: p.itemTrailingEdge,
);

/// המיקום שמתאר את [itemPositions] מול [segments]; null כשאין פריט גלוי.
ReadingPosition? readingPositionFromItems(
  ReadingSegments segments,
  Iterable<ItemPosition> itemPositions, {
  MeasuredLineExtent? measure,
}) {
  if (segments.isEmpty) return null;
  final raw =
      itemPositions
          .where((p) => p.index >= 0 && p.index < segments.length)
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  if (raw.isEmpty) return null;

  final filtered = filterBarelyVisiblePositions(raw);
  final visibleLines = {
    ...sourceLineIndicesForSegmentViewports(
      segments,
      filtered.where(_atBookStart).map(_viewport),
      measure: measure,
    ),
    ...sourceLineIndicesForSegmentViewports(
      segments,
      filtered.where((p) => !_atBookStart(p)).map(_viewport),
      isLineRemnant: isRemnantAbovePositionAnchor,
      measure: measure,
    ),
  }.toList()..sort();
  if (visibleLines.isEmpty) return null;

  final layout = segments.layout;
  final onScreen = raw.where(
    (p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1,
  );
  final window = onScreen.isEmpty ? raw : onScreen;
  final topLine = visibleLines.first;
  final item = layout.itemForLine(topLine);
  final itemPosition = raw.where((p) => p.index == item).firstOrNull;
  return ReadingPosition(
    topLine: topLine,
    intraLineFraction: itemPosition == null
        ? 0
        : _fractionPastAnchor(segments, topLine, itemPosition, measure),
    visibleLines: List<int>.unmodifiable(visibleLines),
    windowFirstLine: layout.firstLineOf(window.first.index),
    windowLastLine: layout.lastLineOf(window.last.index),
  );
}

/// גבולות [line] בתצוגה (חלקי viewport), לפי מיקום הפריט שמכיל אותה.
({double leading, double trailing}) lineEdgesInViewport(
  ReadingSegments segments,
  int line,
  ItemPosition itemPosition, {
  MeasuredLineExtent? measure,
}) {
  final item = itemPosition.index;
  final extent = itemPosition.itemTrailingEdge - itemPosition.itemLeadingEdge;
  final start = lineFractionInItem(segments, item, line, measure: measure);
  final end = lineFractionInItem(
    segments,
    item,
    line,
    intraLineFraction: 1,
    measure: measure,
  );
  return (
    leading: itemPosition.itemLeadingEdge + extent * start,
    trailing: itemPosition.itemLeadingEdge + extent * end,
  );
}

/// שורת המקור שחוצה את הקו שבגובה [fraction] מהתצוגה, לפי הפיקסלים ולא לפי
/// מספר השורות הגלויות; null כשאף פריט אינו חוצה אותו.
int? lineCrossingViewportFraction(
  ReadingSegments segments,
  Iterable<ItemPosition> itemPositions,
  double fraction, {
  MeasuredLineExtent? measure,
}) {
  final layout = segments.layout;
  for (final p in itemPositions) {
    if (p.index < 0 || p.index >= segments.length) continue;
    if (p.itemLeadingEdge > fraction || p.itemTrailingEdge <= fraction) {
      continue;
    }
    final last = layout.lastLineOf(p.index);
    for (var line = layout.firstLineOf(p.index); line < last; line++) {
      final edges = lineEdgesInViewport(segments, line, p, measure: measure);
      if (edges.trailing > fraction) return line;
    }
    return last;
  }
  return null;
}

double _fractionPastAnchor(
  ReadingSegments segments,
  int line,
  ItemPosition itemPosition,
  MeasuredLineExtent? measure,
) {
  final edges = lineEdgesInViewport(
    segments,
    line,
    itemPosition,
    measure: measure,
  );
  final extent = edges.trailing - edges.leading;
  if (!extent.isFinite || extent <= 0) return 0;
  return ((kReadingAnchorAlignment - edges.leading) / extent).clamp(0.0, 1.0);
}

/// העוגן שמתאר את המסך כפי שהוא: נקודת [ReadingPosition.topLine] שעל קו
/// העוגן, או תחילת השורה כשהיא עוד מתחתיו (למשל בראש הספר).
ReadingAnchor? readingAnchorFromItems(
  ReadingSegments segments,
  Iterable<ItemPosition> itemPositions, {
  MeasuredLineExtent? measure,
}) {
  final position = readingPositionFromItems(
    segments,
    itemPositions,
    measure: measure,
  );
  return position == null
      ? null
      : readingAnchorAt(segments, itemPositions, position, measure: measure);
}

/// העוגן של [position] כפי שהוא מוצג ב-[itemPositions].
ReadingAnchor readingAnchorAt(
  ReadingSegments segments,
  Iterable<ItemPosition> itemPositions,
  ReadingPosition position, {
  MeasuredLineExtent? measure,
}) {
  final line = position.topLine;
  final item = segments.layout.itemForLine(line);
  final itemPosition = itemPositions.where((p) => p.index == item).firstOrNull;
  if (itemPosition == null) return ReadingAnchor(line: line);
  final edges = lineEdgesInViewport(
    segments,
    line,
    itemPosition,
    measure: measure,
  );
  // תחילת השורה מעל קו העוגן בלי חלק שעבר אותו: יעד שיושר מעליו (למשל ל-0).
  if (edges.leading >= kReadingAnchorAlignment ||
      position.intraLineFraction == 0) {
    return ReadingAnchor(line: line, alignment: edges.leading.clamp(0.0, 1.0));
  }
  return ReadingAnchor(
    line: line,
    intraLineFraction: position.intraLineFraction,
  );
}
