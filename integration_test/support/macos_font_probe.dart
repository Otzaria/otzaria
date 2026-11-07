import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

IntegrationTestWidgetsFlutterBinding initializeMacosFontProbeBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native resize and snapshot callbacks need frames between explicit pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  return binding;
}

const fontProbeFailureSnapshotJs = r'''
if (document.__otzariaFontDocumentId !== documentId || document.__otzariaFontBootAttempt !== owner) {
  return JSON.stringify({availability: 'stale-document'});
}
var progress = window.__otzariaFontProbeRendering;
var current = progress && progress.documentId === documentId && progress.owner === owner;
return JSON.stringify({
  availability: current ? 'captured' : 'trace-unavailable',
  capturedAtEpochMilliseconds: Date.now(),
  visibilityState: document.visibilityState, readyState: document.readyState,
  viewport: {width: innerWidth, height: innerHeight, dpr: devicePixelRatio},
  fontsStatus: document.fonts.status,
  faces: Array.from(document.fonts).slice(0, 16).map(f => ({family: f.family, weight: f.weight, status: f.status})),
  renderingProgress: current ? progress : null
});
''';

String buildFontProbeFailureSnapshotScript({
  required String? documentId,
  required String owner,
}) =>
    '(function(documentId, owner) { $fontProbeFailureSnapshotJs })'
    '(${jsonEncode(documentId)}, ${jsonEncode(owner)});';

class FontProbeViewProgress {
  FontProbeViewProgress(int index)
    : report = {
        'index': index,
        'status': 'pending',
        'events': <Map<String, Object?>>[],
        'operations': <Map<String, Object?>>[],
        'droppedEvents': 0,
      };

  final Map<String, Object?> report;
  final _clock = Stopwatch();
  final _disposal = Completer<void>();
  Future<String?> Function()? _failureSnapshot;
  Future<void>? _snapshotCapture;

  Future<void> get whenDisposed => _disposal.future;
  bool _disposed = false;

  bool get isActive => !_disposed && report['status'] != 'failed';

  int get elapsedMicroseconds => _clock.elapsedMicroseconds;

  void mounted() {
    _clock.start();
    record('widget-mounted');
  }

  void record(String event, [Map<String, Object?> details = const {}]) {
    final events = report['events']! as List<Map<String, Object?>>;
    if (events.length == 256) {
      report['droppedEvents'] = (report['droppedEvents']! as int) + 1;
      return;
    }
    events.add({
      'event': event,
      'elapsedMicroseconds': elapsedMicroseconds,
      ...details.map((key, value) => MapEntry(key, _bounded(value))),
    });
  }

  void fail(Object error, StackTrace stack) {
    if (report['status'] == 'failed') return;
    report['status'] = 'failed';
    report['failure'] = {
      'error': _bounded(error.toString()),
      'stack': _bounded(stack.toString().split('\n').take(16).join('\n')),
      'elapsedMicroseconds': elapsedMicroseconds,
    };
    record('failed');
  }

  void registerFailureSnapshot(Future<String?> Function() snapshot) {
    if (_disposed) throw StateError('Font probe view was disposed');
    _failureSnapshot = snapshot;
  }

  Future<void> captureFailureSnapshot({
    Duration timeout = const Duration(seconds: 2),
  }) => _snapshotCapture ??= _captureFailureSnapshot(timeout);

  Future<void> _captureFailureSnapshot(Duration timeout) async {
    final read = _failureSnapshot;
    final snapshot = <String, Object?>{
      'status': 'pending',
      'requestedMicroseconds': elapsedMicroseconds,
      'requestedAtEpochMilliseconds': DateTime.now().millisecondsSinceEpoch,
      'timeoutMilliseconds': timeout.inMilliseconds,
    };
    report['failureSnapshot'] = snapshot;
    if (_disposed || read == null) {
      snapshot['status'] = _disposed ? 'disposed' : 'not-registered';
      return;
    }
    try {
      final value = await Future<String?>.sync(read).timeout(timeout);
      if (_disposed || !identical(read, _failureSnapshot)) {
        snapshot['status'] = _disposed ? 'disposed' : 'replaced';
        return;
      }
      if (value == null || utf8.encode(value).length > 16 * 1024) {
        throw StateError('Font probe snapshot is missing or exceeds 16 KiB');
      }
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Font probe snapshot is not an object');
      }
      snapshot['value'] = decoded;
      snapshot['status'] = 'captured';
    } on TimeoutException {
      snapshot['status'] = 'timed-out';
    } catch (error) {
      snapshot['status'] = 'failed';
      snapshot['error'] = _bounded(error.toString());
    } finally {
      snapshot['finishedMicroseconds'] = elapsedMicroseconds;
    }
  }

  Future<T> observe<T>(
    String name,
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!isActive) throw StateError('Font probe view is no longer active');
    final observation = <String, Object?>{
      'name': name,
      'status': 'pending',
      'startedMicroseconds': elapsedMicroseconds,
      'timeoutMilliseconds': timeout.inMilliseconds,
    };
    (report['operations']! as List<Map<String, Object?>>).add(observation);
    record('$name-started');
    try {
      final response = Future<T>.sync(operation).then(
        (value) {
          observation['responseMicroseconds'] = elapsedMicroseconds;
          if (!isActive || observation['status'] != 'pending') {
            observation['lateResponse'] = true;
            throw StateError('$name completed after the observation ended');
          }
          observation['status'] = 'completed';
          record('$name-completed');
          return value;
        },
        onError: (Object error, StackTrace stack) {
          observation['error'] = _bounded(error.toString());
          if (observation['status'] == 'pending' && isActive) {
            observation['status'] = 'failed';
          } else {
            observation['lateError'] = true;
          }
          Error.throwWithStackTrace(error, stack);
        },
      );
      return await response.timeout(
        timeout,
        onTimeout: () {
          observation['status'] = 'timed-out';
          observation['timedOutMicroseconds'] = elapsedMicroseconds;
          throw TimeoutException('Font probe $name did not finish', timeout);
        },
      );
    } catch (error, stack) {
      fail(error, stack);
      rethrow;
    }
  }

  void complete() {
    final operations = report['operations']! as List<Map<String, Object?>>;
    if (!isActive || operations.any((o) => o['status'] != 'completed')) {
      throw StateError('An incomplete font probe cannot pass');
    }
    report['status'] = 'completed';
    record('completed');
  }

  void dispose() {
    _disposed = true;
    _failureSnapshot = null;
    report['disposed'] = true;
    for (final operation
        in report['operations']! as List<Map<String, Object?>>) {
      if (operation['status'] == 'pending') operation['status'] = 'disposed';
    }
    if (report['status'] == 'pending') report['status'] = 'disposed';
    record('disposed');
    if (!_disposal.isCompleted) _disposal.complete();
  }

  Object? _bounded(Object? value) => value is String && value.length > 2048
      ? '${value.substring(0, 2048)}… [truncated]'
      : value;
}
