import 'dart:convert';
import 'dart:math' as math;

const _comparisonKeys = [
  'protocolVersion',
  'fixtureId',
  'buildMode',
  'cacheState',
  'hardwareId',
  'os',
  'flutterVersion',
  'warmup',
  'repetitions',
  'launchCount',
  'viewport',
  'settings',
  'sampling',
];

List<Map<String, dynamic>> parseProbeRecords(String source) {
  final result = <Map<String, dynamic>>[];
  final lines = const LineSplitter().convert(source.replaceFirst('\ufeff', ''));
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    final value = jsonDecode(lines[i]);
    if (value is! Map<String, dynamic> || value['type'] is! String) {
      throw FormatException('phases.jsonl: רשומה לא תקינה בשורה ${i + 1}');
    }
    result.add(value);
  }
  return result;
}

Map<String, dynamic>? sampleDistribution(Iterable<num> values) {
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  if (sorted.isEmpty) return null;
  if (sorted.any((v) => !v.isFinite)) {
    throw const FormatException('מדידה אינה מספר סופי');
  }
  double quantile(double p) => sorted[(p * sorted.length).ceil() - 1];
  return {
    'count': sorted.length,
    'min': sorted.first,
    'mean': sorted.reduce((a, b) => a + b) / sorted.length,
    'p50': quantile(.50),
    'p95': quantile(.95),
    'p99': quantile(.99),
    'max': sorted.last,
  };
}

class ProcessSample {
  const ProcessSample({
    required this.epochMs,
    required this.pid,
    required this.name,
    this.launchIndex = 0,
    this.monotonicMs,
    this.startTicks,
    this.rootPid,
    this.cpuSeconds,
    this.workingSetMb,
    this.privateMb,
    this.handles,
    this.threads,
    this.treeAgeMs,
  });

  final int epochMs;
  final int pid;
  final String name;
  final int launchIndex;
  final double? monotonicMs;
  final String? startTicks;
  final int? rootPid;
  final double? cpuSeconds;
  final double? workingSetMb;
  final double? privateMb;
  final int? handles;
  final int? threads;
  final double? treeAgeMs;

  String get identity => '$pid:${startTicks ?? "unknown"}';
}

List<ProcessSample> parseProcessSamples(String source) {
  final lines = const LineSplitter()
      .convert(source.replaceFirst('\ufeff', ''))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];
  final headers = _csvRow(lines.first);
  if (headers.toSet().length != headers.length ||
      !headers.contains('epoch_ms') ||
      !headers.contains('pid') ||
      !headers.contains('name')) {
    throw const FormatException('כותרת samples.csv לא תקינה');
  }
  final result = <ProcessSample>[];
  for (var i = 1; i < lines.length; i++) {
    final cells = _csvRow(lines[i]);
    if (cells.length != headers.length) {
      throw FormatException('samples.csv: מספר שדות שגוי בשורה ${i + 1}');
    }
    final row = Map.fromIterables(headers, cells);
    double? number(String key) {
      final text = row[key];
      if (text == null || text.isEmpty) return null;
      final value = double.tryParse(text);
      if (value == null || !value.isFinite || value < 0) {
        throw FormatException('samples.csv: $key לא תקין בשורה ${i + 1}');
      }
      return value;
    }

    int? integer(String key) {
      final value = number(key);
      if (value != null && value != value.truncateToDouble()) {
        throw FormatException('samples.csv: $key אינו שלם בשורה ${i + 1}');
      }
      return value?.toInt();
    }

    final epoch = integer('epoch_ms');
    final pid = integer('pid');
    final startTicks = row['identity_start_ticks'];
    if (epoch == null ||
        pid == null ||
        row['name']!.isEmpty ||
        (startTicks != null &&
            startTicks.isNotEmpty &&
            !RegExp(r'^\d+$').hasMatch(startTicks))) {
      throw FormatException('samples.csv: זהות חסרה או שגויה בשורה ${i + 1}');
    }
    result.add(
      ProcessSample(
        epochMs: epoch,
        pid: pid,
        name: row['name']!,
        launchIndex: integer('launch_index') ?? 0,
        monotonicMs: number('monotonic_ms'),
        startTicks: startTicks == null || startTicks.isEmpty
            ? null
            : startTicks,
        rootPid: integer('root_pid'),
        cpuSeconds: number('cpu_total_s'),
        workingSetMb: number('ws_mb'),
        privateMb: number('priv_mb'),
        handles: integer('handles'),
        threads: integer('threads'),
        treeAgeMs: number('tree_age_ms'),
      ),
    );
  }
  return result;
}

Map<String, dynamic> buildProbeReport({
  required List<Map<String, dynamic>> records,
  Map<String, dynamic> metadata = const {},
  List<ProcessSample> samples = const [],
}) {
  _validateSampleOrder(samples);
  final meta = <String, dynamic>{...metadata};
  final warnings = <String>{};
  final conflicts = <String>{};
  final launchesSeen = <int>{};
  final launchesDone = <int>{};
  var doneFailed = false;
  for (final record in records.where((r) => r['type'] == 'meta')) {
    launchesSeen.add(_launch(record));
    if (record['schemaVersion'] != null &&
        meta['schemaVersion'] != null &&
        record['schemaVersion'] != meta['schemaVersion']) {
      conflicts.add('schemaVersion');
    }
    for (final key in _comparisonKeys) {
      if (meta[key] != null &&
          record[key] != null &&
          !_same(meta[key], record[key])) {
        conflicts.add(key);
      }
      if (record[key] != null) {
        meta.putIfAbsent(key, () => record[key]);
      }
    }
    meta.putIfAbsent('schemaVersion', () => record['schemaVersion']);
  }
  if (meta['schemaVersion'] != null &&
      meta['schemaVersion'] != 1 &&
      meta['schemaVersion'] != 2) {
    throw FormatException('גרסת schema לא נתמכת: ${meta['schemaVersion']}');
  }
  final legacy = meta['schemaVersion'] != 2;
  final runnerFailed = !legacy && meta['status'] != 'passed';
  final samplerErrors =
      _integer(meta['samplerErrorCount'], 'samplerErrorCount') ?? 0;
  meta.putIfAbsent('launchCount', () => 1);
  final launchCount = _integer(meta['launchCount'], 'launchCount');
  if (launchCount == null || launchCount < 1) {
    throw const FormatException('launchCount חייב להיות מספר חיובי');
  }
  for (final record in records.where((r) => r['type'] == 'done')) {
    if (!launchesDone.add(_launch(record))) {
      warnings.add('יותר מרשומת done אחת לאותה הפעלה');
      doneFailed = true;
    }
    if (record['success'] == false || record['status'] == 'failed') {
      doneFailed = true;
    }
  }
  final phases = <String, List<Map<String, dynamic>>>{};
  final phaseKeys = <(int, String, bool, int)>{};
  final legacyErrors = records
      .where((r) => r['type'] == 'note' && r['name'] == 'phase_error')
      .map((r) => r['phase'])
      .toSet();
  for (final source in records.where((r) => r['type'] == 'phase')) {
    final phase = <String, dynamic>{...source};
    final name = phase['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('שלב ללא שם');
    }
    final status = legacy
        ? (phase['error'] != null || legacyErrors.contains(name)
              ? 'failed'
              : 'passed')
        : phase['status'];
    if (!{'passed', 'failed', 'skipped'}.contains(status)) {
      throw FormatException('$name: status לא תקין');
    }
    if (!legacy && phase['warmup'] is! bool) {
      throw FormatException('$name: חסר warmup מפורש');
    }
    phase['status'] = status;
    phase['warmup'] ??= false;
    phase['launchIndex'] = _launch(phase);
    if (!legacy) {
      final iteration = phase['iteration'];
      if (iteration is! int) {
        throw FormatException('$name: iteration חייב להיות מספר שלם');
      }
      if (!phaseKeys.add((
        _launch(phase),
        name,
        phase['warmup'] as bool,
        iteration,
      ))) {
        throw FormatException('$name: חזרה כפולה באותה הפעלה');
      }
    }
    if (status == 'passed') {
      final duration = _number(phase['durationMs'], 'durationMs');
      final start = _integer(phase['startMs'], 'startMs');
      final end = _integer(phase['endMs'], 'endMs');
      if (duration == null || (!legacy && (start == null || end == null))) {
        throw FormatException('$name: מדידה מוצלחת ללא זמן');
      }
      if (start != null && end != null && end < start) {
        warnings.add('שעון הקיר נסוג ב-$name; דגימות התהליך אינן משויכות');
      }
      if (!legacy) _validateFrames(phase);
    }
    phases.putIfAbsent(name, () => []).add(phase);
  }
  final expectedLaunches = {for (var i = 0; i < launchCount; i++) i};
  final phaseLaunches = phases.values
      .expand((p) => p)
      .map((p) => p['launchIndex'])
      .toSet();
  final complete =
      _sameSet(expectedLaunches, launchesDone) &&
      (legacy || _sameSet(expectedLaunches, launchesSeen)) &&
      _sameSet(expectedLaunches, phaseLaunches);
  if (legacy) {
    warnings.add('קלט legacy: השהיות האבחון עשויות להיכלל בזמן; אינו baseline');
  }
  if (!complete) {
    warnings.add('ההרצה חלקית: חסרה meta/done או קיימת הפעלה לא צפויה');
  }
  if (conflicts.isNotEmpty) {
    warnings.add('metadata סותר בין מקורות: ${conflicts.join(", ")}');
  }
  if (runnerFailed) {
    warnings.add('ה-runner לא אישר הצלחה: ${meta['status'] ?? "לא נמסר"}');
  }
  if (samplerErrors > 0) {
    warnings.add(
      'הדוגם החיצוני דיווח $samplerErrors שגיאות; יש לבדוק samples.csv.errors.jsonl',
    );
  }
  final scenarios = [
    for (final entry in phases.entries)
      _scenario(entry.key, entry.value, samples, legacy: legacy),
  ];
  final failed = doneFailed || scenarios.any((s) => s['failures'] != 0);
  final hasMeasurements = scenarios.any((s) => (s['measured'] as int) > 0);
  if (failed) warnings.add('אחד השלבים נכשל; זמני כשל לא נכללים באחוזונים');
  if (scenarios.any((s) => (s['measured'] as int) < 100)) {
    warnings.add('p95/p99 עם מעט חזרות מתארים את המדגם בלבד; יש לבדוק את n');
  }
  if (scenarios.any((s) => s['frames']['truncatedIterations'] != 0)) {
    warnings.add('איסוף frames נחתך; אחוזוני הפריימים של התרחיש אינם זמינים');
  }
  if (samples.isEmpty) {
    warnings.add('אין דגימות תהליך חיצוניות; CPU/private/handles אינם ידועים');
  }
  final eligibility = <String>[
    if (legacy) 'legacy_schema',
    if (!complete) 'incomplete_run',
    if (failed) 'failed_run',
    if (runnerFailed) 'runner_not_passed',
    if (samplerErrors > 0) 'sampler_errors',
    if (phases.isEmpty) 'no_scenarios',
    if (!hasMeasurements) 'no_measured_samples',
    if (meta['dirty'] != false) 'unverified_worktree',
    if (meta['commit'] is! String ||
        !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(meta['commit'] as String))
      'missing_commit',
    for (final key in _comparisonKeys)
      if (meta[key] == null || meta[key] == '') 'missing_metadata:$key',
    for (final key in conflicts) 'conflicting_metadata:$key',
  ];
  return {
    'schemaVersion': 2,
    'sourceSchemaVersion': legacy ? 1 : 2,
    'metadata': meta,
    'complete': complete,
    'successful': complete && !failed && !runnerFailed && hasMeasurements,
    'comparisonEligibility': eligibility,
    'quantileMethod': 'nearest-rank: ceil(p * n) - 1, no interpolation',
    'warnings': warnings.toList(),
    'scenarios': scenarios,
    'notes': records.where((r) => r['type'] == 'note').toList(),
  };
}

Map<String, dynamic> _scenario(
  String name,
  List<Map<String, dynamic>> phases,
  List<ProcessSample> samples, {
  required bool legacy,
}) {
  final measured = phases
      .where(
        (p) => p['status'] == 'passed' && p['warmup'] != true,
      )
      .toList();
  final failed = phases.where((p) => p['status'] == 'failed').length;
  final skipped = phases.where((p) => p['status'] == 'skipped').length;
  final truncatedFrames = measured.where((p) {
    final frames = _map(p['frames']);
    return frames['truncated'] == true ||
        (_integer(frames['droppedFrames'], 'frames.droppedFrames') ?? 0) > 0;
  }).length;
  final frameValues = <String, List<num>>{
    'buildMs': [],
    'rasterMs': [],
    'totalMs': [],
  };
  for (final phase in measured) {
    final frames = _map(phase['frames']);
    for (final key in frameValues.keys) {
      if (frames[key] case final List values) {
        frameValues[key]!.addAll(values.cast<num>());
      }
    }
  }
  Iterable<num> values(String key) sync* {
    for (final phase in measured) {
      final value = _number(phase[key], key);
      if (value != null) yield value;
    }
  }

  final rssPeak = values('rssPeakBytes').toList();
  final rssDeltas = <num>[];
  for (final phase in measured) {
    final before = _number(phase['rssStartBytes'], 'rssStartBytes');
    final after = _number(phase['rssEndBytes'], 'rssEndBytes');
    if (before != null && after != null) rssDeltas.add(after - before);
  }
  if (legacy && rssPeak.isEmpty) {
    rssPeak.addAll(values('rssPeakMb').map((v) => v * 1048576));
  }
  return {
    'name': name,
    'status': failed > 0
        ? 'failed'
        : measured.isEmpty
        ? (skipped > 0 ? 'skipped' : 'unmeasured')
        : skipped > 0
        ? 'partial'
        : 'passed',
    'measured': measured.length,
    'warmupExcluded': phases.where((p) => p['warmup'] == true).length,
    'failures': failed,
    'skipped': skipped,
    'latencyMs': sampleDistribution(
      measured.map((p) => p['durationMs'] as num),
    ),
    'frames': {
      'count': frameValues['buildMs']!.length,
      'truncatedIterations': truncatedFrames,
      for (final key in frameValues.keys)
        key: truncatedFrames > 0 ? null : sampleDistribution(frameValues[key]!),
      if (legacy) 'legacySummaries': measured.map((p) => p['frames']).toList(),
    },
    'memory': {
      'rssPeakBytes': _max(rssPeak),
      'rssEndBytes': sampleDistribution(values('rssEndBytes')),
      'rssDeltaBytes': sampleDistribution(rssDeltas),
    },
    'heap': _snapshots(measured, 'heap', [
      'heapUsage',
      'heapCapacity',
      'externalUsage',
      'isolateCount',
    ]),
    'counters': _snapshots(measured, 'counters', [
      'activeWork',
      'openTabs',
      'flutterViews',
      'schedulerCallbacks',
      'queueDepth',
    ]),
    'resources': _resources(measured, samples),
    'samples': [
      for (final phase in phases)
        {...phase}
          ..remove('frames')
          ..remove('type')
          ..remove('name'),
    ],
  };
}

Map<String, dynamic> _snapshots(
  List<Map<String, dynamic>> phases,
  String prefix,
  List<String> keys,
) => {
  for (final point in ['Before', 'After'])
    point.toLowerCase(): {
      for (final key in keys)
        key: sampleDistribution([
          for (final phase in phases)
            if (_number(_map(phase['$prefix$point'])[key], key)
                case final value?)
              value,
        ]),
    },
};

Map<String, dynamic> _resources(
  List<Map<String, dynamic>> phases,
  List<ProcessSample> samples,
) {
  final cpu = <num>[];
  final workingSet = <num>[];
  final private = <num>[];
  final handles = <num>[];
  final threads = <num>[];
  final processes = <num>[];
  final treeAges = <num>[];
  final unavailable = <String>{};
  var ticks = 0;
  var cpuSeconds = 0.0;
  var coveredMs = 0.0;
  var windowMs = 0.0;
  for (final phase in phases) {
    final start = phase['startMs'];
    final end = phase['endMs'];
    if (start is! num || end is! num || end < start) continue;
    windowMs += end - start;
    final groups = <String, List<ProcessSample>>{};
    for (final sample in samples) {
      if (sample.launchIndex != phase['launchIndex'] ||
          sample.epochMs < start ||
          sample.epochMs > end)
        continue;
      groups
          .putIfAbsent('${sample.epochMs}:${sample.monotonicMs}', () => [])
          .add(sample);
    }
    List<ProcessSample>? previous;
    for (final current in groups.values) {
      final identities = current.map((s) => s.identity).toSet();
      if (identities.length != current.length) {
        throw const FormatException('תהליך כפול באותה דגימת זמן');
      }
      ticks++;
      processes.add(current.length);
      treeAges.addAll(current.map((s) => s.treeAgeMs).whereType<num>());
      final roots = current.map((s) => s.rootPid).toSet();
      final completeRoot =
          roots.length == 1 &&
          roots.first != null &&
          current.any((s) => s.pid == roots.first);
      if (roots.any((id) => id != null) && !completeRoot) {
        unavailable.add('עץ תהליך ללא שורש מזוהה באותה דגימה');
        previous = null;
        continue;
      }
      void total(
        List<num> target,
        num? Function(ProcessSample) get, [
        num factor = 1,
      ]) {
        final values = current.map(get).toList();
        if (values.every((v) => v != null)) {
          target.add(values.cast<num>().reduce((a, b) => a + b) * factor);
        }
      }

      total(workingSet, (s) => s.workingSetMb, 1048576);
      total(private, (s) => s.privateMb, 1048576);
      total(handles, (s) => s.handles);
      total(threads, (s) => s.threads);
      if (previous != null) {
        final previousById = {for (final s in previous) s.identity: s};
        final deltaMs =
            current.first.monotonicMs != null &&
                previous.first.monotonicMs != null
            ? current.first.monotonicMs! - previous.first.monotonicMs!
            : null;
        final stable =
            _sameSet(identities, previousById.keys.toSet()) &&
            completeRoot &&
            current.first.rootPid == previous.first.rootPid &&
            current.every(
              (s) => s.startTicks != null && s.cpuSeconds != null,
            ) &&
            previous.every((s) => s.startTicks != null && s.cpuSeconds != null);
        if (!stable || deltaMs == null || deltaMs <= 0) {
          unavailable.add('CPU: זהות עץ השתנתה או חסרים מונה/שעון מונוטוני');
        } else if ((current.first.epochMs - previous.first.epochMs - deltaMs)
                .abs() >
            50) {
          unavailable.add('CPU: שעון הקיר השתנה לעומת השעון המונוטוני');
        } else {
          final deltas = [
            for (final s in current)
              s.cpuSeconds! - previousById[s.identity]!.cpuSeconds!,
          ];
          if (deltas.any((v) => v < 0)) {
            unavailable.add('CPU: מונה מצטבר נסוג');
          } else {
            final delta = deltas.reduce((a, b) => a + b);
            cpu.add(delta / deltaMs * 100000);
            cpuSeconds += delta;
            coveredMs += deltaMs;
          }
        }
      }
      previous = current;
    }
  }
  if (ticks == 0) unavailable.add('אין דגימות תהליך בתוך גבולות השלבים');
  if (cpu.isEmpty)
    unavailable.add('אין שתי דגימות CPU תקינות סמוכות באותו שלב');
  if (private.isEmpty) unavailable.add('private memory לא נמדד');
  if (handles.isEmpty) unavailable.add('handles לא נמדדו');
  return {
    'sampledTicks': ticks,
    'cpuIntervalCount': cpu.length,
    'cpuCorePercent': sampleDistribution(cpu),
    'cpuAverageCorePercent': coveredMs > 0
        ? cpuSeconds / coveredMs * 100000
        : null,
    'sampledCpuSeconds': cpu.isEmpty ? null : cpuSeconds,
    'cpuCoveredMs': coveredMs,
    'phaseWindowMs': windowMs,
    'cpuCoverageFraction': windowMs > 0 ? coveredMs / windowMs : null,
    'treeWorkingSetPeakBytes': _max(workingSet),
    'treePrivatePeakBytes': _max(private),
    'handlesPeak': _max(handles),
    'threadsPeak': _max(threads),
    'processesPeak': _max(processes),
    'maxTreeAgeMs': _max(treeAges),
    'unavailable': unavailable.toList(),
  };
}

Map<String, dynamic> compareProbeReports(
  Map<String, dynamic> baseline,
  Map<String, dynamic> candidate,
) {
  final reasons = <String>{};
  for (final entry in {'baseline': baseline, 'candidate': candidate}.entries) {
    final report = entry.value;
    if (report['sourceSchemaVersion'] != 2)
      reasons.add('${entry.key}:legacy_schema');
    if (report['complete'] != true) reasons.add('${entry.key}:incomplete_run');
    if (report['successful'] != true)
      reasons.add('${entry.key}:unsuccessful_run');
    for (final reason in report['comparisonEligibility'] as List? ?? const []) {
      reasons.add('${entry.key}:$reason');
    }
    if (_map(report['metadata'])['dirty'] != false) {
      reasons.add('${entry.key}:unverified_worktree');
    }
  }
  final beforeMeta = _map(baseline['metadata']);
  final afterMeta = _map(candidate['metadata']);
  for (final key in _comparisonKeys) {
    if (beforeMeta[key] == null ||
        afterMeta[key] == null ||
        !_same(beforeMeta[key], afterMeta[key]))
      reasons.add('metadata:$key');
  }
  final before = {
    for (final row in baseline['scenarios'] as List? ?? const [])
      (row as Map<String, dynamic>)['name'] as String: row,
  };
  final after = {
    for (final row in candidate['scenarios'] as List? ?? const [])
      (row as Map<String, dynamic>)['name'] as String: row,
  };
  final rows = <Map<String, dynamic>>[];
  for (final name in {...before.keys, ...after.keys}) {
    final a = before[name];
    final b = after[name];
    final status = a == null
        ? 'missing_in_baseline'
        : b == null
        ? 'missing_in_candidate'
        : reasons.isNotEmpty
        ? 'incompatible'
        : a['status'] != 'passed' || b['status'] != 'passed'
        ? 'unavailable'
        : a['measured'] != b['measured']
        ? 'different_sample_count'
        : !_sameIterations(a, b)
        ? 'different_repetition_layout'
        : 'compared';
    rows.add({
      'name': name,
      'status': status,
      if (status == 'compared')
        'metrics': {
          for (final path in _comparedMetrics)
            path: _difference(_at(a!, path), _at(b!, path)),
        },
    });
  }
  return {
    'comparable': reasons.isEmpty,
    'baselineCommit': beforeMeta['commit'],
    'candidateCommit': afterMeta['commit'],
    'reasons': reasons.toList(),
    'scenarios': rows,
  };
}

final _comparedMetrics = [
  for (final q in ['p50', 'p95', 'p99']) 'latencyMs.$q',
  for (final frame in ['buildMs', 'rasterMs', 'totalMs'])
    for (final q in ['p50', 'p95', 'p99']) 'frames.$frame.$q',
  'memory.rssPeakBytes',
  'heap.after.heapUsage.p50',
  'heap.after.externalUsage.p50',
  'resources.cpuAverageCorePercent',
  'resources.treeWorkingSetPeakBytes',
  'resources.treePrivatePeakBytes',
  'resources.handlesPeak',
  'resources.processesPeak',
  'counters.after.activeWork.max',
  'counters.after.openTabs.max',
  'counters.after.flutterViews.max',
  'counters.after.schedulerCallbacks.max',
];

Map<String, dynamic> _difference(Object? a, Object? b) => {
  'baseline': a,
  'candidate': b,
  'available': a is num && b is num,
  'delta': a is num && b is num ? b - a : null,
  'deltaPercent': a is num && b is num && a != 0 ? (b - a) / a * 100 : null,
};

String renderProbeMarkdown(Map<String, dynamic> report) {
  final meta = _map(report['metadata']);
  final out = StringBuffer('# דוח מדידות ביצועים\n\n')
    ..writeln(
      'Commit: `${meta['commit'] ?? "לא נמסר"}` · '
      'מצב: ${meta['buildMode'] ?? "לא נמסר"} · מטמון: ${meta['cacheState'] ?? "לא נמסר"}',
    )
    ..writeln(
      '\nהרצה שלמה: ${report['complete']} · הצלחה: ${report['successful']}',
    )
    ..writeln(
      '\n| תרחיש | מצב | n | p50 ms | p95 ms | p99 ms | build p95 ms | raster p95 ms | RSS peak MiB |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final scenario in report['scenarios'] as List) {
    final s = scenario as Map<String, dynamic>;
    out.writeln(
      '| ${_cell(s['name'])} | ${s['status']} | ${s['measured']} | '
      '${_format(_at(s, 'latencyMs.p50'))} | ${_format(_at(s, 'latencyMs.p95'))} | '
      '${_format(_at(s, 'latencyMs.p99'))} | ${_format(_at(s, 'frames.buildMs.p95'))} | '
      '${_format(_at(s, 'frames.rasterMs.p95'))} | '
      '${_format(_scale(_at(s, 'memory.rssPeakBytes'), 1048576))} |',
    );
  }
  out.writeln(
    '\n| תרחיש | CPU ממוצע % ליבה | כיסוי CPU % | private peak MiB | heap אחרי p50 MiB | handles peak | תהליכים peak |',
  );
  out.writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final scenario in report['scenarios'] as List) {
    final s = scenario as Map<String, dynamic>;
    out.writeln(
      '| ${_cell(s['name'])} | '
      '${_format(_at(s, 'resources.cpuAverageCorePercent'))} | '
      '${_format(_scale(_at(s, 'resources.cpuCoverageFraction'), .01))} | '
      '${_format(_scale(_at(s, 'resources.treePrivatePeakBytes'), 1048576))} | '
      '${_format(_scale(_at(s, 'heap.after.heapUsage.p50'), 1048576))} | '
      '${_format(_at(s, 'resources.handlesPeak'))} | '
      '${_format(_at(s, 'resources.processesPeak'))} |',
    );
  }
  out.writeln(
    '\nאחוזונים: nearest-rank על דגימות מוצלחות בלבד, ללא warmup. '
    'מקף מציין מדד חסר. CPU: ‏100% = ליבה אחת; private memory הוא commit פרטי, '
    'ואינו אומדן לזיכרון native בלבד. דגימות גודל וזמן כיסוי CPU מפורטים ב-JSON.',
  );
  final comparison = _map(report['comparison']);
  if (comparison.isNotEmpty) {
    out.writeln('\n## השוואה ל-baseline\n');
    if (comparison['comparable'] != true) {
      out.writeln(
        'ההשוואה המספרית חסומה: ${(comparison['reasons'] as List).join(", ")}.',
      );
    } else {
      out.writeln('| תרחיש | מצב | שינוי p50 | שינוי p95 | שינוי p99 |');
      out.writeln('|---|---|---:|---:|---:|---:|');
      for (final row in comparison['scenarios'] as List) {
        final s = row as Map<String, dynamic>;
        final metrics = _map(s['metrics']);
        String change(String p) =>
            _format(_map(metrics['latencyMs.$p'])['deltaPercent'], suffix: '%');
        out.writeln(
          '| ${_cell(s['name'])} | ${s['status']} | ${change('p50')} | '
          '${change('p95')} | ${change('p99')} |',
        );
      }
      out.writeln(
        '\nשינוי חיובי הוא עלייה בזמן; אלה הבדלים תיאוריים, ללא קביעת מובהקות או סף CI.',
      );
    }
  }
  final warnings = report['warnings'] as List;
  if (warnings.isNotEmpty) {
    out.writeln('\n## מגבלות המדידה\n');
    for (final warning in warnings) out.writeln('- ${_cell(warning)}');
  }
  return out.toString();
}

void _validateSampleOrder(List<ProcessSample> samples) {
  final previous = <int, ProcessSample>{};
  final identities = <int, Set<String>>{};
  for (final current in samples) {
    final last = previous[current.launchIndex];
    if (last != null &&
        (current.epochMs < last.epochMs ||
            (current.monotonicMs != null &&
                last.monotonicMs != null &&
                current.monotonicMs! < last.monotonicMs!))) {
      throw const FormatException(
        'samples.csv: דגימות אינן בסדר זמן; השעון נסוג או הקלט שגוי',
      );
    }
    if (last == null ||
        current.epochMs != last.epochMs ||
        current.monotonicMs != last.monotonicMs) {
      identities[current.launchIndex] = {};
    }
    if (!identities[current.launchIndex]!.add(current.identity)) {
      throw const FormatException(
        'samples.csv: זהות תהליך כפולה באותה דגימת זמן',
      );
    }
    previous[current.launchIndex] = current;
  }
}

bool _sameIterations(Map<String, dynamic> a, Map<String, dynamic> b) {
  List<String>? keys(Map<String, dynamic> row) {
    final samples = row['samples'];
    if (samples is! List) return null;
    return [
      for (final sample in samples)
        jsonEncode([
          sample['launchIndex'],
          sample['iteration'],
          sample['warmup'],
          sample['status'],
        ]),
    ]..sort();
  }

  final before = keys(a);
  final after = keys(b);
  return before != null && after != null && _same(before, after);
}

void _validateFrames(Map<String, dynamic> phase) {
  final frames = _map(phase['frames']);
  if (frames.isEmpty) return;
  final count = _integer(frames['count'], 'frames.count');
  for (final key in ['buildMs', 'rasterMs', 'totalMs']) {
    final values = frames[key];
    if (values is! List || count == null || values.length != count) {
      throw FormatException('${phase['name']}: frames.$key אינו תואם ל-count');
    }
    for (final value in values) {
      if (_number(value, 'frames.$key') == null) {
        throw FormatException('frames.$key מכיל דגימה חסרה');
      }
    }
  }
}

List<String> _csvRow(String line) {
  final result = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      result.add(cell.toString());
      cell = StringBuffer();
    } else {
      cell.write(ch);
    }
  }
  if (quoted) throw const FormatException('מחרוזת CSV לא סגורה');
  result.add(cell.toString());
  return result;
}

num? _number(Object? value, String name) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$name חייב להיות מספר סופי ולא שלילי');
  }
  return value;
}

int? _integer(Object? value, String name) {
  final n = _number(value, name);
  if (n != null && n != n.truncate())
    throw FormatException('$name חייב להיות שלם');
  return n?.toInt();
}

int _launch(Map<String, dynamic> record) =>
    _integer(record['launchIndex'], 'launchIndex') ?? 0;
num? _max(List<num> values) => values.isEmpty ? null : values.reduce(math.max);
Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};
bool _sameSet(Set<Object?> a, Set<Object?> b) =>
    a.length == b.length && a.containsAll(b);
bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return _sameSet(a.keys.toSet(), b.keys.toSet()) &&
        a.keys.every((key) => _same(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}

Object? _at(Map<String, dynamic> row, String path) {
  Object? value = row;
  for (final key in path.split('.')) value = _map(value)[key];
  return value;
}

num? _scale(Object? value, num divisor) =>
    value is num ? value / divisor : null;
String _format(Object? value, {String suffix = ''}) =>
    value is num ? '${value.toStringAsFixed(3)}$suffix' : '—';
String _cell(Object? value) =>
    '$value'.replaceAll('|', '\\|').replaceAll('\n', ' ');
