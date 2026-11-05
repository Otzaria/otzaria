import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

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
  });

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
