import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

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
}
