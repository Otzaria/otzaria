/// Analysis is intentionally separate from collection. A successful harness
/// run is not evidence that WebKit did (or did not) suspend JavaScript.
Map<String, Object?> analyzeAppleQuietWindow({
  required Map<String, dynamic> before,
  required Map<String, dynamic> after,
  required Map<String, dynamic> driver,
  required int armStartMs,
  required int armEndMs,
}) {
  verifyAppleDocumentIdentity(before, after);
  final start = (driver['quietStartMs'] as num).toDouble();
  final end = (driver['quietEndMs'] as num).toDouble();
  final elapsed = (driver['quietElapsedMs'] as num).toDouble();
  final received = (driver['armReceivedMs'] as num).toDouble();
  final replied = (driver['armReplyMs'] as num).toDouble();
  if (end <= start ||
      elapsed <= 0 ||
      armEndMs < armStartMs ||
      received > replied ||
      replied > start) {
    throw StateError('Invalid quiet/coordination boundaries');
  }
  // A request/reply exchange bounds the difference between the device's wall
  // clock and the external driver's wall clock. No clock sync is assumed.
  final offsetMin = received - armEndMs;
  final offsetMax = replied - armStartMs;
  final uncertainty = offsetMax - offsetMin;
  if (uncertainty < 0) throw StateError('Invalid clock-offset interval');
  const edgeGuardMs = 1000.0;
  final first = before['readAt'] as Map;
  final last = after['readAt'] as Map;
  final wallDelta = (last['wallMs'] as num) - (first['wallMs'] as num);
  final monoDelta = (last['monoMs'] as num) - (first['monoMs'] as num);
  const clockToleranceMs = 250.0;
  var stableClock =
      (end - start - elapsed).abs() <= 250 &&
      (wallDelta - monoDelta).abs() <= clockToleranceMs &&
      uncertainty <= 1000;
  if (stableClock && (last['wallMs'] as num) + offsetMax < end) {
    throw StateError(
      'The page was read before the external quiet interval ended',
    );
  }
  var maxCallbackClockDriftMs = 0.0;
  final streams = <String, Object?>{};
  for (final name in ['interval', 'raf', 'localAsync']) {
    final stream = (after['streams'] as Map)[name] as Map;
    final callbacks = stream['callbacks'] as List;
    final dropped = stream['dropped'] as int;
    final total = stream['total'] as int;
    if (total != callbacks.length + dropped || dropped < 0) {
      throw StateError('Inconsistent bounded callback log: $name');
    }
    var inside = 0;
    var afterEnd = 0;
    var boundary = 0;
    var previousMono = double.negativeInfinity;
    final provenTimes = <double>[];
    for (final callback in callbacks.cast<Map>()) {
      final wall = (callback['wallMs'] as num).toDouble();
      final mono = (callback['monoMs'] as num).toDouble();
      if (!wall.isFinite ||
          !mono.isFinite ||
          mono < previousMono ||
          wall > (last['wallMs'] as num) + 1 ||
          mono > (last['monoMs'] as num) + 1) {
        throw StateError('Invalid/nonmonotonic callback timestamp: $name');
      }
      previousMono = mono;
      // Endpoint agreement does not detect a temporary clock step at execution.
      for (final anchor in [first, last]) {
        final drift =
            ((wall - (anchor['wallMs'] as num)) -
                    (mono - (anchor['monoMs'] as num)))
                .abs();
        if (drift > maxCallbackClockDriftMs) maxCallbackClockDriftMs = drift;
        if (drift > clockToleranceMs) stableClock = false;
      }
      final earliest = wall + offsetMin;
      final latest = wall + offsetMax;
      if (earliest > start + edgeGuardMs && latest < end - edgeGuardMs) {
        inside++;
        provenTimes.add(wall);
      } else if (earliest >= end) {
        afterEnd++;
      } else if (latest >= start) {
        boundary++;
      }
    }
    double? longestRecordedGap;
    for (var i = 1; i < provenTimes.length; i++) {
      final gap = provenTimes[i] - provenTimes[i - 1];
      if (longestRecordedGap == null || gap > longestRecordedGap) {
        longestRecordedGap = gap;
      }
    }
    streams[name] = {
      'callbacksInsideQuiet': inside,
      'callbacksAfterQuiet': afterEnd,
      'callbacksAtUncertainEdges': boundary,
      'totalSinceArm': total,
      'dropped': dropped,
      'longestRecordedInteriorGapMs': longestRecordedGap,
      'interpretation':
          'Callbacks are execution times, not scheduled deadlines. Zero does '
          'not prove engine suspension; a positive count does not prove '
          'continuous execution. Queued callbacks after resume are excluded.',
    };
  }
  // One contradictory stream makes the shared page clock uncertain for all.
  for (final stream in streams.values.cast<Map<String, Object?>>()) {
    stream['classification'] = !stableClock
        ? 'clockUncertain'
        : (stream['callbacksInsideQuiet'] as int) > 0
        ? 'callbacksObservedInsideQuiet'
        : (stream['dropped'] as int) > 0
        ? 'incompleteCallbackLog'
        : 'noCallbacksObservedInsideQuiet';
    if (!stableClock) {
      for (final key in [
        'callbacksInsideQuiet',
        'callbacksAfterQuiet',
        'callbacksAtUncertainEdges',
        'longestRecordedInteriorGapMs',
      ]) {
        stream[key] = null;
      }
    }
  }
  return {
    'clockStable': stableClock,
    'deviceToDriverOffsetMs': {'min': offsetMin, 'max': offsetMax},
    'clockUncertaintyMs': uncertainty,
    'edgeGuardMs': edgeGuardMs,
    'clockToleranceMs': clockToleranceMs,
    'maxCallbackClockDriftMs': maxCallbackClockDriftMs,
    'deviceWallMinusMonotonicDeltaMs': wallDelta - monoDelta,
    'driverWallMinusMonotonicDeltaMs': end - start - elapsed,
    'lateReadAfterQuietMs': (last['wallMs'] as num) + offsetMin - end,
    'streams': streams,
    'engineSuspension':
        'unavailable: public metadata is not a suspension query',
  };
}

void verifyAppleDocumentIdentity(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  for (final key in [
    'documentToken',
    'stateCanary',
    'timeOrigin',
    'bootCount',
    'phase',
  ]) {
    if (before[key] == null || before[key] != after[key]) {
      throw StateError('The document/boot changed across observations: $key');
    }
  }
  if (after['ready'] != true || (after['errors'] as List).isNotEmpty) {
    throw StateError('Fixture SDK readiness or JavaScript error failure');
  }
}

typedef AppleActivityBoundary = ({
  Map<String, dynamic> identity,
  Map<String, dynamic> document,
});

void verifyAppleVisibilityRoundTrip(
  AppleActivityBoundary beforeHide,
  AppleActivityBoundary whileHidden,
  AppleActivityBoundary afterShow,
) {
  for (final observation in [whileHidden, afterShow]) {
    verifyAppleRuntimeIdentity(beforeHide.identity, observation.identity);
    verifyAppleDocumentIdentity(beforeHide.document, observation.document);
  }
}

void verifyAppleRuntimeIdentity(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  for (final key in ['hostPid', 'appBootToken', 'controllerToken']) {
    if (before[key] == null || before[key] != after[key]) {
      throw StateError('Runtime identity changed/unavailable: $key');
    }
  }
}
