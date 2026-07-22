/// תשתית "מצב קריאה רציף" — רינדור בלבד.
///
/// **כלל מפתח:** כל ה-state ב-`TextBookBloc` (visibleIndices, selectedIndex,
/// highlightedLine, חיפוש, קישורים, פסיקות וכו') משתמש ב-**שורות מקור**
/// כאינדקסים. הסגמנטים נחשבים רק כפריט-תצוגה ב-`ScrollablePositionedList`.
///
/// תרגום:
/// - שורה → סגמנט: [segmentIndexForLine] — לפני קריאת `scrollTo(index:)`.
/// - viewport → שורות: [sourceLineIndicesForSegmentViewports] — אחרי
///   `positionsListener` כדי לחשב מחדש visibleIndices ברמת שורות.
///
/// **אסור** להזליג segmentIndex אל ה-state של ה-bloc. הוא מקומי לרינדור.
library;

import 'package:characters/characters.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;

class ReadingLineRange {
  final int lineIndex;
  final int start;
  final int end;

  const ReadingLineRange({
    required this.lineIndex,
    required this.start,
    required this.end,
  });

  bool containsOffset(int offset) => offset >= start && offset < end;
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

final Expando<List<ReadingSegment>> _lineSegmentsCache =
    Expando<List<ReadingSegment>>('lineReadingSegments');
final Expando<List<ReadingSegment>> _continuousSegmentsCache =
    Expando<List<ReadingSegment>>('continuousReadingSegments');
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

bool isReadingHeaderLine(String line) {
  final headerPattern = RegExp(r'^\s*<h[1-6]', caseSensitive: false);
  return headerPattern.hasMatch(line);
}

bool _isLineLoaded(List<bool>? loadedLineFlags, int index) {
  if (loadedLineFlags == null) {
    return true;
  }
  if (index < 0 || index >= loadedLineFlags.length) {
    return false;
  }
  return loadedLineFlags[index];
}

ReadingSegment _buildNonContinuousSegment(
  List<String> lines,
  int index, {
  List<bool>? loadedLineFlags,
}) {
  final isLoaded = _isLineLoaded(loadedLineFlags, index);
  final text = isLoaded ? lines[index] : '';
  return ReadingSegment(
    text: text,
    sourceLineIndices: [index],
    lineRanges: isLoaded
        ? [
            ReadingLineRange(
              lineIndex: index,
              start: 0,
              end: text.length,
            ),
          ]
        : const [],
    isHeader: isLoaded && isReadingHeaderLine(lines[index]),
    isLoaded: isLoaded,
  );
}

bool _isLoadedParagraphLine(
  List<String> lines,
  int index, {
  List<bool>? loadedLineFlags,
}) =>
    _isLineLoaded(loadedLineFlags, index) && !isReadingHeaderLine(lines[index]);

ReadingSegment _buildLoadedParagraphSegment(
  List<String> lines,
  List<int> paragraphLines,
) {
  final buffer = StringBuffer();
  final ranges = <ReadingLineRange>[];
  for (final lineIndex in paragraphLines) {
    final text = lines[lineIndex].trim();
    if (buffer.isNotEmpty) {
      buffer.write(' ');
    }
    final start = buffer.length;
    buffer.write(text);
    ranges.add(
      ReadingLineRange(
        lineIndex: lineIndex,
        start: start,
        end: buffer.length,
      ),
    );
  }

  return ReadingSegment(
    text: buffer.toString(),
    sourceLineIndices: List<int>.unmodifiable(paragraphLines),
    lineRanges: List<ReadingLineRange>.unmodifiable(ranges),
    isHeader: false,
    isLoaded: true,
  );
}

ReadingSegment _buildUnloadedRangeSegment(int startLine, int endLine) {
  final lineCount = endLine - startLine + 1;
  return ReadingSegment(
    text: '',
    sourceLineIndices: List<int>.unmodifiable(
      List<int>.generate(lineCount, (offset) => startLine + offset),
    ),
    lineRanges: const [],
    isHeader: false,
    isLoaded: false,
  );
}

List<ReadingSegment> _buildContinuousSegments(
  List<String> lines, {
  required int startIndex,
  required int endIndex,
  List<bool>? loadedLineFlags,
}) {
  if (lines.isEmpty || startIndex > endIndex) {
    return const [];
  }

  final segments = <ReadingSegment>[];
  final paragraphLines = <int>[];

  void flushParagraph() {
    if (paragraphLines.isEmpty) {
      return;
    }
    segments.add(_buildLoadedParagraphSegment(lines, paragraphLines));
    paragraphLines.clear();
  }

  var index = startIndex;
  while (index <= endIndex) {
    if (!_isLineLoaded(loadedLineFlags, index)) {
      flushParagraph();
      final unloadedStart = index;
      while (index <= endIndex && !_isLineLoaded(loadedLineFlags, index)) {
        index++;
      }
      segments.add(_buildUnloadedRangeSegment(unloadedStart, index - 1));
      continue;
    }

    final line = lines[index];
    if (isReadingHeaderLine(line)) {
      flushParagraph();
      segments.add(
        ReadingSegment(
          text: line,
          sourceLineIndices: [index],
          lineRanges: [
            ReadingLineRange(
              lineIndex: index,
              start: 0,
              end: line.length,
            ),
          ],
          isHeader: true,
          isLoaded: true,
        ),
      );
      index++;
      continue;
    }

    paragraphLines.add(index);
    index++;
  }

  flushParagraph();
  return segments;
}

/// מחשב את רשימת הסגמנטים לרינדור.
///
/// במצב הרגיל (`continuous: false`) — כל שורה היא סגמנט נפרד (זה גם
/// מבטיח שהמיפוי שורה↔סגמנט הוא 1:1 ולא נדרשת המרה).
///
/// במצב רציף (`continuous: true`) — שורות עוקבות שאינן כותרת מתמזגות
/// לפסקה אחת; כותרת (`<h1>`–`<h6>`) שוברת פסקה.
List<ReadingSegment> buildReadingSegments(
  List<String> lines, {
  required bool continuous,
  List<bool>? loadedLineFlags,
}) {
  if (!continuous) {
    if (loadedLineFlags == null) {
      final cached = _lineSegmentsCache[lines];
      if (cached != null) {
        return cached;
      }
    }

    final segments = [
      for (var index = 0; index < lines.length; index++)
        _buildNonContinuousSegment(
          lines,
          index,
          loadedLineFlags: loadedLineFlags,
        ),
    ];
    if (loadedLineFlags == null) {
      _lineSegmentsCache[lines] = segments;
    }
    return segments;
  }

  if (loadedLineFlags == null) {
    final cached = _continuousSegmentsCache[lines];
    if (cached != null) {
      return cached;
    }
  }

  final segments = _buildContinuousSegments(
    lines,
    startIndex: 0,
    endIndex: lines.length - 1,
    loadedLineFlags: loadedLineFlags,
  );
  if (loadedLineFlags == null) {
    _continuousSegmentsCache[lines] = segments;
  }
  return segments;
}

List<ReadingSegment> updateReadingSegmentsForRange(
  List<ReadingSegment> currentSegments,
  List<String> nextLines, {
  required List<bool> loadedLineFlags,
  required bool continuous,
  required int startLine,
  required int endLine,
}) {
  if (nextLines.isEmpty) {
    return const [];
  }

  final normalizedStart = startLine < 0 ? 0 : startLine;
  final normalizedEnd = endLine >= nextLines.length
      ? nextLines.length - 1
      : endLine;
  if (normalizedStart > normalizedEnd) {
    return currentSegments;
  }

  if (currentSegments.isEmpty) {
    return buildReadingSegments(
      nextLines,
      continuous: continuous,
      loadedLineFlags: loadedLineFlags,
    );
  }

  if (!continuous) {
    final nextSegments = List<ReadingSegment>.of(currentSegments);
    if (nextSegments.length < nextLines.length) {
      for (var index = nextSegments.length; index < nextLines.length; index++) {
        nextSegments.add(
          _buildNonContinuousSegment(
            nextLines,
            index,
            loadedLineFlags: loadedLineFlags,
          ),
        );
      }
    }

    for (var index = normalizedStart; index <= normalizedEnd; index++) {
      nextSegments[index] = _buildNonContinuousSegment(
        nextLines,
        index,
        loadedLineFlags: loadedLineFlags,
      );
    }
    return nextSegments;
  }

  var windowStart = normalizedStart;
  while (windowStart > 0 &&
      _isLoadedParagraphLine(
        nextLines,
        windowStart - 1,
        loadedLineFlags: loadedLineFlags,
      ) &&
      _isLoadedParagraphLine(
        nextLines,
        windowStart,
        loadedLineFlags: loadedLineFlags,
      )) {
    windowStart--;
  }

  var windowEnd = normalizedEnd;
  while (windowEnd + 1 < nextLines.length &&
      _isLoadedParagraphLine(
        nextLines,
        windowEnd,
        loadedLineFlags: loadedLineFlags,
      ) &&
      _isLoadedParagraphLine(
        nextLines,
        windowEnd + 1,
        loadedLineFlags: loadedLineFlags,
      )) {
    windowEnd++;
  }

  final replaceStart = currentSegments.indexWhere(
    (segment) => segment.endLineIndex >= windowStart,
  );
  if (replaceStart < 0) {
    final lastSegment = currentSegments.last;
    if (windowStart > lastSegment.endLineIndex) {
      final appendStart = lastSegment.endLineIndex + 1;
      final appendedSegments = _buildContinuousSegments(
        nextLines,
        startIndex: appendStart,
        endIndex: windowEnd,
        loadedLineFlags: loadedLineFlags,
      );
      if (appendedSegments.isEmpty) {
        return currentSegments;
      }
      return List<ReadingSegment>.unmodifiable([
        ...currentSegments,
        ...appendedSegments,
      ]);
    }

    return buildReadingSegments(
      nextLines,
      continuous: true,
      loadedLineFlags: loadedLineFlags,
    );
  }

  var replaceEnd = currentSegments.lastIndexWhere(
    (segment) => segment.startLineIndex <= windowEnd,
  );
  if (replaceEnd < replaceStart) {
    replaceEnd = replaceStart;
  }

  final replaceStartSegment = currentSegments[replaceStart];
  final replaceEndSegment = currentSegments[replaceEnd];
  final expandedWindowStart = replaceStartSegment.isLoaded
      ? replaceStartSegment.startLineIndex
      : windowStart;
  final expandedWindowEnd = replaceEndSegment.isLoaded
      ? replaceEndSegment.endLineIndex
      : windowEnd;
  final replacementSegments = _buildContinuousSegments(
    nextLines,
    startIndex: expandedWindowStart,
    endIndex: expandedWindowEnd,
    loadedLineFlags: loadedLineFlags,
  );

  final prefixSegments = <ReadingSegment>[];
  if (!replaceStartSegment.isLoaded &&
      replaceStartSegment.startLineIndex < expandedWindowStart) {
    prefixSegments.add(
      _buildUnloadedRangeSegment(
        replaceStartSegment.startLineIndex,
        expandedWindowStart - 1,
      ),
    );
  }

  final suffixSegments = <ReadingSegment>[];
  if (!replaceEndSegment.isLoaded &&
      expandedWindowEnd < replaceEndSegment.endLineIndex) {
    suffixSegments.add(
      _buildUnloadedRangeSegment(
        expandedWindowEnd + 1,
        replaceEndSegment.endLineIndex,
      ),
    );
  }

  final nextSegments = List<ReadingSegment>.of(currentSegments);
  nextSegments.replaceRange(
    replaceStart,
    replaceEnd + 1,
    [
      ...prefixSegments,
      ...replacementSegments,
      ...suffixSegments,
    ],
  );
  return nextSegments;
}

/// מאתר את האינדקס של הסגמנט שמכיל את שורת המקור [lineIndex].
///
/// משמש בכל אתר קריאה לגלילה (`scrollController.scrollTo(index: ...)`):
/// השורה הלוגית מתורגמת לסגמנט שאליו צריך לגלול.
int segmentIndexForLine(List<ReadingSegment> segments, int lineIndex) {
  if (segments.isEmpty) {
    return 0;
  }
  final exact = segments.indexWhere(
    (segment) => segment.containsLine(lineIndex),
  );
  if (exact >= 0) {
    return exact;
  }
  if (lineIndex <= segments.first.startLineIndex) {
    return 0;
  }
  for (var index = segments.length - 1; index >= 0; index--) {
    if (segments[index].startLineIndex <= lineIndex) {
      return index;
    }
  }
  return segments.length - 1;
}

/// השבר היחסי של שורת [lineIndex] בתוך הסגמנט [segment] (0..1).
///
/// משמש לדיוק עדין של גלילה: אחרי שגולשים לסגמנט, ה-`scrollOffsetController`
/// מתקדם בשבר הזה בתוך הסגמנט כדי שהשורה הספציפית תהיה גלויה.
/// [intraLineFraction] (0..1) מוסיף דיוק לתוך השורה עצמה — מיקום ההתאמה בתוך
/// הפסקה — כדי שהגלילה תגיע למילה ולא לתחילת הפסקה.
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

/// ממיר רשימת `ItemPosition` (במונחי segmentIndex) לרשימת שורות-מקור גלויות.
///
/// במצב הרגיל זה איזומורפי — segmentIndex == lineIndex, אבל ההמרה עוברת
/// דרך אותה פונקציה כדי ש-`_resolveVisibleSourceIndices` ב-bloc לא יצטרך
/// להבדיל בין המצבים.
List<int> sourceLineIndicesForSegmentViewports(
  List<ReadingSegment> segments,
  Iterable<ReadingSegmentViewport> viewports, {
  bool Function(double leadingEdge, double trailingEdge)? isLineRemnant,
}) {
  final sourceIndices = <int>{};
  for (final viewport in viewports) {
    if (viewport.segmentIndex < 0 || viewport.segmentIndex >= segments.length) {
      continue;
    }

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
  return sourceIndices.toList()..sort();
}
