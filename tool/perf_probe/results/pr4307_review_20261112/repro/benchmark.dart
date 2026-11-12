import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'chunked_list.dart';
import 'content_line_changes.dart';

part 'engine_sources.dart';
part 'consumer_sources.dart';

typedef BookContentRangeChunk = ({
  int startLine,
  int totalLines,
  List<String> lines,
});
typedef Emitter<T> = void Function(T);
typedef _CountChunk = ({List<String> lines, List<bool>? loaded});
typedef _CountResult = ({Int32List counts, int chars, int loaded});

const _releaseContentMinLines = 2000;
final _combining = RegExp(r'\p{M}', unicode: true);
int sink = 0;
Object? keepAlive;
List<TextBookLoaded> protectedFixtures = [];

// These reject unsupported fixtures instead of pretending to model HTML work.
class notes {
  static String stripInlineNotes(String text) {
    if (text.contains('<') || text.contains('&') || text.contains('footnote')) {
      throw StateError('Only plain text is supported by this microbenchmark');
    }
    return text;
  }
}

class html {
  static dynamic parseFragment(String text) => throw StateError('HTML fixture');
}

String removeHtmlTags(String text) => throw StateError('HTML fixture');

class TextBook {
  final String title;
  const TextBook(this.title);
}

class BookContentRange {
  final int startLine;
  final int totalLines;
  final List<String> lines;
  BookContentRange(this.startLine, this.totalLines, this.lines);
  int get endLine => startLine + lines.length - 1;
}

class TextBookState {}

class ApplyFullBookContent {
  final String bookTitle;
  final List<String> content;
  ApplyFullBookContent(this.content, [this.bookTitle = 'fixture']);
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class TextBookLoaded extends TextBookState {
  final TextBook book;
  final List<String> content;
  final List<bool> loadedLineFlags;
  final int contentVersion;
  final List<int> visibleIndices;
  final ContentLineChanges? contentChanges;
  TextBookLoaded(
    this.content,
    this.loadedLineFlags, {
    this.book = const TextBook('fixture'),
    this.contentVersion = 0,
    this.visibleIndices = const [0],
    this.contentChanges,
  });
  TextBookLoaded copyWith({
    List<String>? content,
    List<bool>? loadedLineFlags,
    int? contentVersion,
    ContentLineChanges? contentChanges,
  }) => TextBookLoaded(
    content ?? this.content,
    loadedLineFlags ?? this.loadedLineFlags,
    book: book,
    contentVersion: contentVersion ?? this.contentVersion,
    visibleIndices: visibleIndices,
    contentChanges: contentChanges ?? this.contentChanges,
  );
}

abstract class Engine {
  TextBookState state;
  List<bool> _loadedContentFlags;
  bool _supportsContentRangeLoading = true;
  bool _inlineNotesFullScanDone = false;
  List<Object> _loadedContentRanges = const [];
  int keepStart = 0;
  int keepEnd = 0;
  int coverage = 0;
  Engine(TextBookLoaded snapshot)
    : state = snapshot,
      _loadedContentFlags = snapshot.loadedLineFlags;
  void _ensureLoadedContentTrackingBook(TextBook book) {}
  void _markLoadedContentRange(
    TextBook book,
    int first,
    int last, {
    int? totalLines,
  }) {
    coverage ^= first ^ last ^ (totalLines ?? 0);
  }

  ({int startLine, int endLine}) _calculateContentWindow(
    TextBookLoaded state,
    List<int> indices,
  ) => (startLine: keepStart, endLine: keepEnd);
  int _fullContentLength(BookContentRange range) =>
      max(range.totalLines, range.endLine + 1);
  TextBookLoaded _withInlineNotesCommentator(
    TextBookLoaded state, {
    Iterable<String>? scanOnly,
  }) {
    // Common, data-dependent consumption; note parsing itself is out of scope.
    var count = 0;
    if (scanOnly != null) {
      for (final line in scanOnly) {
        count += line.length;
      }
    }
    sink ^= count;
    return state;
  }

  void _applyContentRanges(
    String bookTitle,
    List<BookContentRangeChunk> ranges,
    Emitter<TextBookState> emit,
  );
  void _releaseContentOutsideWindow(
    TextBookLoaded state,
    Emitter<TextBookState> emit,
  );
  void _setLoadedContentFlags(TextBook book, List<bool> flags);
  void _onApplyFullBookContent(
    ApplyFullBookContent event,
    Emitter<TextBookState> emit,
  );
  List<String> _contentWithAppliedRange(BookContentRange range);
  List<bool> _loadedContentFlagsWithAppliedRange(BookContentRange range);
  TextBookLoaded apply(List<BookContentRangeChunk> ranges) {
    _applyContentRanges('fixture', ranges, (next) {
      state = next;
    });
    sink ^= coverage;
    return state as TextBookLoaded;
  }

  TextBookLoaded evict(int start, int end) {
    keepStart = start;
    keepEnd = end;
    _releaseContentOutsideWindow(state as TextBookLoaded, (next) {
      state = next;
    });
    sink ^= coverage ^ _loadedContentRanges.length;
    return state as TextBookLoaded;
  }

  TextBookLoaded initialize(int length, int start, List<String> lines) {
    final range = BookContentRange(start, length, lines);
    final content = _contentWithAppliedRange(range);
    _setLoadedContentFlags(
      const TextBook('fixture'),
      _loadedContentFlagsWithAppliedRange(range),
    );
    final result = TextBookLoaded(content, _loadedContentFlags);
    state = result;
    return result;
  }

  TextBookLoaded fullContent(List<String> full) {
    _onApplyFullBookContent(ApplyFullBookContent(full), (next) {
      state = next;
    });
    sink ^= _inlineNotesFullScanDone ? 1 : 0;
    return state as TextBookLoaded;
  }
}

final pool = List<String>.generate(
  1024,
  (i) =>
      'line-${i.toString().padLeft(4, '0')} ' + 'plain text '.padRight(91, 'x'),
  growable: false,
);
final edited = List<String>.generate(
  640,
  (i) =>
      'edit-${i.toString().padLeft(4, '0')} ' +
      'changed text '.padRight(91, 'y'),
  growable: false,
);

TextBookLoaded fixture(int length, bool chunked, {bool full = false}) {
  final content = List<String>.filled(length, '');
  final flags = List<bool>.filled(length, false);
  final resident = full ? length : min(length, 5120);
  for (var i = 0; i < resident; i++) {
    content[i] = pool[i % pool.length];
    flags[i] = true;
  }
  return TextBookLoaded(
    chunked ? ChunkedList.from(content, defaultValue: '') : content,
    chunked
        ? ChunkedList.from(flags, defaultValue: false)
        : List<bool>.unmodifiable(flags),
  );
}

Engine engine(bool candidate, TextBookLoaded state) =>
    candidate ? CandidateEngine(state) : BaselineEngine(state);
TextBookLoaded emptyState() => TextBookLoaded(const [], const []);

class Workload {
  final String name;
  final Object? Function(bool candidate) operation;
  final int operations;
  final String scope;
  Workload(
    this.name,
    this.operation, {
    this.operations = 1,
    this.scope = 'synchronous production list work',
  });
}

List<Workload> workloads(int length) {
  final flatSparse = fixture(length, false);
  final chunkSparse = fixture(length, true);
  final flatFull = fixture(length, false, full: true);
  final chunkFull = fixture(length, true, full: true);
  protectedFixtures = [flatSparse, chunkSparse, flatFull, chunkFull];
  final start = min(length - 640, 1280);
  final edits = [(startLine: start, totalLines: length, lines: edited)];
  final unchanged = [
    (
      startLine: start,
      totalLines: length,
      lines: flatFull.content.sublist(start, start + 640),
    ),
  ];
  final windowStart = min(length - 381, 1200);
  final full = flatFull.content;
  final initial = pool.take(261).toList(growable: false);
  final scanLength = min(length, 5120);
  final smallFlat = fixture(scanLength, false, full: true);
  final smallChunk = fixture(scanLength, true, full: true);
  final longPlain = List<String>.filled(scanLength, 'z' * 1024);
  final longFlags = List<bool>.unmodifiable(
    List<bool>.filled(scanLength, true),
  );
  final longChunk = ChunkedList.from(longPlain, defaultValue: '');
  final longChunkFlags = ChunkedList.from(longFlags, defaultValue: false);
  const worker =
      'production count body; worker CPU only, excludes isolate transfer and UI';
  return [
    Workload(
      'initial_partial_261',
      (c) => engine(c, emptyState()).initialize(length, 0, initial),
    ),
    Workload(
      'changed_range_sparse',
      (c) => engine(c, c ? chunkSparse : flatSparse).apply(edits),
    ),
    Workload(
      'changed_range_full_ready',
      (c) => engine(c, c ? chunkFull : flatFull).apply(edits),
    ),
    Workload(
      'changed_range_from_flat_full',
      (c) => engine(c, flatFull).apply(edits),
    ),
    Workload(
      'noop_flat_full',
      (c) => engine(c, flatFull).apply(unchanged),
      operations: 32,
    ),
    Workload(
      'noop_full_ready',
      (c) => engine(c, c ? chunkFull : flatFull).apply(unchanged),
      operations: 32,
    ),
    Workload(
      'noop_sparse_ready',
      (c) => engine(c, c ? chunkSparse : flatSparse).apply(unchanged),
      operations: 32,
    ),
    Workload(
      'evict_from_flat_full',
      (c) => engine(c, flatFull).evict(windowStart, windowStart + 380),
    ),
    Workload(
      'evict_full_ready',
      (c) => engine(
        c,
        c ? chunkFull : flatFull,
      ).evict(windowStart, windowStart + 380),
    ),
    Workload('count_sparse', (c) {
      final s = c ? chunkSparse : flatSparse;
      return _countChunks([(lines: s.content, loaded: s.loadedLineFlags)]);
    }, scope: worker),
    Workload('count_full', (c) {
      final s = c ? chunkFull : flatFull;
      return _countChunks([(lines: s.content, loaded: s.loadedLineFlags)]);
    }, scope: worker),
    Workload(
      'raw_chars_under_limit_window',
      (c) {
        final s = c ? smallChunk : smallFlat;
        return _rawCharactersExceed([
          (lines: s.content, loaded: s.loadedLineFlags),
        ], 1024 * 1024);
      },
      operations: 16,
      scope: 'production preflight only for a range shorter than10000; exact1MiB cutoff',
    ),
    Workload(
      'raw_chars_early_exit_window',
      (c) => _rawCharactersExceed([
        (
          lines: c ? longChunk : longPlain,
          loaded: c ? longChunkFlags : longFlags,
        ),
      ], 1024 * 1024),
      operations: 16,
      scope: 'production preflight shorter than10000, exits at1MiB',
    ),
    Workload('partial_warm_full_edit_hide_sequence', (c) {
      final e = engine(c, emptyState());
      e.initialize(length, 0, initial);
      final count = min(length, 5120);
      final ranges = <BookContentRangeChunk>[];
      for (var i = 0; i < count; i += 640) {
        ranges.add((
          startLine: i,
          totalLines: length,
          lines: full.sublist(i, min(i + 640, count)),
        ));
      }
      e.apply(ranges);
      e.fullContent(full);
      e.apply(edits);
      return e.evict(windowStart, windowStart + 380);
    }),
  ];
}

int checksum(Object? value) {
  if (value is TextBookLoaded) {
    var sum = value.contentVersion;
    for (var i = 0; i < value.content.length; i++) {
      sum =
          ((sum * 31) ^
              value.content[i].hashCode ^
              i ^
              (value.loadedLineFlags[i] ? 1 : 0)) &
          0x3fffffff;
    }
    return sum;
  }
  if (value is _CountResult) {
    var sum = value.chars + value.loaded;
    for (final n in value.counts) {
      sum += n;
    }
    return sum;
  }
  if (value is bool) return value ? 1 : 0;
  throw StateError('Unknown result ${value.runtimeType}');
}

void verify(Workload work) {
  final a = work.operation(false), b = work.operation(true);
  if (checksum(a) != checksum(b)) throw StateError('Mismatch in ${work.name}');
  if (a is TextBookLoaded && b is TextBookLoaded) {
    if (a.content.length != b.content.length)
      throw StateError('Length mismatch');
    for (var i = 0; i < a.content.length; i++) {
      if (a.content[i] != b.content[i] ||
          a.loadedLineFlags[i] != b.loadedLineFlags[i])
        throw StateError('${work.name} differs at $i');
    }
  }
}

void main(List<String> args) {
  final processIndex = args.isEmpty ? 0 : int.parse(args[0]);
  final samples = args.length < 2 ? 8 : int.parse(args[1]);
  if (samples < 2 || samples.isOdd)
    throw ArgumentError('samples must be a positive even integer >=2');
  stdout.writeln(
    jsonEncode({
      'metadata': true,
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'process_index': processIndex,
      'samples_per_side_per_case': samples,
      'warmups_per_side': 4,
      'unit': 'microseconds_per_operation',
      'order': 'ABBA blocks, BAAB for odd process; paired in same AOT binary',
      'sizes': [2000, 50000, 1000000],
      'scope':
          'List work only; not application latency, UI frame timing or I/O',
    }),
  );
  for (final length in [2000, 50000, 1000000]) {
    final all = workloads(length);
    final sourceChecksums = protectedFixtures
        .map(checksum)
        .toList(growable: false);
    for (final w in all) {
      verify(w);
      for (var i = 0; i < 4; i++) {
        keepAlive = w.operation(false);
        keepAlive = w.operation(true);
      }
      final raw = <String, List<double>>{'baseline': [], 'candidate': []};
      var checksumSum = 0;
      for (var block = 0; block < samples ~/ 2; block++) {
        final order = (processIndex + block).isEven
            ? [false, true, true, false]
            : [true, false, false, true];
        for (final candidate in order) {
          final watch = Stopwatch()..start();
          for (var i = 0; i < w.operations; i++) {
            keepAlive = w.operation(candidate);
          }
          watch.stop();
          final time =
              watch.elapsedTicks * 1000000 / watch.frequency / w.operations;
          raw[candidate ? 'candidate' : 'baseline']!.add(time);
          checksumSum ^= checksum(keepAlive);
        }
      }
      stdout.writeln(
        jsonEncode({
          'case': w.name,
          'lines': length,
          'process_index': processIndex,
          'operations_per_sample': w.operations,
          'samples_us': raw,
          'scope': w.scope,
          'checksum': checksumSum,
          'all_outputs_equal_before_timing': true,
        }),
      );
    }
    for (var i = 0; i < protectedFixtures.length; i++) {
      if (checksum(protectedFixtures[i]) != sourceChecksums[i])
        throw StateError('A protected source snapshot was mutated');
    }
    stdout.writeln(
      jsonEncode({
        'source_snapshot_checks_passed': true,
        'lines': length,
        'process_index': processIndex,
      }),
    );
  }
  stderr.writeln('sink=$sink keep=${keepAlive.runtimeType}');
}
