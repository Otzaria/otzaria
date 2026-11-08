import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/macos_font_probe.dart';

void main() {
  test('a native operation is retained before its response', () async {
    final progress = FontProbeViewProgress(2)..mounted();
    final response = Completer<int>();
    final result = progress.observe('screenshot', () => response.future);
    final partial = jsonDecode(jsonEncode(progress.report)) as Map;
    expect(partial['status'], 'pending');
    expect(partial['index'], 2);
    expect((partial['operations'] as List).single['status'], 'pending');
    expect(progress.complete, throwsStateError);
    response.complete(4);
    expect(await result, 4);
    progress.complete();
    expect(progress.report['status'], 'completed');
  });

  test('a screenshot timeout stays incomplete after a late response', () async {
    final progress = FontProbeViewProgress(0)..mounted();
    final response = Completer<int>();
    await expectLater(
      progress.observe(
        'screenshot',
        () => response.future,
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
    response.complete(4);
    await pumpEventQueue();
    final operation = (progress.report['operations'] as List).single as Map;
    expect(operation['status'], 'timed-out');
    expect(operation['lateResponse'], isTrue);
    expect(progress.report['status'], 'failed');
    expect(progress.complete, throwsStateError);
  });

  test('a late native error does not replace the timeout failure', () async {
    final progress = FontProbeViewProgress(0)..mounted();
    final response = Completer<int>();
    await expectLater(
      progress.observe(
        'rendering',
        () => response.future,
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
    final originalFailure = progress.report['failure'];
    response.completeError(StateError('late failure'));
    await pumpEventQueue();
    final operation = (progress.report['operations'] as List).single as Map;
    expect(operation['status'], 'timed-out');
    expect(operation['lateError'], isTrue);
    expect(progress.report['failure'], same(originalFailure));
  });

  test(
    'disposal fences a pending native response and subsequent work',
    () async {
      final progress = FontProbeViewProgress(0)..mounted();
      final response = Completer<int>();
      final result = progress.observe('boot', () => response.future);
      final assertion = expectLater(result, throwsStateError);
      progress.dispose();
      response.complete(4);
      await assertion;
      final operation = (progress.report['operations'] as List).single as Map;
      expect(operation['status'], 'disposed');
      expect(operation['lateResponse'], isTrue);
      var called = false;
      await expectLater(
        progress.observe('screenshot', () async {
          called = true;
          return 4;
        }),
        throwsStateError,
      );
      expect(called, isFalse);
    },
  );

  test('an independent navigation failure fences pending work', () async {
    final progress = FontProbeViewProgress(0)..mounted();
    final response = Completer<int>();
    final result = progress.observe('rendering', () => response.future);
    final assertion = expectLater(result, throwsStateError);
    progress.fail(StateError('main-frame load failed'), StackTrace.current);
    response.complete(4);
    await assertion;
    final operation = (progress.report['operations'] as List).single as Map;
    expect(operation['status'], 'pending');
    expect(operation['lateResponse'], isTrue);
    expect(progress.report['status'], 'failed');
    expect(
      (progress.report['failure'] as Map)['error'],
      contains('main-frame'),
    );
  });

  test(
    'a completed view keeps serving a fresh survivor font until disposal',
    () async {
      final progress = FontProbeViewProgress(1)..mounted();
      expect(await progress.observe('rendering', () async => 4), 4);
      progress.complete();
      expect(progress.isActive, isTrue);
      expect(
        await progress.observe('fresh-survivor-font-load', () async => 8),
        8,
      );
      progress.dispose();
      expect(progress.isActive, isFalse);
      expect(progress.report['status'], 'completed');
      final operations = progress.report['operations'] as List;
      expect(
        operations.every((dynamic o) => o['status'] == 'completed'),
        isTrue,
      );
    },
  );

  test('synchronous native setup errors retain the failed operation', () async {
    final progress = FontProbeViewProgress(0)..mounted();
    await expectLater(
      progress.observe<int>('screenshot', () => throw StateError('native')),
      throwsStateError,
    );
    expect((progress.report['operations'] as List).single['status'], 'failed');
    expect(progress.report['status'], 'failed');
  });

  test('raw lifecycle diagnostics are bounded and report dropped events', () {
    final progress = FontProbeViewProgress(0);
    for (var i = 0; i < 300; i++) {
      progress.record('scheme-request', {'url': 'x' * 3000});
    }
    final events = progress.report['events'] as List;
    expect(events, hasLength(256));
    expect((events.first['url'] as String).length, lessThan(2100));
    expect(progress.report['droppedEvents'], 44);
  });

  test(
    'a failure snapshot is captured once without healing the failure',
    () async {
      final progress = FontProbeViewProgress(0)..mounted();
      progress.fail(StateError('rendering timed out'), StackTrace.current);
      final original = progress.report['failure'];
      var reads = 0;
      progress.registerFailureSnapshot(() async {
        reads++;
        return '{"renderingProgress":{"phase":"frame-1"}}';
      });
      await Future.wait([
        progress.captureFailureSnapshot(),
        progress.captureFailureSnapshot(),
      ]);
      final snapshot = progress.report['failureSnapshot'] as Map;
      expect(reads, 1);
      expect(snapshot['status'], 'captured');
      expect(snapshot['value']['renderingProgress']['phase'], 'frame-1');
      expect(progress.report['status'], 'failed');
      expect(progress.report['failure'], same(original));
      expect(progress.complete, throwsStateError);
    },
  );

  test(
    'snapshot timeout ignores a late response and preserves the error',
    () async {
      final progress = FontProbeViewProgress(0)..mounted();
      progress.fail(StateError('rendering timed out'), StackTrace.current);
      final original = progress.report['failure'];
      final response = Completer<String?>();
      progress.registerFailureSnapshot(() => response.future);
      await progress.captureFailureSnapshot(
        timeout: const Duration(milliseconds: 5),
      );
      final beforeLateResponse = jsonEncode(progress.report['failureSnapshot']);
      response.complete('{"renderingProgress":{"phase":"completed"}}');
      await pumpEventQueue();
      expect(
        jsonEncode(progress.report['failureSnapshot']),
        beforeLateResponse,
      );
      expect(
        (progress.report['failureSnapshot'] as Map)['status'],
        'timed-out',
      );
      expect(progress.report['failure'], same(original));
      expect(progress.report['status'], 'failed');
    },
  );

  test('snapshot native errors remain secondary and bounded', () async {
    for (final asynchronous in [false, true]) {
      final progress = FontProbeViewProgress(0)..mounted();
      progress.fail(StateError('original failure'), StackTrace.current);
      final original = progress.report['failure'];
      progress.registerFailureSnapshot(() {
        final error = StateError('x' * 3000);
        if (asynchronous) return Future.error(error);
        throw error;
      });
      await progress.captureFailureSnapshot();
      final snapshot = progress.report['failureSnapshot'] as Map;
      expect(snapshot['status'], 'failed');
      expect((snapshot['error'] as String).length, lessThan(2100));
      expect(progress.report['failure'], same(original));
    }
  });

  test('snapshot data must be a bounded UTF-8 JSON object', () async {
    for (final value in [
      null,
      '[]',
      'broken',
      jsonEncode({'large': 'א' * 9000}),
    ]) {
      final progress = FontProbeViewProgress(0)..mounted();
      progress.fail(StateError('original failure'), StackTrace.current);
      final original = progress.report['failure'];
      progress.registerFailureSnapshot(() async => value);
      await progress.captureFailureSnapshot();
      expect((progress.report['failureSnapshot'] as Map)['status'], 'failed');
      expect((progress.report['failureSnapshot'] as Map)['value'], isNull);
      expect(progress.report['failure'], same(original));
    }
  });

  test(
    'disposal fences snapshot dispatch and pending snapshot results',
    () async {
      final disposed = FontProbeViewProgress(0)..mounted();
      var reads = 0;
      disposed.registerFailureSnapshot(() async {
        reads++;
        return '{}';
      });
      disposed.dispose();
      await disposed.captureFailureSnapshot();
      expect(reads, 0);
      expect((disposed.report['failureSnapshot'] as Map)['status'], 'disposed');
      expect(
        () => disposed.registerFailureSnapshot(() async => '{}'),
        throwsStateError,
      );

      final pending = FontProbeViewProgress(1)..mounted();
      final response = Completer<String?>();
      pending.registerFailureSnapshot(() => response.future);
      final capture = pending.captureFailureSnapshot();
      pending.dispose();
      response.complete('{"renderingProgress":{"phase":"completed"}}');
      await capture;
      expect((pending.report['failureSnapshot'] as Map)['status'], 'disposed');
      expect((pending.report['failureSnapshot'] as Map)['value'], isNull);
    },
  );

  test(
    'unregistered views do not create a diagnostic native operation',
    () async {
      final progress = FontProbeViewProgress(0)..mounted();
      await progress.captureFailureSnapshot();
      expect(
        (progress.report['failureSnapshot'] as Map)['status'],
        'not-registered',
      );
      expect(progress.report['operations'], isEmpty);
    },
  );

  test(
    'a replacement snapshot callback fences an older pending result',
    () async {
      final progress = FontProbeViewProgress(0)..mounted();
      final response = Completer<String?>();
      progress.registerFailureSnapshot(() => response.future);
      final capture = progress.captureFailureSnapshot();
      progress.registerFailureSnapshot(() async => '{"owner":"new"}');
      response.complete('{"owner":"old"}');
      await capture;
      final snapshot = progress.report['failureSnapshot'] as Map;
      expect(snapshot['status'], 'replaced');
      expect(snapshot['value'], isNull);
    },
  );

  test(
    'all ten snapshot requests can wait within one concurrent budget',
    () async {
      final responses = List.generate(10, (_) => Completer<String?>());
      final views = List.generate(10, FontProbeViewProgress.new);
      var reads = 0;
      for (var i = 0; i < views.length; i++) {
        views[i].mounted();
        views[i].fail(StateError('batch failed'), StackTrace.current);
        views[i].registerFailureSnapshot(() {
          reads++;
          return responses[i].future;
        });
      }
      final capture = Future.wait(views.map((p) => p.captureFailureSnapshot()));
      expect(reads, 10);
      expect(
        views.every(
          (p) => (p.report['failureSnapshot'] as Map)['status'] == 'pending',
        ),
        isTrue,
      );
      for (final response in responses) {
        response.complete('{}');
      }
      await capture;
      expect(views.every((p) => p.report['status'] == 'failed'), isTrue);
      expect(
        views.every(
          (p) => (p.report['failureSnapshot'] as Map)['status'] == 'captured',
        ),
        isTrue,
      );
    },
  );

  for (final failed in [false, true]) {
    test(
      'disposal completion preserves a ${failed ? 'failed' : 'completed'} observation',
      () async {
        final progress = FontProbeViewProgress(0)..mounted();
        if (failed) {
          progress.fail(StateError('native failure'), StackTrace.current);
        } else {
          progress.complete();
        }
        var notified = false;
        unawaited(progress.whenDisposed.then((_) => notified = true));
        await pumpEventQueue();
        expect(notified, isFalse);
        progress.dispose();
        await progress.whenDisposed;
        expect(notified, isTrue);
        expect(progress.isActive, isFalse);
        expect(progress.report['disposed'], isTrue);
        expect(progress.report['status'], failed ? 'failed' : 'completed');
        progress.dispose();
        await progress.whenDisposed;
      },
    );
  }
}
