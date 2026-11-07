import 'dart:convert';
import 'dart:io';

import 'new_contract.dart' as repaired;
import 'old_contract.dart' as original;

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

bool equalValues(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => equalValues(a[i], b[i])).every((v) => v);
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && equalValues(a[key], b[key]));
  }
  return a == b;
}

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> extractReport(Map<String, dynamic> evidence, String key) =>
    ((evidence[key] as List).cast<Map>().singleWhere(
      (entry) => entry['path'] == 'app-report.json',
    )['value'] as Map)['applePluginActivity'] as Map<String, dynamic>;

void main(List<String> args) {
  final macEvidence = readJson(args[0]);
  final iosEvidence = readJson(args[1]);
  final mac = extractReport(macEvidence, 'originalJson');
  final ios = extractReport(iosEvidence['iosRetry'] as Map<String, dynamic>,
      'originalSourceJson');
  final iosDriver = readJson(args[2]);
  require(mac['status'] == 'passed', 'Retained Mac execution was not passed');
  require(ios['status'] == 'failed', 'The historical iOS failure was altered');
  final result = <String, Object?>{
    'classification': 'IMPLEMENTATION_RETAINED_INPUT_REPLAY_ONLY',
    'nativeExecution': 'NOT_RUN',
    'independentQA': 'NOT_RUN',
    'historicalMacNativeStatus': mac['status'],
    'historicalIOSNativeStatus': ios['status'],
    'records': <Object?>[],
  };
  var macPages = 0;
  var iosPages = 0;
  for (final platform in [
    {'name': 'macos', 'report': mac},
    {'name': 'ios', 'report': ios},
  ]) {
    final name = platform['name'] as String;
    final report = platform['report'] as Map<String, dynamic>;
    for (final phase in (report['phases'] as List).cast<Map>()) {
      for (final page in ((phase['pages'] as List?) ?? []).cast<Map>()) {
        if (!page.containsKey('analysis')) continue;
        final before = page['before'] as Map<String, dynamic>;
        final after = page['afterCommand'] as Map<String, dynamic>;
        final driver = phase['driver'] as Map<String, dynamic>;
        final arm = phase['arm'] as Map;
        final old = original.analyzeAppleQuietWindow(
          before: before,
          after: after,
          driver: driver,
          armStartMs: arm['requestStartMs'] as int,
          armEndMs: arm['requestEndMs'] as int,
        );
        require(equalValues(old, page['analysis']),
            'Original analysis differs: ' + name + '/' + phase['name'].toString());
        final changed = repaired.analyzeAppleQuietWindow(
          before: before,
          after: after,
          driver: name == 'ios' ? iosDriver : driver,
          armStartMs: arm['requestStartMs'] as int,
          armEndMs: arm['requestEndMs'] as int,
        );
        require(changed['clockStable'] == true, 'Replay clock is uncertain');
        require(changed['edgeGuardMs'] == 1000 && changed['clockToleranceMs'] == 250,
            'Clock thresholds changed');
        for (final stream in (changed['streams'] as Map).values.cast<Map>()) {
          require(stream['dropped'] == 0, 'A retained callback log is incomplete');
          if (phase['name'] == 'visible') {
            require(stream['classification'] == 'callbacksObservedInsideQuiet',
                'Replay visible positive control failed');
          }
        }
        (result['records'] as List).add({
          'platform': name,
          'phase': phase['name'],
          'pluginId': page['pluginId'],
          'historicalPhaseStatus': phase['status'],
          'originalAnalysis': old,
          'repairedReplayAnalysis': changed,
        });
        name == 'macos' ? macPages++ : iosPages++;
      }
    }
  }
  require(macPages == 8 && iosPages == 1, 'Unexpected analyzed page coverage');
  final notRun = (ios['phases'] as List).cast<Map>().where((p) => p['status'] == 'notRun');
  require(notRun.length == 6, 'Historical unexecuted iOS phases were altered');
  result['macPages'] = macPages;
  result['macStreams'] = macPages * 3;
  result['iosPages'] = iosPages;
  result['iosRemainingPhases'] = notRun.map((p) => p['name']).toList();
  result['status'] = 'passed';
  File(args[3]).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result) + '\n');
  print('SELF_REPLAY_RESULT ' + jsonEncode(result));
}
