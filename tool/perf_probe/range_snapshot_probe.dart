// Requires the repository package configuration (flutter pub get).
// dart --suppress-analytics compile exe tool/perf_probe/range_snapshot_probe.dart -o /tmp/range_probe
// /tmp/range_probe > /tmp/range_probe.jsonl
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:otzaria/text_book/models/chunked_list.dart';

typedef _Range = ({int start, List<String> lines});
int _sink = 0;
Object? _keepAlive;

class _Snapshot {
  final List<String> content;
  final List<bool> flags;
  final int version;
  _Snapshot(this.content, this.flags, [this.version = 0]);
}

final _payloads = List.generate(
  2,
  (version) => List.generate(
    640,
    (line) =>
        '$version:$line אָבְגּ דּהוז חטיכ למנס עפּצק רשת ${'אבּגד '.padRight(96, 'ט')}',
    growable: false,
  ),
  growable: false,
);

_Snapshot _empty(int length, bool paged) => paged
    ? _Snapshot(
        ChunkedList<String>.filled(length, ''),
        ChunkedList<bool>.filled(length, false),
      )
    : _Snapshot(
        List<String>.filled(length, ''),
        List<bool>.unmodifiable(List<bool>.filled(length, false)),
      );

List<_Range> _ranges(int length, int batch, int phase) {
  final count = min(length, 640 * batch);
  final start = max(0, length - count);
  return [
    for (var offset = 0; offset < count; offset += 640)
      (
        start: start + offset,
        lines: count - offset >= 640
            ? _payloads[phase]
            : _payloads[phase].sublist(0, count - offset),
      ),
  ];
}

// Matches the current range handler's list work, excluding notes, Bloc and I/O.
_Snapshot _flatApply(_Snapshot current, List<_Range> ranges) {
  final applicable = ranges.where((range) => range.lines.isNotEmpty).toList();
  if (applicable.isEmpty) return current;
  final content = List<String>.of(current.content);
  final flags = List<bool>.of(current.flags);
  var changed = false;
  for (final range in applicable) {
    final end = range.start + range.lines.length;
    if (content.length < end) {
      content.addAll(List<String>.filled(end - content.length, ''));
      changed = true;
    }
    if (flags.length < end) {
      flags.addAll(List<bool>.filled(end - flags.length, false));
      changed = true;
    }
    for (var offset = 0; offset < range.lines.length; offset++) {
      final index = range.start + offset;
      if (index >= 0 && index < content.length) {
        if (content[index] != range.lines[offset] || !flags[index]) {
          changed = true;
        }
        content[index] = range.lines[offset];
        flags[index] = true;
      }
    }
  }
  return changed
      ? _Snapshot(content, List<bool>.unmodifiable(flags), current.version + 1)
      : current;
}

_Snapshot _pagedApply(_Snapshot current, List<_Range> ranges) {
  final applicable = ranges.where((range) => range.lines.isNotEmpty).toList();
  if (applicable.isEmpty) return current;
  final content = (current.content as ChunkedList<String>).edit();
  final flags = (current.flags as ChunkedList<bool>).edit();
  for (final range in applicable) {
    final end = range.start + range.lines.length;
    if (content.length < end) content.length = end;
    if (flags.length < end) flags.length = end;
    final start = max(0, range.start);
    if (start < end) {
      content.setRange(start, end, range.lines, start - range.start);
      flags.fillRange(start, end, true);
    }
  }
  final changed = content.changed || flags.changed;
  final nextContent = content.build();
  final nextFlags = flags.build();
  return changed
      ? _Snapshot(nextContent, nextFlags, current.version + 1)
      : current;
}

// Mirrors production's conversion-before-change-check path, including a flat
// snapshot returned unchanged when every incoming value was already loaded.
_Snapshot _pagedApplyWithConversion(
  _Snapshot current,
  List<_Range> ranges, {
  bool preflightFlat = false,
}) {
  final applicable = ranges.where((range) => range.lines.isNotEmpty).toList();
  if (applicable.isEmpty) return current;
  if (preflightFlat &&
      (current.content is! ChunkedList<String> ||
          current.flags is! ChunkedList<bool>) &&
      current.flags.length >= current.content.length &&
      applicable.every((range) {
        final end = range.start + range.lines.length;
        if (end > current.content.length) return false;
        for (var index = max(0, range.start); index < end; index++) {
          if (!current.flags[index] ||
              current.content[index] != range.lines[index - range.start]) {
            return false;
          }
        }
        return true;
      })) {
    return current;
  }
  final content = ChunkedList<String>.from(
    current.content,
    defaultValue: '',
  ).edit();
  final flags = ChunkedList<bool>.from(
    current.flags,
    defaultValue: false,
  ).edit();
  if (flags.length < content.length) flags.length = content.length;
  for (final range in applicable) {
    final end = range.start + range.lines.length;
    if (content.length < end) content.length = end;
    if (flags.length < end) flags.length = end;
    final start = max(0, range.start);
    if (start < end) {
      content.setRange(start, end, range.lines, start - range.start);
      flags.fillRange(start, end, true);
    }
  }
  if (!content.changed && !flags.changed) return current;
  return _Snapshot(content.build(), flags.build(), current.version + 1);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _emit(
  String name,
  int lines,
  int operations,
  List<double> samples, {
  Map<String, Object?> extra = const {},
}) {
  final rawSamples = List<double>.of(samples);
  samples.sort();
  double percentile(double p) => samples[((samples.length - 1) * p).round()];
  stdout.writeln(
    jsonEncode({
      'case': name,
      'lines': lines,
      'operations_per_sample': operations,
      'sample_count': samples.length,
      'unit': 'us_per_operation',
      'samples_us': rawSamples,
      'p50': percentile(.5),
      'p95': percentile(.95),
      'min': samples.first,
      'max': samples.last,
      ...extra,
    }),
  );
}

void _measure(
  String name,
  int lines,
  Object? Function() operation, {
  int sampleCount = 31,
  int operations = 1,
  Map<String, Object?> extra = const {},
}) {
  for (var i = 0; i < 10; i++) {
    _keepAlive = operation();
  }
  final samples = <double>[];
  for (var i = 0; i < sampleCount; i++) {
    final watch = Stopwatch()..start();
    for (var j = 0; j < operations; j++) {
      _keepAlive = operation();
    }
    watch.stop();
    samples.add(watch.elapsedTicks * 1000000 / watch.frequency / operations);
  }
  _emit(name, lines, operations, samples, extra: extra);
}

void _runSize(int length, int sampleCount) {
  final flat = _flatApply(_empty(length, false), _ranges(length, 1, 0));
  final paged = _pagedApply(_empty(length, true), _ranges(length, 1, 0));
  final operations = length < 10000 ? 8 : 1;
  _measure(
    'flat_content_copy',
    length,
    () => List<String>.of(flat.content),
    sampleCount: sampleCount,
    operations: operations,
  );
  _measure(
    'flat_flags_copy',
    length,
    () => List<bool>.of(flat.flags),
    sampleCount: sampleCount,
    operations: operations,
  );
  _measure(
    'flat_flags_freeze',
    length,
    () => List<bool>.unmodifiable(flat.flags),
    sampleCount: sampleCount,
    operations: operations,
  );
  for (final batch in [1, 8]) {
    final first = _ranges(length, batch, 0);
    final second = _ranges(length, batch, 1);
    for (final isPaged in [false, true]) {
      final apply = isPaged ? _pagedApply : _flatApply;
      final initial = _empty(length, isPaged);
      _measure(
        '${isPaged ? 'paged' : 'flat'}_load_fresh_${batch}x640',
        length,
        () => apply(initial, first),
        sampleCount: sampleCount,
        operations: operations,
        extra: {
          'resident_lines_before': 0,
          'patched_lines': min(length, 640 * batch),
          'flags_change': true,
        },
      );
      var current = apply(initial, first);
      var phase = 0;
      _measure(
        '${isPaged ? 'paged' : 'flat'}_apply_${batch}x640',
        length,
        () {
          phase ^= 1;
          current = apply(current, phase == 0 ? first : second);
          _sink += current.content[length - 1].length + current.version;
          return current;
        },
        sampleCount: sampleCount,
        operations: operations,
      );
      current = apply(current, first);
      _measure(
        '${isPaged ? 'paged' : 'flat'}_noop_${batch}x640',
        length,
        () => apply(current, first),
        sampleCount: sampleCount,
        operations: operations,
      );
    }
  }
  final newerFlat = _flatApply(flat, _ranges(length, 1, 1));
  final newerPaged = _pagedApply(paged, _ranges(length, 1, 1));
  _measure(
    'flat_list_equals_late_change',
    length,
    () => _listEquals(flat.content, newerFlat.content),
    sampleCount: sampleCount,
    operations: operations,
  );
  _measure(
    'paged_list_equals_late_change',
    length,
    () => _listEquals(paged.content, newerPaged.content),
    sampleCount: sampleCount,
    operations: operations,
  );
  _measure(
    'revision_first_late_change',
    length,
    () =>
        flat.version != newerFlat.version ||
        !_listEquals(flat.content, newerFlat.content),
    sampleCount: sampleCount,
    operations: 1000,
  );

  final indices = List.generate(
    65536,
    (i) => ((i * 1664525 + 1013904223) & 0x7fffffff) % length,
    growable: false,
  );
  for (final isPaged in [false, true]) {
    for (final full in [false, true]) {
      final base = full
          ? _Snapshot(
              List<String>.filled(length, _payloads[0][0]),
              List<bool>.filled(length, true),
            )
          : flat;
      final source = isPaged
          ? (full
                ? _Snapshot(
                    ChunkedList<String>.from(base.content, defaultValue: ''),
                    ChunkedList<bool>.from(base.flags, defaultValue: false),
                  )
                : paged)
          : base;
      final prefix =
          '${isPaged ? 'paged' : 'flat'}_${full ? 'full' : 'sparse'}';
      if (full) {
        var current = source;
        var phase = 0;
        final first = _ranges(length, 1, 0);
        final second = _ranges(length, 1, 1);
        final apply = isPaged ? _pagedApply : _flatApply;
        _measure(
          '${isPaged ? 'paged' : 'flat'}_full_resident_apply_1x640',
          length,
          () {
            phase ^= 1;
            current = apply(current, phase == 0 ? first : second);
            _sink += current.version;
            return current;
          },
          sampleCount: sampleCount,
          operations: operations,
          extra: {'resident_lines_before': length, 'flags_change': false},
        );
      }
      _measure(
        '${prefix}_random_65536',
        length,
        () {
          var sum = 0;
          for (final index in indices) {
            sum += source.content[index].length + (source.flags[index] ? 1 : 0);
          }
          _sink = sum;
          return sum;
        },
        sampleCount: min(15, sampleCount),
        extra: {'reads_per_operation': indices.length, 'includes_flags': true},
      );
      _measure(
        '${prefix}_viewport_128',
        length,
        () {
          var sum = 0;
          final start = max(0, length - 128);
          for (var index = start; index < length; index++) {
            sum += source.content[index].length + (source.flags[index] ? 1 : 0);
          }
          _sink = sum;
          return sum;
        },
        sampleCount: sampleCount,
        operations: 100,
        extra: {
          'reads_per_operation': min(128, length),
          'includes_flags': true,
        },
      );
      _measure(
        '${prefix}_scan_indexed',
        length,
        () {
          var sum = 0;
          for (var index = 0; index < source.content.length; index++) {
            sum += source.content[index].length + (source.flags[index] ? 1 : 0);
          }
          _sink = sum;
          return sum;
        },
        sampleCount: min(15, sampleCount),
        extra: {'reads_per_operation': length, 'includes_flags': true},
      );
      _measure(
        '${prefix}_scan_iterator',
        length,
        () {
          var sum = 0;
          for (final line in source.content) {
            sum += line.length;
          }
          _sink = sum;
          return sum;
        },
        sampleCount: min(15, sampleCount),
        extra: {'reads_per_operation': length, 'includes_flags': false},
      );
    }
  }
}

void _runFlatConversion(int length, int sampleCount) {
  final flat = _Snapshot(
    List<String>.filled(length, _payloads[0][0]),
    List<bool>.unmodifiable(List<bool>.filled(length, true)),
  );
  _Snapshot convert() => _Snapshot(
    ChunkedList<String>.from(flat.content, defaultValue: ''),
    ChunkedList<bool>.from(flat.flags, defaultValue: false),
  );
  final paged = convert();
  final range = _ranges(length, 1, 1);
  final start = max(0, length ~/ 2 - 320);
  final end = min(length, start + 640);
  _Snapshot retain(_Snapshot source) => _Snapshot(
    (source.content as ChunkedList<String>).retainRange(start, end),
    (source.flags as ChunkedList<bool>).retainRange(start, end),
  );
  _Snapshot flatRetain() => _Snapshot(
    List<String>.filled(length, '')..setRange(start, end, flat.content, start),
    List<bool>.unmodifiable(
      List<bool>.filled(length, false)..setRange(start, end, flat.flags, start),
    ),
  );
  final expected = flatRetain();
  final actual = retain(convert());
  if (!_listEquals(expected.content, actual.content) ||
      !_listEquals(expected.flags, actual.flags) ||
      !_listEquals(
        _flatApply(flat, range).content,
        _pagedApply(convert(), range).content,
      )) {
    throw StateError('Flat-to-chunked conversion changed source indices/text');
  }
  final cases = <String, _Snapshot Function()>{
    'flat_full_resident_from_flat_apply_1x640': () => _flatApply(flat, range),
    'paged_from_flat_full_apply_1x640': () => _pagedApply(convert(), range),
    'paged_convert_full_lists': convert,
    'flat_full_retain_viewport': flatRetain,
    'paged_from_flat_full_retain_viewport': () => retain(convert()),
    'paged_existing_full_retain_viewport': () => retain(paged),
  };
  for (final entry in cases.entries) {
    _measure(
      entry.key,
      length,
      entry.value,
      sampleCount: sampleCount,
      operations: length < 10000 ? 8 : 1,
      extra: {
        'resident_lines_before': length,
        'retained_or_patched_lines': 640,
        'source_is_flat': !entry.key.startsWith('paged_existing'),
        'conversion_included':
            entry.key.startsWith('paged_from_flat') ||
            entry.key == 'paged_convert_full_lists',
        'logical_indices_and_text_verified': true,
      },
    );
  }
}

void _runFlatNoop(
  int length,
  int sampleCount, {
  bool reverse = false,
  bool distinctEqualStrings = false,
}) {
  final flat = _Snapshot(
    List<String>.filled(length, _payloads[0][0]),
    List<bool>.unmodifiable(List<bool>.filled(length, true)),
    17,
  );
  final rangeLines = min(length, 640);
  final ranges = <_Range>[
    (
      start: length - rangeLines,
      lines: List<String>.generate(
        rangeLines,
        (_) => distinctEqualStrings
            ? String.fromCharCodes(_payloads[0][0].codeUnits)
            : _payloads[0][0],
        growable: false,
      ),
    ),
  ];
  if (distinctEqualStrings &&
      ranges.single.lines.any((line) => identical(line, flat.content.last))) {
    throw StateError(
      'The value-equal fixture must use distinct string objects',
    );
  }
  final paged = _Snapshot(
    ChunkedList<String>.from(flat.content, defaultValue: ''),
    ChunkedList<bool>.from(flat.flags, defaultValue: false),
    flat.version,
  );
  final cases = <String, ({_Snapshot source, _Snapshot Function() apply})>{
    'flat_from_flat_full_noop_1x640': (
      source: flat,
      apply: () => _flatApply(flat, ranges),
    ),
    'paged_from_flat_full_noop_without_preflight_1x640': (
      source: flat,
      apply: () => _pagedApplyWithConversion(flat, ranges),
    ),
    'paged_from_flat_full_noop_preflight_1x640': (
      source: flat,
      apply: () => _pagedApplyWithConversion(flat, ranges, preflightFlat: true),
    ),
    'paged_existing_full_noop_1x640': (
      source: paged,
      apply: () =>
          _pagedApplyWithConversion(paged, ranges, preflightFlat: true),
    ),
  };
  for (final entry in cases.entries) {
    final source = entry.value.source;
    for (var repeat = 0; repeat < 3; repeat++) {
      final result = entry.value.apply();
      if (!identical(result, source) ||
          result.version != 17 ||
          !_listEquals(result.content, flat.content) ||
          !_listEquals(result.flags, flat.flags)) {
        throw StateError('Full-resident no-op changed snapshot identity/data');
      }
    }
  }
  final entries = reverse ? cases.entries.toList().reversed : cases.entries;
  for (final entry in entries) {
    _measure(
      entry.key,
      length,
      entry.value.apply,
      sampleCount: sampleCount,
      operations: length < 10000 ? 8 : 1,
      extra: {
        'resident_lines_before': length,
        'range_lines': rangeLines,
        'changed_lines': 0,
        'distinct_equal_strings': distinctEqualStrings,
        'source_is_flat': identical(entry.value.source, flat),
        'returns_original_snapshot': true,
        'revision_unchanged': true,
        'conversion_included':
            entry.key == 'paged_from_flat_full_noop_without_preflight_1x640',
        'preflight_guard_enabled':
            entry.key == 'paged_from_flat_full_noop_preflight_1x640' ||
            entry.key == 'paged_existing_full_noop_1x640',
        'preflight_scan_performed':
            entry.key == 'paged_from_flat_full_noop_preflight_1x640',
        if (entry.key == 'flat_from_flat_full_noop_1x640')
          'copied_reference_slots': 2 * length,
        'scope':
            'identical range after full-content flat publication; repeated no-op keeps original source representation; excludes tracking metadata and Bloc emission',
      },
    );
  }
}

Future<void> _allocationWorker() async {
  final service = await Service.getInfo();
  stdout.writeln(
    jsonEncode({'ready': true, 'service_uri': service.serverUri?.toString()}),
  );
  var snapshots = <_Snapshot>[];
  var length = 0;
  var paged = false;
  var phase = 0;
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final command = jsonDecode(line) as Map<String, dynamic>;
    switch (command['op']) {
      case 'setup':
        length = command['lines'] as int;
        paged = command['paged'] as bool;
        final apply = paged ? _pagedApply : _flatApply;
        final batch = command['full_resident'] == true
            ? (length + 639) ~/ 640
            : 8;
        snapshots = List.generate(
          command['windows'] as int? ?? 1,
          (_) => apply(_empty(length, paged), _ranges(length, batch, 0)),
        );
        phase = 0;
      case 'apply':
        final apply = paged ? _pagedApply : _flatApply;
        final first = _ranges(length, 1, 0);
        final second = _ranges(length, 1, 1);
        for (var i = 0; i < (command['iterations'] as int); i++) {
          phase ^= 1;
          snapshots[0] = apply(snapshots[0], phase == 0 ? first : second);
        }
      case 'clear':
        snapshots = [];
      case 'exit':
        return;
    }
    _keepAlive = snapshots;
    stdout.writeln(
      jsonEncode({
        'done': command['op'],
        'checksum': snapshots.fold(
          0,
          (sum, x) => sum + x.content.length + x.version,
        ),
      }),
    );
  }
}

Future<void> main(List<String> args) async {
  if (args.contains('--allocation-worker')) return _allocationWorker();
  final sampleOption = args
      .where((a) => a.startsWith('--samples='))
      .firstOrNull;
  final samples = sampleOption == null
      ? 31
      : int.parse(sampleOption.split('=').last);
  final flatNoopOnly = args.contains('--flat-noop-only');
  final reverseCases = args.contains('--reverse-cases');
  final distinctEqualStrings = args.contains('--distinct-equal-strings');
  stdout.writeln(
    jsonEncode({
      'metadata': true,
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'processors': Platform.numberOfProcessors,
      'chunk_length': ChunkedList.chunkLength,
      'samples': samples,
      'sizes': [2000, 50000, 1000000],
      'case_set': flatNoopOnly
          ? 'flat_full_noop'
          : args.contains('--conversion-only')
          ? 'flat_conversion'
          : 'standard',
      if (flatNoopOnly) 'case_order': reverseCases ? 'reverse' : 'forward',
      'scope':
          'in-memory reference-array copies, immutable snapshot operations, and list reads; excludes layout, rendering, notes scanning, state construction and I/O',
      'payload': flatNoopOnly && distinctEqualStrings
          ? 'preallocated equal Hebrew strings with combining marks; source and incoming string identities differ; string allocation excluded'
          : 'preallocated Hebrew combining marks; same string references reused; string allocation excluded',
    }),
  );
  for (final size in [2000, 50000, 1000000]) {
    if (flatNoopOnly) {
      _runFlatNoop(
        size,
        samples,
        reverse: reverseCases,
        distinctEqualStrings: distinctEqualStrings,
      );
    } else if (args.contains('--conversion-only')) {
      _runFlatConversion(size, samples);
    } else {
      _runSize(size, samples);
    }
  }
  stdout.writeln(
    jsonEncode({
      'done': true,
      'sink': _sink,
      'alive': _keepAlive != null,
      'rss': ProcessInfo.currentRss,
      'max_rss': ProcessInfo.maxRss,
    }),
  );
}
