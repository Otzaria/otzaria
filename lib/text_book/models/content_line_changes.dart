import 'package:flutter/foundation.dart';

typedef ContentLineRange = ({int first, int last});

/// טווחי המקור שהשתנו מאז גרסת תוכן אחת, בלי לשמור את התוכן הקודם.
@immutable
class ContentLineChanges {
  ContentLineChanges({
    required this.fromVersion,
    required Iterable<ContentLineRange> ranges,
    List<String>? previousContent,
    List<bool>? previousLoadedLineFlags,
  }) : ranges = List.unmodifiable(_merge(ranges)),
       _previousContent = previousContent == null
           ? null
           : WeakReference(previousContent),
       _previousLoadedLineFlags = previousLoadedLineFlags == null
           ? null
           : WeakReference(previousLoadedLineFlags);

  final int fromVersion;
  final List<ContentLineRange> ranges;
  final WeakReference<List<String>>? _previousContent;
  final WeakReference<List<bool>>? _previousLoadedLineFlags;

  /// תצלום המקור, כל עוד הוא מוחזק במקום אחר.
  List<String>? get previousContent => _previousContent?.target;

  /// התאמה לדגלי הטעינה של תצלום המקור.
  bool matchesPreviousFlags(List<bool>? flags) {
    final previous = _previousLoadedLineFlags;
    return previous == null
        ? flags == null
        : flags != null && identical(previous.target, flags);
  }

  /// האם אחד הטווחים שהשתנו חופף לשורות המבוקשות.
  bool affects(int first, int last) {
    var low = 0;
    var high = ranges.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (ranges[mid].last < first) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < ranges.length && ranges[low].first <= last;
  }

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
