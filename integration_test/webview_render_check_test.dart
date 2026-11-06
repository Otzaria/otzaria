// הרצה: flutter test integration_test/webview_render_check_test.dart -d windows
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart'
    show WindowsWebViewCreationFailures;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:win32/win32.dart';

const _nativeDeadline = Duration(seconds: 10);
const _probeHtml = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>lifecycle-check</title></head>
<body><div id="marker">webview-alive</div><textarea id="draft"></textarea>
<script>
window.probeValue = 42;
window.probeState = {schemaVersion: 2, revision: 0};
window.probeTicks = 0;
setInterval(() => {
  window.probeTicks++;
  const until = performance.now() + 2;
  while (performance.now() < until) {}
}, 20);
</script>
</body>
</html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WebView2 confirms suspend, preserves drafts, and releases repeated hosts',
    (tester) async {
      final dataDir = await Directory.systemTemp.createTemp('wv2_render_check');
      AppPaths.debugOverrideDataRootPath(dataDir.path);
      final counts = <String, int>{
        'hostsCreated': 0,
        'nativeHostsClosed': 0,
        'pauseAttempts': 0,
        'pauseConfirmed': 0,
      };
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await WebViewEnvironmentHolder.disposeForAppRestart();
        AppPaths.debugOverrideDataRootPath(null);
        _report({'phase': 'summary', ...counts});
        try {
          await dataDir.delete(recursive: true);
        } catch (_) {}
      });

      final version = await WebViewEnvironment.getAvailableVersion();
      expect(version, isNotNull, reason: 'WebView2 Runtime חסר במחשב');
      _report({'phase': 'runtime', 'webView2Version': version});

      WebViewEnvironment? previousEnvironment;
      for (var cycle = 1; cycle <= 3; cycle++) {
        await Future.wait([
          WebViewEnvironmentHolder.initialize(),
          WebViewEnvironmentHolder.initialize(),
        ]);
        final environment = WebViewEnvironmentHolder.environment;
        expect(environment, isNotNull);
        expect(environment, isNot(same(previousEnvironment)));
        final probe = await _renderProbe(
          tester,
          environment!,
          cycle: cycle,
          onCreated: () => counts['hostsCreated'] = counts['hostsCreated']! + 1,
        );
        final controller = probe.controller;
        final draft = 'draft-$cycle: טיוטה שטרם נשמרה';
        await controller
            .evaluateJavascript(
              source:
                  '''
            window.probeState.revision = $cycle;
            document.getElementById('draft').value = ${jsonEncode(draft)};
          ''',
            )
            .timeout(_nativeDeadline);
        await _checkState(controller, cycle, draft);

        for (var sample = 0; sample < 2; sample++) {
          await _measureResources(environment, cycle, 'active', sample);
        }
        counts['pauseAttempts'] = counts['pauseAttempts']! + 1;
        final pauseWatch = Stopwatch()..start();
        final pauseError = await _pauseOutcome(controller);
        pauseWatch.stop();
        expect(pauseError, anyOf(isNull, 'WEBVIEW_SUSPEND_REJECTED'));
        if (pauseError == null) {
          counts['pauseConfirmed'] = counts['pauseConfirmed']! + 1;
        }
        _report({
          'cycle': cycle,
          'phase': 'pauseCompletion',
          'confirmed': pauseError == null,
          'error': pauseError,
          'awaitMicros': pauseWatch.elapsedMicroseconds,
        });

        // אין evaluateJavascript במופע המושהה: הוא עלול להעיר את WebView2.
        for (var sample = 0; sample < 2; sample++) {
          await _measureResources(
            environment,
            cycle,
            pauseError == null ? 'confirmedSuspended' : 'suspendRejected',
            sample,
          );
        }
        await _resumeAndCheck(controller, cycle, draft, phase: 'resume');

        // מחברים מטפל שגיאה לפני resume, שיכול לבטל את ה-pause הממתין.
        final rapidPause = _pauseOutcome(controller);
        await _resumeAndCheck(controller, cycle, draft, phase: 'rapidResume');
        final rapidError = await rapidPause;
        expect(
          rapidError,
          anyOf(
            isNull,
            'WEBVIEW_LIFECYCLE_CANCELLED',
            'WEBVIEW_SUSPEND_REJECTED',
          ),
        );
        _report({
          'cycle': cycle,
          'phase': 'rapidPauseCompletion',
          'confirmed': rapidError == null,
          'error': rapidError,
        });
        await _checkState(controller, cycle, draft);
        expect(probe.loadCount(), 1, reason: 'resume אינו אמור לטעון דף חדש');

        await _closeProbe(tester, probe.nativeChannel);
        counts['nativeHostsClosed'] = counts['nativeHostsClosed']! + 1;
        await _measureResources(environment, cycle, 'afterHostClose', 0);
        _report({'cycle': cycle, 'phase': 'hostClosed', ...counts});
        await WebViewEnvironmentHolder.disposeForAppRestart();
        expect(WebViewEnvironmentHolder.environment, isNull);
        previousEnvironment = environment;
      }
      expect(counts['hostsCreated'], 3);
      expect(counts['nativeHostsClosed'], counts['hostsCreated']);
      expect(
        counts['pauseConfirmed'],
        greaterThan(0),
        reason: 'נדרש לפחות TrySuspend מוצלח אחד כדי לבדוק את מסלול ההשהיה',
      );
    },
    skip: !Platform.isWindows,
  );
}

Future<String?> _pauseOutcome(InAppWebViewController controller) async {
  try {
    await controller.pause().timeout(_nativeDeadline);
    return null;
  } on PlatformException catch (error) {
    return error.code;
  }
}

Future<void> _resumeAndCheck(
  InAppWebViewController controller,
  int cycle,
  String draft, {
  required String phase,
}) async {
  final watch = Stopwatch()..start();
  await controller.resume().timeout(_nativeDeadline);
  final completionMicros = watch.elapsedMicroseconds;
  final state = await _checkState(controller, cycle, draft);
  final initialTicks = state['ticks'] as num;
  final deadline = Stopwatch()..start();
  num ticks = initialTicks;
  while (ticks <= initialTicks && deadline.elapsed < _nativeDeadline) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ticks =
        await controller
                .evaluateJavascript(source: 'window.probeTicks')
                .timeout(_nativeDeadline)
            as num;
  }
  expect(ticks, greaterThan(initialTicks), reason: 'טיימר הדף לא חזר לפעול');
  watch.stop();
  _report({
    'cycle': cycle,
    'phase': phase,
    'resumeMicros': completionMicros,
    'resumeToPageProgressMicros': watch.elapsedMicroseconds,
  });
}

Future<Map<String, dynamic>> _checkState(
  InAppWebViewController controller,
  int cycle,
  String draft,
) async {
  final encoded = await controller
      .evaluateJavascript(
        source: '''JSON.stringify({
      value: window.probeValue,
      marker: document.getElementById('marker').textContent,
      draft: document.getElementById('draft').value,
      state: window.probeState,
      ticks: window.probeTicks
    })''',
      )
      .timeout(_nativeDeadline);
  final state = jsonDecode(encoded as String) as Map<String, dynamic>;
  expect(state['value'], 42);
  expect(state['marker'], 'webview-alive');
  expect(state['draft'], draft);
  expect(state['state'], {'schemaVersion': 2, 'revision': cycle});
  return state;
}

typedef _RenderedProbe = ({
  InAppWebViewController controller,
  MethodChannel nativeChannel,
  int Function() loadCount,
});

Future<_RenderedProbe> _renderProbe(
  WidgetTester tester,
  WebViewEnvironment environment, {
  required int cycle,
  required VoidCallback onCreated,
}) async {
  final controllerCompleter = Completer<InAppWebViewController>();
  final loadedCompleter = Completer<void>();
  final webViewKey = UniqueKey();
  final events = <String>[];
  var loadCount = 0;
  final creationFailures = WindowsWebViewCreationFailures.stream.listen((
    failure,
  ) {
    if (failure.creationKey == webViewKey) {
      events.add('creation failed: ${failure.error}');
    }
  });

  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InAppWebView(
            key: webViewKey,
            webViewEnvironment: environment,
            initialData: InAppWebViewInitialData(data: _probeHtml),
            onWebViewCreated: (controller) {
              onCreated();
              controllerCompleter.complete(controller);
            },
            onLoadStart: (controller, url) => events.add('load started: $url'),
            onLoadStop: (controller, url) {
              loadCount++;
              events.add('load stopped: $url');
              if (!loadedCompleter.isCompleted) loadedCompleter.complete();
            },
            onReceivedError: (controller, request, error) => events.add(
              'navigation failed: ${request.url}, '
              'mainFrame=${request.isForMainFrame}, '
              '${error.type}: ${error.description}',
            ),
            onReceivedHttpError: (controller, request, response) => events.add(
              'HTTP failed: ${request.url}, status=${response.statusCode}',
            ),
            onProcessFailed: (controller, detail) => events.add(
              'process failed: ${detail.kind}, reason=${detail.reason}, '
              'exitCode=${detail.exitCode}',
            ),
          ),
        ),
      ),
    );

    final deadline = Stopwatch()..start();
    while (!loadedCompleter.isCompleted &&
        deadline.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      loadedCompleter.isCompleted,
      isTrue,
      reason:
          'הדף לא סיים להיטען תוך 30 שניות — מסך ריק? '
          'cycle=$cycle, controllerCreated=${controllerCompleter.isCompleted}, '
          'events=$events',
    );

    final controller = await controllerCompleter.future;
    final nativeChannel = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_${controller.getViewId()}',
    );
    await nativeChannel
        .invokeMethod<Object?>('getUrl', {})
        .timeout(
          _nativeDeadline,
        );
    return (
      controller: controller,
      nativeChannel: nativeChannel,
      loadCount: () => loadCount,
    );
  } finally {
    await creationFailures.cancel();
  }
}

Future<void> _closeProbe(WidgetTester tester, MethodChannel channel) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < _nativeDeadline) {
    try {
      await channel
          .invokeMethod<Object?>('getUrl', {})
          .timeout(_nativeDeadline);
    } on MissingPluginException {
      // ה-manager מסיר את ערוץ המופע ומוחק את ה-host באותה קריאת dispose.
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('ערוץ המופע הנייטיבי נשאר רשום אחרי הסרת ה-widget');
}

typedef _ProcessPoint = ({
  int creation100ns,
  int cpu100ns,
  int? privateBytes,
});

typedef _ProcessInterval = ({
  Map<int, _ProcessPoint> before,
  Map<int, _ProcessPoint> after,
  int elapsedMicros,
});

Future<Map<int, WebViewProcess>> _processes(
  WebViewEnvironment environment,
) async {
  final infos = await environment.getProcessInfos().timeout(_nativeDeadline);
  return {
    for (final info in infos)
      ?info.processId: (
        kind: info.kind.name(),
        pid: info.processId!,
        page: null,
      ),
  };
}

Map<int, _ProcessPoint> _processPoints(Set<int> ids) => {
  for (final id in ids) id: ?_processPoint(id),
};

_ProcessPoint? _processPoint(int id) {
  final handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, id);
  if (!handle.value.isValid) return null;
  final times = calloc<FILETIME>(4);
  final counters = calloc<PROCESS_MEMORY_COUNTERS>();
  try {
    final result = GetProcessTimes(
      handle.value,
      times,
      times + 1,
      times + 2,
      times + 3,
    );
    if (!result.value || _fileTimeTicks(times[1]) != 0) return null;
    final size = sizeOf<PROCESS_MEMORY_COUNTERS>();
    counters.ref.cb = size;
    final memory = GetProcessMemoryInfo(handle.value, counters, size);
    return (
      creation100ns: _fileTimeTicks(times[0]),
      cpu100ns: _fileTimeTicks(times[2]) + _fileTimeTicks(times[3]),
      privateBytes: memory.value ? counters.ref.PagefileUsage : null,
    );
  } finally {
    calloc.free(times);
    calloc.free(counters);
    handle.value.close();
  }
}

int _fileTimeTicks(FILETIME time) =>
    (time.dwHighDateTime << 32) | time.dwLowDateTime;

Future<_ProcessInterval> _processInterval(Set<int> ids) async {
  final before = _processPoints(ids);
  final clock = Stopwatch()..start();
  await Future<void>.delayed(const Duration(milliseconds: 750));
  final after = _processPoints(ids);
  clock.stop();
  return (
    before: before,
    after: after,
    elapsedMicros: clock.elapsedMicroseconds,
  );
}

Future<void> _measureResources(
  WebViewEnvironment environment,
  int cycle,
  String phase,
  int sample,
) async {
  final beforeProcesses = await _processes(environment);
  final beforeIds = {pid, ...beforeProcesses.keys};
  final interval = await Isolate.run(() => _processInterval(beforeIds));
  final before = interval.before;
  final after = interval.after;
  final afterProcesses = await _processes(environment);
  final afterIds = {pid, ...afterProcesses.keys};
  final delta = <int, int>{
    for (final id in beforeIds.intersection(afterIds))
      if (before[id] case final previous?)
        if (after[id] case final current?)
          if (previous.creation100ns == current.creation100ns &&
              current.cpu100ns >= previous.cpu100ns)
            id: current.cpu100ns - previous.cpu100ns,
  };
  // getProcessInfos מחזיר רשימה ריקה גם כשהשאילתה הנייטיבית אינה זמינה.
  final webviewCpuComplete =
      beforeProcesses.isNotEmpty &&
      setEquals(beforeProcesses.keys.toSet(), afterProcesses.keys.toSet()) &&
      afterProcesses.keys.every(delta.containsKey);
  double percentOfOneCore(int ticks) =>
      100 * ticks / (interval.elapsedMicros * 10);
  final webviewTicks = webviewCpuComplete
      ? afterProcesses.keys.fold(0, (sum, id) => sum + delta[id]!)
      : null;
  final processes = afterProcesses.values.toList();
  final memoryComplete =
      webviewCpuComplete &&
      afterIds.every(
        (id) => delta.containsKey(id) && after[id]?.privateBytes != null,
      );
  // PID שהוחלף או קריאה שנכשלה אינם זיכרון אפס; אין סכום חלקי שנראה מלא.
  final memory = memoryComplete
      ? buildProcessTreeSample(
          hostBytes: after[pid]!.privateBytes,
          processes: [
            for (final process in processes)
              (
                kind: process.kind,
                bytes: after[process.pid]!.privateBytes,
                page: null,
              ),
          ],
        )
      : null;
  _report({
    'cycle': cycle,
    'phase': phase,
    'sample': sample,
    'intervalMicros': interval.elapsedMicros,
    'logicalProcessors': Platform.numberOfProcessors,
    'hostCpuPercentOfOneCore': delta[pid] == null
        ? null
        : percentOfOneCore(delta[pid]!),
    'webviewCpuPercentOfOneCore': webviewTicks == null
        ? null
        : percentOfOneCore(webviewTicks),
    'webviewCpuComplete': webviewCpuComplete,
    'webviewProcessesBefore': beforeProcesses.length,
    'webviewProcessesAfter': afterProcesses.length,
    'webviewProcessListEmpty': afterProcesses.isEmpty,
    'browserChildrenAfter': processes.where((p) => p.kind != 'BROWSER').length,
    'privateMemoryMetric': 'windowsPrivateCommit',
    'privateMemoryUnit': 'MiB',
    'hostPrivateCommitMiB':
        delta.containsKey(pid) && after[pid]?.privateBytes != null
        ? (after[pid]!.privateBytes! / (1 << 20)).round()
        : null,
    'memoryComplete': memoryComplete,
    'memory': memory?.toJson(),
  });
}

void _report(Map<String, Object?> values) {
  debugPrint(
    '[WebView2 lifecycle] ${jsonEncode({
      'schemaVersion': 1,
      'source': 'synthetic CI/debug sample; not production savings evidence',
      'processScope': 'host plus WebView2 environment process list',
      ...values,
    })}',
  );
}
