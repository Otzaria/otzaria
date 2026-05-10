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

  const ReadingSegment({
    required this.text,
    required this.sourceLineIndices,
    required this.lineRanges,
    required this.isHeader,
  });

  int get startLineIndex => sourceLineIndices.first;

  bool containsLine(int lineIndex) => sourceLineIndices.contains(lineIndex);

  int lineForTextOffset(int offset) {
    for (final range in lineRanges) {
      if (range.containsOffset(offset)) {
        return range.lineIndex;
      }
    }
    return startLineIndex;
  }
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

bool isReadingHeaderLine(String line) {
  final headerPattern = RegExp(r'^\s*<h[1-6]', caseSensitive: false);
  return headerPattern.hasMatch(line);
}

List<ReadingSegment> buildReadingSegments(
  List<String> lines, {
  required bool continuous,
}) {
  if (!continuous) {
    final cached = _lineSegmentsCache[lines];
    if (cached != null) {
      return cached;
    }

    final segments = [
      for (var index = 0; index < lines.length; index++)
        ReadingSegment(
          text: lines[index],
          sourceLineIndices: [index],
          lineRanges: [
            ReadingLineRange(
              lineIndex: index,
              start: 0,
              end: lines[index].length,
            ),
          ],
          isHeader: isReadingHeaderLine(lines[index]),
        ),
    ];
    _lineSegmentsCache[lines] = segments;
    return segments;
  }

  final cached = _continuousSegmentsCache[lines];
  if (cached != null) {
    return cached;
  }

  final segments = <ReadingSegment>[];
  final paragraphLines = <int>[];

  void flushParagraph() {
    if (paragraphLines.isEmpty) {
      return;
    }

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

    segments.add(
      ReadingSegment(
        text: buffer.toString(),
        sourceLineIndices: List<int>.unmodifiable(paragraphLines),
        lineRanges: List<ReadingLineRange>.unmodifiable(ranges),
        isHeader: false,
      ),
    );
    paragraphLines.clear();
  }

  for (var index = 0; index < lines.length; index++) {
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
        ),
      );
      continue;
    }

    paragraphLines.add(index);
  }

  flushParagraph();
  _continuousSegmentsCache[lines] = segments;
  return segments;
}

int segmentIndexForLine(List<ReadingSegment> segments, int lineIndex) {
  if (segments.isEmpty) {
    return 0;
  }
  final exact =
      segments.indexWhere((segment) => segment.containsLine(lineIndex));
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

double lineFractionWithinSegment(ReadingSegment segment, int lineIndex) {
  final lineOffset = segment.sourceLineIndices.indexOf(lineIndex);
  if (lineOffset <= 0 || segment.sourceLineIndices.length <= 1) {
    return 0;
  }
  return lineOffset / segment.sourceLineIndices.length;
}

List<int> sourceLineIndicesForSegments(
  List<ReadingSegment> segments,
  Iterable<int> segmentIndices,
) {
  final sourceIndices = <int>{};
  for (final segmentIndex in segmentIndices) {
    if (segmentIndex < 0 || segmentIndex >= segments.length) {
      continue;
    }
    sourceIndices.addAll(segments[segmentIndex].sourceLineIndices);
  }
  return sourceIndices.toList()..sort();
}

List<int> sourceLineIndicesForSegmentViewports(
  List<ReadingSegment> segments,
  Iterable<ReadingSegmentViewport> viewports,
) {
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

    final startFraction = (-viewport.leadingEdge / extent).clamp(0.0, 1.0);
    final endFraction = ((1.0 - viewport.leadingEdge) / extent).clamp(0.0, 1.0);
    var startOffset = (startFraction * lineCount).floor() - 1;
    var endOffset = (endFraction * lineCount).ceil() + 1;

    startOffset = startOffset.clamp(0, lineCount - 1);
    endOffset = endOffset.clamp(startOffset + 1, lineCount);

    sourceIndices.addAll(segment.sourceLineIndices.sublist(
      startOffset,
      endOffset,
    ));
  }
  return sourceIndices.toList()..sort();
}
