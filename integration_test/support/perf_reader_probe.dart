import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:path/path.dart' as p;

import 'perf_recorder.dart';

class PerfReaderProbe {
  PerfReaderProbe(this.binding, this.recorder)
    : _previousStatsEnabled = SmartTextRenderStats.enabled {
    SmartTextRenderStats.enabled = true;
  }

  final IntegrationTestWidgetsFlutterBinding binding;
  final PerfRecorder recorder;
  final bool _previousStatsEnabled;
  final _reads = <Map<String, Object?>>[];
  final _readers =
      <
        ({
          TextBookTab tab,
          ValueNotifier<ReadingPosition?> position,
          VoidCallback listener,
        })
      >[];
  Map<String, Object?>? _activePhase;
  String? _traceUnavailable = kProfileMode
      ? null
      : 'Layout/paint timeline capture requires a profile build.';
  int _sample = 0;
  int requestsStarted = 0;
  int pendingReads = 0;

  TextBookTab createTab(TextBook book) {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = TextBookBloc(
      repository: _MeasuredRepository(this),
      initialState: TextBookInitial.named(
        book,
        1,
        false,
        const [],
        splitedView: false,
        showPageShapeView: false,
      ),
      readingPosition: position,
    );
    final tab = TextBookTab(
      book: book,
      index: 1,
      commentators: const [],
      splitedView: false,
      showPageShapeView: false,
      blocOverride: bloc,
    );
    void forwardPosition() => position.value = tab.lines.position.value;
    tab.lines.position.addListener(forwardPosition);
    _readers.add((tab: tab, position: position, listener: forwardPosition));
    return tab;
  }

  Map<String, Object?> snapshot() {
    final reader = _readers.where((item) => !item.tab.bloc.isClosed).lastOrNull;
    final state = reader?.tab.bloc.state;
    return {
      'requestsStarted': requestsStarted,
      'pendingReads': pendingReads,
      if (state is TextBookLoaded) ...{
        'lines': state.content.length,
        'contentType': state.content.runtimeType.toString(),
        'flagsType': state.loadedLineFlags.runtimeType.toString(),
        'contentVersion': state.contentVersion,
      },
    };
  }

  Future<T> _read<T>(
    String operation,
    TextBook book,
    Future<T> Function() action,
    Map<String, Object?> Function(T) describe, {
    int? firstLine,
    int? lastLine,
  }) async {
    final phase = _activePhase;
    final requestId = requestsStarted++;
    pendingReads++;
    final start = developer.Timeline.now;
    final watch = Stopwatch()..start();
    late T result;
    String? error;
    try {
      return result = await action();
    } catch (failure) {
      error = failure.toString();
      rethrow;
    } finally {
      watch.stop();
      pendingReads--;
      _reads.add({
        'type': 'reader_repository_read',
        'requestId': requestId,
        'operation': operation,
        'book': book.title,
        'phase': phase,
        'firstLine': firstLine,
        'lastLine': lastLine,
        'startTimelineUs': start,
        'endTimelineUs': developer.Timeline.now,
        'durationUs': watch.elapsedMicroseconds,
        'status': error == null ? 'passed' : 'failed',
        'error': ?error,
        if (error == null) ...describe(result),
      });
    }
  }

  Future<void> phase(
    String name,
    Future<void> Function() action, {
    int iteration = 0,
    bool warmup = false,
    bool sampleHeap = true,
    bool requireNoContentReads = false,
    Map<String, Object?>? details,
  }) async {
    final id = 'reader_${_sample++}';
    Map<String, Object?>? before, after, smartText;
    var actionStarted = false, actionFailed = false;
    int? start, end;
    Map<String, dynamic>? trace;
    Future<void> run() async {
      actionStarted = true;
      try {
        await recorder.phase(
          name,
          () async {
            _activePhase = {
              'id': id,
              'name': name,
              'iteration': iteration,
              'warmup': warmup,
            };
            before = snapshot();
            SmartTextRenderStats.reset();
            start = developer.Timeline.now;
            developer.Timeline.instantSync(
              'reader.phase.begin',
              arguments: {'id': id},
            );
            final readsBefore = requestsStarted;
            try {
              if (requireNoContentReads && pendingReads != 0) {
                throw StateError(
                  'Steady reader phase started with pending content reads.',
                );
              }
              await action();
              if (requireNoContentReads && readsBefore != requestsStarted) {
                throw StateError(
                  'Content I/O occurred during a preloaded reader phase.',
                );
              }
            } finally {
              developer.Timeline.instantSync(
                'reader.phase.end',
                arguments: {'id': id},
              );
              end = developer.Timeline.now;
              smartText = SmartTextRenderStats.takeAndReset();
              after = snapshot();
              _activePhase = null;
            }
          },
          iteration: iteration,
          warmup: warmup,
          sampleHeap: sampleHeap,
          details: details,
        );
      } catch (_) {
        actionFailed = true;
        rethrow;
      }
    }

    try {
      if (_traceUnavailable != null) {
        await run();
      } else {
        try {
          trace = (await binding.traceTimeline(
            run,
            streams: const ['Dart', 'Embedder', 'GC'],
          )).toJson();
        } catch (error) {
          // An action failure must not become an unavailable metric or a retry.
          if (actionFailed) rethrow;
          _traceUnavailable = 'VM timeline unavailable: $error';
          if (!actionStarted) await run();
        }
      }
    } finally {
      String? traceFile;
      Map<String, Object?>? pipeline;
      if (trace != null) {
        traceFile = 'reader_trace_$id.json';
        await File(
          p.join(recorder.file.parent.path, traceFile),
        ).writeAsString(jsonEncode(trace));
        if (start != null && end != null) {
          pipeline = readerPipelineMeasurements(trace, id, start!, end!);
        }
      }
      for (final read in _reads) {
        recorder.write(read);
      }
      _reads.clear();
      recorder.write({
        'type': 'reader_phase',
        'id': id,
        'name': name,
        'iteration': iteration,
        'warmup': warmup,
        'startTimelineUs': start,
        'endTimelineUs': end,
        'before': before,
        'after': after,
        'smartText': smartText,
        'timelineFile': traceFile,
        'pipeline': pipeline,
        'timelineUnavailableReason':
            pipeline?['unavailableReason'] ??
            (trace == null
                ? _traceUnavailable ??
                      'The action failed before a trace was returned.'
                : null),
      });
    }
  }

  void releaseClosedReaders() {
    for (final reader
        in _readers.where((item) => item.tab.bloc.isClosed).toList()) {
      reader.tab.lines.position.removeListener(reader.listener);
      reader.position.dispose();
      _readers.remove(reader);
    }
  }

  void dispose() {
    for (final reader in _readers) {
      reader.tab.lines.position.removeListener(reader.listener);
      reader.position.dispose();
    }
    for (final read in _reads) {
      recorder.write(read);
    }
    _reads.clear();
    SmartTextRenderStats.enabled = _previousStatsEnabled;
  }
}

class _MeasuredRepository extends TextBookRepository {
  _MeasuredRepository(this.probe) : super(fileSystem: FileSystemData.instance);
  final PerfReaderProbe probe;

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) => probe._read(
    'getBookContentRange',
    book,
    () =>
        super.getBookContentRange(book, startLine: startLine, endLine: endLine),
    (range) => {
      'returnedLines': range?.lines.length,
      'totalLines': range?.totalLines,
    },
    firstLine: startLine,
    lastLine: endLine,
  );

  @override
  Future<String> getBookContent(TextBook book) => probe._read(
    'getBookContent',
    book,
    () => super.getBookContent(book),
    (text) => {'returnedUtf16Units': text.length},
  );
}

Map<String, Object?> readerPipelineMeasurements(
  Map<String, dynamic> trace,
  String id,
  int start,
  int end,
) {
  final events = (trace['traceEvents'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  bool hasMarker(String name) => events.any(
    (event) => event['name'] == name && (event['args'] as Map?)?['id'] == id,
  );
  if (!hasMarker('reader.phase.begin') || !hasMarker('reader.phase.end')) {
    return {
      'unavailableReason':
          'Missing phase markers; the timeline may be truncated.',
    };
  }
  final stacks = <String, List<Map>>{};
  final intervals = <String, Map<String, List<(num, num)>>>{
    'LAYOUT': {},
    'PAINT': {},
  };
  void add(Map event, num finish) {
    final at = event['ts'];
    final name = event['name'];
    if (at is! num ||
        name is! String ||
        at < start ||
        finish > end ||
        finish < at) {
      return;
    }
    final kind = name == 'LAYOUT' || name.startsWith('LAYOUT (')
        ? 'LAYOUT'
        : name == 'PAINT' || name.startsWith('PAINT (')
        ? 'PAINT'
        : null;
    if (kind != null) {
      (intervals[kind]!['${event['pid']}:${event['tid']}'] ??= []).add((
        at,
        finish,
      ));
    }
  }

  final ordered = events.indexed.toList()
    ..sort((a, b) {
      final time = ((a.$2['ts'] as num?) ?? 0).compareTo(
        (b.$2['ts'] as num?) ?? 0,
      );
      return time == 0 ? a.$1.compareTo(b.$1) : time;
    });
  for (final (_, event) in ordered) {
    final at = event['ts'];
    if (at is! num) continue;
    final stack = stacks.putIfAbsent(
      '${event['pid']}:${event['tid']}',
      () => [],
    );
    switch (event['ph']) {
      case 'B':
        stack.add(event);
      case 'E':
        if (stack.isNotEmpty) add(stack.removeLast(), at);
      case 'X':
        final duration = event['dur'];
        if (duration is num) add(event, at + duration);
    }
  }
  if (stacks.values.expand((stack) => stack).any((event) {
    final at = event['ts'];
    final name = event['name'];
    return at is num &&
        at >= start &&
        at <= end &&
        name is String &&
        (name.startsWith('LAYOUT') || name.startsWith('PAINT'));
  })) {
    return {
      'unavailableReason':
          'An incomplete layout/paint interval remains in the trace.',
    };
  }
  final result = <String, Object?>{};
  for (final kind in intervals.entries) {
    final merged = <Map<String, Object?>>[];
    num total = 0;
    for (final thread in kind.value.entries) {
      final spans = thread.value..sort((a, b) => a.$1.compareTo(b.$1));
      num? first, last;
      void flush() {
        if (first == null) return;
        merged.add({'thread': thread.key, 'startUs': first, 'endUs': last});
        total += last! - first;
      }

      for (final span in spans) {
        if (last == null || span.$1 > last) {
          flush();
          first = span.$1;
          last = span.$2;
        } else if (span.$2 > last) {
          last = span.$2;
        }
      }
      flush();
    }
    result['${kind.key.toLowerCase()}IntervalsUs'] = merged;
    result['${kind.key.toLowerCase()}TotalMs'] = merged.isEmpty
        ? null
        : total / 1000;
  }
  result['unavailableReason'] = intervals.values.every((value) => value.isEmpty)
      ? 'No complete layout/paint calls inside the action window.'
      : null;
  return result;
}
