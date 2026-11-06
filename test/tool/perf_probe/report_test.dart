import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/perf_probe/src/report.dart';

Map<String, dynamic> metadata({Map<String, dynamic> changes = const {}}) => {
  'schemaVersion': 2,
  'protocolVersion': 2,
  'commit': '1111111111111111111111111111111111111111',
  'dirty': false,
  'status': 'passed',
  'fixtureId': 'unit-test-fixture',
  'buildMode': 'profile',
  'cacheState': 'cold',
  'hardwareId': 'unit-test-host',
  'os': 'windows-test',
  'flutterVersion': 'test-version',
  'warmup': 1,
  'repetitions': 2,
  'launchCount': 1,
  'viewport': {'width': 1200, 'height': 800, 'devicePixelRatio': 1},
  'settings': {'fontSize': 20, 'fontFamily': 'test-font'},
  'sampling': {'intervalMs': 500, 'treeRefreshMs': 2000, 'heap': true},
  ...changes,
};

Map<String, dynamic> phase({
  String name = 'open',
  double duration = 10,
  int start = 0,
  int end = 1000,
  int launch = 0,
  int iteration = 0,
  String status = 'passed',
  bool warmup = false,
  List<num> frames = const [],
  Map<String, dynamic> extra = const {},
}) => {
  'type': 'phase',
  'name': name,
  'status': status,
  'warmup': warmup,
  'iteration': iteration,
  'launchIndex': launch,
  'durationMs': duration,
  'startMs': start,
  'endMs': end,
  'frames': {
    'count': frames.length,
    'buildMs': frames,
    'rasterMs': frames,
    'totalMs': frames,
  },
  ...extra,
};

Map<String, dynamic> report(
  List<Map<String, dynamic>> phases, {
  Map<String, dynamic> changes = const {},
  List<ProcessSample> samples = const [],
  List<Map<String, dynamic>>? records,
}) => buildProbeReport(
  metadata: metadata(changes: changes),
  records:
      records ??
      [
        {'type': 'meta', 'schemaVersion': 2},
        ...phases,
        {'type': 'done'},
      ],
  samples: samples,
);

Map<String, dynamic> scenario(
  Map<String, dynamic> report, [
  String name = 'open',
]) => (report['scenarios'] as List).cast<Map<String, dynamic>>().singleWhere(
  (s) => s['name'] == name,
);

ProcessSample sample(
  int epoch,
  double? cpu, {
  int pid = 1,
  String? identity = '123',
  double? monotonic,
  int launch = 0,
  double? private = 10,
  double? ws = 20,
  int? handles = 4,
}) => ProcessSample(
  epochMs: epoch,
  pid: pid,
  rootPid: 1,
  name: pid == 1 ? 'otzaria' : 'child',
  startTicks: identity,
  cpuSeconds: cpu,
  monotonicMs: monotonic ?? epoch.toDouble(),
  launchIndex: launch,
  privateMb: private,
  workingSetMb: ws,
  handles: handles,
);

void main() {
  group('אחוזונים ותקינות קלט', () {
    test('nearest-rank ידוע, ללא interpolation או עיגול מוקדם', () {
      final values = List.generate(20, (i) => 20 - i);
      final result = sampleDistribution(values)!;
      expect(result, {
        'count': 20,
        'min': 1.0,
        'mean': 10.5,
        'p50': 10.0,
        'p95': 19.0,
        'p99': 20.0,
        'max': 20.0,
      });
      expect(values.first, 20);
      expect(sampleDistribution([1, 2, 3])!['p50'], 2);
      expect(sampleDistribution([]), isNull);
      expect(() => sampleDistribution([double.nan]), throwsFormatException);
    });

    test('JSONL שגוי אינו נזרק בשקט', () {
      expect(parseProbeRecords('\ufeff{"type":"meta"}\n\n').length, 1);
      expect(() => parseProbeRecords('{"type":'), throwsFormatException);
      expect(() => parseProbeRecords('[1,2]'), throwsFormatException);
    });

    test('CSV מכיל ערכים חסרים ושמות מצוטטים, בלי תלות בתרבות מערכת', () {
      final parsed = parseProcessSamples(
        '\ufeffepoch_ms,pid,name,cpu_total_s,ws_mb,priv_mb,identity_start_ticks,handles,threads,root_pid,monotonic_ms,launch_index\n'
        '1000,5,"process,with""quote",,12.5,9.75,638000000000000000,,3,5,10.25,1\n',
      ).single;
      expect(parsed.name, 'process,with"quote');
      expect(parsed.cpuSeconds, isNull);
      expect(parsed.handles, isNull);
      expect(parsed.workingSetMb, 12.5);
      expect(parsed.startTicks, '638000000000000000');
      expect(parsed.monotonicMs, 10.25);
      expect(parsed.launchIndex, 1);
      expect(
        () => parseProcessSamples('epoch_ms,pid,name\n1,2,app,extra'),
        throwsFormatException,
      );
      expect(
        () => parseProcessSamples('epoch_ms,pid,name,cpu_total_s\n1,2,app,NaN'),
        throwsFormatException,
      );
      expect(
        () => parseProcessSamples('epoch_ms,pid,name\n1,2,"app'),
        throwsFormatException,
      );
    });

    test('מדידה מוצלחת חייבת זמן וספירת frames תואמת', () {
      expect(
        () => report([
          phase(extra: {'durationMs': -1}),
        ]),
        throwsFormatException,
      );
      expect(
        () => report([
          phase(extra: {'status': 'unknown'}),
        ]),
        throwsFormatException,
      );
      expect(
        () => report([
          phase(extra: {'warmup': null}),
        ]),
        throwsFormatException,
      );
      expect(
        () => report([
          phase(
            extra: {
              'frames': {
                'count': 1,
                'buildMs': [],
                'rasterMs': [],
                'totalMs': [],
              },
            },
          ),
        ]),
        throwsFormatException,
      );
    });
  });

  group('איסוף תרחישים', () {
    test('מזהה חזרה נדרש וחזרה כפולה באותו launch נדחית', () {
      expect(
        () => report([
          phase(extra: {'iteration': null}),
        ]),
        throwsFormatException,
      );
      expect(() => report([phase(), phase()]), throwsFormatException);
      final result = report([phase(warmup: true), phase()]);
      expect(scenario(result)['measured'], 1);
    });

    test('truncation אינו יוצר אחוזוני frames ממדגם מוטה', () {
      final value = phase(frames: [1, 2]);
      (value['frames'] as Map)['truncated'] = true;
      (value['frames'] as Map)['droppedFrames'] = 5;
      final row = scenario(
        report([
          value,
          phase(frames: [3], iteration: 1),
        ]),
      );
      expect(row['frames']['truncatedIterations'], 1);
      expect(row['frames']['buildMs'], isNull);
      expect(row['latencyMs']['count'], 2);
    });

    test('warmup, כשל ודילוג אינם משפרים או מקלקלים את מדגם ההצלחה', () {
      final result = report([
        phase(duration: 1000, warmup: true, frames: [1000]),
        phase(duration: 10, frames: [1, 2]),
        phase(duration: 20, iteration: 1, frames: [3]),
        phase(duration: 9000, status: 'failed', iteration: 2, frames: [9000]),
        phase(
          status: 'skipped',
          iteration: 3,
          extra: {'reason': 'not available'},
        ),
      ]);
      final row = scenario(result);
      expect(row['measured'], 2);
      expect(row['warmupExcluded'], 1);
      expect(row['failures'], 1);
      expect(row['skipped'], 1);
      expect(row['latencyMs']['p50'], 10);
      expect(row['latencyMs']['p99'], 20);
      expect(row['frames']['buildMs']['count'], 3);
      expect(row['frames']['buildMs']['p95'], 3);
      expect(result['successful'], isFalse);
      expect(result['comparisonEligibility'], contains('failed_run'));
    });

    test('אין מדידה מוצגת כאפס; דילוג נשאר גלוי', () {
      final result = report([phase(status: 'skipped')]);
      final row = scenario(result);
      expect(row['latencyMs'], isNull);
      expect(row['frames']['buildMs'], isNull);
      expect(row['resources']['sampledCpuSeconds'], isNull);
      expect(row['resources']['cpuAverageCorePercent'], isNull);
      expect(row['resources']['treePrivatePeakBytes'], isNull);
      expect(row['resources']['handlesPeak'], isNull);
      expect(row['status'], 'skipped');
      expect(renderProbeMarkdown(result), contains('—'));
    });

    test('heap ומונים נפרדים מ-RSS וערכי delta יכולים להיות שליליים', () {
      final row = scenario(
        report([
          phase(
            extra: {
              'rssStartBytes': 100,
              'rssEndBytes': 80,
              'rssPeakBytes': 120,
              'heapBefore': {
                'heapUsage': 50,
                'externalUsage': 10,
                'isolateCount': 2,
              },
              'heapAfter': {
                'heapUsage': 40,
                'externalUsage': 11,
                'isolateCount': 2,
              },
              'countersBefore': {
                'activeWork': 1,
                'openTabs': 1,
                'queueDepth': null,
              },
              'countersAfter': {
                'activeWork': 0,
                'openTabs': 0,
                'queueDepth': null,
              },
            },
          ),
        ]),
      );
      expect(row['memory']['rssDeltaBytes']['p50'], -20);
      expect(row['heap']['after']['heapUsage']['p50'], 40);
      expect(row['counters']['after']['activeWork']['max'], 0);
      expect(row['counters']['after']['queueDepth'], isNull);
    });

    test('meta ו-done נדרשים לכל הפעלה בנפרד', () {
      final partial = report(
        [],
        changes: {'launchCount': 2},
        records: [
          {'type': 'meta', 'schemaVersion': 2, 'launchIndex': 0},
          phase(launch: 0),
          {'type': 'done', 'launchIndex': 0},
          {'type': 'meta', 'schemaVersion': 2, 'launchIndex': 1},
          phase(launch: 1),
        ],
      );
      expect(partial['complete'], isFalse);
      expect(partial['comparisonEligibility'], contains('incomplete_run'));
    });

    test('legacy נשמר עם מגבלה מפורשת ואינו הופך ל-baseline', () {
      final result = buildProbeReport(
        records: [
          {'type': 'meta', 'pid': 1},
          {
            'type': 'phase',
            'name': 'reader',
            'durationMs': 310,
            'frames': {'count': 5, 'buildP95Ms': 12},
          },
          {'type': 'done'},
        ],
      );
      expect(result['sourceSchemaVersion'], 1);
      expect(result['comparisonEligibility'], contains('legacy_schema'));
      final row = scenario(result, 'reader');
      expect(row['latencyMs']['p50'], 310);
      expect(row['frames']['buildMs'], isNull);
      expect(row['frames']['legacySummaries'].single['buildP95Ms'], 12);
      expect(row['resources']['sampledCpuSeconds'], isNull);
    });
  });

  group('משאבים ועץ תהליכים', () {
    test('דגימות מחוץ לסדר אינן סופרות פעמיים את אותו חלון CPU', () {
      expect(
        () => report(
          [phase(end: 1500)],
          samples: [
            sample(0, 0),
            sample(1000, 1),
            sample(500, .5),
            sample(1500, 1.5),
          ],
        ),
        throwsFormatException,
      );
    });

    test(
      'CPU משוקלל בזמן, אחוזונים לפי intervals וסכום זיכרון באותה דגימה',
      () {
        final row = scenario(
          report(
            [phase(start: 0, end: 1500)],
            samples: [
              sample(0, 10),
              sample(0, 2, pid: 2, identity: '456'),
              sample(500, 10.25),
              sample(500, 2.25, pid: 2, identity: '456'),
              sample(1500, 10.75),
              sample(1500, 2.25, pid: 2, identity: '456'),
            ],
          ),
        );
        final resource = row['resources'];
        expect(resource['sampledCpuSeconds'], 1);
        expect(resource['cpuAverageCorePercent'], closeTo(200 / 3, 1e-8));
        expect(resource['cpuCorePercent']['p50'], 50);
        expect(resource['cpuCorePercent']['p95'], 100);
        expect(resource['cpuCoveredMs'], 1500);
        expect(resource['cpuCoverageFraction'], 1);
        expect(resource['treeWorkingSetPeakBytes'], 40 * 1048576);
        expect(resource['treePrivatePeakBytes'], 20 * 1048576);
        expect(resource['handlesPeak'], 8);
        expect(resource['processesPeak'], 2);
      },
    );

    test('מונה CPU אמיתי ללא שינוי הוא אפס', () {
      final resource = scenario(
        report(
          [phase()],
          samples: [
            sample(0, 2),
            sample(1000, 2),
          ],
        ),
      )['resources'];
      expect(resource['sampledCpuSeconds'], 0);
      expect(resource['cpuAverageCorePercent'], 0);
    });

    test('לא סופרים דגימות halo או CPU שבין שתי חזרות', () {
      final outside = scenario(
        report(
          [phase(start: 100, end: 900)],
          samples: [
            sample(0, 0),
            sample(1000, 50),
          ],
        ),
      )['resources'];
      expect(outside['sampledCpuSeconds'], isNull);
      final row = scenario(
        report(
          [
            phase(start: 0, end: 500),
            phase(start: 1000, end: 1500, iteration: 1),
          ],
          samples: [
            sample(0, 0),
            sample(500, .5),
            sample(1000, 90),
            sample(1500, 90.5),
          ],
        ),
      );
      expect(row['resources']['sampledCpuSeconds'], 1);
      expect(row['resources']['cpuCoveredMs'], 1000);
    });

    test('PID reuse ויצירה או סגירה של ילד אינם חיבור CPU בין תהליכים', () {
      for (final samples in [
        [sample(0, 0), sample(1000, 200, identity: '999')],
        [sample(0, 0), sample(1000, 1), sample(1000, 100, pid: 2)],
        [sample(0, 0), sample(0, 100, pid: 2), sample(1000, 1)],
      ]) {
        final resource = scenario(
          report([phase()], samples: samples),
        )['resources'];
        expect(resource['sampledCpuSeconds'], isNull);
        expect(resource['cpuIntervalCount'], 0);
      }
    });

    test('כשל קריאת CPU אינו אפס ואינו מגושר בדגימה הבאה', () {
      final resource = scenario(
        report(
          [phase()],
          samples: [
            sample(0, 1),
            sample(500, null),
            sample(1000, 4),
          ],
        ),
      )['resources'];
      expect(resource['sampledCpuSeconds'], isNull);
      expect(resource['cpuCoveredMs'], 0);
    });

    test('מונה נסוג וזהות חסרה משאירים CPU לא זמין', () {
      for (final samples in [
        [sample(0, 100), sample(1000, 1)],
        [sample(0, 1, identity: null), sample(1000, 2, identity: null)],
      ]) {
        final resource = scenario(
          report([phase()], samples: samples),
        )['resources'];
        expect(resource['sampledCpuSeconds'], isNull);
      }
    });

    test('ערך חסר בילד אינו מוצג כסך העץ', () {
      final resource = scenario(
        report(
          [phase()],
          samples: [
            sample(0, 0),
            sample(0, 0, pid: 2, private: null, handles: null),
          ],
        ),
      )['resources'];
      expect(resource['treePrivatePeakBytes'], isNull);
      expect(resource['handlesPeak'], isNull);
      expect(resource['treeWorkingSetPeakBytes'], 40 * 1048576);
    });

    test('לא מחברים CPU בין שתי הפעלות עם שעון מונוטוני שמתחיל מחדש', () {
      final result = report(
        [],
        changes: {'launchCount': 2},
        records: [
          for (var launch = 0; launch < 2; launch++) ...[
            {'type': 'meta', 'schemaVersion': 2, 'launchIndex': launch},
            phase(launch: launch),
            {'type': 'done', 'launchIndex': launch},
          ],
        ],
        samples: [
          sample(0, 0),
          sample(1000, 1),
          sample(0, 100, launch: 1),
          sample(1000, 101, launch: 1),
        ],
      );
      expect(result['complete'], isTrue);
      expect(scenario(result)['resources']['sampledCpuSeconds'], 2);
      expect(scenario(result)['resources']['cpuAverageCorePercent'], 100);
    });

    test('שורה כפולה לאותה זהות ובאותה דגימה נדחית', () {
      expect(
        () => report([phase()], samples: [sample(0, 0), sample(0, 0)]),
        throwsFormatException,
      );
    });
  });

  group('השוואת commits', () {
    test('אותו n עם חלוקה שונה של חזרות בין launches אינו השוואה', () {
      Map<String, dynamic> twoLaunches(bool balanced) => report(
        [],
        changes: {'launchCount': 2},
        records: [
          {'type': 'meta', 'schemaVersion': 2, 'launchIndex': 0},
          phase(),
          if (!balanced) phase(iteration: 1),
          {'type': 'done', 'launchIndex': 0},
          {'type': 'meta', 'schemaVersion': 2, 'launchIndex': 1},
          if (balanced) phase(launch: 1),
          phase(name: 'anchor', launch: 1),
          {'type': 'done', 'launchIndex': 1},
        ],
      );
      final comparison = compareProbeReports(
        twoLaunches(true),
        twoLaunches(false),
      );
      final row = (comparison['scenarios'] as List).singleWhere(
        (r) => r['name'] == 'open',
      );
      expect(row['status'], 'different_repetition_layout');
      expect(row.containsKey('metrics'), isFalse);
    });

    test('כשל runner או sampler אינו baseline גם כאשר יש done', () {
      final baseline = report([phase()]);
      for (final changes in [
        {'status': 'failed'},
        {'status': 'running'},
        {'status': null},
        {'samplerErrorCount': 1},
        {'commit': ''},
      ]) {
        final comparison = compareProbeReports(
          baseline,
          report([phase()], changes: changes),
        );
        expect(comparison['comparable'], isFalse, reason: '$changes');
      }
    });

    test('מספרי הבסיס והמועמד נשמרים; אין סף CI', () {
      final baseline = report([phase(duration: 10)]);
      final candidate = report(
        [phase(duration: 15)],
        changes: {
          'commit': '2222222222222222222222222222222222222222',
          'settings': {'fontFamily': 'test-font', 'fontSize': 20},
        },
      );
      final comparison = compareProbeReports(baseline, candidate);
      expect(comparison['comparable'], isTrue);
      final difference =
          comparison['scenarios'].single['metrics']['latencyMs.p50'];
      expect(difference, {
        'baseline': 10.0,
        'candidate': 15.0,
        'available': true,
        'delta': 5.0,
        'deltaPercent': 50.0,
      });
      expect(
        comparison['scenarios']
            .single['metrics']['resources.handlesPeak']['available'],
        isFalse,
      );
    });

    test('אין אחוז שינוי אינסופי כאשר ה-baseline הוא אפס', () {
      final comparison = compareProbeReports(
        report([phase(duration: 0)]),
        report([phase(duration: 1)]),
      );
      final difference =
          comparison['scenarios'].single['metrics']['latencyMs.p50'];
      expect(difference['delta'], 1);
      expect(difference['deltaPercent'], isNull);
      expect(() => jsonEncode(comparison), returnsNormally);
    });

    test(
      'חומרה, build mode, cache state, sampling ופרוטוקול שונים חוסמים השוואה',
      () {
        final baseline = report([phase()]);
        for (final change in [
          {'hardwareId': 'other-host'},
          {'buildMode': 'debug'},
          {'cacheState': 'warm'},
          {'protocolVersion': 3},
          {'fixtureId': 'different-fixture'},
          {
            'sampling': {'intervalMs': 1000},
          },
          {
            'viewport': {'width': 100},
          },
          {'dirty': true},
        ]) {
          final comparison = compareProbeReports(
            baseline,
            report([phase()], changes: change),
          );
          expect(comparison['comparable'], isFalse, reason: '$change');
          expect(
            comparison['scenarios'].single.containsKey('metrics'),
            isFalse,
          );
        }
      },
    );

    test('סתירה בין ה-runner לבין האפליקציה גלויה וחוסמת baseline', () {
      final candidate = report(
        [],
        records: [
          {'type': 'meta', 'schemaVersion': 2, 'buildMode': 'debug'},
          phase(),
          {'type': 'done'},
        ],
      );
      expect(
        candidate['comparisonEligibility'],
        contains('conflicting_metadata:buildMode'),
      );
      expect(
        compareProbeReports(report([phase()]), candidate)['comparable'],
        isFalse,
      );
    });

    test('תרחיש חסר או מדגם בגודל שונה אינם השוואה מוצלחת', () {
      final baseline = report([phase(), phase(name: 'removed')]);
      final candidate = report([
        phase(),
        phase(iteration: 1),
        phase(name: 'added'),
      ]);
      final rows =
          compareProbeReports(baseline, candidate)['scenarios'] as List;
      expect(rows.map((r) => r['status']), [
        'different_sample_count',
        'missing_in_candidate',
        'missing_in_baseline',
      ]);
    });
  });

  test('ה-CLI כותב JSON ו-Markdown מאותם נתונים', () async {
    final directory = Directory.systemTemp.createTempSync('perf-report-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    File(
      '${directory.path}/manifest.json',
    ).writeAsStringSync(jsonEncode(metadata()));
    File('${directory.path}/phases.jsonl').writeAsStringSync(
      [
        {'type': 'meta', 'schemaVersion': 2},
        phase(duration: 12.345),
        {'type': 'done'},
      ].map(jsonEncode).join('\n'),
    );
    final packageConfig = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(packageConfig.readAsStringSync())['packages'] as List;
    final flutter = packages.singleWhere((p) => p['name'] == 'flutter') as Map;
    final root = flutter['rootUri'] as String;
    final flutterUri = packageConfig.uri.resolve(
      root.endsWith('/') ? root : '$root/',
    );
    final dart = File.fromUri(
      flutterUri.resolve(
        '../../bin/cache/dart-sdk/bin/dart${Platform.isWindows ? ".exe" : ""}',
      ),
    ).path;
    final result = await Process.run(dart, [
      'tool/perf_probe/analyze.dart',
      directory.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final json =
        jsonDecode(File('${directory.path}/report.json').readAsStringSync())
            as Map<String, dynamic>;
    final markdown = File('${directory.path}/report.md').readAsStringSync();
    expect(scenario(json)['latencyMs']['p95'], 12.345);
    expect(markdown, contains('12.345'));
    expect(markdown, isNot(contains('NaN')));
  });
}
