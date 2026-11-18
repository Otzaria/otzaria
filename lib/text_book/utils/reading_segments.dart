/// תשתית "מצב קריאה רציף" — רינדור בלבד.
///
/// **כלל מפתח:** כל ה-state ב-`TextBookBloc` (visibleIndices, selectedIndex,
/// highlightedLine, חיפוש, קישורים, פסיקות וכו') משתמש ב-**שורות מקור**
/// כאינדקסים. הסגמנטים נחשבים רק כפריטי-תצוגה ברשימת הקריאה.
///
/// התרגום בין שורות לפריטים נעשה רק ב-`LineScrollController`.
/// **אסור** להזליג segmentIndex אל ה-state של ה-bloc. הוא מקומי לרינדור.
library;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/content_line_changes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/text_book/utils/reading_layout.dart';

export 'package:otzaria/text_book/utils/reading_layout.dart';
export 'package:otzaria/text_book/models/content_line_changes.dart';

class ReadingLineRange {
  final int lineIndex;
  final int start;
  final int end;

  const ReadingLineRange({
    required this.lineIndex,
    required this.start,
    required this.end,
  });
}

class ReadingSegment {
  final String text;
  final List<int> sourceLineIndices;
  final List<ReadingLineRange> lineRanges;
  final bool isHeader;
  final bool isLoaded;

  const ReadingSegment({
    required this.text,
    required this.sourceLineIndices,
    required this.lineRanges,
    required this.isHeader,
    this.isLoaded = true,
  });

  int get startLineIndex => sourceLineIndices.first;

  int get endLineIndex => sourceLineIndices.last;

  bool containsLine(int lineIndex) =>
      lineIndex >= startLineIndex && lineIndex <= endLineIndex;
}

class ReadingSegmentViewport {
  final int segmentIndex;
  final double leadingEdge;
  final double trailingEdge;

  const ReadingSegmentViewport({
    required this.segmentIndex,
    required this.leadingEdge,
    required this.trailingEdge,
  });
}

/// מעל מה שמוצג בבת אחת; בלי תקרה, גלילה בספר שלם שומרת עותק של כל
/// טקסטו בפסקאות הממוזגות.
const int kMaxBuiltReadingSegments = 256;

/// פריטי הרינדור של [layout] מול התוכן הנוכחי. מספר הפריטים קבוע לפי
/// הפריסה; פריט שחלק משורותיו לא נטען מסומן `isLoaded == false`.
class ReadingSegments {
  ReadingSegments({
    required this.layout,
    required this.content,
    this.loadedLineFlags,
    this.maxCachedSegments = kMaxBuiltReadingSegments,
    this.maxCachedCharacters = 512 * 1024,
    this.readerIdentity,
    this.contentVersion = 0,
    this.contentChanges,
  }) : assert(maxCachedSegments > 0),
       assert(maxCachedCharacters >= 0);

  final ReadingLayout layout;
  final List<String> content;
  final Object? readerIdentity;
  final int contentVersion;
  final ContentLineChanges? contentChanges;

  /// null מציין שאין דלתא ידועה מהתצלום המבוקש, ונדרשת השוואה מלאה.
  List<ContentLineRange>? changedLinesSince(ReadingSegments before) {
    if (readerIdentity != null &&
        before.readerIdentity != null &&
        !identical(readerIdentity, before.readerIdentity)) {
      return null;
    }
    if (identical(content, before.content) &&
        identical(loadedLineFlags, before.loadedLineFlags)) {
      return const [];
    }
    final changes = contentChanges;
    if (readerIdentity == null ||
        !identical(readerIdentity, before.readerIdentity) ||
        content.length != before.content.length ||
        changes == null ||
        changes.fromVersion != before.contentVersion ||
        contentVersion == before.contentVersion) {
      return null;
    }
    return changes.ranges;
  }

  /// null = כל השורות טעונות.
  final List<bool>? loadedLineFlags;

  final int maxCachedSegments;
  final int maxCachedCharacters;

  final Map<int, ReadingSegment> _built = {};
  final Set<int> _visibleItems = {};
  int _cachedCharacters = 0;

  @visibleForTesting
  int get debugBuiltCount => _built.length;

  @visibleForTesting
  int get debugCachedCharacters => _cachedCharacters;

  int get length => layout.itemCount;

  bool get isEmpty => layout.isEmpty;

  bool get isNotEmpty => layout.isNotEmpty;

  ReadingSegment operator [](int item) {
    RangeError.checkValidIndex(item, this, 'item', length);
    final cached = _built.remove(item);
    final segment = cached ?? _buildSegment(item);
    _built[item] = segment;
    if (cached == null) _cachedCharacters += segment.text.length;
    _trimCache(keep: item);
    return segment;
  }

  /// שומר את פריטי המסך גם כשהטקסט שלהם חורג מתקציב המטמון.
  void retainVisibleItems(Iterable<int> items) {
    _visibleItems
      ..clear()
      ..addAll(items);
    _trimCache();
  }

  void _trimCache({int? keep}) {
    var count = _built.length;
    var characters = _cachedCharacters;
    if (count <= maxCachedSegments && characters <= maxCachedCharacters) return;
    final evicted = <int>[];
    for (final entry in _built.entries) {
      if (entry.key == keep || _visibleItems.contains(entry.key)) continue;
      evicted.add(entry.key);
      characters -= entry.value.text.length;
      count--;
      if (count <= maxCachedSegments && characters <= maxCachedCharacters) {
        break;
      }
    }
    for (final item in evicted) {
      _built.remove(item);
    }
    _cachedCharacters = characters;
  }

  void _reuseUnchanged(ReadingSegments before, ContentLineChanges changes) {
    if (!identical(layout, before.layout) ||
        !identical(readerIdentity, before.readerIdentity) ||
        !changes.matchesPreviousFlags(before.loadedLineFlags) ||
        changes.fromVersion != before.contentVersion ||
        contentVersion <= before.contentVersion) {
      return;
    }
    for (final entry in before._built.entries) {
      final segment = entry.value;
      if (!changes.affects(segment.startLineIndex, segment.endLineIndex)) {
        _built[entry.key] = segment;
        _cachedCharacters += segment.text.length;
      }
    }
  }

  ReadingSegment get first => this[0];

  ReadingSegment get last => this[length - 1];

  bool _isLineLoaded(int line) {
    final flags = loadedLineFlags;
    if (flags == null) return true;
    return line >= 0 && line < flags.length && flags[line];
  }

  ReadingSegment _buildSegment(int item) {
    final first = layout.firstLineOf(item);
    final last = layout.lastLineOf(item);
    if (first == last) {
      final isLoaded = _isLineLoaded(first);
      final text = isLoaded ? content[first] : '';
      return ReadingSegment(
        text: text,
        sourceLineIndices: [first],
        lineRanges: isLoaded
            ? [ReadingLineRange(lineIndex: first, start: 0, end: text.length)]
            : const [],
        isHeader: isLoaded && isReadingHeaderLine(text),
        isLoaded: isLoaded,
      );
    }

    final lineIndices = List<int>.unmodifiable(
      List<int>.generate(last - first + 1, (offset) => first + offset),
    );
    for (var line = first; line <= last; line++) {
      if (!_isLineLoaded(line)) {
        return ReadingSegment(
          text: '',
          sourceLineIndices: lineIndices,
          lineRanges: const [],
          isHeader: false,
          isLoaded: false,
        );
      }
    }

    final buffer = StringBuffer();
    final ranges = <ReadingLineRange>[];
    for (var line = first; line <= last; line++) {
      if (buffer.isNotEmpty) buffer.write(' ');
      final start = buffer.length;
      buffer.write(content[line].trim());
      ranges.add(
        ReadingLineRange(lineIndex: line, start: start, end: buffer.length),
      );
    }
    return ReadingSegment(
      text: buffer.toString(),
      sourceLineIndices: lineIndices,
      lineRanges: List<ReadingLineRange>.unmodifiable(ranges),
      isHeader: false,
    );
  }
}

final Expando<ReadingSegments> _segmentsByContent = Expando<ReadingSegments>(
  'readingSegments',
);

/// סגמנטי הרינדור של [state], לפי [readingLayoutOf]. נשמרים לפי זהות התוכן
/// כדי ש-emit שאינו משנה תוכן (גלילה, בחירה) לא יבנה פסקאות מחדש.
ReadingSegments readingSegmentsOf(TextBookLoaded state) {
  final layout = readingLayoutOf(state);
  final cached = _segmentsByContent[state.content];
  if (cached != null &&
      identical(cached.layout, layout) &&
      identical(cached.loadedLineFlags, state.loadedLineFlags) &&
      identical(cached.readerIdentity, state.readerIdentity) &&
      cached.contentVersion == state.contentVersion &&
      identical(cached.contentChanges, state.contentChanges)) {
    cached.retainVisibleItems(state.visibleIndices.map(layout.itemForLine));
    return cached;
  }
  final segments = ReadingSegments(
    layout: layout,
    content: state.content,
    loadedLineFlags: state.loadedLineFlags,
    readerIdentity: state.readerIdentity,
    contentVersion: state.contentVersion,
    contentChanges: state.contentChanges,
  );
  final changes = layout.continuous ? state.contentChanges : null;
  final previousContent = changes?.previousContent;
  if (changes != null && previousContent != null) {
    final before = _segmentsByContent[previousContent];
    if (before != null) segments._reuseUnchanged(before, changes);
  }
  _segmentsByContent[state.content] = segments;
  segments.retainVisibleItems(state.visibleIndices.map(layout.itemForLine));
  return segments;
}

final Expando<List<double>> _lineBoundaryFractionsCache = Expando<List<double>>(
  'lineBoundaryFractions',
);

final RegExp _htmlTagPattern = RegExp(r'<[^>]*>');
final RegExp _htmlEntityPattern = RegExp(r'&[a-zA-Z]+;|&#\d+;');

/// אורך התצוגה של הטקסט: ללא גוף הערות inline (כמו ברינדור), ללא תגיות,
/// בספירת graphemes - כך שניקוד וישויות HTML אינם מטים את המשקל.
int _visibleTextLength(String text) => notes
    .stripInlineNotes(text)
    .replaceAll(_htmlTagPattern, '')
    .replaceAll(_htmlEntityPattern, ' ')
    .characters
    .length;

/// גבולות מצטברים (0..1) של שורות הסגמנט לפי אורך הטקסט הנראה - קירוב
/// לחלקן היחסי של השורות בגובה המרונדר. מחושב פעם אחת לכל סגמנט.
List<double>? _lineBoundaryFractions(ReadingSegment segment) {
  if (!segment.isLoaded) {
    return null;
  }
  final lineCount = segment.sourceLineIndices.length;
  if (segment.lineRanges.length != lineCount || segment.text.isEmpty) {
    return null;
  }
  final cached = _lineBoundaryFractionsCache[segment];
  if (cached != null) {
    return cached;
  }

  final boundaries = List<double>.filled(lineCount + 1, 0);
  var total = 0.0;
  for (var i = 0; i < lineCount; i++) {
    final range = segment.lineRanges[i];
    final visible = _visibleTextLength(
      segment.text.substring(range.start, range.end),
    );
    total += visible + (i < lineCount - 1 ? 1 : 0);
    boundaries[i + 1] = total;
  }
  if (total <= 0) {
    return null;
  }
  for (var i = 1; i <= lineCount; i++) {
    boundaries[i] /= total;
  }
  _lineBoundaryFractionsCache[segment] = boundaries;
  return boundaries;
}

/// האינדקס הגדול ביותר שבו `boundaries[i] <= value` (חיפוש בינארי).
int _lastIndexAtOrBelow(List<double> boundaries, double value) {
  var low = 0;
  var high = boundaries.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (boundaries[mid] <= value) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

/// האינדקס הקטן ביותר שבו `boundaries[i] >= value` (חיפוש בינארי).
int _firstIndexAtOrAbove(List<double> boundaries, double value) {
  var low = 0;
  var high = boundaries.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (boundaries[mid] < value) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

/// גבולות [line] בפריט [item] (חלק 0..1 מגובה הפריט) כפי שנמדדו ברינדור;
/// null כשהפריט אינו בנוי.
typedef MeasuredLineExtent =
    ({double top, double bottom})? Function(int item, int line);

/// אינדקס הפריט שמכיל את שורת המקור [lineIndex].
int segmentIndexForLine(ReadingSegments segments, int lineIndex) =>
    segments.layout.itemForLine(lineIndex);

/// השבר היחסי של שורת מקור בתוך הפריט; [intraLineFraction] מוסיף מיקום בתוכה.
double lineFractionWithinSegment(
  ReadingSegment segment,
  int lineIndex, {
  double intraLineFraction = 0,
}) {
  if (!segment.isLoaded) {
    return 0;
  }
  final within = intraLineFraction.clamp(0.0, 1.0);
  final lineCount = segment.sourceLineIndices.length;
  final lineOffset = lineIndex - segment.startLineIndex;
  if (lineCount <= 1) {
    return within;
  }
  // שקלול לפי אורך הטקסט הנראה: שורות (פסוקים) נבדלות מאוד באורכן, וחלוקה
  // שווה לפי מספר שורות מפספסת את היעד בכמה שורות בפסקאות ארוכות.
  final boundaries = _lineBoundaryFractions(segment);
  if (boundaries != null) {
    final offset = lineOffset.clamp(0, lineCount - 1);
    final start = boundaries[offset];
    return start + within * (boundaries[offset + 1] - start);
  }
  return ((lineOffset.clamp(0, lineCount - 1)) + within) / lineCount;
}

/// כמו [lineFractionWithinSegment], אך לפי הגובה שנמדד כשהפריט [item] בנוי.
double lineFractionInItem(
  ReadingSegments segments,
  int item,
  int lineIndex, {
  double intraLineFraction = 0,
  MeasuredLineExtent? measure,
}) {
  final segment = segments[item];
  final measured = _measuredLines(segment, item, measure);
  if (measured == null) {
    return lineFractionWithinSegment(
      segment,
      lineIndex,
      intraLineFraction: intraLineFraction,
    );
  }
  final offset = (lineIndex - segment.startLineIndex)
      .clamp(0, segment.sourceLineIndices.length - 1)
      .toInt();
  final extent = measured(offset);
  return extent.top +
      intraLineFraction.clamp(0.0, 1.0) * (extent.bottom - extent.top);
}

/// גבולות השורות של פריט בנוי לפי מיקום השורה בו; null — אין מדידה.
({double top, double bottom}) Function(int offset)? _measuredLines(
  ReadingSegment segment,
  int item,
  MeasuredLineExtent? measure,
) {
  if (measure == null || !segment.isLoaded) return null;
  if (measure(item, segment.startLineIndex) == null) return null;
  return (offset) =>
      measure(item, segment.sourceLineIndices[offset]) ??
      (
        top: lineFractionWithinSegment(
          segment,
          segment.sourceLineIndices[offset],
        ),
        bottom: lineFractionWithinSegment(
          segment,
          segment.sourceLineIndices[offset],
          intraLineFraction: 1,
        ),
      );
}

/// האינדקס הקטן ביותר ב-[0, count) שבו [test] מתקיים, בהנחה שהוא מונוטוני.
int _firstOffsetWhere(int count, bool Function(int offset) test) {
  var low = 0;
  var high = count;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (test(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}

/// ממיר רשימת `ItemPosition` (במונחי segmentIndex) לרשימת שורות-מקור גלויות;
/// במצב הרגיל segmentIndex == lineIndex.
List<int> sourceLineIndicesForSegmentViewports(
  ReadingSegments segments,
  Iterable<ReadingSegmentViewport> viewports, {
  bool Function(double leadingEdge, double trailingEdge)? isLineRemnant,
  MeasuredLineExtent? measure,
}) {
  final sourceIndices = <int>{};
  final measuredViewports = measure == null
      ? null
      : <int, ReadingSegmentViewport>{};
  for (final viewport in viewports) {
    if (viewport.segmentIndex < 0 || viewport.segmentIndex >= segments.length) {
      continue;
    }
    measuredViewports?[viewport.segmentIndex] = viewport;

    final segment = segments[viewport.segmentIndex];
    final lineCount = segment.sourceLineIndices.length;
    if (segment.isHeader || lineCount <= 1) {
      sourceIndices.addAll(segment.sourceLineIndices);
      continue;
    }

    final extent = viewport.trailingEdge - viewport.leadingEdge;
    if (!extent.isFinite || extent <= 0) {
      sourceIndices.add(segment.startLineIndex);
      continue;
    }

    if (!segment.isLoaded) {
      final startFraction = (-viewport.leadingEdge / extent).clamp(0.0, 1.0);
      final endFraction = ((1.0 - viewport.leadingEdge) / extent).clamp(
        0.0,
        1.0,
      );
      final centerFraction = (startFraction + endFraction) / 2;
      final centerOffset = (centerFraction * (lineCount - 1)).round();
      final sliceStart = (centerOffset - 1).clamp(0, lineCount - 1);
      final sliceEnd = (centerOffset + 2).clamp(sliceStart + 1, lineCount);
      sourceIndices.addAll(
        segment.sourceLineIndices.sublist(
          sliceStart,
          sliceEnd,
        ),
      );
      continue;
    }

    final startFraction = (-viewport.leadingEdge / extent).clamp(0.0, 1.0);
    final endFraction = ((1.0 - viewport.leadingEdge) / extent).clamp(0.0, 1.0);

    final measured = _measuredLines(segment, viewport.segmentIndex, measure);
    if (measured != null) {
      var first = _firstOffsetWhere(
        lineCount,
        (offset) => measured(offset).bottom > startFraction,
      ).clamp(0, lineCount - 1);
      final end = _firstOffsetWhere(
        lineCount,
        (offset) => measured(offset).top >= endFraction,
      ).clamp(first + 1, lineCount);
      if (isLineRemnant != null) {
        while (first < end - 1) {
          final line = measured(first);
          if (!isLineRemnant(
            viewport.leadingEdge + extent * line.top,
            viewport.leadingEdge + extent * line.bottom,
          )) {
            break;
          }
          first++;
        }
      }
      sourceIndices.addAll(segment.sourceLineIndices.sublist(first, end));
      continue;
    }

    // גבולות השורות משוקללים לפי אורך הטקסט הנראה - חייב להיות זהה לשקלול
    // ב-lineFractionWithinSegment כדי שהנחיתה וההדגשה יצביעו על אותה שורה.
    final boundaries = _lineBoundaryFractions(segment);
    double lineStartFraction(int offset) =>
        boundaries != null ? boundaries[offset] : offset / lineCount;
    double lineEndFraction(int offset) =>
        boundaries != null ? boundaries[offset + 1] : (offset + 1) / lineCount;

    // חיפוש בינארי - סגמנט ללא כותרות עשוי להכיל אלפי שורות, והמסלול רץ
    // בכל עדכון גלילה.
    var startOffset = boundaries != null
        ? _lastIndexAtOrBelow(boundaries, startFraction).clamp(0, lineCount - 1)
        : (startFraction * lineCount).floor();
    startOffset = (startOffset - 1).clamp(0, lineCount - 1);

    var endOffset = boundaries != null
        ? _firstIndexAtOrAbove(boundaries, endFraction)
        : (endFraction * lineCount).ceil();
    endOffset = (endOffset + 1).clamp(startOffset + 1, lineCount);

    // שורות מעל קו העוגן בתוך פסקה ממוזגת הן שייר של הסעיף הקודם -
    // בלעדי הסינון ההדגשה בסרגל הניווט נופלת על הפרשה/הסעיף הקודמים.
    if (isLineRemnant != null) {
      while (startOffset < endOffset - 1) {
        final lineLeading =
            viewport.leadingEdge + extent * lineStartFraction(startOffset);
        final lineTrailing =
            viewport.leadingEdge + extent * lineEndFraction(startOffset);
        if (!isLineRemnant(lineLeading, lineTrailing)) break;
        startOffset++;
      }
    }

    sourceIndices.addAll(
      segment.sourceLineIndices.sublist(
        startOffset,
        endOffset,
      ),
    );
  }
  var result = sourceIndices.toList();
  if (measure != null) {
    final visible = result.where((line) {
      final item = segments.layout.itemForLine(line);
      if (!segments[item].isLoaded) return true;
      final bounds = measure(item, line);
      if (bounds == null) return true;
      final viewport = measuredViewports![item]!;
      final extent = viewport.trailingEdge - viewport.leadingEdge;
      if (!extent.isFinite || extent <= 0) return true;
      final leading = viewport.leadingEdge + extent * bounds.top;
      final trailing = viewport.leadingEdge + extent * bounds.bottom;
      return trailing > 0 &&
          leading < 1 &&
          !(isLineRemnant?.call(leading, trailing) ?? false);
    }).toList();
    if (visible.isNotEmpty) result = visible;
  }
  return result..sort();
}
