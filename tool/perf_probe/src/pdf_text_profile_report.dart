import 'dart:convert';

import 'report.dart' show sampleDistribution;

const pdfTextProfileProtocolVersion = 1;
const pdfTextProfilePhases = ['pipeline', 'cacheFirst', 'cacheRepeat'];
const pdfTextProfileTimings = [
  'rawLoadUs',
  'formatUs',
  'cacheLoadUs',
  'matchingUs',
  'rectsUs',
];

/// מאמת דוח מלא; שלב חסר או parity שנכשל אינם מדידת הצלחה.
void validatePdfTextProfileReport(Map<String, Object?> report) {
  final expectedSummary = _validateAndSummarize(report);
  if (jsonEncode(_map(report['summary'], 'summary')) !=
      jsonEncode(expectedSummary)) {
    throw const FormatException('סיכום הטקסט אינו נגזר מהמדידות');
  }
}

Map<String, Object?> _validateAndSummarize(Map<String, Object?> report) {
  if (report['protocolVersion'] is! int ||
      report['protocolVersion'] != pdfTextProfileProtocolVersion ||
      report['status'] != 'passed' ||
      report['timeUnit'] != 'microseconds' ||
      report['rawLoadScope'] != 'native-normalization-scheduling-transfer' ||
      report['cacheState'] != 'structured-cache-reset-per-iteration') {
    throw const FormatException('חוזה מדידת הטקסט אינו נתמך');
  }
  final configuration = _map(report['configuration'], 'configuration');
  final pages = _list(configuration['pageNumbers'], 'pageNumbers');
  final pageCount = _integer(configuration['documentPageCount']);
  final warmup = _integer(configuration['warmup']);
  final repetitions = _integer(configuration['repetitions']);
  final cache = _map(configuration['cache'], 'cache');
  final maximumPages = _integer(cache['maximumPages']);
  final maximumBytes = _integer(cache['maximumBytes']);
  if (pageCount < 1 ||
      repetitions < 1 ||
      maximumPages != 16 ||
      maximumBytes != 8 * 1024 * 1024 ||
      pages.length <= maximumPages ||
      pages.toSet().length != pages.length ||
      configuration['normalizeHebrewText'] is! bool ||
      configuration['decodeLegacyHebrewText'] is! bool) {
    throw const FormatException('תצורת מדידת הטקסט אינה תקינה');
  }
  for (final page in pages) {
    if (_integer(page) < 1 || (page as int) > pageCount) {
      throw const FormatException('מספר עמוד אינו בתחום המסמך');
    }
  }
  final queries = _list(configuration['queries'], 'queries');
  final queryIds = <String>{};
  for (final value in queries) {
    final query = _map(value, 'query');
    final id = query['id'];
    if (id is! String ||
        id.isEmpty ||
        !queryIds.add(id) ||
        query['source'] is! String ||
        !['literal', 'regex'].contains(query['kind']) ||
        query['caseSensitive'] is! bool ||
        query['multiLine'] is! bool ||
        query['unicode'] is! bool ||
        query['dotAll'] is! bool) {
      throw const FormatException('זהות שאילתה אינה תקינה');
    }
  }
  if (queryIds.isEmpty) throw const FormatException('אין שאילתות למדידה');

  final observations = _list(report['observations'], 'observations');
  final expected = pages.length * (warmup + repetitions) * 3;
  if (observations.length != expected) {
    throw const FormatException('מדידת הטקסט אינה מכילה את כל המעברים');
  }
  final seen = <String>{};
  final signatures = <int, String>{};
  for (final value in observations) {
    final row = _map(value, 'observation');
    final iteration = _integer(row['iteration']);
    final page = _integer(row['pageNumber']);
    final phase = row['phase'];
    if (iteration >= warmup + repetitions ||
        !pages.contains(page) ||
        !pdfTextProfilePhases.contains(phase) ||
        !seen.add('$iteration/$phase/$page') ||
        row['warmup'] != (iteration < warmup) ||
        row['parity'] != true) {
      throw const FormatException('מדידה חסרה, כפולה או ללא parity');
    }
    for (final field in pdfTextProfileTimings) {
      final unavailable = phase == 'pipeline'
          ? field == 'cacheLoadUs'
          : field == 'formatUs';
      if (unavailable) {
        if (row[field] != null) {
          throw FormatException('$field אינו נמדד בשלב $phase');
        }
      } else {
        _integer(row[field]);
      }
    }
    // מעבר סדרתי ארוך מה-LRU חייב להראות את החילוץ החוזר בפועל.
    if (_integer(row['rawLoadCalls']) != 1 ||
        _integer(row['formatRawCalls']) != (phase == 'pipeline' ? 1 : 0) ||
        _integer(row['cachedPagesAfter']) > maximumPages ||
        _integer(row['cachedBytesAfter']) > maximumBytes ||
        (phase == 'pipeline' &&
            (row['cachedPagesAfter'] != 0 || row['cachedBytesAfter'] != 0)) ||
        (phase != 'pipeline' &&
            (row['cacheLoadUs'] as int) < (row['rawLoadUs'] as int))) {
      throw const FormatException('ספירת חילוץ או תקציב מטמון אינה תקינה');
    }
    for (final field in ['textCharacters', 'characterRects', 'fragments']) {
      _integer(row[field]);
    }
    for (final field in ['textSha256', 'geometrySha256', 'matchesSha256']) {
      final digest = row[field];
      if (digest is! String ||
          digest.length != 64 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        throw FormatException('טביעת $field חסרה או לא תקינה');
      }
    }
    final matches = _list(row['queries'], 'query observations');
    final seenQueries = <String>{};
    for (var index = 0; index < matches.length; index++) {
      final value = matches[index];
      final match = _map(value, 'query observation');
      final id = match['id'];
      if (id is! String ||
          !queryIds.contains(id) ||
          !seenQueries.add(id) ||
          index >= queries.length ||
          _map(queries[index], 'query')['id'] != id) {
        throw const FormatException('תוצאת שאילתה חסרה או כפולה');
      }
      _integer(match['matches']);
      _integer(match['rects']);
    }
    if (seenQueries.length != queryIds.length) {
      throw const FormatException('לא נמדדו כל השאילתות');
    }
    final signature = jsonEncode([
      row['textCharacters'],
      row['characterRects'],
      row['fragments'],
      row['textSha256'],
      row['geometrySha256'],
      row['matchesSha256'],
      matches,
    ]);
    final previous = signatures[page];
    if (previous != null && previous != signature) {
      throw const FormatException('התוכן או ההתאמות השתנו בין המדידות');
    }
    signatures[page] = signature;
  }
  return _summarize(
    configuration,
    observations.map((row) => _map(row, 'observation')).toList(),
  );
}

/// מסכם חזרות שלמות; זמני עמודים שונים אינם חזרות של אותו workload.
Map<String, Object?> buildPdfTextProfileReport({
  required Map<String, Object?> configuration,
  required List<Map<String, Object?>> observations,
}) {
  final report = <String, Object?>{
    'protocolVersion': pdfTextProfileProtocolVersion,
    'status': 'passed',
    'timeUnit': 'microseconds',
    'rawLoadScope': 'native-normalization-scheduling-transfer',
    'cacheState': 'structured-cache-reset-per-iteration',
    'configuration': configuration,
    'observations': observations,
  };
  report['summary'] = _validateAndSummarize(report);
  return report;
}

Map<String, Object?> _summarize(
  Map<String, Object?> configuration,
  List<Map<String, Object?>> observations,
) {
  final repetitions = configuration['repetitions'] as int;
  final warmup = configuration['warmup'] as int;
  return {
    for (final phase in pdfTextProfilePhases)
      phase: {
        for (final timing in pdfTextProfileTimings)
          timing: sampleDistribution([
            for (
              var iteration = warmup;
              iteration < warmup + repetitions;
              iteration++
            )
              if (observations.any(
                (row) => row['phase'] == phase && row[timing] != null,
              ))
                observations
                    .where(
                      (row) =>
                          row['phase'] == phase &&
                          row['iteration'] == iteration,
                    )
                    .fold<int>(0, (sum, row) => sum + (row[timing] as int)),
          ]),
        'rawLoadCalls': observations
            .where((row) => row['phase'] == phase && row['warmup'] == false)
            .fold<int>(0, (sum, row) => sum + (row['rawLoadCalls'] as int)),
      },
  };
}

int _integer(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('מדידת טקסט דורשת מספר שלם שאינו שלילי');
  }
  return value;
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$field אינו אובייקט');
  }
  return value;
}

List<Object?> _list(Object? value, String field) {
  if (value is! List) throw FormatException('$field אינו מערך');
  return value;
}
