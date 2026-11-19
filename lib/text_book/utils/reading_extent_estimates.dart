import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/text_book/utils/reading_extent_worker_queue.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show removeHtmlTags;
import 'package:positioned_sliver_list/positioned_list.dart';

/// מידות הטקסט שנמדדו פעם אחת לסגנון, בלי לפרוס פסקאות לצורך הערכה.
class ReadingExtentMetrics {
  const ReadingExtentMetrics({
    required this.lineExtent,
    required this.charWidth,
    this.contentWidthRatio = 1,
    this.verticalPadding = 4,
  });

  final double lineExtent;
  final double charWidth;
  final double contentWidthRatio;
  final double verticalPadding;
}

/// מונה תווים לכל שורת מקור; בחימום מעדכן רק טווחים ששונו.
class ReadingExtentEstimates {
  ReadingExtentEstimates(ReadingSegments segments)
    : this.withWorkerQueue(segments, _countWorkers);

  @visibleForTesting
  ReadingExtentEstimates.withWorkerQueue(this.segments, this._workerQueue)
    : _counts = Int32List(segments.content.length) {
    _counts.fillRange(0, _counts.length, -1);
  }

  ReadingSegments segments;
  final ReadingExtentWorkerQueue _workerQueue;
  ReadingExtentWorkerJob<_CountResult>? _workerJob;
  Int32List _counts;
  bool _disposed = false;
  // ממוצע קבוע מונע שינוי של כל הערכות הספר בכל מנת חימום.
  double _unloadedLineChars = 200;
  bool _fullRefresh = true;
  final _pendingRanges = <ContentLineRange>[];
  Future<({bool full, List<ContentLineRange> ranges})>? _refreshing;

  bool get needsRefresh => _fullRefresh || _pendingRanges.isNotEmpty;

  @visibleForTesting
  int debugCountedLines = 0;

  @visibleForTesting
  int get debugStorageBytes => _counts.lengthInBytes;

  /// משחרר עבודה ממתינה; חישוב פעיל מסתיים בלי לפרסם תוצאה.
  void dispose() {
    _disposed = true;
    _workerJob?.cancel();
    _pendingRanges.clear();
    _fullRefresh = false;
  }

  void update(ReadingSegments next) {
    final changedReader = !identical(
      next.readerIdentity,
      segments.readerIdentity,
    );
    final changes = changedReader ? null : next.changedLinesSince(segments);
    segments = next;
    if (changes == null) {
      _fullRefresh = true;
      _pendingRanges.clear();
      if (changedReader || _counts.length != next.content.length) {
        _counts = Int32List(next.content.length);
        _counts.fillRange(0, _counts.length, -1);
        _unloadedLineChars = 200;
      }
    } else if (!_fullRefresh) {
      _pendingRanges.addAll(changes);
    }
  }

  /// מדגם גדול נספר ב־isolate יחיד; עדכונים שמגיעים בינתיים מתמזגים אחריו.
  Future<({bool full, List<ContentLineRange> ranges})> refresh({
    bool Function()? shouldContinue,
  }) => _refreshing ??= _refresh(
    shouldContinue,
  ).whenComplete(() => _refreshing = null);

  Future<({bool full, List<ContentLineRange> ranges})> _refresh(
    bool Function()? shouldContinue,
  ) async {
    var replacedAll = false;
    final applied = <ContentLineRange>[];
    while (!_disposed &&
        (_fullRefresh || _pendingRanges.isNotEmpty) &&
        (shouldContinue?.call() ?? true)) {
      final full = _fullRefresh;
      _fullRefresh = false;
      final ranges = full
          ? [
              if (segments.content.isNotEmpty)
                (first: 0, last: segments.content.length - 1),
            ]
          : ContentLineChanges(fromVersion: 0, ranges: _pendingRanges).ranges;
      _pendingRanges.clear();
      final chunks = _chunks(ranges);
      final costly =
          chunks.fold<int>(0, (sum, chunk) => sum + chunk.lines.length) >=
              10000 ||
          _rawCharactersExceed(chunks, 1024 * 1024);
      _CountResult? result;
      if (costly) {
        final job = _workerQueue.enqueue(
          () => compute(_countChunks, chunks, debugLabel: 'readingExtents'),
        );
        _workerJob = job;
        try {
          result = await job.result;
        } finally {
          _workerJob = null;
        }
      } else {
        result = _countChunks(chunks);
      }
      if (_disposed || result == null) {
        return (full: false, ranges: <ContentLineRange>[]);
      }
      if (_fullRefresh) continue;
      final hasUnloaded = result.loaded != result.counts.length;
      var meanMayChange = !hasUnloaded;
      var known = result.loaded;
      var chars = result.chars;
      var cursor = 0;
      for (final range in ranges) {
        final length = range.last - range.first + 1;
        if (hasUnloaded) {
          for (var i = 0; i < length; i++) {
            final previous = _counts[range.first + i];
            final count = result.counts[cursor + i];
            if (count < 0 && previous >= 0) {
              result.counts[cursor + i] = previous;
              known++;
              chars += previous;
            } else if (count >= 0 && count != previous) {
              meanMayChange = true;
            }
          }
        }
        if (!full) {
          _counts.setRange(range.first, range.last + 1, result.counts, cursor);
        }
        cursor += length;
      }
      debugCountedLines += cursor;
      if (full) {
        replacedAll = true;
        _counts = result.counts;
        // שחרור תוכן בלבד לא משנה את ברירת המחדל שנקבעה לפני החימום.
        if (meanMayChange) {
          _unloadedLineChars = known == 0 ? 200 : chars / known;
        }
      }
      applied.addAll(ranges);
    }
    return (
      full: replacedAll,
      ranges: ContentLineChanges(fromVersion: 0, ranges: applied).ranges,
    );
  }

  void initializeSynchronously() {
    if (!_fullRefresh) return;
    final result = _countChunks(
      _chunks([
        if (segments.content.isNotEmpty)
          (first: 0, last: segments.content.length - 1),
      ]),
    );
    _counts = result.counts;
    _unloadedLineChars = result.loaded == 0
        ? 200
        : result.chars / result.loaded;
    debugCountedLines += _counts.length;
    _fullRefresh = false;
  }

  List<_CountChunk> _chunks(List<ContentLineRange> ranges) => [
    for (final range in ranges)
      (
        lines: range.first == 0 && range.last + 1 == segments.content.length
            ? segments.content
            : segments.content.sublist(range.first, range.last + 1),
        loaded: segments.loadedLineFlags == null
            ? null
            : range.first == 0 &&
                  segments.loadedLineFlags!.length == range.last + 1
            ? segments.loadedLineFlags
            : [
                for (var line = range.first; line <= range.last; line++)
                  line < segments.loadedLineFlags!.length &&
                      segments.loadedLineFlags![line],
              ],
      ),
  ];

  double estimate(int index, double width, ReadingExtentMetrics metrics) {
    final layout = segments.layout;
    final available = width * metrics.contentWidthRatio;
    if (index < 0 ||
        index >= layout.itemCount ||
        available <= metrics.charWidth) {
      return metrics.lineExtent + metrics.verticalPadding;
    }
    final first = layout.firstLineOf(index);
    final last = layout.lastLineOf(index);
    var chars = (last - first).toDouble();
    for (var line = first; line <= last; line++) {
      final count = _counts[line];
      chars += count < 0 ? _unloadedLineChars : count;
    }
    final lines = math.max(1, (chars * metrics.charWidth / available).ceil());
    return lines * metrics.lineExtent + metrics.verticalPadding;
  }
}

typedef _CountChunk = ({List<String> lines, List<bool>? loaded});
typedef _CountResult = ({Int32List counts, int chars, int loaded});

final _countWorkers = ReadingExtentWorkerQueue();

bool _rawCharactersExceed(List<_CountChunk> chunks, int limit) {
  var total = 0;
  for (final chunk in chunks) {
    for (var line = 0; line < chunk.lines.length; line++) {
      if (chunk.loaded == null || chunk.loaded![line]) {
        total += chunk.lines[line].length;
        if (total >= limit) return true;
      }
    }
  }
  return false;
}

_CountResult _countChunks(List<_CountChunk> chunks) {
  final counts = Int32List(
    chunks.fold<int>(0, (sum, chunk) => sum + chunk.lines.length),
  );
  var cursor = 0;
  var chars = 0;
  var loaded = 0;
  for (final chunk in chunks) {
    for (var line = 0; line < chunk.lines.length; line++) {
      final count = chunk.loaded == null || chunk.loaded![line]
          ? visibleReadingCharCount(chunk.lines[line])
          : -1;
      counts[cursor++] = count;
      if (count >= 0) {
        chars += count;
        loaded++;
      }
    }
  }
  return (counts: counts, chars: chars, loaded: loaded);
}

/// הערכה סינכרונית לקוראים קטנים; בקורא חי העטיפה סופרת ספר גדול ברקע.
ItemExtentEstimator readingExtentEstimator(
  ReadingSegments segments,
  double fontSize, {
  double lineHeight = 1.5,
  double contentWidthRatio = 1,
  double verticalPadding = 4,
}) {
  ReadingExtentEstimates? data;
  final metrics = ReadingExtentMetrics(
    lineExtent: fontSize * lineHeight,
    charWidth: fontSize * 0.45,
    contentWidthRatio: contentWidthRatio,
    verticalPadding: verticalPadding,
  );
  return (index, width) {
    data ??= ReadingExtentEstimates(segments)..initializeSynchronously();
    return data!.estimate(index, width, metrics);
  };
}

final _combining = RegExp(r'\p{M}', unicode: true);

/// סופר את הטקסט הגלוי, בלי גוף הערות ובלי סימנים שמשולבים באות בסיס.
@visibleForTesting
int visibleReadingCharCount(String text) {
  var plain = notes.stripInlineNotes(text);
  if (plain.contains('<')) plain = removeHtmlTags(plain);
  if (plain.contains('&')) plain = html.parseFragment(plain).text ?? plain;
  var count = 0;
  final length = plain.length;
  for (var i = 0; i < length; i++) {
    var code = plain.codeUnitAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < length) {
      final low = plain.codeUnitAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
        i++;
      }
    }
    if ((code >= 0x591 && code <= 0x5BD) ||
        code == 0x5BF ||
        code == 0x5C1 ||
        code == 0x5C2 ||
        code == 0x5C4 ||
        code == 0x5C5 ||
        code == 0x5C7) {
      continue;
    }
    // שאר הגוש העברי (אותיות, מקף, פסק, סוף פסוק) אינו משולב — בלי RegExp.
    if (code < 0x300 || (code >= 0x591 && code < 0x600)) {
      count++;
    } else if (!_combining.hasMatch(String.fromCharCode(code))) {
      count++;
    }
  }
  return count;
}
