import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:vm_service/vm_service.dart' show IsolateRef, VmService;
import 'package:vm_service/vm_service_io.dart';

class PerfSkipped implements Exception {
  const PerfSkipped(this.reason);
  final String reason;
}

String perfOption(String name, String fallback) =>
    Platform.environment[name] ?? fallback;

String get perfBuildMode =>
    kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

/// שיוך לפי תחילת בניית הפריים, גם כשה-engine מדווח אותו אחרי סיום השלב.
int frameBuildEpochUs(FrameTiming frame) =>
    frame.timestampInMicroseconds(FramePhase.rasterFinishWallTime) -
    (frame.timestampInMicroseconds(FramePhase.rasterFinish) -
        frame.timestampInMicroseconds(FramePhase.buildStart));

List<FrameTiming> framesInWindow(
  Iterable<FrameTiming> frames,
  int startUs,
  int endUs,
) => frames.where((frame) {
  final at = frameBuildEpochUs(frame);
  return at >= startUs && at < endUs;
}).toList();

Map<String, Object?> frameMeasurements(List<FrameTiming> frames) => {
  'count': frames.length,
  'buildMs': [
    for (final frame in frames) frame.buildDuration.inMicroseconds / 1000,
  ],
  'rasterMs': [
    for (final frame in frames) frame.rasterDuration.inMicroseconds / 1000,
  ],
  'totalMs': [
    for (final frame in frames) frame.totalSpan.inMicroseconds / 1000,
  ],
  if (frames.isEmpty)
    'unavailableReason': 'No frame began inside the measured interval.',
};

class PerfRecorder {
  PerfRecorder(this.file, this.binding, {required this.launchIndex})
    : _sink = file.openWrite() {
    binding.addTimingsCallback(_onTimings);
  }

  final File file;
  final SchedulerBinding binding;
  final int launchIndex;
  final IOSink _sink;
  final _frames = <FrameTiming>[];
  final PerfHeapSampler heap = PerfHeapSampler();
  Map<String, Object?> Function()? counters;
  void Function()? verifyAction;
  bool _collecting = false;
  int _droppedFrames = 0;

  void _onTimings(List<FrameTiming> frames) {
    if (!_collecting) {
      return;
    }
    const limit = 20000;
    final available = limit - _frames.length;
    if (frames.length > available) {
      _droppedFrames += frames.length - available;
    }
    _frames.addAll(frames.take(available));
  }

  void write(Map<String, Object?> record) =>
      _sink.writeln(jsonEncode({'launchIndex': launchIndex, ...record}));

  Future<void> phase(
    String name,
    Future<void> Function() body, {
    int iteration = 0,
    bool warmup = false,
    Map<String, Object?>? details,
    bool sampleHeap = true,
  }) async {
    if (_collecting) {
      throw StateError('Nested performance phases are not supported.');
    }
    final heapBefore = sampleHeap ? await heap.sample() : null;
    final countersBefore = counters?.call();
    _frames.clear();
    _droppedFrames = 0;
    _collecting = true;
    final rssStart = ProcessInfo.currentRss;
    var rssPeak = rssStart;
    final rssTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > rssPeak) {
        rssPeak = rss;
      }
    });
    final startUs = DateTime.now().microsecondsSinceEpoch;
    final clock = Stopwatch()..start();
    Object? failure;
    StackTrace? failureStack;
    var status = 'passed';
    String? reason;
    try {
      await body();
    } on PerfSkipped catch (error) {
      status = 'skipped';
      reason = error.reason;
    } catch (error, stack) {
      status = 'failed';
      failure = error;
      failureStack = stack;
    }
    clock.stop();
    final endUs = DateTime.now().microsecondsSinceEpoch;
    rssTimer.cancel();
    try {
      verifyAction?.call();
    } catch (error, stack) {
      status = 'failed';
      failure ??= error;
      failureStack ??= stack;
    }
    final rssEnd = ProcessInfo.currentRss;
    if (rssEnd > rssPeak) {
      rssPeak = rssEnd;
    }
    final countersAfter = counters?.call();
    final wallClockDriftUs = (endUs - startUs - clock.elapsedMicroseconds)
        .abs();
    if (wallClockDriftUs > 50000) {
      status = 'failed';
      failure ??= StateError(
        'Wall clock changed during the phase; resource/frame attribution is invalid.',
      );
      failureStack ??= StackTrace.current;
    }
    // Release batches timings about once a second. This drain is not latency.
    await Future<void>.delayed(
      Duration(milliseconds: kReleaseMode ? 1200 : 250),
    );
    _collecting = false;
    final frames = framesInWindow(_frames, startUs, endUs);
    final heapAfter = sampleHeap ? await heap.sample() : null;
    write({
      'type': 'phase',
      'name': name,
      'status': status,
      'warmup': warmup,
      'iteration': iteration,
      'startMs': startUs ~/ 1000,
      'endMs': endUs ~/ 1000,
      'durationMs': clock.elapsedMicroseconds / 1000,
      'reason': reason,
      if (failure != null) 'error': '$failure',
      'rssStartBytes': rssStart,
      'rssEndBytes': rssEnd,
      'rssPeakBytes': rssPeak,
      'frames': {
        ...frameMeasurements(frames),
        'truncated': _droppedFrames > 0,
        'droppedFrames': _droppedFrames,
        'attribution': 'build-start-wall-time',
      },
      'heapBefore': heapBefore,
      'heapAfter': heapAfter,
      if (heapBefore == null || heapAfter == null)
        'heapUnavailableReason': sampleHeap
            ? heap.unavailableReason
            : 'Disabled during startup.',
      'countersBefore': countersBefore,
      'countersAfter': countersAfter,
      'details': details,
    });
    await _sink.flush();
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  void skip(String name, String reason) => write({
    'type': 'phase',
    'name': name,
    'status': 'skipped',
    'warmup': false,
    'iteration': 0,
    'reason': reason,
  });

  Future<void> dispose() async {
    binding.removeTimingsCallback(_onTimings);
    await heap.dispose();
    await _sink.close();
  }
}

class PerfHeapSampler {
  VmService? _service;
  String? unavailableReason = 'VM service has not been connected.';

  Future<void> connect() async {
    if (kReleaseMode) {
      unavailableReason = 'Dart VM service is unavailable in release builds.';
      return;
    }
    try {
      final info = await developer.Service.getInfo().timeout(
        const Duration(seconds: 5),
      );
      final uri = info.serverUri;
      if (uri == null) {
        unavailableReason = 'This process has no Dart VM service endpoint.';
        return;
      }
      final ws = uri.replace(scheme: 'ws', path: '${uri.path}ws');
      _service = await vmServiceConnectUri(
        ws.toString(),
      ).timeout(const Duration(seconds: 5));
      unavailableReason = null;
    } catch (error) {
      unavailableReason = 'VM service connection failed: $error';
    }
  }

  Future<Map<String, Object?>?> sample() async {
    final service = _service;
    if (service == null) {
      return null;
    }
    try {
      final vm = await service.getVM().timeout(const Duration(seconds: 5));
      var usage = 0, capacity = 0, external = 0, isolates = 0;
      for (final isolate in vm.isolates ?? <IsolateRef>[]) {
        if (isolate.isSystemIsolate == true) {
          continue;
        }
        final id = isolate.id;
        if (id == null) {
          throw StateError('Application isolate has no id.');
        }
        final memory = await service
            .getMemoryUsage(id)
            .timeout(const Duration(seconds: 5));
        if (memory.heapUsage == null ||
            memory.heapCapacity == null ||
            memory.externalUsage == null) {
          throw StateError('Incomplete VM memory sample.');
        }
        usage += memory.heapUsage!;
        capacity += memory.heapCapacity!;
        external += memory.externalUsage!;
        isolates++;
      }
      if (isolates == 0) {
        throw StateError('No application isolates were sampled.');
      }
      return {
        'heapUsage': usage,
        'heapCapacity': capacity,
        'externalUsage': external,
        'isolateCount': isolates,
      };
    } catch (error) {
      unavailableReason =
          'Heap sample unavailable (isolate may have exited): $error';
      return null;
    }
  }

  Future<void> dispose() async => _service?.dispose();
}
