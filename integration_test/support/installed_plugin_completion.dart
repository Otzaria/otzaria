import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';

import 'perf_recorder.dart';

void registerInstalledPluginReportFinalizer(
  IntegrationTestWidgetsFlutterBinding binding,
  Future<void> Function(bool passed) save,
) {
  // tearDownAll runs in reverse order, before the binding releases the driver.
  tearDownAll(() => finalizeInstalledPluginReport(binding, save));
}

Future<void> finalizeInstalledPluginReport(
  IntegrationTestWidgetsFlutterBinding binding,
  Future<void> Function(bool passed) save,
) async {
  try {
    await save(binding.failureMethodsDetails.isEmpty);
  } catch (error, stack) {
    binding.results['installed plugin final report'] = Failure(
      'installed plugin final report',
      '$error\n$stack',
    );
    rethrow;
  }
}

class InstalledPluginFrameTimings {
  InstalledPluginFrameTimings(this.binding) {
    binding.addTimingsCallback(_onTimings);
  }

  final SchedulerBinding binding;
  final _frames = <FrameTiming>[];
  var droppedFrames = 0;
  var _lastDelivered = -1;
  int? _target;
  Completer<void>? _delivered;

  void _onTimings(List<FrameTiming> frames) {
    for (final frame in frames) {
      if (_frames.length < 20000) {
        _frames.add(frame);
      } else {
        droppedFrames++;
      }
      if (frame.frameNumber > _lastDelivered) {
        _lastDelivered = frame.frameNumber;
      }
    }
    final delivered = _delivered;
    if (delivered != null &&
        !delivered.isCompleted &&
        _lastDelivered >= _target!) {
      delivered.complete();
    }
  }

  Future<Map<String, Object?>> finish({
    required int startUs,
    required int endUs,
    required int lastFrameNumber,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (lastFrameNumber < 0) {
      throw StateError('The engine frame number is unavailable.');
    }
    if (_delivered != null) {
      throw StateError('A frame timing drain is already in progress.');
    }
    if (_lastDelivered < lastFrameNumber) {
      _target = lastFrameNumber;
      _delivered = Completer<void>();
      try {
        await _delivered!.future.timeout(timeout);
      } finally {
        _delivered = null;
        _target = null;
      }
    }
    return {
      ...frameMeasurements(framesInWindow(_frames, startUs, endUs)),
      'lastFrameNumber': lastFrameNumber,
      'deliveredThroughFrameNumber': _lastDelivered,
      'truncated': droppedFrames > 0,
      'attribution': 'build-start-wall-time',
    };
  }

  void dispose() => binding.removeTimingsCallback(_onTimings);
}
