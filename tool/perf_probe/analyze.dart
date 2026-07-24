// מנתח את פלט אבחון המשאבים: מצליב את גבולות השלבים (phases.jsonl, נכתב
// מתוך התרחיש) עם דגימות ה-CPU/RAM החיצוניות (samples.csv) ומדפיס דוח.
//
// הרצה: dart run tool/perf_probe/analyze.dart <run-dir>

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/perf_probe/analyze.dart <run-dir>');
    exit(64);
  }
  final runDir = Directory(args.first);
  final phasesFile = File('${runDir.path}/phases.jsonl');
  final samplesFile = File('${runDir.path}/samples.csv');
  if (!phasesFile.existsSync()) {
    stderr.writeln('phases.jsonl not found in ${runDir.path}');
    exit(66);
  }

  final phases = <Map<String, dynamic>>[];
  final notes = <Map<String, dynamic>>[];
  for (final line in phasesFile.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final record = jsonDecode(line) as Map<String, dynamic>;
    if (record['type'] == 'phase') phases.add(record);
    if (record['type'] == 'note') notes.add(record);
  }

  final samples = <_Sample>[];
  if (samplesFile.existsSync()) {
    for (final line in samplesFile.readAsLinesSync().skip(1)) {
      final parts = line.split(',');
      if (parts.length < 6) continue;
      samples.add(
        _Sample(
          epochMs: int.parse(parts[0]),
          pid: int.parse(parts[1]),
          name: parts[2],
          cpuTotalS: double.parse(parts[3]),
          wsMb: double.parse(parts[4]),
          privMb: double.parse(parts[5]),
        ),
      );
    }
  }

  final report = <Map<String, dynamic>>[];
  stdout.writeln('');
  stdout.writeln('=== דוח אבחון משאבים ===');
  stdout.writeln('');
  final header = [
    'phase'.padRight(26),
    'sec'.padLeft(6),
    'cpuAvg%'.padLeft(8),
    'cpuPk%'.padLeft(7),
    'cpuSec'.padLeft(7),
    'rssStart'.padLeft(9),
    'rssEnd'.padLeft(8),
    'rssPeak'.padLeft(8),
    'treePk'.padLeft(8),
    'frames'.padLeft(7),
    'bldAvg'.padLeft(7),
    'bldP95'.padLeft(7),
    'rstP95'.padLeft(7),
    'jank'.padLeft(5),
  ].join(' ');
  stdout.writeln(header);
  stdout.writeln('-' * header.length);

  for (final phase in phases) {
    final start = phase['startMs'] as int;
    final end = phase['endMs'] as int;
    final durationS = (end - start) / 1000;

    final window = samples
        .where((s) => s.epochMs >= start - 250 && s.epochMs <= end + 250)
        .toList();
    final cpu = _cpuStats(window);
    final treePeakWs = _treePeakWs(window);

    final frames = phase['frames'] as Map<String, dynamic>;
    final row = {
      'phase': phase['name'],
      'durationS': _r1(durationS),
      'cpuAvgPct': cpu.avgPct,
      'cpuPeakPct': cpu.peakPct,
      'cpuSeconds': cpu.totalCpuS,
      'cpuSecondsByProc': cpu.byProcess,
      'rssStartMb': phase['rssStartMb'],
      'rssEndMb': phase['rssEndMb'],
      'rssPeakMb': phase['rssPeakMb'],
      'treePeakWsMb': treePeakWs,
      'frames': frames,
    };
    report.add(row);

    stdout.writeln(
      [
        '${phase['name']}'.padRight(26),
        _r1(durationS).toString().padLeft(6),
        cpu.avgPct.toString().padLeft(8),
        cpu.peakPct.toString().padLeft(7),
        cpu.totalCpuS.toString().padLeft(7),
        '${phase['rssStartMb']}'.padLeft(9),
        '${phase['rssEndMb']}'.padLeft(8),
        '${phase['rssPeakMb']}'.padLeft(8),
        treePeakWs.toString().padLeft(8),
        '${frames['count']}'.padLeft(7),
        '${frames['buildAvgMs']}'.padLeft(7),
        '${frames['buildP95Ms']}'.padLeft(7),
        '${frames['rasterP95Ms']}'.padLeft(7),
        '${frames['jankOver33Ms']}'.padLeft(5),
      ].join(' '),
    );
  }

  stdout.writeln('');
  stdout.writeln('--- סה"כ CPU (שניות ליבה) לפי תהליך, כל ההרצה ---');
  final totalByProc = _totalCpuByProcess(samples);
  final sortedProcs = totalByProc.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedProcs) {
    stdout.writeln('  ${e.key.padRight(20)} ${e.value.toStringAsFixed(1)}s');
  }

  stdout.writeln('');
  stdout.writeln('--- שלבים לפי צריכת CPU (שניות ליבה) ---');
  final byCpu = [...report]
    ..sort(
      (a, b) =>
          (b['cpuSeconds'] as double).compareTo(a['cpuSeconds'] as double),
    );
  for (final row in byCpu.take(8)) {
    stdout.writeln(
      '  ${(row['phase'] as String).padRight(26)} '
      '${row['cpuSeconds']}s (avg ${row['cpuAvgPct']}%)',
    );
  }

  stdout.writeln('');
  stdout.writeln('--- שלבים לפי גידול RSS (MB) ---');
  final byRss = [...report]
    ..sort(
      (a, b) => ((b['rssEndMb'] as num) - (b['rssStartMb'] as num)).compareTo(
        (a['rssEndMb'] as num) - (a['rssStartMb'] as num),
      ),
    );
  for (final row in byRss.take(8)) {
    final delta = _r1(
      ((row['rssEndMb'] as num) - (row['rssStartMb'] as num)).toDouble(),
    );
    stdout.writeln(
      '  ${(row['phase'] as String).padRight(26)} '
      '+$delta MB (peak ${row['rssPeakMb']})',
    );
  }

  for (final note in notes) {
    stdout.writeln('note: ${jsonEncode(note)}');
  }

  final outFile = File('${runDir.path}/report.json');
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('');
  stdout.writeln('דוח מלא: ${outFile.path}');
}

class _Sample {
  final int epochMs;
  final int pid;
  final String name;
  final double cpuTotalS;
  final double wsMb;
  final double privMb;
  _Sample({
    required this.epochMs,
    required this.pid,
    required this.name,
    required this.cpuTotalS,
    required this.wsMb,
    required this.privMb,
  });
}

class _CpuStats {
  final double avgPct;
  final double peakPct;
  final double totalCpuS;
  final Map<String, double> byProcess;
  _CpuStats(this.avgPct, this.peakPct, this.totalCpuS, this.byProcess);
}

/// CPU בחלון: דלתא של cpu_total_s לכל pid (מונוטוני), מסוכם לעץ.
/// avg% = שניות CPU חלקי משך החלון (100% = ליבה אחת מלאה).
_CpuStats _cpuStats(List<_Sample> window) {
  if (window.length < 2) return _CpuStats(0, 0, 0, const {});
  final byPid = <int, List<_Sample>>{};
  for (final s in window) {
    byPid.putIfAbsent(s.pid, () => []).add(s);
  }

  var totalCpuS = 0.0;
  final byProcess = <String, double>{};
  for (final list in byPid.values) {
    final delta = list.last.cpuTotalS - list.first.cpuTotalS;
    if (delta <= 0) continue;
    totalCpuS += delta;
    byProcess[list.first.name] = (byProcess[list.first.name] ?? 0) + delta;
  }

  final windowS = (window.last.epochMs - window.first.epochMs) / 1000;
  final avgPct = windowS <= 0 ? 0.0 : totalCpuS / windowS * 100;

  // שיא: סכום דלתאות ה-CPU של כל התהליכים בין שתי חותמות זמן סמוכות.
  final timestamps = window.map((s) => s.epochMs).toSet().toList()..sort();
  var peakPct = 0.0;
  for (var i = 1; i < timestamps.length; i++) {
    final dtS = (timestamps[i] - timestamps[i - 1]) / 1000;
    if (dtS <= 0.05) continue;
    var deltaSum = 0.0;
    for (final list in byPid.values) {
      _Sample? prev, curr;
      for (final s in list) {
        if (s.epochMs == timestamps[i - 1]) prev = s;
        if (s.epochMs == timestamps[i]) curr = s;
      }
      if (prev != null && curr != null) {
        final d = curr.cpuTotalS - prev.cpuTotalS;
        if (d > 0) deltaSum += d;
      }
    }
    final pct = deltaSum / dtS * 100;
    if (pct > peakPct) peakPct = pct;
  }

  return _CpuStats(
    _r1(avgPct),
    _r1(peakPct),
    _r1(totalCpuS),
    byProcess.map((k, v) => MapEntry(k, _r1(v))),
  );
}

double _treePeakWs(List<_Sample> window) {
  final byTimestamp = <int, double>{};
  for (final s in window) {
    byTimestamp[s.epochMs] = (byTimestamp[s.epochMs] ?? 0) + s.wsMb;
  }
  if (byTimestamp.isEmpty) return 0;
  return _r1(byTimestamp.values.reduce((a, b) => a > b ? a : b));
}

Map<String, double> _totalCpuByProcess(List<_Sample> samples) {
  final byPid = <int, List<_Sample>>{};
  for (final s in samples) {
    byPid.putIfAbsent(s.pid, () => []).add(s);
  }
  final result = <String, double>{};
  for (final list in byPid.values) {
    final delta = list.last.cpuTotalS - list.first.cpuTotalS;
    if (delta <= 0) continue;
    result[list.first.name] = _r1((result[list.first.name] ?? 0) + delta);
  }
  return result;
}

double _r1(double v) => (v * 10).round() / 10;
