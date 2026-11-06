import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/frame_stats_overlay.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}

void main() {
  late String outputPath;

  setUp(() {
    outputPath =
        '${Directory.systemTemp.createTempSync('diag').path}/out.jsonl';
    DeveloperDiagnostics.instance
      ..resetForTesting()
      ..outputPath = outputPath
      ..errorLogWriter = (_) {}
      ..processSampler = () async => null;
  });

  tearDown(() => DeveloperDiagnostics.instance.resetForTesting());

  Widget host() => const MaterialApp(home: FrameStatsOverlay(child: _Probe()));

  Future<void> pressShortcut(
    WidgetTester tester, {
    LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
  }) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets(
    'diagnostics describe the active window across focus and disposal',
    (
      tester,
    ) async {
      final first = AppWindowKeys();
      final second = AppWindowKeys(id: AppWindowId('view:2'));
      AppWindowKeys.register(first);
      AppWindowKeys.register(second);
      addTearDown(AppWindowKeys.resetForTest);

      Widget window(AppWindowKeys keys, String title) => AppWindowScope(
        controller: _FakeWindow(),
        geometry: _FakeWindow(),
        keys: keys,
        child: FrameStatsOverlay(
          contextProvider: () => {'title': title},
          child: const SizedBox(),
        ),
      );
      Widget host({bool showSecond = true}) => Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            window(first, 'ראשון'),
            if (showSecond) window(second, 'שני'),
          ],
        ),
      );

      AppWindowKeys.activate(first);
      await tester.pumpWidget(host());
      expect(
        DeveloperDiagnostics.instance.contextProvider!()['title'],
        'ראשון',
      );
      AppWindowKeys.activate(second);
      expect(DeveloperDiagnostics.instance.contextProvider!()['title'], 'שני');
      AppWindowKeys.unregister(second);
      await tester.pumpWidget(host(showSecond: false));
      expect(
        DeveloperDiagnostics.instance.contextProvider!()['title'],
        'ראשון',
      );
      await tester.pumpWidget(const SizedBox());
      expect(DeveloperDiagnostics.instance.contextProvider!(), isEmpty);
    },
  );

  testWidgets('Ctrl+Shift+I turns developer mode on and off', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byType(FrameStatsPanel), findsNothing);

    await pressShortcut(tester);
    expect(find.byType(FrameStatsPanel), findsOneWidget);
    expect(DeveloperDiagnostics.instance.isCollecting, isTrue);

    await pressShortcut(tester);
    expect(find.byType(FrameStatsPanel), findsNothing);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });

  testWidgets('Cmd+Shift+I works too', (tester) async {
    await tester.pumpWidget(host());
    await pressShortcut(tester, modifier: LogicalKeyboardKey.metaLeft);
    expect(find.byType(FrameStatsPanel), findsOneWidget);

    await pressShortcut(tester, modifier: LogicalKeyboardKey.metaLeft);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });

  testWidgets('Ctrl+I and Shift+I are ignored', (tester) async {
    await tester.pumpWidget(host());
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
    expect(find.byType(FrameStatsPanel), findsNothing);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });

  testWidgets('toggling the panel keeps the app state', (tester) async {
    await tester.pumpWidget(host());
    final before = tester.state(find.byType(_Probe));

    await pressShortcut(tester);
    await tester.pump();
    expect(identical(tester.state(find.byType(_Probe)), before), isTrue);

    await pressShortcut(tester);
    expect(identical(tester.state(find.byType(_Probe)), before), isTrue);
  });

  testWidgets('the panel works above the Navigator, as in App.builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FrameStatsOverlay(child: child!),
        home: const _Probe(),
      ),
    );
    DeveloperDiagnostics.instance.toggle();
    await tester.pump();

    final stats = find.textContaining('frames/s');
    expect(stats, findsOneWidget);
    expect(
      find.ancestor(of: stats, matching: find.byType(Material)),
      findsWidgets,
      reason: 'text without a Material ancestor renders with debug underlines',
    );
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    expect(tester.takeException(), isNull);

    DeveloperDiagnostics.instance.resetForTesting();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed snapshot reports an error instead of saved', (
    tester,
  ) async {
    final blocked = File('$outputPath.blocked')..writeAsStringSync('blocked');
    DeveloperDiagnostics.instance.outputPath = '${blocked.path}/out.jsonl';
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => FrameStatsOverlay(child: child!),
        home: const _Probe(),
      ),
    );
    DeveloperDiagnostics.instance.toggle();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(FluentIcons.camera_24_regular));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();
    expect(find.text(CommonMessages.diagnosticsSaveError), findsOneWidget);
    expect(find.textContaining('saved:'), findsNothing);
    expect(tester.takeException(), isNull);
    UiSnack.hide();
    await tester.pump();
  });

  test('formatFrameStats shows timings, memory and top rebuilds', () {
    final text = formatFrameStats(
      const FrameStats(
        framesPerSecond: 2,
        buildAvgMs: 12,
        buildMaxMs: 30,
        rasterAvgMs: 2,
        rasterMaxMs: 4,
        slowInWindow: 1,
        slowTotal: 7,
        rssMb: 420,
        peakRssMb: 512,
        topRebuilds: [MapEntry('TextBookScreen', 10)],
      ),
    );
    expect(text, contains('frames/s  2'));
    expect(text, contains('build ms  avg 12.0  max 30.0'));
    expect(text, contains('raster ms avg 2.0  max 4.0'));
    expect(text, contains('slow      1 (2s)  total 7'));
    expect(text, contains('memory    420 MiB  peak 512 MiB'));
    expect(text, contains('rebuild   10x TextBookScreen'));
  });

  test('formatFrameStats shows the WebView process tree when sampled', () {
    final text = formatFrameStats(
      const FrameStats(
        rssMb: 300,
        peakRssMb: 320,
        processes: ProcessTreeSample(
          metric: ProcessMemoryMetric.privateCommit,
          hostPrivMb: 262,
          webview: {
            'BROWSER': (count: 1, privMb: 61, eachMb: [61], pages: []),
            'RENDERER': (count: 2, privMb: 130, eachMb: [70, 60], pages: []),
          },
        ),
      ),
    );
    expect(text, contains('memory    300 MiB  peak 320 MiB  commit 262 MiB'));
    expect(
      text,
      contains('webview   commit 191 MiB  3 proc  2 rend 130 MiB (max 70)'),
    );
  });

  test('formatFrameStats distinguishes anonymous RSS from private commit', () {
    final text = formatFrameStats(
      const FrameStats(
        processes: ProcessTreeSample(
          metric: ProcessMemoryMetric.anonymousRss,
          hostPrivMb: 15,
          webview: {
            'RENDERER': (count: 1, privMb: 4, eachMb: [4], pages: []),
          },
        ),
      ),
    );
    expect(text, contains('RssAnon 15 MiB'));
    expect(text, contains('webview   RssAnon 4 MiB'));
    expect(text, isNot(contains('commit')));
    expect(text, isNot(contains('priv')));
  });

  test('unknown metrics do not claim private memory or commit', () {
    final text = formatFrameStats(
      const FrameStats(processes: ProcessTreeSample(hostPrivMb: 2)),
    );
    expect(text, contains('memory 2 MiB'));
    expect(text, isNot(contains('commit')));
    expect(text, isNot(contains('priv')));
    expect(text, isNot(contains('RssAnon')));
  });

  test('renderer details can be absent without fabricating a maximum', () {
    final text = formatFrameStats(
      const FrameStats(
        processes: ProcessTreeSample(
          metric: ProcessMemoryMetric.privateCommit,
          webview: {
            'RENDERER': (count: 1, privMb: 4, eachMb: [], pages: []),
          },
        ),
      ),
    );
    expect(text, contains('webview   commit 4 MiB  1 proc  1 rend 4 MiB'));
    expect(text, isNot(contains('max 0')));
    expect(text, isNot(contains('(max')));
  });

  test('formatFrameStats has no process line without a sample', () {
    expect(formatFrameStats(const FrameStats()), isNot(contains('webview')));
  });

  test('formatFrameStats shows estimate refreshes when there were any', () {
    final text = formatFrameStats(
      const FrameStats(
        estimates: EstimateRefreshWindow(
          count: 2,
          totalMs: 12.5,
          items: 380000,
          deferred: 1,
          skipped: 3,
        ),
      ),
    );
    expect(
      text,
      contains('estimates 2x  12.5 ms  380000 items  deferred 1  skipped 3'),
    );
    expect(formatFrameStats(const FrameStats()), isNot(contains('estimates')));
  });

  test('formatFrameStats handles an idle window', () {
    final text = formatFrameStats(const FrameStats());
    expect(text, contains('frames/s  0'));
    expect(text, contains('avg -  max -'));
  });

  testWidgets('two windows in one isolate toggle once, from the active one', (
    tester,
  ) async {
    final original = AppWindowKeys.current;
    addTearDown(() => AppWindowKeys.activate(original));
    final window = _FakeWindow();
    final a = AppWindowKeys(id: const AppWindowId('a'));
    final b = AppWindowKeys(id: const AppWindowId('b'));
    Widget tree(AppWindowKeys keys) => Expanded(
      child: AppWindowScope(
        controller: window,
        geometry: window,
        keys: keys,
        child: const FrameStatsOverlay(child: _Probe()),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(children: [tree(a), tree(b)]),
      ),
    );
    AppWindowKeys.activate(b);

    await pressShortcut(tester);
    expect(DeveloperDiagnostics.instance.isCollecting, isTrue);

    await pressShortcut(tester);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });
}
