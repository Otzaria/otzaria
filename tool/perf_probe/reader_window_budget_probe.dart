import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:otzaria/text_book/models/chunked_list.dart';

const _chunkLines = ChunkedList.chunkLength;
const _referenceBytes = 8;
const _budgetBytes = 1024 * 1024;
const _viewportLines = 48;
const _observedSizeLimit = 128;

enum _Policy { symmetric, directional }

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class _Source {
  _Source(this.length, this.reader, {this.oversizedLine});

  final int length;
  final int reader;
  final int? oversizedLine;
  String? _oversizedText;
  int readLines = 0;
  int readChunks = 0;
  int rereadChunks = 0;
  final _seenChunks = <int>{};

  String line(int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    if (index == oversizedLine) {
      return _oversizedText ??=
          (StringBuffer('[$reader:$index] ')..writeAll(
                Iterable.generate(30000, (_) => 'אבגדהוזחטיכלמנסעפצקרשת'),
              ))
              .toString();
    }
    if (index % 97 == 0) return '';
    final text = StringBuffer('[$reader:$index] ');
    for (var repeat = 0; repeat < 2 + index % 5; repeat++) {
      text.write('טֶקְסְט בְּדִיקָה לקריאה רציפה, ABC 123. ');
    }
    if (index % 101 == 0) return '<h2>$text</h2>';
    if (index % 23 == 0) text.write('<i class="footnote">הערת בדיקה</i>');
    return text.toString();
  }

  _Chunk read(int index) {
    final start = index * _chunkLines;
    final count = math.min(_chunkLines, length - start);
    _check(count > 0, 'Read outside the source');
    readChunks++;
    if (!_seenChunks.add(index)) rereadChunks++;
    readLines += count;
    return _Chunk(
      index,
      List.generate(count, (offset) => line(start + offset), growable: false),
    );
  }
}

class _Chunk {
  _Chunk(this.index, this.lines)
    : payloadBytes = lines.fold<int>(0, (sum, line) => sum + line.length * 2);

  final int index;
  final List<String> lines;
  final int payloadBytes;

  // Two fixed-size chunk arrays: content references and bool references.
  int get estimatedBytes => payloadBytes + 2 * _chunkLines * _referenceBytes;
}

class _Reader {
  _Reader(this.source)
    : content = ChunkedList<String>.filled(source.length, ''),
      loaded = ChunkedList<bool>.filled(source.length, false);

  final _Source source;
  ChunkedList<String> content;
  ChunkedList<bool> loaded;
  Map<int, _Chunk> chunks = {};
  int? previousStart;
  int? previousEnd;
  int direction = 1;
  int checkedLines = 0;
  int alreadyLoadedLines = 0;
  int evictedChunks = 0;
  int rejectedPrefetchBytes = 0;
  int rejectedPrefetchReads = 0;
  int avoidedRejectedReads = 0;
  final _observedChunkBytes = <int, int>{};

  _Chunk read(int index) {
    final chunk = source.read(index);
    _observedChunkBytes.remove(index);
    _observedChunkBytes[index] = chunk.estimatedBytes;
    if (_observedChunkBytes.length > _observedSizeLimit) {
      _observedChunkBytes.remove(_observedChunkBytes.keys.first);
    }
    return chunk;
  }

  int get estimatedBytes =>
      chunks.values.fold(0, (sum, c) => sum + c.estimatedBytes);

  Map<int, _Chunk> pin(int start, int end) {
    final moved = previousStart != start || previousEnd != end;
    if (previousStart != null && start != previousStart) {
      direction = start > previousStart! ? 1 : -1;
    }
    previousStart = start;
    previousEnd = end;
    if (moved) {
      for (var line = start; line < end; line++) {
        checkedLines++;
        if (loaded[line]) alreadyLoadedLines++;
      }
    }
    return {
      for (
        var chunk = start ~/ _chunkLines;
        chunk <= (end - 1) ~/ _chunkLines;
        chunk++
      )
        chunk: chunks[chunk] ?? read(chunk),
    };
  }

  void apply(Map<int, _Chunk> selected, int start, int end) {
    final before = content;
    final oldLoaded = loaded;
    final oldProbe = chunks.isEmpty ? null : chunks.keys.first * _chunkLines;
    final oldValue = oldProbe == null ? null : before[oldProbe];
    final oldFlag = oldProbe == null ? null : oldLoaded[oldProbe];
    final first = selected.keys.reduce(math.min) * _chunkLines;
    final last = math.min(
      source.length,
      (selected.keys.reduce(math.max) + 1) * _chunkLines,
    );
    _check(
      selected.length == (last - 1) ~/ _chunkLines - first ~/ _chunkLines + 1,
      'This prototype supports only contiguous retained chunks',
    );
    final contentEdit = content.edit()..retainRange(first, last);
    final flagsEdit = loaded.edit()..retainRange(first, last);
    for (final chunk in selected.values) {
      contentEdit.setRangeValues(chunk.index * _chunkLines, chunk.lines);
      flagsEdit.setRangeValues(
        chunk.index * _chunkLines,
        List<bool>.filled(chunk.lines.length, true),
      );
    }
    for (final index in chunks.keys) {
      if (!selected.containsKey(index)) evictedChunks++;
    }
    chunks = selected;
    content = contentEdit.build();
    loaded = flagsEdit.build();
    _check(
      content.length == source.length && loaded.length == source.length,
      'Logical length changed',
    );
    for (var line = start; line < end; line++) {
      _check(
        loaded[line] && content[line] == source.line(line),
        'Visible source line was lost: $line',
      );
    }
    if (oldProbe != null) {
      _check(
        before[oldProbe] == oldValue && oldLoaded[oldProbe] == oldFlag,
        'A previous snapshot was mutated',
      );
    }
    if (first > 0) {
      _check(content[0].isEmpty && !loaded[0], 'Evicted prefix stayed loaded');
    }
    if (last < source.length) {
      _check(
        content[last].isEmpty && !loaded[last],
        'Evicted suffix stayed loaded',
      );
    }
  }
}

Iterable<int> _candidates(
  int first,
  int last,
  int direction,
  _Policy policy,
) sync* {
  if (policy == _Policy.symmetric) {
    for (var offset = 1; offset <= 2; offset++) {
      yield direction > 0 ? last + offset : first - offset;
      yield direction > 0 ? first - offset : last + offset;
    }
  } else {
    for (var offset = 1; offset <= 3; offset++) {
      yield direction > 0 ? last + offset : first - offset;
    }
    yield direction > 0 ? first - 1 : last + 1;
  }
}

class _Coordinator {
  _Coordinator(this.readers, this.policy, this.budget);

  final List<_Reader> readers;
  final _Policy policy;
  final int budget;
  int peakBytes = 0;
  int peakPinnedBytes = 0;
  int steps = 0;

  void move(int start, {int visibleLines = _viewportLines}) => moveWindows(
    List<int>.filled(readers.length, start),
    visibleLines: visibleLines,
  );

  void moveWindows(List<int> starts, {int visibleLines = _viewportLines}) {
    _check(starts.length == readers.length, 'Missing reader viewport');
    final length = readers.first.source.length;
    final ends = [
      for (final start in starts) math.min(length, start + visibleLines),
    ];
    for (var i = 0; i < starts.length; i++) {
      _check(starts[i] >= 0 && starts[i] < ends[i], 'Invalid viewport');
    }
    final selected = [
      for (var i = 0; i < readers.length; i++)
        readers[i].pin(starts[i], ends[i]),
    ];
    final pinnedBytes = selected.fold<int>(
      0,
      (sum, chunks) =>
          sum +
          chunks.values.fold<int>(
            0,
            (sum, chunk) => sum + chunk.estimatedBytes,
          ),
    );
    final optionalShare = math.max(0, budget - pinnedBytes) ~/ readers.length;
    peakPinnedBytes = math.max(peakPinnedBytes, pinnedBytes);
    for (var i = 0; i < readers.length; i++) {
      final reader = readers[i];
      final start = starts[i];
      final end = ends[i];
      final retained = selected[i];
      var optionalBytes = 0;
      if (optionalShare > 0) {
        for (final candidate in _candidates(
          start ~/ _chunkLines,
          (end - 1) ~/ _chunkLines,
          reader.direction,
          policy,
        )) {
          if (candidate < 0 || candidate * _chunkLines >= length) continue;
          final cached = reader.chunks[candidate];
          final observedBytes = reader._observedChunkBytes[candidate];
          if (cached == null &&
              observedBytes != null &&
              optionalBytes + observedBytes > optionalShare) {
            reader.avoidedRejectedReads++;
            break;
          }
          final chunk = cached ?? reader.read(candidate);
          if (optionalBytes + chunk.estimatedBytes > optionalShare) {
            if (cached == null) {
              reader.rejectedPrefetchBytes += chunk.estimatedBytes;
              reader.rejectedPrefetchReads++;
            }
            break;
          }
          retained[candidate] = chunk;
          optionalBytes += chunk.estimatedBytes;
        }
      }
      reader.apply(retained, start, end);
    }
    final bytes = readers.fold<int>(
      0,
      (sum, reader) => sum + reader.estimatedBytes,
    );
    peakBytes = math.max(peakBytes, bytes);
    _check(
      bytes <= math.max(budget, pinnedBytes),
      'Policy exceeded its estimated budget without pins',
    );
    if (pinnedBytes > budget) {
      _check(
        bytes == pinnedBytes,
        'Speculation was admitted during pinned overflow',
      );
    }
    steps++;
  }

  Map<String, Object> summary() {
    int sum(int Function(_Reader) get) =>
        readers.fold(0, (total, r) => total + get(r));
    return {
      'policy': policy.name,
      'bookLines': readers.first.source.length,
      'readers': readers.length,
      'steps': steps,
      'estimatedBudgetBytes': budget,
      'peakEstimatedRetainedBytes': peakBytes,
      'peakEstimatedPinnedBytes': peakPinnedBytes,
      'visibleLinesChecked': sum((r) => r.checkedLines),
      'visibleLinesAlreadyCached': sum((r) => r.alreadyLoadedLines),
      'visibleLinesMissingBeforeDemand': sum(
        (r) => r.checkedLines - r.alreadyLoadedLines,
      ),
      'generatedReadLines': sum((r) => r.source.readLines),
      'generatedReadChunks': sum((r) => r.source.readChunks),
      'rereadChunks': sum((r) => r.source.rereadChunks),
      'evictedChunks': sum((r) => r.evictedChunks),
      'rejectedPrefetchReads': sum((r) => r.rejectedPrefetchReads),
      'rejectedPrefetchEstimatedBytes': sum((r) => r.rejectedPrefetchBytes),
      'avoidedKnownOversizePrefetchReads': sum((r) => r.avoidedRejectedReads),
      'observedChunkSizeEntries': sum((r) => r._observedChunkBytes.length),
      'logicalIndicesAndVisibleContentVerified': true,
    };
  }
}

Map<String, int> _fullSourceAccounting(int length) {
  final source = _Source(length, 0);
  var characters = 0;
  var checksum = 0;
  for (var line = 0; line < length; line++) {
    final text = source.line(line);
    characters += text.length;
    checksum = (checksum + ((line + 1) * (text.length + 1))) & 0x7fffffff;
  }
  return {
    'bookLines': length,
    'utf16PayloadBytes': characters * 2,
    'currentTwoFullLengthReferenceArraysBytes': 2 * length * _referenceBytes,
    'currentFullWarmupEstimatedBytesPerReader':
        characters * 2 + 2 * length * _referenceBytes,
    'checksum': checksum,
  };
}

List<int> _trace(int length, int requestedStep) {
  final step = math.min(requestedStep, (length - 128) ~/ 14);
  final start = math.min(length ~/ 3, length - 10 * step - _viewportLines);
  return [
    for (var i = 0; i < 10; i++) start + i * step,
    for (var i = 8; i >= 0; i--) start + i * step,
    for (final fraction in [0.9, 0.1, 0.95, 0.05])
      ((length - _viewportLines) * fraction).floor(),
  ];
}

_Coordinator _coordinator(
  int length,
  int readerCount,
  _Policy policy, {
  int? oversizedLine,
}) => _Coordinator(
  List.generate(
    readerCount,
    (reader) => _Reader(_Source(length, reader, oversizedLine: oversizedLine)),
  ),
  policy,
  _budgetBytes,
);

Map<String, Object> _verifyAdmissionRetry() {
  const start = 16666;
  final coordinator = _coordinator(50000, 8, _Policy.directional)..move(start);
  final first = coordinator.summary();
  _check(
    coordinator.readers.every((reader) => reader.rejectedPrefetchReads == 1),
    'Regression fixture must reject one unknown chunk per reader',
  );
  coordinator.move(start);
  final repeated = coordinator.summary();
  _check(
    first['generatedReadChunks'] == repeated['generatedReadChunks'] &&
        first['visibleLinesChecked'] == repeated['visibleLinesChecked'] &&
        repeated['avoidedKnownOversizePrefetchReads'] == 8,
    'Unchanged viewports retried a prefetch known not to fit',
  );

  final expanded = _Coordinator(
    coordinator.readers,
    _Policy.directional,
    2 * _budgetBytes,
  )..move(start);
  final formerlyRejected = start ~/ _chunkLines + 1;
  _check(
    expanded.readers.every(
      (reader) => reader.chunks.containsKey(formerlyRejected),
    ),
    'A previously rejected chunk stayed blocked after capacity increased',
  );

  final bounded = _Reader(_Source(50000, 0));
  for (var chunk = 0; chunk <= _observedSizeLimit; chunk++) {
    bounded.read(chunk);
  }
  _check(
    bounded._observedChunkBytes.length == _observedSizeLimit &&
        !bounded._observedChunkBytes.containsKey(0),
    'Observed size metadata grew beyond its bound',
  );
  return {
    'firstMove': first,
    'unchangedViewport': repeated,
    'expandedBudget': expanded.summary(),
    'knownRejectedChunkAdmittedAfterBudgetIncrease': true,
    'observedSizeCacheBoundVerified': true,
  };
}

void main() {
  final admissionRetry = _verifyAdmissionRetry();
  final full = [
    for (final lines in [2000, 50000, 1000000]) _fullSourceAccounting(lines),
  ];
  final cases = <Map<String, Object>>[];
  for (final account in full) {
    final lines = account['bookLines']!;
    for (final readerCount in [1, 2, 4, 8]) {
      for (final step in [96, 3 * _chunkLines]) {
        for (final policy in _Policy.values) {
          for (final independent in [false, true]) {
            if (independent && readerCount == 1) continue;
            final coordinator = _coordinator(lines, readerCount, policy);
            final starts = [
              for (var reader = 0; reader < readerCount; reader++)
                (lines - _viewportLines) * (reader + 1) ~/ (readerCount + 1),
            ];
            var tick = 0;
            for (final start in _trace(lines, step)) {
              if (independent) {
                final active = tick++ % readerCount;
                starts[active] =
                    (start + active * (lines ~/ readerCount)) %
                    (lines - _viewportLines + 1);
                coordinator.moveWindows(starts);
              } else {
                coordinator.move(start);
              }
            }
            cases.add({
              ...coordinator.summary(),
              'windowMotion': independent
                  ? 'one window moves per step; focus rotates'
                  : 'all windows move together',
              'requestedLogicalLinesPerStep': step,
              'potentialFullWarmupEstimatedBytesAcrossReaders':
                  account['currentFullWarmupEstimatedBytesPerReader']! *
                  readerCount,
            });
          }
        }
      }
    }
  }

  final pinnedOverflow = <Map<String, Object>>[];
  for (final count in [1, 2, 4, 8]) {
    const start = 100 * _chunkLines;
    final coordinator = _coordinator(
      1000000,
      count,
      _Policy.directional,
      oversizedLine: start,
    );
    coordinator.move(start, visibleLines: 200);
    _check(
      coordinator.peakPinnedBytes > _budgetBytes,
      'Fixture did not exceed the budget',
    );
    pinnedOverflow.add({
      ...coordinator.summary(),
      'syntheticPinnedSourceLinesPerReader': 200,
      'oversizedSourceLineUtf16CodeUnits': coordinator.readers.first.source
          .line(start)
          .length,
      'hardCapCompatibleWithPreservingAllVisibleText': false,
    });
  }

  final fullOperation = _coordinator(50000, 1, _Policy.directional)
    ..move(24000);
  final reader = fullOperation.readers.single;
  final before = reader.content;
  final sourceLines = List.generate(
    reader.source.length,
    reader.source.line,
    growable: false,
  );
  var checksum = 0;
  var chars = 0;
  for (var line = 0; line < sourceLines.length; line++) {
    _check(
      sourceLines[line] == reader.source.line(line),
      'Full-content operation changed source text at $line',
    );
    chars += sourceLines[line].length;
    checksum =
        (checksum + ((line + 1) * (sourceLines[line].length + 1))) & 0x7fffffff;
  }
  _check(
    checksum == full[1]['checksum'],
    'Full-content operation lost source text',
  );
  _check(
    identical(before, reader.content),
    'Full-content operation replaced the viewport cache',
  );
  _check(
    !reader.loaded[0] && sourceLines[1] == reader.source.line(1),
    'Full operation relied on sparse placeholders',
  );

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 3,
      'kind':
          'deterministic accounting and content-correctness experiment; not UI or heap benchmark',
      'assumptions': {
        'chunkLines': _chunkLines,
        'referenceBytes': _referenceBytes,
        'utf16BytesPerCodeUnit': 2,
        'cacheBudgetBytes': _budgetBytes,
        'cacheEstimate':
            'UTF-16 text payload plus two 256-slot reference arrays per retained chunk',
        'excludedFromEstimate': [
          'object and string headers',
          'map capacity/entries',
          'bounded observed-chunk-size metadata',
          'allocator/GC overhead',
          'old snapshots and incoming read buffers',
          'layout, rendering, native and repository caches',
        ],
        'source':
            'deterministic generated Hebrew with niqqud, Latin, blank lines, headings and inline-note markup',
        'budgetScope':
            'one simulated coordinator; current Otzaria windows share one engine/isolate, so a shared text-cache coordinator is feasible; this is not a process RSS cap',
        'fullWarmupComparison':
            'potential after full warming of N independently active unsplit readers; current split panes already disable warming',
        'trace':
            '23 moves: forward, reverse, four far jumps; both 96-line and 768-line requested steps are tested, with shorter steps for the 2000-line book',
        'prefetch':
            'same maximum of four extra chunks: symmetric 2+2 or directional 3 ahead +1 behind',
        'admission':
            'all visible chunks pinned; remaining estimated capacity shared equally; first unknown candidate can be read and rejected; previously observed sizes prevent an identical read when it still cannot fit',
        'observedSizeCache': {
          'maxEntriesPerReader': _observedSizeLimit,
          'eviction': 'oldest read, refreshed only by an actual source read',
          'sourceRevision':
              'immutable generated source; production would need invalidation when source content changes',
          'metadataBytesIncludedInBudget': false,
        },
        'pinnedGranularity':
            'whole fetched 256-line chunks intersecting a contiguous viewport; this can retain more payload than the actual visible lines',
        'pinStress':
            '200 source lines (the current continuous-paragraph line cap) containing one synthetic oversized source line; a line-count cap does not bound UTF-16 payload',
        'selectionPins':
            'not modeled: selection, notes, and plugin request pins may be disjoint; retainRange only models a contiguous interval',
        'productionIntegrationBlockers': [
          'plugin_bridge_adapter._loadPluginTextSection reads open-reader state.content without checking loadedLineFlags',
          'buildPageShapeNotesColumn derives inline note rows/ordinals from currently retained content',
          'cross-line selection and note creation need source-range pinning or explicit repository reads',
        ],
        'noLatencyOrFrameTimeClaim': true,
      },
      'fullSourceAccounting': full,
      'cases': cases,
      'admissionRetryRegression': admissionRetry,
      'pinnedOverflow': pinnedOverflow,
      'fullContentOperation': {
        'linesMaterializedOutsideViewportCache': sourceLines.length,
        'estimatedPayloadAndOneListBytes':
            chars * 2 + sourceLines.length * _referenceBytes,
        'lengthChecksumMatched': true,
        'exactPerLineEqualityVerified': true,
        'viewportSnapshotUnchanged': true,
        'independentOfViewportCacheBudget': true,
      },
    }),
  );
}
