import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:otzaria/migration/services/external_book_import.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:path/path.dart' as p;

/// Opt-in probe for issue #4532. Run on the affected Windows machine and
/// storage; fast CI disks cannot reproduce a 93-second kernel I/O stall.
///
/// This measures the book conversion + TOC preparation phase (not DB writes).
/// Both modes execute serially in one worker isolate; only the file read
/// differs. The synchronous baseline reconstructs the pre-#4542 behavior.
Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (final arg in args) {
    final equal = arg.indexOf('=');
    if (!arg.startsWith('--') || equal < 3) {
      _usage();
      exitCode = 64;
      return;
    }
    options[arg.substring(0, equal)] = arg.substring(equal + 1);
  }

  final folder = options['--folder'];
  final file = options['--file'];
  final passes = int.tryParse(options['--runs'] ?? '1') ?? 0;
  final maxFiles = int.tryParse(options['--max-files'] ?? '20000') ?? 0;
  final maxFileMiB = int.tryParse(options['--max-file-mib'] ?? '128') ?? 0;
  if ((folder == null) == (file == null) ||
      passes < 1 ||
      maxFiles < 1 ||
      maxFileMiB < 1) {
    _usage();
    exitCode = 64;
    return;
  }

  final paths = await _collectPaths(
    folder: folder,
    file: file,
    maxFiles: maxFiles,
    maxBytes: maxFileMiB * 1024 * 1024,
  );
  if (paths.isEmpty) {
    stderr.writeln('No supported textual books found.');
    exitCode = 66;
    return;
  }
  stdout.writeln(jsonEncode({
    'probe': 'personal-books-safepoint-4532',
    'textualFiles': paths.length,
    'maxFileMiB': maxFileMiB,
    'runs': passes,
    'note': 'Run on the same slow disk; this does not time SQLite writes.',
  }));

  for (var pass = 0; pass < passes; pass++) {
    final modes = pass.isEven ? <bool>[false, true] : <bool>[true, false];
    final comparable = <Map<String, int>>[];
    for (final asynchronous in modes) {
      final measurement = await _measure(paths, asynchronous);
      stdout.writeln(jsonEncode({'pass': pass + 1, ...measurement}));
      comparable.add(measurement['work'] as Map<String, int>);
    }
    final a = comparable[0];
    final b = comparable[1];
    if (a['processed'] != b['processed'] ||
        a['failed'] != b['failed'] ||
        a['characters'] != b['characters'] ||
        a['tocEntries'] != b['tocEntries'] ||
        a['fingerprint'] != b['fingerprint']) {
      stderr.writeln('ERROR: synchronous and asynchronous results differ.');
      exitCode = 1;
    }
  }
}

void _usage() {
  stderr.writeln(
    'Run using flutter test test/tool/perf_probe/external_books_gc_probe_test.dart '
    'with --dart-define=OTZARIA_GC_PROBE_FOLDER=<books-dir> or '
    '--dart-define=OTZARIA_GC_PROBE_FILE=<book-path>; '
    'see tool/perf_probe/EXTERNAL_BOOKS_GC_PROBE.md.',
  );
}

Future<List<String>> _collectPaths({
  required String? folder,
  required String? file,
  required int maxFiles,
  required int maxBytes,
}) async {
  final paths = <String>[];

  Future<void> accept(File candidate) async {
    final format = documentFormatFromExtension(candidate.path);
    if (format == null || !format.isTextual || !format.isProductionSupported) {
      return;
    }
    try {
      final stat = await candidate.stat();
      if (stat.type == FileSystemEntityType.file &&
          stat.size <= maxBytes &&
          stat.size >= 0) {
        paths.add(candidate.path);
      }
    } on FileSystemException {
      // A disappearing book is handled as a failed item during the scan.
    }
  }

  if (file != null) {
    await accept(File(file));
  } else {
    await for (final entity
        in Directory(folder!).list(recursive: true, followLinks: false)) {
      if (entity is File) await accept(entity);
      if (paths.length >= maxFiles) break;
    }
  }
  paths.sort();
  if (paths.length > maxFiles) return paths.take(maxFiles).toList();
  return paths;
}

Future<Map<String, Object>> _measure(
  List<String> paths,
  bool asynchronous,
) async {
  const cadence = Duration(milliseconds: 16);
  final clock = Stopwatch()..start();
  var previousUs = clock.elapsedMicroseconds;
  var maximumGapMs = 0.0;
  var peakRss = ProcessInfo.currentRss;
  var tickCount = 0;
  final gaps = <double>[];

  // Bounded GC pressure on the caller (UI-like) isolate. This increases the
  // chance of hitting an isolate-group safepoint during slow worker I/O.
  final retained = <Uint8List>[];
  final timer = Timer.periodic(cadence, (_) {
    final nowUs = clock.elapsedMicroseconds;
    final gapMs = (nowUs - previousUs) / 1000.0;
    previousUs = nowUs;
    maximumGapMs = math.max(maximumGapMs, gapMs);
    tickCount++;
    if (gaps.length < 50000) gaps.add(gapMs);
    peakRss = math.max(peakRss, ProcessInfo.currentRss);
    retained.add(Uint8List(128 * 1024));
    if (retained.length > 32) retained.removeAt(0);
  });

  late final Map<String, int> work;
  try {
    work = await Isolate.run(
      () => _prepareBatch(paths, asynchronous),
      debugName: asynchronous ? 'async-book-probe' : 'sync-book-probe',
    );
  } finally {
    // A stalled UI isolate may process the worker-completion message before
    // its overdue Timer callbacks. Include the tail interval explicitly, so
    // cancelling the timer cannot hide a last-second safepoint stall.
    final tailGapMs = (clock.elapsedMicroseconds - previousUs) / 1000.0;
    maximumGapMs = math.max(maximumGapMs, tailGapMs);
    if (gaps.length < 50000) gaps.add(tailGapMs);
    peakRss = math.max(peakRss, ProcessInfo.currentRss);
    timer.cancel();
    clock.stop();
  }

  gaps.sort();
  double percentile(double proportion) => gaps.isEmpty
      ? 0
      : gaps[((gaps.length - 1) * proportion).round()];

  return {
    'mode': asynchronous ? 'async-read' : 'sync-baseline',
    'elapsedMs': clock.elapsedMilliseconds,
    'uiHeartbeatCount': tickCount,
    'sampleCount': gaps.length,
    'samplesTruncated': tickCount > gaps.length,
    'p95HeartbeatGapMs': percentile(0.95),
    'p99HeartbeatGapMs': percentile(0.99),
    'maxHeartbeatGapMs': maximumGapMs,
    'peakProcessRssMiB': peakRss / (1024 * 1024),
    'work': work,
  };
}

Future<Map<String, int>> _prepareBatch(
  List<String> paths,
  bool asynchronous,
) async {
  var processed = 0;
  var failed = 0;
  var characters = 0;
  var tocEntries = 0;
  var fingerprint = 2166136261;

  // A single sequential worker mirrors _collectBookFilesRecursive. No
  // Future.wait, background tasks, unbounded task queues, or stored buffers.
  for (final path in paths) {
    final format = documentFormatFromExtension(path);
    if (format == null || !format.isTextual) continue;
    try {
      final content = asynchronous
          ? await convertDocumentFile(
              path,
              format: format,
              embedImages: false,
            )
          : convertDocumentBytesSync(
              File(path).readAsBytesSync(),
              p.basenameWithoutExtension(path),
              format: format,
              embedImages: false,
              path: path,
            );
      final toc = externalBookTocEntries(
        TocParser.parseEntriesFromContent(content),
      );
      processed++;
      characters += content.length;
      tocEntries += toc.length;
      // Fixed-work checksum: same strings and TOC on both paths should give
      // the same fingerprint without returning multi-MB strings to the UI.
      fingerprint = ((fingerprint * 16777619) ^
              content.length ^
              toc.length ^
              (content.isEmpty ? 0 : content.codeUnitAt(0)) ^
              (content.isEmpty
                  ? 0
                  : content.codeUnitAt(content.length ~/ 2)) ^
              (content.isEmpty
                  ? 0
                  : content.codeUnitAt(content.length - 1))) &
          0x7fffffff;
    } catch (_) {
      failed++;
    }
  }
  return {
    'processed': processed,
    'failed': failed,
    'characters': characters,
    'tocEntries': tocEntries,
    'fingerprint': fingerprint,
  };
}
