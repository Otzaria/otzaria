import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/plugins/services/plugin_webview_diagnostics.dart';

class _Environment extends Fake implements WebViewEnvironment {
  _Environment(this.read);

  final Future<List<BrowserProcessInfo>> Function() read;
  var calls = 0;
  var disposed = false;

  @override
  Future<List<BrowserProcessInfo>> getProcessInfos() {
    calls++;
    if (disposed) {
      throw PlatformException(code: 'webview_environment_unavailable');
    }
    return read();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('reads kind, pid and the main frame of each process', () {
    final processes = pluginWebViewProcesses([
      BrowserProcessInfo(kind: BrowserProcessKind.BROWSER, processId: 1),
      BrowserProcessInfo(
        kind: BrowserProcessKind.RENDERER,
        processId: 2,
        frameInfos: [
          FrameInfo(
            isMainFrame: true,
            request: URLRequest(
              url: WebUri.uri(
                Uri.file(r'C:\p\my.plugin\index.html', windows: true),
              ),
            ),
          ),
        ],
      ),
      BrowserProcessInfo(kind: BrowserProcessKind.GPU),
    ]);

    expect(processes, [
      (kind: 'BROWSER', pid: 1, page: null),
      (kind: 'RENDERER', pid: 2, page: 'my.plugin/index.html'),
      (kind: 'GPU', pid: null, page: null),
    ]);
  });

  group('framePageLabel', () {
    test('a file page keeps only its folder and file name', () {
      expect(
        framePageLabel(
          Uri.file(
            r'C:\Users\someone\plugins\my.plugin\index.html',
            windows: true,
          ),
        ),
        'my.plugin/index.html',
      );
    });

    test('other schemes keep only the host', () {
      expect(
        framePageLabel(Uri.parse('otzaria-plugin://my.plugin/a/b.html')),
        'my.plugin',
      );
      expect(framePageLabel(Uri.parse('http://localhost:5173/')), 'localhost');
      expect(framePageLabel(null), isNull);
    });
  });

  test('registration fills the diagnostics lister once', () {
    final diagnostics = DeveloperDiagnostics.instance..resetForTesting();
    addTearDown(diagnostics.resetForTesting);
    expect(diagnostics.webViewProcessLister, isNull);
    registerPluginWebViewDiagnostics();
    final lister = diagnostics.webViewProcessLister;
    expect(lister, isNotNull);
    registerPluginWebViewDiagnostics();
    expect(identical(diagnostics.webViewProcessLister, lister), isTrue);
  });

  test('an empty native list remains ambiguous with the pinned contract', () {
    final snapshot = pluginWebViewProcessSnapshot([]);
    expect(snapshot.collection.status, ProcessCollectionStatus.unavailable);
    expect(snapshot.collection.reason, 'empty_process_list_ambiguous');
    expect(snapshot.processes, isEmpty);
  });

  test('a missing environment is unavailable without creating one', () async {
    final snapshot = await collectPluginWebViewProcesses(null);
    expect(snapshot.collection.status, ProcessCollectionStatus.unavailable);
    expect(snapshot.collection.reason, 'webview_environment_unavailable');
  });

  test('nonempty enumeration retains a process whose PID is unavailable', () {
    final snapshot = pluginWebViewProcessSnapshot([
      BrowserProcessInfo(kind: BrowserProcessKind.RENDERER),
    ]);
    expect(snapshot.collection.status, ProcessCollectionStatus.collected);
    expect(snapshot.collection.partial, isNull);
    expect(snapshot.processes, [(kind: 'RENDERER', pid: null, page: null)]);
  });

  for (final lateError in [false, true]) {
    test(
      'timeout, pending tick, disposal and late ${lateError ? 'error' : 'success'} preserve host and new environment',
      () async {
        final pending = Completer<List<BrowserProcessInfo>>();
        final oldEnvironment = _Environment(() => pending.future);
        WebViewEnvironment? current = oldEnvironment;
        Future<List<int?>> readBytes(List<int> ids) async => [
          for (final id in ids) (id == pid ? 20 : 3) * (1 << 20),
        ];
        Future<ProcessTreeSample> sample() => sampleWindowsProcessTree(
          webViewProcesses: () => collectPluginWebViewProcesses(current),
          readBytes: readBytes,
          enumerationTimeout: Duration.zero,
        );

        final timedOut = await sample();
        expect(timedOut.webviewCollection.reason, 'process_info_timeout');
        expect(timedOut.hostPrivMb, 20);
        expect(oldEnvironment.calls, 1);
        final stillPending = await sample();
        expect(stillPending.webviewCollection.reason, 'process_info_pending');
        expect(stillPending.hostPrivMb, 20);
        expect(oldEnvironment.calls, 1);

        await oldEnvironment.dispose();
        current = null;
        final disposed = await sample();
        expect(
          disposed.webviewCollection.reason,
          'webview_environment_unavailable',
        );
        expect(disposed.hostPrivMb, 20);
        final replacement = _Environment(
          () async => [
            BrowserProcessInfo(
              kind: BrowserProcessKind.RENDERER,
              processId: 42,
            ),
          ],
        );
        current = replacement;
        final replaced = await sample();
        expect(replaced.hostPrivMb, 20);
        expect(replaced.observedProcessCount, 1);
        expect(replaced.webviewPrivMb, 3);
        expect(replacement.calls, 1);

        if (lateError) {
          pending.completeError(
            PlatformException(code: 'webview_environment_unavailable'),
          );
        } else {
          pending.complete([
            BrowserProcessInfo(kind: BrowserProcessKind.GPU, processId: 99),
          ]);
        }
        await Future<void>.delayed(Duration.zero);
        expect(timedOut.observedProcessCount, isNull);
        expect(replaced.webview['GPU'], isNull);
        final next = await sample();
        expect(next.observedProcessCount, 1);
        expect(replacement.calls, 2);

        final oldAgain = await sampleWindowsProcessTree(
          webViewProcesses: () => collectPluginWebViewProcesses(oldEnvironment),
          readBytes: readBytes,
        );
        expect(
          oldAgain.webviewCollection.reason,
          'webview_environment_unavailable',
        );
        expect(oldAgain.hostPrivMb, 20);
        expect(oldEnvironment.calls, 2);
      },
    );
  }

  test(
    'a pending source does not start another call before its first reply',
    () async {
      final pending = Completer<List<BrowserProcessInfo>>();
      final environment = _Environment(() => pending.future);
      final first = collectPluginWebViewProcesses(environment);
      final second = await collectPluginWebViewProcesses(environment);
      expect(environment.calls, 1);
      expect(second.collection.reason, 'process_info_pending');
      pending.complete([
        BrowserProcessInfo(kind: BrowserProcessKind.BROWSER, processId: 1),
      ]);
      expect((await first).processes.single.pid, 1);
    },
  );

  test(
    'a synchronous collection failure permits a subsequent attempt',
    () async {
      final environment = _Environment(() => throw StateError('failed'));
      for (var i = 0; i < 2; i++) {
        final sample = await sampleWindowsProcessTree(
          webViewProcesses: () => collectPluginWebViewProcesses(environment),
          readBytes: (ids) async => [1 << 20],
        );
        expect(sample.hostPrivMb, 1);
        expect(
          sample.webviewCollection.reason,
          'process_info_collection_failed',
        );
      }
      expect(environment.calls, 2);
    },
  );
}
