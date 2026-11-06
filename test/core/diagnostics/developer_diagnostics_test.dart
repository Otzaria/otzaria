import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

class _BlockedFile extends Fake implements File {
  _BlockedFile(this.delegate);
  final File delegate;
  final started = Completer<void>();
  final release = Completer<void>();
  final recovered = Completer<void>();
  final secondWrite = Completer<void>();
  bool fail = false;
  int successfulWrites = 0;
  int concurrent = 0;
  int maximumConcurrent = 0;

  @override
  Directory get parent => delegate.parent;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    if (!started.isCompleted) started.complete();
    await release.future;
    if (fail) {
      concurrent--;
      throw FileSystemException('Blocked output');
    }
    await delegate.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    concurrent--;
    if (!recovered.isCompleted) recovered.complete();
    if (++successfulWrites == 2) secondWrite.complete();
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseDiagnosticsLaunchMode', () {
    DiagnosticsLaunchMode parse(
      List<String> args, [
      Map<String, String> env = const {},
    ]) => parseDiagnosticsLaunchMode(args, env);

    test('is off by default', () {
      expect(parse(const []), DiagnosticsLaunchMode.off);
      expect(parse(const ['otzaria://open']), DiagnosticsLaunchMode.off);
    });

    test('reads the command-line flag in its accepted spellings', () {
      for (final flag in [
        '--dev-diagnostics',
        '/dev-diagnostics',
        '--DEV_DIAGNOSTICS',
      ]) {
        expect(parse([flag]), DiagnosticsLaunchMode.panel, reason: flag);
      }
      expect(parse(['--dev-diagnostics=log']), DiagnosticsLaunchMode.logOnly);
    });

    test('falls back to the environment variable', () {
      expect(
        parse(const [], {devDiagnosticsEnv: '1'}),
        DiagnosticsLaunchMode.panel,
      );
      expect(
        parse(const [], {devDiagnosticsEnv: 'log'}),
        DiagnosticsLaunchMode.logOnly,
      );
      expect(
        parse(const [], {devDiagnosticsEnv: '0'}),
        DiagnosticsLaunchMode.off,
      );
    });
  });

  test('computeFrameStats summarizes the window', () {
    final stats = computeFrameStats(
      const [
        FrameSample(2, 1, 5),
        FrameSample(4, 1, 8),
        FrameSample(30, 4, 40),
      ],
      window: const Duration(seconds: 2),
      slowTotal: 7,
    );
    expect(stats.framesPerSecond, 2);
    expect(stats.buildAvgMs, 12.0);
    expect(stats.buildMaxMs, 30.0);
    expect(stats.rasterMaxMs, 4.0);
    expect(stats.slowInWindow, 1);
    expect(stats.slowTotal, 7);
  });

  group('estimateRefreshDelta', () {
    const before = EstimateRefreshStats(
      refreshCount: 2,
      lastRefreshItemCount: 50,
      deferredResizeCount: 1,
      skippedResizeCount: 3,
    );

    test('sums the change of every list, counting a new list from zero', () {
      final window = estimateRefreshDelta(const [
        (
          before,
          EstimateRefreshStats(
            refreshCount: 3,
            lastRefreshItemCount: 50,
            lastRefreshDuration: Duration(microseconds: 1500),
            deferredResizeCount: 2,
            skippedResizeCount: 3,
          ),
        ),
        (
          null,
          EstimateRefreshStats(
            refreshCount: 1,
            lastRefreshItemCount: 1000,
            lastRefreshDuration: Duration(microseconds: 2500),
            skippedResizeCount: 4,
          ),
        ),
      ]);
      expect(window.toJson(), {
        'count': 2,
        'totalMs': 4.0,
        'items': 1050,
        'deferred': 1,
        'skipped': 4,
      });
    });

    test('omits the duration when a list refreshed more than once', () {
      final window = estimateRefreshDelta(const [
        (
          before,
          EstimateRefreshStats(
            refreshCount: 5,
            lastRefreshItemCount: 50,
            lastRefreshDuration: Duration(milliseconds: 2),
            deferredResizeCount: 1,
            skippedResizeCount: 3,
          ),
        ),
      ]);
      expect(window.count, 3);
      expect(window.items, 150);
      expect(window.totalMs, isNull);
      expect(window.toJson(), isNot(contains('totalMs')));
    });

    test('a tick without changes is left out of the stats', () {
      final window = estimateRefreshDelta(const [(before, before)]);
      expect(window.isEmpty, isTrue);
      final stats = computeFrameStats(
        const [],
        window: const Duration(seconds: 2),
        slowTotal: 0,
        estimates: window,
      );
      expect(stats.estimates, isNull);
      expect(stats.toJson(), isNot(contains('estimates')));
    });
  });

  group('DeveloperDiagnostics', () {
    late File output;
    late List<String> errorLog;
    final diagnostics = DeveloperDiagnostics.instance;

    setUp(() {
      errorLog = [];
      output = File(
        '${Directory.systemTemp.createTempSync('diag').path}/out.jsonl',
      );
      diagnostics
        ..resetForTesting()
        ..outputPath = output.path
        ..errorLogWriter = errorLog.add;
    });

    tearDown(diagnostics.resetForTesting);

    List<Map<String, dynamic>> records() => [
      for (final line in output.readAsLinesSync())
        jsonDecode(line) as Map<String, dynamic>,
    ];

    test('nothing is collected or written while off', () {
      diagnostics.initFromLaunch(const [], environment: const {});
      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);
      expect(output.existsSync(), isFalse);
    });

    test('log-only launch collects without showing the panel', () async {
      diagnostics.initFromLaunch(const [
        '--dev-diagnostics=log',
      ], environment: const {});
      expect(diagnostics.isCollecting, isTrue);
      expect(diagnostics.panelVisible.value, isFalse);

      await diagnostics.snapshot();
      final types = records().map((r) => r['type']).toList();
      expect(types, ['session', 'snapshot']);
    });

    test(
      'collection state notifies only on log-only start, stop and reset',
      () async {
        final changes = <bool>[];
        void onChange() {
          expect(diagnostics.collectionState.value, diagnostics.isCollecting);
          changes.add(diagnostics.collectionState.value);
        }

        diagnostics.collectionState.addListener(onChange);
        addTearDown(() => diagnostics.collectionState.removeListener(onChange));

        diagnostics.initFromLaunch(const [
          '--dev-diagnostics=log',
        ], environment: const {});
        expect(diagnostics.panelVisible.value, isFalse);
        diagnostics.debugTick();
        diagnostics.debugTick();
        diagnostics.initFromLaunch(const [
          '--dev-diagnostics=log',
        ], environment: const {});
        expect(changes, [true]);
        diagnostics.toggle();
        expect(changes, [true, false]);
        diagnostics.toggle();
        expect(changes, [true, false, true]);
        await diagnostics.snapshot();
        diagnostics.resetForTesting();
        diagnostics.resetForTesting();
        expect(changes, [true, false, true, false]);
      },
    );

    test(
      'launch diagnostics records OS enrichment once without restarting',
      () async {
        var osVersion = 'raw kernel';
        diagnostics.osVersionForTesting = () => osVersion;
        diagnostics.initFromLaunch(const [
          '--dev-diagnostics=log',
        ], environment: const {});
        osVersion = 'Ubuntu 24.04; kernel 6.8';
        diagnostics.debugTick();
        diagnostics.debugTick();
        await diagnostics.snapshot();
        final log = records();
        expect(log.first['osVersion'], 'raw kernel');
        expect(
          log.where((record) => record['type'] == 'session'),
          hasLength(1),
        );
        expect(log.where((record) => record['type'] == 'os_version'), [
          containsPair('osVersion', osVersion),
        ]);
        expect(log.last['osVersion'], osVersion);
        expect(diagnostics.isCollecting, isTrue);
      },
    );

    test(
      'OS enrichment is ignored while off and a new session uses the cache',
      () async {
        var osVersion = 'raw kernel';
        diagnostics.osVersionForTesting = () => osVersion;
        diagnostics.toggle();
        diagnostics.toggle();
        osVersion = 'Android 15; API 35';
        diagnostics.debugTick();
        diagnostics.toggle();
        diagnostics.debugTick();
        await diagnostics.snapshot();
        final log = records();
        expect(log.where((record) => record['type'] == 'os_version'), isEmpty);
        expect(
          log.where((record) => record['type'] == 'session').last['osVersion'],
          osVersion,
        );
      },
    );

    test(
      'diagnostics started after OS warmup needs no metadata correction',
      () async {
        diagnostics.osVersionForTesting = () =>
            'macOS Version 15.4.1 (Build 24E263)';
        diagnostics.toggle();
        diagnostics.debugTick();
        await diagnostics.snapshot();
        final log = records();
        expect(log.first['osVersion'], 'macOS Version 15.4.1 (Build 24E263)');
        expect(log.where((record) => record['type'] == 'os_version'), isEmpty);
      },
    );

    test('stats records carry the smartText counters', () async {
      diagnostics.toggle();
      expect(SmartTextRenderStats.enabled, isTrue);
      SmartTextRenderStats.fastLine(heading: false);
      SmartTextRenderStats.fullLine(columnMode: true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await diagnostics.snapshot();

      final stats = records().firstWhere((r) => r['type'] == 'stats');
      expect(stats['smartText'], containsPair('fastInline', 1));
      expect(stats['smartText'], containsPair('fullHtml', 1));

      diagnostics.toggle();
      expect(SmartTextRenderStats.enabled, isFalse);
    });

    test('DB backlog is sampled while idle without starting workers', () async {
      final gate = Completer<void>();
      final reads = [
        for (var i = 0; i < 3; i++)
          DbReadWorker.trackFallbackRead(() => gate.future),
      ];
      try {
        diagnostics.toggle();
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await diagnostics.snapshot();
        final sample = records().firstWhere(
          (record) => record['type'] == 'stats',
        );
        expect(sample['fps'], 0);
        expect(sample['dbReads'], containsPair('liveWorkers', 0));
        expect(sample['dbReads'], containsPair('activeFallbackReads', 2));
        expect(sample['dbReads'], containsPair('queuedReads', 1));
        expect(sample['dbReads']['estimatedQueuedBytes'], greaterThan(0));
      } finally {
        gate.complete();
        await Future.wait(reads);
      }
      await diagnostics.snapshot();
      final latest = records().lastWhere(
        (record) => record['type'] == 'snapshot',
      );
      expect(latest['dbReads'], containsPair('activeFallbackReads', 0));
      expect(latest['dbReads'], containsPair('queuedReads', 0));
      expect(latest['dbReads'], containsPair('estimatedQueuedBytes', 0));
      expect(DbReadWorker.resourceUsage.liveWorkers, 0);
    });

    test('toggling off a launch request stops collecting', () {
      diagnostics
        ..initFromLaunch(const ['--dev-diagnostics'], environment: const {})
        ..toggle();
      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);

      diagnostics.toggle();
      expect(diagnostics.isCollecting, isTrue);
      expect(diagnostics.panelVisible.value, isTrue);
    });

    test('snapshot includes the app context', () async {
      diagnostics.contextProvider = () => {'screen': 'reading', 'tabs': 3};
      diagnostics.toggle();
      await diagnostics.snapshot();

      final snapshot = records().firstWhere((r) => r['type'] == 'snapshot');
      expect(snapshot['context'], {'screen': 'reading', 'tabs': 3});
      expect(snapshot, contains('rssMb'));
      expect(errorLog.single, startsWith('=== Developer snapshot'));
    });

    testWidgets('stopping restores the paint flags present before collection', (
      tester,
    ) async {
      final color = debugCurrentRepaintColor;
      try {
        diagnostics.toggle();
        debugRepaintRainbowEnabled = true;
        debugPaintSizeEnabled = true;
        diagnostics.toggle();
        expect(debugRepaintRainbowEnabled, isFalse);
        expect(debugPaintSizeEnabled, isFalse);
        await tester.idle();
        debugPaintSizeEnabled = true;
        diagnostics.toggle();
        debugPaintSizeEnabled = false;
        diagnostics.toggle();
        expect(debugPaintSizeEnabled, isTrue);
        await tester.idle();
      } finally {
        debugRepaintRainbowEnabled = false;
        debugPaintSizeEnabled = false;
        debugCurrentRepaintColor = color;
      }
    });

    test('failed output is retained for one explicit snapshot retry', () async {
      final changes = <bool>[];
      void onChange() => changes.add(diagnostics.collectionState.value);
      diagnostics.collectionState.addListener(onChange);
      addTearDown(() => diagnostics.collectionState.removeListener(onChange));
      final blocked = File('${output.parent.path}/blocked')
        ..writeAsStringSync('not a directory');
      diagnostics.outputPath = '${blocked.path}/out.jsonl';
      diagnostics.toggle();
      expect(await diagnostics.snapshot(), isNull);
      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);
      expect(changes, [true, false]);
      expect(errorLog, isEmpty);
      await blocked.delete();
      expect(await diagnostics.snapshot(), diagnostics.outputPath);
      expect(changes, [true, false]);
      final restored = File(diagnostics.outputPath)
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(
        restored.where((record) => record['type'] == 'session'),
        hasLength(1),
      );
      expect(
        restored.where((record) => record['type'] == 'snapshot'),
        hasLength(2),
      );
    });

    test('concurrent snapshots each persist once', () async {
      diagnostics.toggle();
      await Future.wait([diagnostics.snapshot(), diagnostics.snapshot()]);
      expect(
        records().where((record) => record['type'] == 'session'),
        hasLength(1),
      );
      expect(
        records().where((record) => record['type'] == 'snapshot'),
        hasLength(2),
      );
    });

    test(
      'blocked output serializes snapshots and persists stop once',
      () async {
        final blocked = _BlockedFile(output);
        await IOOverrides.runZoned(() async {
          diagnostics.toggle();
          final first = diagnostics.snapshot();
          await blocked.started.future;
          final second = diagnostics.snapshot();
          diagnostics.toggle();
          expect(diagnostics.isCollecting, isFalse);
          blocked.release.complete();
          await Future.wait([first, second]);
        }, createFile: (_) => blocked);
        expect(blocked.maximumConcurrent, 1);
        expect(
          records().where((record) => record['type'] == 'snapshot'),
          hasLength(2),
        );
        expect(
          records().where((record) => record['type'] == 'end'),
          hasLength(1),
        );
      },
    );

    test(
      'blocked output bounds pending slow frames and toggle recovers',
      () async {
        final blocked = _BlockedFile(output)..fail = true;
        await IOOverrides.runZoned(() async {
          diagnostics.toggle();
          final saving = diagnostics.snapshot();
          await blocked.started.future;
          final timing = FrameTiming(
            vsyncStart: 0,
            buildStart: 0,
            buildFinish: 100000,
            rasterStart: 100000,
            rasterFinish: 110000,
            rasterFinishWallTime: DateTime.now().microsecondsSinceEpoch,
          );
          TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .onReportTimings!(
            List.filled(5000, timing),
          );
          expect(diagnostics.isCollecting, isFalse);
          var periodicTimers = 0;
          runZoned(
            diagnostics.toggle,
            zoneSpecification: ZoneSpecification(
              createPeriodicTimer: (self, parent, zone, duration, callback) {
                periodicTimers++;
                return parent.createPeriodicTimer(zone, duration, callback);
              },
            ),
          );
          expect(diagnostics.isCollecting, isFalse);
          expect(periodicTimers, 0);
          blocked.release.complete();
          expect(await saving, isNull);
          blocked.fail = false;
          diagnostics.toggle();
          await blocked.recovered.future;
          await Future<void>.delayed(Duration.zero);
          expect(diagnostics.isCollecting, isTrue);
          diagnostics.toggle();
          await diagnostics.snapshot();
        }, createFile: (_) => blocked);
        final slow = records().where(
          (record) => record['type'] == 'slow_frame',
        );
        expect(slow.length, inInclusiveRange(1000, 4999));
        expect(blocked.maximumConcurrent, 1);
        expect(
          records().where((record) => record['type'] == 'snapshot'),
          hasLength(2),
        );
      },
    );

    test(
      'cap drains remaining records after a blocked write succeeds',
      () async {
        final blocked = _BlockedFile(output);
        await IOOverrides.runZoned(() async {
          diagnostics.toggle();
          final saving = diagnostics.snapshot();
          await blocked.started.future;
          final timing = FrameTiming(
            vsyncStart: 0,
            buildStart: 0,
            buildFinish: 100000,
            rasterStart: 100000,
            rasterFinish: 110000,
            rasterFinishWallTime: DateTime.now().microsecondsSinceEpoch,
          );
          TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .onReportTimings!(
            List.filled(10000, timing),
          );
          expect(diagnostics.isCollecting, isFalse);
          blocked.release.complete();
          await saving;
          await blocked.secondWrite.future.timeout(const Duration(seconds: 5));
          diagnostics.toggle();
          TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .onReportTimings!(
            List.filled(100, timing),
          );
          expect(diagnostics.isCollecting, isTrue);
          diagnostics.toggle();
          await diagnostics.snapshot();
        }, createFile: (_) => blocked);
        expect(blocked.maximumConcurrent, 1);
        expect(
          records().where((record) => record['type'] == 'slow_frame'),
          hasLength(4194),
        );
      },
    );

    test(
      'launch diagnostics runs after existing version initialization',
      () async {
        final source = File('lib/main.dart').readAsStringSync();
        final start = source.indexOf('void main(List<String> args) async {');
        final end = source.indexOf('void _installGlobalErrorHandlers()', start);
        final mainSource = source.substring(start, end);
        expect(
          mainSource.indexOf(
            'DeveloperDiagnostics.instance.initFromLaunch(args)',
          ),
          greaterThan(mainSource.indexOf('await _initializeLogMetadata()')),
        );
        ErrorLogFile.setAppVersion('1.2.3+45');
        diagnostics.initFromLaunch(const [
          '--dev-diagnostics=log',
        ], environment: const {});
        await diagnostics.snapshot();
        expect(records().first['version'], '1.2.3+45');
      },
    );

    group('process tree', () {
      const sample = ProcessTreeSample(
        webviewCollection: ProcessCollection.collected(),
        hostPrivMb: 260,
        webview: {
          'RENDERER': (
            count: 2,
            observedCount: 2,
            privMb: 120,
            eachMb: [70, 50],
            pages: [],
            measuredPageCount: 0,
          ),
        },
      );
      late int calls;

      setUp(() {
        calls = 0;
        diagnostics.processSampler = () async {
          calls++;
          return sample;
        };
      });

      Future<void> settle() => Future<void>.delayed(Duration.zero);

      // חייב לרוץ ראשון: אחריו ציר הזמן מסומן כחשוף לכל הקובץ.
      test('is not sampled before the window is revealed', () async {
        expect(StartupTimeline.instance.toJson()['revealMs'], isNull);
        diagnostics.toggle();
        for (var i = 0; i < 10; i++) {
          diagnostics.debugTick();
          await settle();
        }
        expect(calls, 0);
      });

      group('after reveal', () {
        setUpAll(StartupTimeline.instance.finishAtReveal);

        test('is sampled once every few ticks', () async {
          diagnostics.toggle();
          for (var i = 0; i < 11; i++) {
            diagnostics.debugTick();
            await settle();
          }
          expect(calls, 3);
        });

        test('a slow sample is never overlapped', () async {
          final pending = Completer<ProcessTreeSample?>();
          diagnostics.processSampler = () {
            calls++;
            return pending.future;
          };
          diagnostics.toggle();
          for (var i = 0; i < 12; i++) {
            diagnostics.debugTick();
            await settle();
          }
          expect(calls, 1);
          pending.complete(sample);
        });

        test(
          'a fresh sample writes a stats line even without frames',
          () async {
            diagnostics.toggle();
            diagnostics.debugTick();
            await settle();
            diagnostics.debugTick();
            diagnostics.debugTick();
            expect(diagnostics.stats.value.processes, sample);
            await diagnostics.snapshot();

            final stats = records().where((r) => r['type'] == 'stats');
            expect(stats, hasLength(1));
            expect(stats.single['processes'], sample.toJson());
            final snapshot = records().singleWhere(
              (r) => r['type'] == 'snapshot',
            );
            expect(snapshot['processes']['webviewPrivMb'], 120);
            expect(snapshot['processes'], contains('ageMs'));
          },
        );

        test('a failing sampler does not stop collection', () async {
          diagnostics.processSampler = () async {
            calls++;
            throw StateError('no access');
          };
          diagnostics.toggle();
          for (var i = 0; i < 6; i++) {
            diagnostics.debugTick();
            await settle();
          }
          expect(diagnostics.isCollecting, isTrue);
          expect(calls, 2);
          expect(diagnostics.stats.value.processes, isNull);
        });

        test('a sample that lands after stopping is dropped', () async {
          final pending = Completer<ProcessTreeSample?>();
          diagnostics.processSampler = () => pending.future;
          diagnostics.toggle();
          diagnostics.debugTick();
          diagnostics.toggle();
          pending.complete(sample);
          await settle();
          diagnostics.processSampler = () async => null;
          diagnostics.toggle();
          diagnostics.debugTick();
          await settle();
          expect(diagnostics.stats.value.processes, isNull);
        });

        test(
          'a sample from an earlier session is dropped after restart',
          () async {
            final pending = Completer<ProcessTreeSample?>();
            diagnostics.processSampler = () => pending.future;
            diagnostics.toggle();
            diagnostics.debugTick();
            diagnostics
              ..toggle()
              ..toggle();
            expect(diagnostics.isCollecting, isTrue);
            pending.complete(sample);
            await settle();
            diagnostics.debugTick();
            // הדגימה של ה-session הקודם לא נקלטה; ה-tick רק התחיל דגימה חדשה.
            expect(diagnostics.stats.value.processes, isNull);
          },
        );

        testWidgets(
          'enumeration timeout retains host within the diagnostics deadline',
          (tester) async {
            final pending = Completer<WebViewProcessSnapshot>();
            diagnostics.processSampler = () => sampleWindowsProcessTree(
              webViewProcesses: () => pending.future,
              readBytes: (ids) async => [8 << 20],
            );
            diagnostics.toggle();
            diagnostics.debugTick();
            await tester.pump(const Duration(seconds: 1));
            diagnostics.debugTick();
            final sample = diagnostics.stats.value.processes;
            expect(sample, isNotNull);
            expect(sample!.hostPrivMb, 8);
            expect(sample.webviewCollection.reason, 'process_info_timeout');
            expect(sample.observedProcessCount, isNull);
            pending.completeError(StateError('late collection failure'));
            await tester.pump();
            diagnostics.resetForTesting();
          },
        );

        test(
          'the default sampler uses the registered WebView lister',
          () async {
            diagnostics.resetForTesting();
            var listed = 0;
            diagnostics.webViewProcessLister = () async {
              listed++;
              return const WebViewProcessSnapshot.collected([]);
            };
            diagnostics.toggle();
            diagnostics.debugTick();
            await Future<void>.delayed(const Duration(milliseconds: 300));
            expect(listed, Platform.isWindows ? 1 : 0);
          },
        );
      });
    });

    testWidgets('stats count the estimate refreshes of a tracked list since '
        'collection started', (tester) async {
      final width = ValueNotifier(400.0);
      final layoutKey = ValueNotifier<Object?>(null);
      final controller = ItemScrollController();
      addTearDown(width.dispose);
      addTearDown(layoutKey.dispose);
      // שני מופעים על אותו בקר, כמו בהחלפת תצוגה באותו פריים.
      diagnostics
        ..trackEstimateRefreshes(controller)
        ..trackEstimateRefreshes(controller);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.topLeft,
            child: ListenableBuilder(
              listenable: Listenable.merge([width, layoutKey]),
              builder: (_, _) => SizedBox(
                width: width.value,
                height: 300,
                child: ScrollablePositionedList.builder(
                  itemScrollController: controller,
                  itemCount: 100,
                  crossAxisLayoutKey: layoutKey.value == null
                      ? null
                      : (_) => layoutKey.value,
                  estimateExtent: (_, crossAxis) => 40000 / crossAxis,
                  itemBuilder: (_, index) => SizedBox(height: 100.0 + index),
                ),
              ),
            ),
          ),
        ),
      );
      // לפני תחילת האיסוף: אינו נספר.
      width.value = 380;
      await tester.pump();

      diagnostics.toggle();
      await tester.pump(const Duration(seconds: 1));
      expect(diagnostics.stats.value.estimates, isNull);
      diagnostics.untrackEstimateRefreshes(controller);

      width.value = 360;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final refreshed = diagnostics.stats.value.estimates!;
      expect(refreshed.count, 1);
      expect(refreshed.items, 100);
      expect(refreshed.totalMs, isNotNull);
      expect(refreshed.skipped, 0);

      layoutKey.value = 'same';
      await tester.pump();
      width.value = 340;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final skipped = diagnostics.stats.value.estimates!;
      expect(skipped.count, 0);
      expect(skipped.skipped, 1);

      diagnostics
        ..untrackEstimateRefreshes(controller)
        ..toggle();
    });

    test('toggling it off stops collecting', () {
      diagnostics.toggle();
      expect(diagnostics.isCollecting, isTrue);
      expect(diagnostics.panelVisible.value, isTrue);
      diagnostics.performanceOverlay.value = true;
      diagnostics.toggle();

      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);
      expect(diagnostics.performanceOverlay.value, isFalse);
    });
  });
}
