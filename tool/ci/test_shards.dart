// Splits the test files across CI shards by their recorded run time.
//
//   dart tool/ci/test_shards.dart <index> <total>
//       Prints the test files of shard <index> (0-based), one per line.
//   dart tool/ci/test_shards.dart --record <results.json>...
//       Updates tool/ci/test_timings.json from `flutter test` json reports
//       (the `test-results-*` artifacts of a CI run).
import 'dart:convert';
import 'dart:io';

const _timingsPath = 'tool/ci/test_timings.json';

void main(List<String> args) {
  if (args.isNotEmpty && args.first == '--record') {
    _record(args.skip(1).toList());
    return;
  }
  if (args.length != 2) {
    stderr.writeln('usage: test_shards.dart <index> <total>');
    exit(64);
  }
  final index = int.parse(args[0]);
  final total = int.parse(args[1]);
  for (final file in shardFiles(_testFiles(), _readTimings(), index, total)) {
    stdout.writeln(file);
  }
}

List<String> _testFiles() =>
    Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where(isShardedTestFile)
        .toList()
      ..sort();

/// קובץ בדיקה שנכנס ל-shards של Linux. ה-goldens רצים ב-job נפרד על
/// Windows, פלטפורמת הייחוס שלהם.
bool isShardedTestFile(String path) =>
    path.endsWith('_test.dart') && !path.startsWith('test/goldens/');

Map<String, double> _readTimings() {
  final file = File(_timingsPath);
  if (!file.existsSync()) return {};
  return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>).map(
    (k, v) => MapEntry(k, (v as num).toDouble()),
  );
}

/// Longest-first greedy split. Files without a recorded time weigh the median.
List<String> shardFiles(
  List<String> files,
  Map<String, double> timings,
  int index,
  int total,
) {
  final known = files.map((f) => timings[f]).whereType<double>().toList()
    ..sort();
  final fallback = known.isEmpty ? 1.0 : known[known.length ~/ 2];
  final weighted = [for (final f in files) (f, timings[f] ?? fallback)]
    ..sort((a, b) {
      final byWeight = b.$2.compareTo(a.$2);
      return byWeight != 0 ? byWeight : a.$1.compareTo(b.$1);
    });
  final loads = List<double>.filled(total, 0);
  final mine = <String>[];
  for (final (file, weight) in weighted) {
    var target = 0;
    for (var s = 1; s < total; s++) {
      if (loads[s] < loads[target]) target = s;
    }
    loads[target] += weight;
    if (target == index) mine.add(file);
  }
  return mine..sort();
}

void _record(List<String> reports) {
  final files = _testFiles();
  final timings = _readTimings();
  for (final report in reports) {
    final suitePaths = <int, String>{};
    final testSuites = <int, int>{};
    final starts = <int, int>{};
    final ends = <int, int>{};
    for (final line in File(report).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final event = jsonDecode(line) as Map<String, dynamic>;
      final time = event['time'] as int? ?? 0;
      switch (event['type']) {
        case 'suite':
          final suite = event['suite'] as Map<String, dynamic>;
          final path = (suite['path'] as String?)?.replaceAll(r'\', '/');
          if (path != null) suitePaths[suite['id'] as int] = path;
        case 'testStart':
          final test = event['test'] as Map<String, dynamic>;
          final suiteId = test['suiteID'] as int;
          testSuites[test['id'] as int] = suiteId;
          starts[suiteId] = starts[suiteId] ?? time;
        case 'testDone':
          final suiteId = testSuites[event['testID'] as int];
          if (suiteId != null) ends[suiteId] = time;
      }
    }
    for (final MapEntry(key: id, value: path) in suitePaths.entries) {
      final start = starts[id], end = ends[id];
      if (start == null || end == null) continue;
      final file = files.where((f) => path.endsWith('/$f')).firstOrNull;
      if (file != null) timings[file] = (end - start) / 1000;
    }
  }
  final sorted = {
    for (final f in files)
      if (timings[f] case final t?) f: double.parse(t.toStringAsFixed(1)),
  };
  File(_timingsPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
  stdout.writeln('Recorded ${sorted.length} of ${files.length} test files.');
}
