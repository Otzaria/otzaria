import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/perf_pdf_image_budget.dart';
import '../../../integration_test/support/perf_recorder.dart';

FrameTiming frame({required int buildEpochUs, int engineOrigin = 100000}) =>
    FrameTiming(
      vsyncStart: engineOrigin,
      buildStart: engineOrigin + 1000,
      buildFinish: engineOrigin + 3000,
      rasterStart: engineOrigin + 3500,
      rasterFinish: engineOrigin + 7000,
      rasterFinishWallTime: buildEpochUs + 6000,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('frame windows use engine wall timestamps, not callback arrival', () {
    final before = frame(buildEpochUs: 99999);
    final first = frame(buildEpochUs: 100000);
    final last = frame(buildEpochUs: 199999, engineOrigin: 9000000);
    final after = frame(buildEpochUs: 200000);
    final delayedBatch = [after, last, before, first];
    expect(frameBuildEpochUs(last), 199999);
    expect(framesInWindow(delayedBatch, 100000, 200000), [last, first]);
    expect(frameMeasurements([first]), {
      'count': 1,
      'buildMs': [2.0],
      'rasterMs': [3.5],
      'totalMs': [7.0],
    });
  });

  test(
    'an interval with no frames remains missing, not a zero-duration frame',
    () {
      final result = frameMeasurements([]);
      expect(result['count'], 0);
      expect(result['buildMs'], isEmpty);
      expect(result['unavailableReason'], isNotNull);
    },
  );

  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'perf-recorder-test-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('failed actions are persisted as failed and still propagate', () async {
    final file = File('${directory.path}/phases.jsonl');
    final recorder = PerfRecorder(file, binding, launchIndex: 4);
    final error = StateError('A real failure');
    try {
      await expectLater(
        recorder.phase('open', () async => throw error, sampleHeap: false),
        throwsA(same(error)),
      );
    } finally {
      await recorder.dispose();
    }
    final record =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(record['status'], 'failed');
    expect(record['error'], contains('A real failure'));
    expect(record['launchIndex'], 4);
    expect(record['heapBefore'], isNull);
    expect(record['heapUnavailableReason'], isNotNull);
    expect(record['imageBudgetBefore'], isNull);
    expect(record['imageBudgetAfter'], isNull);
    expect(record['imageBudgetUnavailableReason'], isNotNull);
  });

  test(
    'PDF budget samples use action boundaries, before the frame drain',
    () async {
      final budget = PdfImageCacheBudget(maximumBytes: 100);
      final pending = budget.tryReserve(60, keepNeeded: true)!;
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0)
        ..imageBudget = () => capturePdfImageBudget(budget);
      PdfImageCacheEntry? retained;
      Timer? release;
      try {
        await recorder.phase('render', () async {
          retained = pending.commit(retainedBytes: 40, onEvict: () {});
          release = Timer(
            const Duration(milliseconds: 5),
            () => retained!.dispose(),
          );
        }, sampleHeap: false);
        final record =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(record['imageBudgetBefore']['pendingBytes'], 60);
        expect(record['imageBudgetBefore']['speculativePendingBytes'], 60);
        expect(record['imageBudgetAfter']['retainedBytes'], 40);
        expect(record['imageBudgetAfter']['pendingBytes'], 0);
        expect(record['imageBudgetAfter']['speculativePendingBytes'], 0);
        expect(record['imageBudgetAfter']['processPeakEstimatedBytes'], 60);
        expect(budget.retainedBytes, 0);
        expect(budget.peakEstimatedBytes, 60);
      } finally {
        release?.cancel();
        retained?.dispose();
        pending.dispose();
        await recorder.dispose();
        budget.dispose();
      }
    },
  );

  test(
    'sampling does not evict pinned work, cancel reservations or reset peaks',
    () {
      final budget = PdfImageCacheBudget(maximumBytes: 50);
      final retained = budget
          .tryReserve(80, allowOverBudget: true)!
          .commit(
            retainedBytes: 60,
            onEvict: () => fail('Sampling must not evict an image.'),
            isPinned: true,
          )!;
      final pending = budget.tryReserve(
        20,
        allowOverBudget: true,
        keepNeeded: true,
      )!;
      try {
        final before = capturePdfImageBudget(budget);
        expect(before['retainedBytes'], 60);
        expect(before['pendingBytes'], 20);
        expect(before['speculativePendingBytes'], 20);
        expect(before['estimatedBytes'], 80);
        expect(before['processPeakEstimatedBytes'], 80);
        expect(retained.isDisposed, isFalse);
        retained.dispose();
        final closing = capturePdfImageBudget(budget);
        expect(closing['retainedBytes'], 0);
        expect(closing['pendingBytes'], 20);
        expect(closing['processPeakEstimatedBytes'], 80);
        pending.dispose();
        final closed = capturePdfImageBudget(budget);
        expect(closed['estimatedBytes'], 0);
        expect(closed['processPeakEstimatedBytes'], 80);
        expect(before['retainedBytes'], 60);
        expect(closing['pendingBytes'], 20);
      } finally {
        retained.dispose();
        pending.dispose();
        budget.dispose();
      }
    },
  );

  test('a failed action still records outstanding PDF work', () async {
    final budget = PdfImageCacheBudget(maximumBytes: 100);
    final pending = budget.tryReserve(50, keepNeeded: true)!;
    final file = File('${directory.path}/phases.jsonl');
    final recorder = PerfRecorder(file, binding, launchIndex: 0)
      ..imageBudget = () => capturePdfImageBudget(budget);
    try {
      await expectLater(
        recorder.phase(
          'failed',
          () async => throw StateError('render failed'),
          sampleHeap: false,
        ),
        throwsStateError,
      );
      final record =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(record['status'], 'failed');
      expect(record['imageBudgetAfter']['pendingBytes'], 50);
      expect(record['imageBudgetAfter']['speculativePendingBytes'], 50);
      expect(budget.pendingBytes, 50);
    } finally {
      pending.dispose();
      await recorder.dispose();
      budget.dispose();
    }
  });

  test(
    'a truncated passive observation is a failure, not faster idle',
    () async {
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0);
      try {
        await expectLater(
          recorder.phase(
            'idle',
            () async {},
            observationWindow: const Duration(seconds: 3),
            sampleHeap: false,
          ),
          throwsStateError,
        );
        final record =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(record['status'], 'failed');
        expect(record['measurementKind'], 'resource-observation');
        expect(record['observationWindowMs'], 3000);
        expect(record['error'], contains('before its fixed window'));
      } finally {
        await recorder.dispose();
      }
    },
  );

  test(
    'a completed passive observation preserves its requested window',
    () async {
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0);
      const window = Duration(milliseconds: 5);
      try {
        await recorder.phase(
          'idle',
          () => waitForPerfObservation(window),
          observationWindow: window,
          sampleHeap: false,
        );
        final record =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(record['status'], 'passed');
        expect(record['measurementKind'], 'resource-observation');
        expect(record['observationWindowMs'], 5);
        expect(record['durationMs'], greaterThanOrEqualTo(5));
      } finally {
        await recorder.dispose();
      }
    },
  );

  test(
    'an asynchronously captured application error fails its phase',
    () async {
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0);
      recorder.verifyAction = () => throw StateError('Captured widget error');
      try {
        await expectLater(
          recorder.phase('render', () async {}, sampleHeap: false),
          throwsStateError,
        );
      } finally {
        await recorder.dispose();
      }
      final record =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(record['status'], 'failed');
      expect(record['error'], contains('Captured widget error'));
    },
  );

  test(
    'warmup and explicit unavailable phases cannot masquerade as samples',
    () async {
      final file = File('${directory.path}/phases.jsonl');
      final recorder = PerfRecorder(file, binding, launchIndex: 0);
      try {
        await recorder.phase(
          'warm',
          () async {},
          warmup: true,
          iteration: 2,
          sampleHeap: false,
        );
        await recorder.phase(
          'unsupported',
          () async => throw const PerfSkipped('No device'),
          sampleHeap: false,
        );
      } finally {
        await recorder.dispose();
      }
      final records = (await file.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(records[0]['warmup'], isTrue);
      expect(records[0]['iteration'], 2);
      expect(records[1]['status'], 'skipped');
      expect(records[1]['reason'], 'No device');
    },
  );
}
