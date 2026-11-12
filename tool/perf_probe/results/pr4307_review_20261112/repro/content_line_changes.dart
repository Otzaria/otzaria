

typedef ContentLineRange = ({int first, int last});

/// טווחי המקור שהשתנו מאז גרסת תוכן אחת, בלי לשמור את התוכן הקודם.
class ContentLineChanges {
  ContentLineChanges({
    required this.fromVersion,
    required Iterable<ContentLineRange> ranges,
  }) : ranges = List.unmodifiable(_merge(ranges));

  final int fromVersion;
  final List<ContentLineRange> ranges;

  static List<ContentLineRange> _merge(Iterable<ContentLineRange> ranges) {
    final sorted = ranges.toList()..sort((a, b) => a.first.compareTo(b.first));
    final merged = <ContentLineRange>[];
    for (final range in sorted) {
      if (range.first < 0 || range.last < range.first) {
        throw ArgumentError.value(range, 'range');
      }
      if (merged.isEmpty || range.first > merged.last.last + 1) {
        merged.add(range);
      } else if (range.last > merged.last.last) {
        merged[merged.length - 1] = (
          first: merged.last.first,
          last: range.last,
        );
      }
    }
    return merged;
  }
}
