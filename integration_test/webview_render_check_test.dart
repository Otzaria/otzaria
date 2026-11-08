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

        // שומרים handles בזמן שה-host חי; רשימת הסביבה יכולה להיעלם בסגירה.
        final tracked = await _captureTrackedProcesses(environment);
        try {
          await _closeProbe(tester, probe.nativeChannel);
          final closedAt = Stopwatch()..start();
          counts['nativeHostsClosed'] = counts['nativeHostsClosed']! + 1;
          await _measureResources(environment, cycle, 'afterHostClose', 0);
          await _measureTrackedProcesses(
            tracked,
            cycle,
            'trackedAfterHostClose',
            closedAt,
          );
          _report({'cycle': cycle, 'phase': 'hostClosed', ...counts});
          await WebViewEnvironmentHolder.disposeForAppRestart();
          final disposedAt = Stopwatch()..start();
          expect(WebViewEnvironmentHolder.environment, isNull);
          await _measureTrackedProcesses(
            tracked,
            cycle,
            'trackedAfterEnvironmentDispose',
            disposedAt,
          );
          previousEnvironment = environment;
        } finally {
          for (final process in tracked.entries) {
            process.close();
          }
        }
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

  testWidgets(
    'WebView2 keeps a visible peer alive across suspend and disposal',
    (tester) async {
      final dataDir = await Directory.systemTemp.createTemp('wv2_pair_check');
      final first = _IsolationProbe('first', 101);
      final peer = _IsolationProbe('peer', 102);
      AppPaths.debugOverrideDataRootPath(dataDir.path);
      addTearDown(() async {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          try {
            await WebViewEnvironmentHolder.disposeForAppRestart().timeout(
              _nativeDeadline,
            );
          } finally {
            AppPaths.debugOverrideDataRootPath(null);
            try {
              await dataDir.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      await WebViewEnvironmentHolder.initialize().timeout(_nativeDeadline);
      final environment = WebViewEnvironmentHolder.environment!;
      final firstWidget = first.widget(environment);
      final peerWidget = peer.widget(environment);
      Future<void> mount({bool includeFirst = true}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  key: const ValueKey('isolation-pane-first'),
                  child: includeFirst ? firstWidget : const SizedBox.shrink(),
                ),
                Expanded(
                  key: const ValueKey('isolation-pane-peer'),
                  child: peerWidget,
                ),
              ],
            ),
          ),
        ),
      );

      await mount();
      final firstView = await first.ready(tester);
      final peerView = await peer.ready(tester);
      expect(
        firstView.controller.getViewId(),
        isNot(peerView.controller.getViewId()),
      );
      final firstBounds = tester.getRect(find.byKey(first.key));
      final peerBounds = tester.getRect(find.byKey(peer.key));
      expect(firstBounds.isEmpty, isFalse);
      expect(peerBounds.isEmpty, isFalse);
      expect(firstBounds.overlaps(peerBounds), isFalse);
      final browsers = (await _processes(
        environment,
      )).values.where((process) => process.kind == 'BROWSER').toList();
      expect(
        browsers,
        hasLength(1),
        reason: 'שני המופעים חייבים לחלוק browser',
      );

      await first.initialize(firstView);
      await peer.initialize(peerView);
      for (final view in [firstView, peerView]) {
        await view.controller.resume().timeout(_nativeDeadline);
        expect(
          await view.controller
              .evaluateJavascript(
                source:
                    '!document.hidden && document.visibilityState === "visible"',
              )
              .timeout(_nativeDeadline),
          isTrue,
        );
      }
      await _expectIsolationProgress(first, firstView);
      await _expectIsolationProgress(peer, peerView);

      expect(await _pauseOutcome(firstView.controller), isNull);
      await _expectIsolationProgress(peer, peerView);
      await firstView.controller.resume().timeout(_nativeDeadline);
      await _expectIsolationProgress(first, firstView);

      await mount(includeFirst: false);
      await tester.pump();
      expect(tester.getRect(find.byKey(peer.key)), peerBounds);
      await _waitForProbeClosed(tester, firstView.nativeChannel);
      await _expectIsolationProgress(peer, peerView);

      // pause/resume מפעילים את ה-browser gate גם אחרי סגירת הבעלים האחר.
      expect(await _pauseOutcome(peerView.controller), isNull);
      await peerView.controller.resume().timeout(_nativeDeadline);
      await _expectIsolationProgress(peer, peerView);
      await _closeProbe(tester, peerView.nativeChannel);
      await WebViewEnvironmentHolder.disposeForAppRestart().timeout(
        _nativeDeadline,
      );
      expect(WebViewEnvironmentHolder.environment, isNull);
      final summary = jsonEncode({
        'sharedBrowserProcessId': browsers.single.pid,
        'hostsCreated': first.creations + peer.creations,
        'nativeHostsClosed': 2,
        'initiallyVisibleViews': 2,
        'firstLoads': first.loads,
        'peerLoads': peer.loads,
        'peerProgressAfterFirstSuspend': true,
        'peerProgressAfterFirstClose': true,
        'peerPauseResumeAfterFirstClose': true,
      });
      debugPrint('[WebView2 isolation] $summary');
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
  await _waitForProbeClosed(tester, channel);
}

Future<void> _waitForProbeClosed(
  WidgetTester tester,
  MethodChannel channel,
) async {
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

class _IsolationProbe {
  _IsolationProbe(this.name, this.revision)
    : key = ValueKey('isolation-view-$name'),
      documentId = '$name-${DateTime.now().microsecondsSinceEpoch}';

  final String name;
  final int revision;
  final Key key;
  final String documentId;
  final created = Completer<InAppWebViewController>();
  final loaded = Completer<void>();
  final events = <String>[];
  InAppWebViewController? currentController;
  int creations = 0;
  int loads = 0;
  String get draft => 'draft-$name: טיוטה עצמאית';

  Widget widget(WebViewEnvironment environment) => InAppWebView(
    key: key,
    webViewEnvironment: environment,
    initialData: InAppWebViewInitialData(data: _probeHtml),
    onWebViewCreated: (controller) {
      creations++;
      currentController = controller;
      if (!created.isCompleted) created.complete(controller);
    },
    onLoadStop: (controller, url) {
      loads++;
      if (!loaded.isCompleted) loaded.complete();
    },
    onReceivedError: (controller, request, error) => events.add(
      '${request.url}: ${error.type}: ${error.description}',
    ),
    onProcessFailed: (controller, detail) => events.add(
      '${detail.kind}: ${detail.reason}, exitCode=${detail.exitCode}',
    ),
  );

  Future<_RenderedProbe> ready(WidgetTester tester) async {
    final deadline = Stopwatch()..start();
    while (!loaded.isCompleted &&
        deadline.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      loaded.isCompleted,
      isTrue,
      reason: 'מופע $name לא נטען תוך 30 שניות: $events',
    );
    final controller = await created.future.timeout(_nativeDeadline);
    final channel = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_${controller.getViewId()}',
    );
    await channel.invokeMethod<Object?>('getUrl', {}).timeout(_nativeDeadline);
    return (
      controller: controller,
      nativeChannel: channel,
      loadCount: () => loads,
    );
  }

  Future<void> initialize(_RenderedProbe view) async {
    final values = jsonEncode({
      'revision': revision,
      'draft': draft,
      'documentId': documentId,
    });
    await view.controller
        .evaluateJavascript(
          source:
              '''(() => {
      const values = $values;
      window.probeState.revision = values.revision;
      document.getElementById('draft').value = values.draft;
      window.probeDocumentId = values.documentId;
      window.probeProgress = [];
      setInterval(() => {
        window.probeProgress.push({at: Date.now(), ticks: window.probeTicks});
        if (window.probeProgress.length > 100) window.probeProgress.shift();
      }, 50);
    })()''',
        )
        .timeout(_nativeDeadline);
  }
}

Future<void> _expectIsolationProgress(
  _IsolationProbe probe,
  _RenderedProbe view,
) async {
  // קריאת JS עלולה להעיר מופע מושהה; סופרים רק טיקים שקדמו לקריאה.
  final startMs = DateTime.now().millisecondsSinceEpoch;
  await Future<void>.delayed(const Duration(seconds: 1));
  final endMs = DateTime.now().millisecondsSinceEpoch;
  final encoded = await view.controller
      .evaluateJavascript(source: 'JSON.stringify(window.probeProgress)')
      .timeout(_nativeDeadline);
  final samples = (jsonDecode(encoded as String) as List)
      .cast<Map<String, dynamic>>()
      .where(
        (sample) =>
            (sample['at'] as num) > startMs && (sample['at'] as num) < endMs,
      )
      .toList();
  final midpointMs = startMs + (endMs - startMs) ~/ 2;
  for (final half in [
    samples.where((sample) => (sample['at'] as num) < midpointMs).toList(),
    samples.where((sample) => (sample['at'] as num) >= midpointMs).toList(),
  ]) {
    expect(
      half.length,
      greaterThanOrEqualTo(2),
      reason: 'מופע ${probe.name} לא דגם התקדמות בכל חצי של החלון השקט',
    );
    expect(
      half.last['ticks'],
      greaterThan(half.first['ticks'] as num),
      reason: 'טיימר ${probe.name} נעצר במהלך החלון השקט',
    );
  }
  await _checkState(view.controller, probe.revision, probe.draft);
  expect(
    await view.controller
        .evaluateJavascript(source: 'window.probeDocumentId')
        .timeout(_nativeDeadline),
    probe.documentId,
  );
  expect(probe.currentController, same(view.controller));
  expect(probe.creations, 1);
  expect(view.loadCount(), 1);
}

typedef _IdentifiedWebViewProcess = ({String kind, int pid, String? page});

typedef _ProcessPoint = ({
  int creation100ns,
  int? exit100ns,
  int cpu100ns,
  int? privateBytes,
});

typedef _ProcessInterval = ({
  Map<int, _ProcessPoint> before,
  Map<int, _ProcessPoint> after,
  int elapsedMicros,
});

Future<Map<int, _IdentifiedWebViewProcess>> _processes(
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
  final handle = OpenProcess(
    PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE,
    false,
    id,
  );
  if (!handle.value.isValid) return null;
  try {
    final point = _readProcessPoint(handle.value);
    return point?.exit100ns == null ? point : null;
  } finally {
    handle.value.close();
  }
}

/// exitTime אינו מוגדר בתהליך חי. Wait(0) הוא בדיקת חיות שאינה חוסמת.
_ProcessPoint? _readProcessPoint(HANDLE handle) {
  final times = calloc<FILETIME>(4);
  final counters = calloc<PROCESS_MEMORY_COUNTERS>();
  try {
    for (var attempt = 0; attempt < 2; attempt++) {
      final before = WaitForSingleObject(handle, 0).value;
      if (before != WAIT_OBJECT_0 && before != WAIT_TIMEOUT) return null;
      final result = GetProcessTimes(
        handle,
        times,
        times + 1,
        times + 2,
        times + 3,
      );
      if (!result.value) return null;
      final creation = _fileTimeTicks(times[0]);
      final cpu = _fileTimeTicks(times[2]) + _fileTimeTicks(times[3]);
      if (before == WAIT_OBJECT_0) {
        final exit = _fileTimeTicks(times[1]);
        if (exit <= 0 || exit < creation) return null;
        return (
          creation100ns: creation,
          exit100ns: exit,
          cpu100ns: cpu,
          privateBytes: 0,
        );
      }
      final size = sizeOf<PROCESS_MEMORY_COUNTERS>();
      counters.ref.cb = size;
      final memory = GetProcessMemoryInfo(handle, counters, size);
      final after = WaitForSingleObject(handle, 0).value;
      if (after == WAIT_TIMEOUT) {
        return (
          creation100ns: creation,
          exit100ns: null,
          cpu100ns: cpu,
          privateBytes: memory.value ? counters.ref.PagefileUsage : null,
        );
      }
      if (after != WAIT_OBJECT_0) return null;
      // יצא במהלך הקריאה: קוראים שוב רק אחרי אישור היציאה, לקבלת מוני הסיום.
    }
    return null;
  } finally {
    calloc.free(times);
    calloc.free(counters);
  }
}

class _TrackedProcess {
  _TrackedProcess(this.info, this.creation100ns, this._handle);

  factory _TrackedProcess.capture(_IdentifiedWebViewProcess info) {
    final handle = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE,
      false,
      info.pid,
    ).value;
    if (!handle.isValid) return _TrackedProcess(info, null, null);
    var adopted = false;
    try {
      final point = _readProcessPoint(handle);
      if (point == null || point.exit100ns != null) {
        return _TrackedProcess(info, null, null);
      }
      final process = _TrackedProcess(info, point.creation100ns, handle);
      adopted = true;
      return process;
    } finally {
      if (!adopted) handle.close();
    }
  }

  final _IdentifiedWebViewProcess info;
  final int? creation100ns;
  HANDLE? _handle;

  _ProcessPoint? read() {
    final handle = _handle;
    if (handle == null) return null;
    final point = _readProcessPoint(handle);
    return point?.creation100ns == creation100ns ? point : null;
  }

  void close() {
    final handle = _handle;
    _handle = null;
    handle?.close();
  }
}

typedef _TrackedProcesses = ({
  List<_TrackedProcess> entries,
  bool captureListStable,
});

Future<_TrackedProcesses> _captureTrackedProcesses(
  WebViewEnvironment environment,
) async {
  final before = await _processes(environment);
  final tracked = <_TrackedProcess>[];
  try {
    for (final process in before.values) {
      tracked.add(_TrackedProcess.capture(process));
    }
    final after = await _processes(environment);
    // אותו PID חייב עדיין להשתייך לסביבה לפני הסגירה; ה-handle מכאן ואילך
    // מצביע לאותה זהות OS גם לאחר exit ושימוש חוזר ב-PID.
    for (final process in tracked) {
      if (after[process.info.pid]?.kind != process.info.kind) {
        process.close();
      }
    }
    return (
      entries: tracked,
      captureListStable:
          before.isNotEmpty &&
          setEquals(before.keys.toSet(), after.keys.toSet()) &&
          before.values.every((p) => after[p.pid]?.kind == p.kind),
    );
  } catch (_) {
    for (final process in tracked) {
      process.close();
    }
    rethrow;
  }
}

Future<void> _measureTrackedProcesses(
  _TrackedProcesses tracked,
  int cycle,
  String phase,
  Stopwatch boundaryClock,
) async {
  Map<int, _ProcessPoint> read() => {
    for (final process in tracked.entries) process.info.pid: ?process.read(),
  };

  // מספר קטן וקבוע של handles, ללא lookup נוסף לפי PID או המתנה חוסמת.
  final before = read();
  final clock = Stopwatch()..start();
  await Future<void>.delayed(const Duration(milliseconds: 750));
  final after = read();
  clock.stop();
  final delta = <int, int>{
    for (final process in tracked.entries)
      if (before[process.info.pid] case final previous?)
        if (after[process.info.pid] case final current?)
          if (current.cpu100ns >= previous.cpu100ns &&
              (previous.exit100ns == null ||
                  previous.exit100ns == current.exit100ns))
            process.info.pid: current.cpu100ns - previous.cpu100ns,
  };
  final unreadable = tracked.entries.length - after.length;
  final exited = after.values.where((point) => point.exit100ns != null).length;
  final alive = after.length - exited;
  // שלמות מתייחסת לזהויות שנלכדו בלבד, גם אם נוספו תהליכים בזמן הלכידה.
  final cpuComplete =
      tracked.entries.isNotEmpty && delta.length == tracked.entries.length;
  final memoryComplete =
      tracked.entries.isNotEmpty &&
      unreadable == 0 &&
      after.values.every((point) => point.privateBytes != null);
  _report({
    'cycle': cycle,
    'phase': phase,
    'processScope':
        'fixed WebView2 identities captured before host close; host and later processes excluded',
    'captureListStable': tracked.captureListStable,
    'trackedProcesses': tracked.entries.length,
    'trackedAlive': alive,
    'trackedExited': exited,
    'trackedUnreadable': unreadable,
    'intervalMicros': clock.elapsedMicroseconds,
    'observedAfterBoundaryMicros': boundaryClock.elapsedMicroseconds,
    'trackedCpuComplete': cpuComplete,
    'trackedCpuPercentOfOneCore': cpuComplete
        ? 100 *
              delta.values.fold(0, (sum, ticks) => sum + ticks) /
              (clock.elapsedMicroseconds * 10)
        : null,
    'privateMemoryMetric': 'windowsPrivateCommit',
    'privateMemoryUnit': 'MiB',
    'trackedMemoryComplete': memoryComplete,
    'trackedAlivePrivateCommitMiB': memoryComplete
        ? (after.values.fold(0, (sum, point) => sum + point.privateBytes!) /
                  (1 << 20))
              .round()
        : null,
  });
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
          metric: ProcessMemoryMetric.privateCommit,
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
