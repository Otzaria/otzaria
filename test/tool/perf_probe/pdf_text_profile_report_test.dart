import 'dart:convert';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/pdf_text_profile_report.dart';

Map<String, Object?> _report() => buildPdfTextProfileReport(
  configuration: {
    'pageNumbers': List.generate(17, (i) => i + 1),
    'documentPageCount': 17,
    'warmup': 1,
    'repetitions': 2,
    'normalizeHebrewText': true,
    'decodeLegacyHebrewText': true,
    'cache': {'maximumPages': 16, 'maximumBytes': 8 * 1024 * 1024},
    'queries': [
      {
        'id': 'word',
        'kind': 'literal',
        'source': 'שלום',
        'caseSensitive': false,
        'multiLine': false,
        'unicode': true,
        'dotAll': false,
      },
    ],
  },
  observations: [
    for (var iteration = 0; iteration < 3; iteration++)
      for (final phase in pdfTextProfilePhases)
        for (var page = 1; page <= 17; page++)
          {
            'iteration': iteration,
            'warmup': iteration == 0,
            'pageNumber': page,
            'phase': phase,
            'rawLoadUs': iteration == 0 ? 1000000 : iteration,
            'formatUs': phase == 'pipeline' ? 2 : null,
            'cacheLoadUs': phase == 'pipeline'
                ? null
                : (iteration == 0 ? 1000003 : iteration + 3),
            'matchingUs': 3,
            'rectsUs': 4,
            'rawLoadCalls': 1,
            'formatRawCalls': phase == 'pipeline' ? 1 : 0,
            'cachedPagesAfter': phase == 'pipeline' ? 0 : 16,
            'cachedBytesAfter': phase == 'pipeline' ? 0 : 4096,
            'parity': true,
            'textCharacters': 100,
            'characterRects': 100,
            'fragments': 20,
            'queries': [
              {'id': 'word', 'matches': 1, 'rects': 1},
            ],
            'textSha256': 'a' * 64,
            'geometrySha256': 'b' * 64,
            'matchesSha256': 'c' * 64,
          },
  ],
);

void main() {
  test(
    'aggregates complete measured sweeps, excluding warmup and unavailable phases',
    () {
      final report = _report();
      validatePdfTextProfileReport(report);
      final summary = report['summary'] as Map;
      expect((summary['pipeline'] as Map)['rawLoadUs'], {
        'count': 2,
        'min': 17.0,
        'mean': 25.5,
        'p50': 17.0,
        'p95': 34.0,
        'p99': 34.0,
        'max': 34.0,
      });
      expect((summary['pipeline'] as Map)['cacheLoadUs'], isNull);
      expect((summary['cacheRepeat'] as Map)['formatUs'], isNull);
      expect((summary['cacheRepeat'] as Map)['rawLoadCalls'], 34);
      final decoded = jsonDecode(jsonEncode(report)) as Map<String, Object?>;
      validatePdfTextProfileReport(decoded);
    },
  );

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing row': (r) => (r['observations'] as List).removeLast(),
    'duplicate row': (r) => r['observations'][1] = r['observations'][0],
    'wrong warmup': (r) => r['observations'][0]['warmup'] = false,
    'unmeasured format on cache': (r) => r['observations'][17]['formatUs'] = 0,
    'unmeasured cache on pipeline': (r) =>
        r['observations'][0]['cacheLoadUs'] = 0,
    'fabricated cache hit': (r) => r['observations'][34]['rawLoadCalls'] = 0,
    'second raw load while formatting': (r) =>
        r['observations'][0]['formatRawCalls'] = 2,
    'cache over page budget': (r) =>
        r['observations'][17]['cachedPagesAfter'] = 17,
    'cache over byte budget': (r) =>
        r['observations'][17]['cachedBytesAfter'] = 9 * 1024 * 1024,
    'negative time': (r) => r['observations'][0]['matchingUs'] = -1,
    'fractional time': (r) => r['observations'][0]['matchingUs'] = 1.5,
    'missing time': (r) => r['observations'][0]['matchingUs'] = null,
    'false parity': (r) => r['observations'][0]['parity'] = false,
    'changed text': (r) => r['observations'][34]['textSha256'] = 'd' * 64,
    'changed geometry': (r) =>
        r['observations'][34]['geometrySha256'] = 'd' * 64,
    'changed matches': (r) => r['observations'][34]['matchesSha256'] = 'd' * 64,
    'unknown query': (r) =>
        r['observations'][0]['queries'][0]['id'] = 'unknown',
    'missing query': (r) => r['observations'][0]['queries'] = [],
    'short digest': (r) => r['observations'][0]['textSha256'] = 'a',
    'unsupported protocol': (r) => r['protocolVersion'] = 2,
    'fractional protocol': (r) => r['protocolVersion'] = 1.0,
    'invented native split': (r) => r['rawLoadScope'] = 'native-only',
    'invented OS cold': (r) => r['cacheState'] = 'cold',
    'unsupported cache budget': (r) =>
        r['configuration']['cache']['maximumPages'] = 32,
    'missing normalization flags': (r) =>
        r['configuration'].remove('normalizeHebrewText'),
    'missing summary': (r) => r.remove('summary'),
    'forged summary': (r) => r['summary']['pipeline']['rawLoadUs']['p50'] = 0,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final report = jsonDecode(jsonEncode(_report())) as Map<String, dynamic>;
      entry.value(report);
      expect(() => validatePdfTextProfileReport(report), throwsFormatException);
    });
  }
}
