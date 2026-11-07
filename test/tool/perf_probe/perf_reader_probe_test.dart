import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/perf_reader_probe.dart';

void main() {
  Map<String, dynamic> trace(List<Map<String, Object?>> calls) => {
    'traceEvents': [
      {
        'name': 'reader.phase.begin',
        'ph': 'i',
        'ts': 0,
        'args': {'id': 'test'},
      },
      ...calls,
      {
        'name': 'reader.phase.end',
        'ph': 'i',
        'ts': 1000,
        'args': {'id': 'test'},
      },
    ],
  };
  Map<String, Object?> event(
    String phase,
    int at, {
    String? name,
    int? duration,
    int thread = 1,
  }) => {
    'ph': phase,
    'ts': at,
    'pid': 1,
    'tid': thread,
    'name': ?name,
    'dur': ?duration,
  };

  test(
    'nested pipeline owners count once and unrelated spans retain pairing',
    () {
      final result = readerPipelineMeasurements(
        trace([
          event('B', 100, name: 'LAYOUT (root)'),
          event('B', 120, name: 'LAYOUT'),
          event('B', 130, name: 'unrelated work'),
          event('E', 140),
          event('E', 160),
          event('E', 200),
          event('X', 210, name: 'PAINT (root)', duration: 30),
          event('X', 215, name: 'PAINT', duration: 10),
          event('X', 300, name: 'LAYOUT', duration: 50),
          event('X', 310, name: 'LAYOUT', duration: 10),
        ]),
        'test',
        0,
        1000,
      );
      expect(result['unavailableReason'], isNull);
      expect(result['layoutTotalMs'], 0.150);
      expect(result['paintTotalMs'], 0.030);
      expect(result['layoutIntervalsUs'], hasLength(2));
    },
  );

  test(
    'equal timestamps retain event order and threads remain independent',
    () {
      final result = readerPipelineMeasurements(
        trace([
          event('B', 100, name: 'LAYOUT (root)'),
          event('B', 100, name: 'unrelated work'),
          event('E', 110),
          event('E', 150),
          event('X', 100, name: 'LAYOUT', duration: 30, thread: 2),
          event('X', -10, name: 'PAINT', duration: 30),
          event('X', 995, name: 'PAINT', duration: 30),
        ]),
        'test',
        0,
        1000,
      );
      expect(result['layoutTotalMs'], 0.080);
      expect(result['layoutIntervalsUs'], hasLength(2));
      expect(result['paintTotalMs'], isNull);
    },
  );

  test('missing markers or incomplete spans never become zero-cost layout', () {
    final missing = readerPipelineMeasurements(
      {
        'traceEvents': [
          event('X', 100, name: 'LAYOUT', duration: 30),
        ],
      },
      'test',
      0,
      1000,
    );
    expect(missing['unavailableReason'], contains('markers'));
    expect(missing['layoutTotalMs'], isNull);
    final incomplete = readerPipelineMeasurements(
      trace([
        event('B', 100, name: 'LAYOUT'),
        event('X', 200, name: 'PAINT', duration: 20),
      ]),
      'test',
      0,
      1000,
    );
    expect(incomplete['unavailableReason'], contains('incomplete'));
    expect(incomplete['paintTotalMs'], isNull);
    final empty = readerPipelineMeasurements(trace([]), 'test', 0, 1000);
    expect(empty['layoutTotalMs'], isNull);
    expect(empty['unavailableReason'], isNotNull);
  });
}
