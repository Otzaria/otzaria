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
  Completer<void>? _delivered;

  void _onTimings(List<FrameTiming> frames) {
    final previousLastDelivered = _lastDelivered;
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
        _lastDelivered > previousLastDelivered) {
      delivered.complete();
    }
  }

  /// [timeout] מגביל היעדר התקדמות; יעד הפריים וחלון המדידה נשארים קבועים.
  /// מגבלת הזמן הכוללת של תרחיש הבדיקה ממשיכה לחול על ההמתנה.
  Future<Map<String, Object?>> finish({
    required int startUs,
    required int endUs,
    required int lastFrameNumber,
    Duration timeout = const Duration(seconds: 5),
    Future<int> Function()? requestFrameAfterWindow,
  }) async {
    if (lastFrameNumber < 0) {
      throw StateError('The engine frame number is unavailable.');
    }
    if (_delivered != null) {
      throw StateError('A frame timing drain is already in progress.');
    }
    _delivered = Completer<void>();
    try {
      final fenceFrameNumber = requestFrameAfterWindow == null
          ? null
          : await requestFrameAfterWindow().timeout(timeout);
      if (fenceFrameNumber != null && fenceFrameNumber <= lastFrameNumber) {
        throw StateError('The raster fence must submit a newer engine frame.');
      }
      final target = fenceFrameNumber ?? lastFrameNumber;
      while (_lastDelivered < target) {
        _delivered = Completer<void>();
        await _delivered!.future.timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException(
              'Frame timing drain incomplete: target=$target, '
              'lastDelivered=$_lastDelivered, received=${_frames.length + droppedFrames}, '
              'inWindow=${framesInWindow(_frames, startUs, endUs).length}, '
              'dropped=$droppedFrames, window=[$startUs, $endUs)',
              timeout,
            );
          },
        );
      }
      return {
        ...frameMeasurements(framesInWindow(_frames, startUs, endUs)),
        'lastFrameNumber': lastFrameNumber,
        'fenceFrameNumber': ?fenceFrameNumber,
        'deliveredThroughFrameNumber': _lastDelivered,
        'truncated': droppedFrames > 0,
        'attribution': 'build-start-wall-time',
      };
    } finally {
      _delivered = null;
    }
  }

  void dispose() => binding.removeTimingsCallback(_onTimings);
}

/// מגיש scene בפריים חדש אחרי שהפריים הנוכחי הסתיים, ומחזיר את מזההו.
Future<int> submitInstalledPluginFrameFence(
  SchedulerBinding binding, {
  required void Function() repaintViews,
  required int Function() frameNumber,
}) async {
  if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
    // Let any current-frame endOfFrame completer finish and clear first.
    await Future<void>.value();
  } else if (binding.schedulerPhase != SchedulerPhase.idle) {
    await binding.endOfFrame;
  }
  repaintViews();
  binding.scheduleFrame();
  await binding.endOfFrame;
  return frameNumber();
}
