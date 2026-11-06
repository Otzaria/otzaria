import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

IntegrationTestWidgetsFlutterBinding initializeMacosFontProbeBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native resize and snapshot callbacks need frames between explicit pumps.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  return binding;
}

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
    report['disposed'] = true;
    for (final operation
        in report['operations']! as List<Map<String, Object?>>) {
      if (operation['status'] == 'pending') operation['status'] = 'disposed';
    }
    if (report['status'] == 'pending') report['status'] = 'disposed';
    record('disposed');
  }

  Object? _bounded(Object? value) => value is String && value.length > 2048
      ? '${value.substring(0, 2048)}… [truncated]'
      : value;
}

Future<T> pumpFontProbeUntil<T>(
  Future<T> future, {
  required Future<void> Function(Duration) pumpFrame,
  Future<void> Function()? start,
  Duration timeout = const Duration(seconds: 60),
}) async {
  T? value;
  Object? error;
  StackTrace? stack;
  var done = false;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stack = s;
      done = true;
    },
  );
  final watch = Stopwatch()..start();
  if (start != null) await start().timeout(timeout);
  while (!done && watch.elapsed < timeout) {
    await pumpFrame(
      const Duration(milliseconds: 100),
    ).timeout(timeout - watch.elapsed);
  }
  if (!done) throw TimeoutException('Font probe did not finish', timeout);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}
