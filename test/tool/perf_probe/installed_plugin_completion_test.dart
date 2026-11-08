import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';

import '../../../integration_test/support/installed_plugin_completion.dart';

FrameTiming _frame(int number, int buildEpochUs) => FrameTiming(
  vsyncStart: 1000,
  buildStart: 2000,
  buildFinish: 4000,
  rasterStart: 4500,
  rasterFinish: 9000,
  rasterFinishWallTime: buildEpochUs + 7000,
  frameNumber: number,
);

void main() {
  late Future<Map<String, dynamic>> driverResponse;
  late Directory directory;
  var driverReturned = false;
  var saved = false;
  // This observer runs after the binding's completion callback.
  tearDownAll(() async {
    final result = await driverResponse.timeout(const Duration(seconds: 5));
    final response = Response.fromJson(result['response']['message'] as String);
    expect(response.allTestsPassed, isTrue);
    expect(saved, isTrue);
    expect(
      jsonDecode(await File('${directory.path}/report.json').readAsString()),
      {
        'status': 'passed',
        'testFailures': <String>[],
      },
    );
    await directory.delete(recursive: true);
  });
  final binding = IntegrationTestWidgetsFlutterBinding();
  registerInstalledPluginReportFinalizer(binding, (passed) async {
    expect(driverReturned, isFalse);
    final releaseWrite = Completer<void>();
    Timer(const Duration(milliseconds: 50), () {
      expect(driverReturned, isFalse);
      releaseWrite.complete();
    });
    await releaseWrite.future;
    final report = {
      'status': passed ? 'passed' : 'failed',
      'testFailures': [
        for (final failure in binding.failureMethodsDetails) failure.details,
      ],
    };
    await File('${directory.path}/report.json').writeAsString(
      jsonEncode(report),
      flush: true,
    );
    saved = true;
    binding.reportData = report;
    expect(driverReturned, isFalse);
  });

  test('the driver completion waits for the final report flush', () async {
    directory = await Directory.systemTemp.createTemp('installed-completion-');
    driverResponse = binding.callback({'command': 'request_data'}).then((
      value,
    ) {
      driverReturned = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(driverReturned, isFalse);
  });

  test('a final report failure preserves the original test failure', () async {
    final original = Failure('scenario', 'original scenario failure');
    final failure = FileSystemException('report write failure');
    binding.results['scenario'] = original;
    try {
      await expectLater(
        finalizeInstalledPluginReport(binding, (passed) async {
          expect(passed, isFalse);
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(binding.failureMethodsDetails, [
        same(original),
        isA<Failure>().having(
          (value) => value.details,
          'details',
          contains('report write failure'),
        ),
      ]);
    } finally {
      binding.results.clear();
    }
  });

  test('a report-only failure makes the binding result fail', () async {
    final failure = FileSystemException('report-only failure');
    try {
      await expectLater(
        finalizeInstalledPluginReport(binding, (passed) async {
          expect(passed, isTrue);
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(
        binding.failureMethodsDetails.single.details,
        contains('report-only failure'),
      );
    } finally {
      binding.results.clear();
    }
  });

  test(
    'late timing batches are drained without extending the measured window',
    () async {
      final recorder = InstalledPluginFrameTimings(binding);
      var returned = false;
      try {
        binding.platformDispatcher.onReportTimings!([_frame(10, 100000)]);
        final measured = recorder
            .finish(
              startUs: 100000,
              endUs: 200000,
              lastFrameNumber: 12,
            )
            .then((value) {
              returned = true;
              return value;
            });
        await Future<void>.delayed(Duration.zero);
        expect(returned, isFalse);
        binding.platformDispatcher.onReportTimings!([_frame(11, 199999)]);
        await Future<void>.delayed(Duration.zero);
        expect(returned, isFalse);
        binding.platformDispatcher.onReportTimings!([
          _frame(12, 200000),
          _frame(13, 300000),
        ]);
        final result = await measured;
        expect(result['count'], 2);
        expect(result['lastFrameNumber'], 12);
        expect(result['deliveredThroughFrameNumber'], 13);
        expect(result['totalMs'], [8.0, 8.0]);
      } finally {
        recorder.dispose();
      }
    },
  );

  test(
    'an idle phase needs no extra frame or timer once delivery is complete',
    () async {
      final recorder = InstalledPluginFrameTimings(binding);
      try {
        binding.platformDispatcher.onReportTimings!([_frame(20, 99999)]);
        final result = await recorder.finish(
          startUs: 100000,
          endUs: 200000,
          lastFrameNumber: 20,
          timeout: Duration.zero,
        );
        expect(result['count'], 0);
        expect(result['unavailableReason'], isNotNull);
      } finally {
        recorder.dispose();
      }
    },
  );

  test('raster progress drains a fixed target beyond five total seconds', () {
    fakeAsync((clock) {
      final recorder = InstalledPluginFrameTimings(binding);
      Map<String, Object?>? result;
      Object? failure;
      try {
        binding.platformDispatcher.onReportTimings!([_frame(10, 99999)]);
        unawaited(
          recorder
              .finish(startUs: 100000, endUs: 200000, lastFrameNumber: 30)
              .then<void>(
                (value) => result = value,
                onError: (Object error) => failure = error,
              ),
        );
        clock.elapse(const Duration(seconds: 4));
        binding.platformDispatcher.onReportTimings!([_frame(20, 150000)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 4));
        expect(failure, isNull);
        expect(result, isNull);
        binding.platformDispatcher.onReportTimings!([
          _frame(31, 199999),
          _frame(32, 300000),
        ]);
        clock.flushMicrotasks();
        expect(failure, isNull);
        expect(result!['lastFrameNumber'], 30);
        expect(result!['deliveredThroughFrameNumber'], 32);
        expect(result!['count'], 2);
        expect(result!['totalMs'], [8.0, 8.0]);
      } finally {
        recorder.dispose();
      }
    });
  });

  test('duplicate and older timing batches cannot reset the stall timeout', () {
    fakeAsync((clock) {
      final recorder = InstalledPluginFrameTimings(binding);
      Object? failure;
      try {
        binding.platformDispatcher.onReportTimings!([_frame(20, 99999)]);
        unawaited(
          recorder
              .finish(startUs: 100000, endUs: 200000, lastFrameNumber: 30)
              .then<void>(
                (_) => fail('The target timing is still missing'),
                onError: (Object error) => failure = error,
              ),
        );
        clock.elapse(const Duration(seconds: 4));
        binding.platformDispatcher.onReportTimings!([
          _frame(20, 99999),
          _frame(19, 99998),
        ]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(failure, isA<TimeoutException>());
      } finally {
        recorder.dispose();
      }
    });
  });

  test('a drain fails five seconds after its last genuine progress', () {
    fakeAsync((clock) {
      final recorder = InstalledPluginFrameTimings(binding);
      Object? failure;
      try {
        binding.platformDispatcher.onReportTimings!([_frame(10, 99999)]);
        unawaited(
          recorder
              .finish(startUs: 100000, endUs: 200000, lastFrameNumber: 30)
              .then<void>(
                (_) => fail('The target timing is still missing'),
                onError: (Object error) => failure = error,
              ),
        );
        clock.elapse(const Duration(seconds: 4));
        binding.platformDispatcher.onReportTimings!([_frame(20, 150000)]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 4999));
        expect(failure, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        expect(failure, isA<TimeoutException>());
        expect(
          (failure as TimeoutException).message,
          contains('lastDelivered=20'),
        );
      } finally {
        recorder.dispose();
      }
    });
  });

  test(
    'a drain waits for the new fence instead of the phase-end frame',
    () async {
      final recorder = InstalledPluginFrameTimings(binding);
      try {
        binding.platformDispatcher.onReportTimings!([_frame(30, 120000)]);
        var requests = 0;
        final pending = recorder.finish(
          startUs: 100000,
          endUs: 200000,
          lastFrameNumber: 40,
          requestFrameAfterWindow: () {
            requests++;
            return Future.value(41);
          },
        );
        var completed = false;
        unawaited(pending.then((_) => completed = true));
        expect(requests, 1);
        binding.platformDispatcher.onReportTimings!([_frame(40, 180000)]);
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        binding.platformDispatcher.onReportTimings!([_frame(41, 250000)]);
        final result = await pending;
        expect(result['count'], 2);
        expect(result['lastFrameNumber'], 40);
        expect(result['fenceFrameNumber'], 41);
        expect(result['deliveredThroughFrameNumber'], 41);
      } finally {
        recorder.dispose();
      }
    },
  );

  test('a post-window frame request cannot hide a missing timing', () async {
    final recorder = InstalledPluginFrameTimings(binding);
    try {
      var requests = 0;
      await expectLater(
        recorder.finish(
          startUs: 100000,
          endUs: 200000,
          lastFrameNumber: 90,
          timeout: Duration.zero,
          requestFrameAfterWindow: () {
            requests++;
            return Future.value(91);
          },
        ),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'unreported phase frame',
            contains('target=91'),
          ),
        ),
      );
      expect(requests, 1);
    } finally {
      recorder.dispose();
    }
  });
  test('missing frame timing retains the observed drain evidence', () async {
    final recorder = InstalledPluginFrameTimings(binding);
    try {
      binding.platformDispatcher.onReportTimings!([_frame(20, 99999)]);
      await expectLater(
        recorder.finish(
          startUs: 100000,
          endUs: 200000,
          lastFrameNumber: 30,
          timeout: Duration.zero,
        ),
        throwsA(
          isA<TimeoutException>()
              .having((error) => error.duration, 'deadline', Duration.zero)
              .having(
                (error) => error.message,
                'drain evidence',
                allOf(
                  contains('target=30'),
                  contains('lastDelivered=20'),
                  contains('received=1'),
                  contains('inWindow=0'),
                  contains('dropped=0'),
                  contains('window=[100000, 200000)'),
                ),
              ),
        ),
      );
    } finally {
      recorder.dispose();
    }
  });

  test(
    'missing final timing fails and releases the drain for later phases',
    () async {
      final recorder = InstalledPluginFrameTimings(binding);
      try {
        await expectLater(
          recorder.finish(
            startUs: 100000,
            endUs: 200000,
            lastFrameNumber: 30,
            timeout: Duration.zero,
          ),
          throwsA(isA<TimeoutException>()),
        );
        binding.platformDispatcher.onReportTimings!([_frame(30, 199999)]);
        expect(
          (await recorder.finish(
            startUs: 100000,
            endUs: 200000,
            lastFrameNumber: 30,
          ))['count'],
          1,
        );
        await expectLater(
          recorder.finish(startUs: 0, endUs: 1, lastFrameNumber: -1),
          throwsStateError,
        );
      } finally {
        recorder.dispose();
      }
    },
  );
  test(
    'the drain remains exclusive while the fence is being submitted',
    () async {
      final recorder = InstalledPluginFrameTimings(binding);
      final fence = Completer<int>();
      try {
        binding.platformDispatcher.onReportTimings!([_frame(30, 120000)]);
        final pending = recorder.finish(
          startUs: 100000,
          endUs: 200000,
          lastFrameNumber: 30,
          requestFrameAfterWindow: () => fence.future,
        );
        await expectLater(
          recorder.finish(startUs: 100000, endUs: 200000, lastFrameNumber: 30),
          throwsStateError,
        );
        fence.complete(31);
        binding.platformDispatcher.onReportTimings!([_frame(31, 250000)]);
        expect((await pending)['fenceFrameNumber'], 31);
      } finally {
        recorder.dispose();
      }
    },
  );

  test('a blocked fence submission fails within the stall deadline', () {
    fakeAsync((clock) {
      final recorder = InstalledPluginFrameTimings(binding);
      final fence = Completer<int>();
      Object? failure;
      try {
        unawaited(
          recorder
              .finish(
                startUs: 100000,
                endUs: 200000,
                lastFrameNumber: 30,
                requestFrameAfterWindow: () => fence.future,
              )
              .then<void>(
                (_) => fail('No fence was submitted'),
                onError: (Object error) => failure = error,
              ),
        );
        clock.elapse(const Duration(milliseconds: 4999));
        expect(failure, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        expect(failure, isA<TimeoutException>());
      } finally {
        recorder.dispose();
      }
    });
  });

  for (final frameNumber in [-1, 30]) {
    test(
      'a non-fresh fence ID $frameNumber is fatal and releases the drain',
      () async {
        final recorder = InstalledPluginFrameTimings(binding);
        try {
          binding.platformDispatcher.onReportTimings!([_frame(30, 120000)]);
          await expectLater(
            recorder.finish(
              startUs: 100000,
              endUs: 200000,
              lastFrameNumber: 30,
              requestFrameAfterWindow: () async => frameNumber,
            ),
            throwsStateError,
          );
          expect(
            (await recorder.finish(
              startUs: 100000,
              endUs: 200000,
              lastFrameNumber: 30,
            ))['count'],
            1,
          );
        } finally {
          recorder.dispose();
        }
      },
    );
  }

  test('a fence paint failure remains fatal', () async {
    final recorder = InstalledPluginFrameTimings(binding);
    final error = StateError('Paint failed');
    try {
      await expectLater(
        recorder.finish(
          startUs: 100000,
          endUs: 200000,
          lastFrameNumber: 30,
          requestFrameAfterWindow: () async => throw error,
        ),
        throwsA(same(error)),
      );
    } finally {
      recorder.dispose();
    }
  });
}
