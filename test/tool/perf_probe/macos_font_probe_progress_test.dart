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
