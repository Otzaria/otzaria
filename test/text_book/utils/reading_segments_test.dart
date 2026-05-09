import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

void main() {
  group('buildReadingSegments', () {
    test('keeps one segment per source line when continuous mode is disabled',
        () {
      final segments = buildReadingSegments(
        const ['line a', 'line b'],
        continuous: false,
      );

      expect(segments, hasLength(2));
      expect(segments[0].text, 'line a');
      expect(segments[0].sourceLineIndices, [0]);
      expect(segments[1].text, 'line b');
      expect(segments[1].sourceLineIndices, [1]);
    });

    test('joins regular lines until the next HTML header', () {
      final segments = buildReadingSegments(
        const [
          '<h2>header</h2>',
          'line a',
          'line b',
          '<h3>subheader</h3>',
          'line c',
        ],
        continuous: true,
      );

      expect(segments, hasLength(4));
      expect(segments[0].isHeader, isTrue);
      expect(segments[0].sourceLineIndices, [0]);
      expect(segments[1].text, 'line a line b');
      expect(segments[1].sourceLineIndices, [1, 2]);
      expect(segments[2].isHeader, isTrue);
      expect(segments[2].sourceLineIndices, [3]);
      expect(segments[3].text, 'line c');
      expect(segments[3].sourceLineIndices, [4]);
    });

    test('keeps ranges that map text offsets back to source lines', () {
      final segments = buildReadingSegments(
        const ['abc', 'def'],
        continuous: true,
      );

      final segment = segments.single;
      expect(segment.text, 'abc def');
      expect(segment.lineForTextOffset(0), 0);
      expect(segment.lineForTextOffset(2), 0);
      expect(segment.lineForTextOffset(4), 1);
      expect(segment.lineForTextOffset(6), 1);
    });

    test('maps visible segment indices back to all visible source lines', () {
      final segments = buildReadingSegments(
        const ['<h2>header</h2>', 'a', 'b', '<h2>next</h2>', 'c'],
        continuous: true,
      );

      expect(sourceLineIndicesForSegments(segments, const [1]), [1, 2]);
      expect(sourceLineIndicesForSegments(segments, const [0, 2]), [0, 3]);
      expect(segmentIndexForLine(segments, 2), 1);
      expect(segmentIndexForLine(segments, 4), 3);
      expect(lineFractionWithinSegment(segments[1], 1), 0);
      expect(lineFractionWithinSegment(segments[1], 2), 0.5);
    });

    test('maps a large visible segment to the visible source-line slice', () {
      final segments = buildReadingSegments(
        List<String>.generate(100, (index) => 'line $index'),
        continuous: true,
      );

      final indices = sourceLineIndicesForSegmentViewports(
        segments,
        const [
          ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: -4,
            trailingEdge: 16,
          ),
        ],
      );

      expect(indices.first, greaterThan(0));
      expect(indices.last, lessThan(100));
      expect(indices.length, lessThan(100));
    });
  });
}
