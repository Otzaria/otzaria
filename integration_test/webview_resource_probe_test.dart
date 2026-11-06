// Opt-in synthetic WebView scenario; see tool/perf_probe/WEBVIEW_RESOURCE_PROBE.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/plugins/services/plugin_webview_diagnostics.dart';
import 'package:path/path.dart' as p;

import '../tool/perf_probe/src/report.dart' show sampleDistribution;
import 'support/perf_recorder.dart';
import 'support/webview_probe_fixture.dart';
import 'support/webview_probe_metrics.dart';
import 'support/webview_probe_window.dart';

const _deadline = Duration(seconds: 30);
const _phases = [
  'environment',
  'firstOpen',
  'visibleIdle',
  'multipleOpen',
  'multipleIdle',
  'scroll',
  'activeHeartbeat',
  'hide',
  'hiddenIdle',
  'resume',
  'discardWidget',
  'recreateAndRestore',
  'backgroundOpen',
  'backgroundIdle',
  'closeWidgets',
  'closedIdle',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('cross-platform WebView resource scenario', (tester) async {
    final outputPath = perfOption(
      'WEBVIEW_PROBE_DEVICE_OUTPUT',
      const String.fromEnvironment('WEBVIEW_PROBE_DEVICE_OUTPUT'),
    );
    if (outputPath.isNotEmpty && !p.isAbsolute(outputPath)) {
      throw ArgumentError(
        'WEBVIEW_PROBE_DEVICE_OUTPUT must be an absolute device path.',
      );
    }
    final outputRoot = outputPath.isEmpty
        ? Directory.systemTemp
        : Directory(outputPath);
    await outputRoot.create(recursive: true);
    final directory = await outputRoot.createTemp(
      'otzaria-webview-probe-',
    );
    final journal = File(p.join(directory.path, 'phases.jsonl'));
    final recorder = PerfRecorder(journal, binding, launchIndex: 0);
    final slots = <_ProbeSlot>[];
    final statuses = {for (final name in _phases) name: 'notRun'};
    WebViewEnvironment? environment;
    String? visible;
    Object? failure;
    late StateSetter rebuild;
    final nativeOutcomes = <String, Object?>{};
    var hasDesktopWindow = false;
    final errors = <String>[];
    var created = 0;
    var removed = 0;
    final allSlots = <_ProbeSlot>[];
    recorder.counters = () => {
      'widgetHosts': slots.length,
      'widgetHostsCreated': created,
      'widgetHostsRemoved': removed,
      'fixtureCommands': allSlots.fold<int>(0, (n, slot) => n + slot.sent),
      'fixtureReplies': allSlots.fold<int>(0, (n, slot) => n + slot.received),
      'fixtureCommandJsonBytes': allSlots.fold<int>(
        0,
        (n, slot) => n + slot.sentBytes,
      ),
      'fixtureReplyJsonBytes': allSlots.fold<int>(
        0,
        (n, slot) => n + slot.receivedBytes,
      ),
    };
    recorder.verifyAction = () {
      if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    };

    Future<WebViewProcessSnapshot> listProcesses() =>
        collectPluginWebViewProcesses(environment);

    Future<void> memory(String phase, String boundary) async {
      ProcessTreeSample? sample;
      String? error;
      try {
        sample = await sampleProcessTree(
          webViewProcesses: listProcesses,
        ).timeout(_deadline);
      } catch (exception) {
        error = exception.toString();
      }
      recorder.write({
        'type': 'webviewMemory',
        'phase': phase,
        'boundary': boundary,
        'sampledAtMs': DateTime.now().millisecondsSinceEpoch,
        ...webViewProbeMemory(
          sample,
          platform: Platform.operatingSystem,
          error: error,
        ),
      });
    }

    Future<void> windowObservation(String phase, String boundary) async {
      final state = await readWebViewProbeWindow(
        Platform.operatingSystem,
      ).timeout(_deadline);
      recorder.write({
        'type': 'nativeWindow',
        'phase': phase,
        'boundary': boundary,
        'sampledAtMs': DateTime.now().millisecondsSinceEpoch,
        ...state,
      });
      if (state['ready'] != true) {
        throw StateError('Desktop window is not visible and opaque: $state');
      }
    }

    Future<void> phase(String name, Future<void> Function() body) async {
      statuses[name] = 'running';
      await memory(name, 'before');
      try {
        if (hasDesktopWindow) await windowObservation(name, 'before');
        await recorder.phase(name, body, sampleHeap: false);
        if (hasDesktopWindow) await windowObservation(name, 'after');
        statuses[name] = 'passed';
      } catch (_) {
        statuses[name] = 'failed';
        rethrow;
      } finally {
        await memory(name, 'after');
      }
    }

    Future<_ProbeSlot> open({bool background = false}) async {
      final slot = _ProbeSlot('host-${created++}', background: background);
      allSlots.add(slot);
      rebuild(() {
        slots.add(slot);
        if (!background) visible = slot.id;
      });
      await tester.pump();
      await slot.created.future.timeout(_deadline);
      await slot.loaded.future.timeout(_deadline);
      await slot.command(background ? 'snapshot' : 'paint');
      return slot;
    }

    Future<void> remove(_ProbeSlot slot) async {
      rebuild(() {
        slots.remove(slot);
        if (visible == slot.id) visible = null;
        removed++;
      });
      await tester.pump();
    }

    Future<void> hide(_ProbeSlot slot) async {
      rebuild(() => visible = null);
      await tester.pump();
      final controller = await slot.created.future;
      var outcome = 'offstageOnly';
      if (Platform.isWindows || Platform.isAndroid) {
        try {
          await controller.pause().timeout(_deadline);
          outcome = Platform.isWindows ? 'suspendConfirmed' : 'onPauseOnly';
        } on PlatformException catch (error) {
          if (!Platform.isWindows ||
              ![
                'WEBVIEW_SUSPEND_REJECTED',
                'WEBVIEW_LIFECYCLE_UNAVAILABLE',
              ].contains(error.code)) {
            rethrow;
          }
          outcome = error.code;
        }
      } else if (Platform.isLinux) {
        await controller.setVisible(visible: false).timeout(_deadline);
        outcome = 'nativeHiddenOnly';
      }
      nativeOutcomes[slot.id] = outcome;
    }

    try {
      final tabCount = int.parse(
        perfOption(
          'WEBVIEW_PROBE_TABS',
          const String.fromEnvironment('WEBVIEW_PROBE_TABS', defaultValue: '3'),
        ),
      );
      final idleMs = int.parse(
        perfOption(
          'WEBVIEW_PROBE_IDLE_MS',
          const String.fromEnvironment(
            'WEBVIEW_PROBE_IDLE_MS',
            defaultValue: '3000',
          ),
        ),
      );
      if (tabCount < 1 || tabCount > 10 || idleMs < 250 || idleMs > 60000) {
        throw ArgumentError(
          'Tabs must be 1..10 and idle duration 250..60000 ms.',
        );
      }
      Future<void> idle() =>
          Future<void>.delayed(Duration(milliseconds: idleMs));
      recorder.write({
        'type': 'meta',
        'schemaVersion': 1,
        'protocol': 'otzaria-synthetic-webview-v1',
        'fixtureVersion': webViewProbeFixtureVersion,
        'fixtureSha256': sha256
            .convert(utf8.encode(webViewProbeHtml))
            .toString(),
        'buildMode': perfBuildMode,
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'flutterVersion': const String.fromEnvironment(
          'WEBVIEW_PROBE_FLUTTER_VERSION',
          defaultValue: 'unavailable',
        ),
        'appCommit': const String.fromEnvironment(
          'WEBVIEW_PROBE_COMMIT',
          defaultValue: 'unavailable',
        ),
        'pid': pid,
        'cores': Platform.numberOfProcessors,
        'tabs': tabCount,
        'idleMs': idleMs,
        'backend': {
          'availability': 'unavailable',
          'requested':
              perfOption('FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND', '') == '1'
              ? 'HWND'
              : 'default',
          'reason':
              'Runtime hosting/backend selection is not exposed by a portable API. Verify using native logs.',
        },
        'externalMetrics': {
          for (final metric in [
            'hostCpu',
            'engineCpu',
            'gpuMemory',
            'enginePss',
          ])
            metric: probeMetric(
              availability: ProbeAvailability.unsupported,
              metric: metric,
              unit: metric.endsWith('Cpu') ? 'percentOfOneCore' : 'bytes',
              scope: metric,
              reason:
                  'Use the platform tools in WEBVIEW_RESOURCE_PROBE.md; this probe does not collect this metric.',
            ),
        },
        'limitations': [
          'Synthetic InAppWebViews, not the plugin dispatcher, SDK or an installed plugin.',
          'Offstage 1x1 models app background hosting; it is still a WebView.',
          'Widget removal is not native disposal acknowledgement or proof of process exit.',
          'Fixture JSON byte counts exclude platform codecs and all other bridge traffic.',
          'Flutter FrameTiming is not WebView paint timing or input-to-photon latency.',
          'Boundary process samples are outside action latency and frame-batch draining.',
          'No WebView calls during idle windows. Endpoint reads intentionally wake pages.',
          'No cold filesystem/engine claim; environment setup and host creation are separate.',
        ],
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Stack(
                fit: StackFit.expand,
                children: [
                  for (final slot in slots)
                    Offstage(
                      key: ValueKey(slot.id),
                      offstage: visible != slot.id,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: slot.background ? 1 : double.infinity,
                          height: slot.background ? 1 : double.infinity,
                          child: InAppWebView(
                            webViewEnvironment: environment,
                            initialData: InAppWebViewInitialData(
                              data: webViewProbeHtml,
                            ),
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                            ),
                            onWebViewCreated: slot.attach,
                            onLoadStop: (_, _) {
                              slot.loads++;
                              if (!slot.loaded.isCompleted) {
                                slot.loaded.complete();
                              }
                            },
                            onReceivedError: (_, request, error) {
                              if (request.isForMainFrame != false) {
                                errors.add('${slot.id}: ${error.description}');
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
      final nativeWindow = await prepareWebViewProbeWindow(
        platform: Platform.operatingSystem,
        pumpFrame: () => tester.pump(),
      );
      recorder.write({
        'type': 'nativeWindow',
        'phase': 'setup',
        'boundary': 'after',
        'sampledAtMs': DateTime.now().millisecondsSinceEpoch,
        ...nativeWindow,
      });
      hasDesktopWindow = nativeWindow['availability'] == 'collected';
      recorder.write({
        'type': 'viewport',
        'physicalWidth': tester.view.physicalSize.width,
        'physicalHeight': tester.view.physicalSize.height,
        'devicePixelRatio': tester.view.devicePixelRatio,
      });
      if (Platform.isWindows) {
        await phase('environment', () async {
          environment = await WebViewEnvironment.create(
            settings: WebViewEnvironmentSettings(
              userDataFolder: p.join(directory.path, 'webview2'),
            ),
          ).timeout(_deadline);
        });
      } else {
        statuses['environment'] = 'unsupported';
        recorder.skip(
          'environment',
          'An explicit shared WebView2 environment is Windows-only.',
        );
      }
      late _ProbeSlot active;
      await phase('firstOpen', () async => active = await open());
      final firstSnapshot = await active.command('snapshot');
      recorder.write({
        'type': 'runtime',
        'userAgent': firstSnapshot['userAgent'],
        'provider': await _runtimeProvider(),
      });
      await phase('visibleIdle', idle);
      await phase('multipleOpen', () async {
        for (var i = 1; i < tabCount; i++) {
          await hide(active);
          active = await open();
        }
      });
      await phase('multipleIdle', idle);
      await phase('scroll', () async {
        final snapshot = await active.command('scroll');
        expect(snapshot['scrollY'], greaterThan(0));
      });
      await active.command('draft', 'טיוטה סינתטית: 0123456789');
      final before = await active.command('heartbeat');
      await phase('activeHeartbeat', idle);
      final beforeHide = await active.command('snapshot');
      await phase('hide', () => hide(active));
      await phase('hiddenIdle', idle);
      final loads = active.loads;
      await phase('resume', () async {
        rebuild(() => visible = active.id);
        await tester.pump();
        final controller = await active.created.future;
        if (Platform.isWindows || Platform.isAndroid) {
          await controller.resume().timeout(_deadline);
        } else if (Platform.isLinux) {
          await controller.setVisible(visible: true).timeout(_deadline);
        }
        final after = await active.command('paint');
        expect(after['draft'], before['draft']);
        expect(after['revision'], before['revision']);
        expect(
          active.loads,
          loads,
          reason: 'Resume must retain the same page.',
        );
        recorder.write({
          'type': 'heartbeatObservation',
          'beforeHide': beforeHide,
          'afterResume': after,
          'window':
              'Before hide through the resume command, not only hiddenIdle.',
          'nativeOutcomes': nativeOutcomes,
        });
      });
      final saved = await active.command('stop');
      await phase('discardWidget', () => remove(active));
      await phase('recreateAndRestore', () async {
        active = await open();
        final restored = await active.command('restore', saved);
        expect(restored['schemaVersion'], saved['schemaVersion']);
        expect(restored['draft'], saved['draft']);
        expect(restored['revision'], saved['revision']);
        expect(
          restored['scrollY'],
          closeTo((saved['scrollY'] as num).toDouble(), 2),
        );
      });
      late _ProbeSlot background;
      await phase('backgroundOpen', () async {
        background = await open(background: true);
        await background.command('heartbeat');
      });
      await phase('backgroundIdle', idle);
      recorder.write({
        'type': 'backgroundObservation',
        'readAfterExplicitWake': true,
        'snapshot': await background.command('stop'),
      });
      await phase('closeWidgets', () async {
        removed += slots.length;
        rebuild(() {
          slots.clear();
          visible = null;
        });
        await tester.pump();
      });
      await phase('closedIdle', idle);
      for (final name in [
        'windowMinimize',
        'applicationBackground',
        'realPluginDiscard',
      ]) {
        statuses[name] = 'notRun';
        recorder.skip(
          name,
          'Requires a platform/device driver or the real app; not simulated by Offstage.',
        );
      }
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await environment?.dispose().timeout(_deadline);
      } catch (error) {
        failure ??= error;
        rethrow;
      } finally {
        await recorder.dispose();
        final records = (await journal.readAsLines())
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        final report = {
          'scenarioStatus': failure == null ? 'completed' : 'failed',
          'error': failure?.toString(),
          'phases': statuses,
          'nativeVisibility': nativeOutcomes,
          'records': records,
          'flutterFrameSummary': {
            for (final record in records.where(
              (r) => r['type'] == 'phase' && r['frames'] != null,
            ))
              record['name'] as String: record['frames']['truncated'] == true
                  ? null
                  : sampleDistribution(
                      (record['frames']['totalMs'] as List).cast<num>(),
                    ),
          },
        };
        await File(
          p.join(directory.path, 'report.json'),
        ).writeAsString(jsonEncode(report), flush: true);
        binding.reportData = {'webviewResourceProbe': report};
        // ignore: avoid_print
        print('WEBVIEW_PROBE_REPORT ${directory.path}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<Map<String, Object?>> _runtimeProvider() async {
  try {
    if (Platform.isWindows) {
      final version = await WebViewEnvironment.getAvailableVersion().timeout(
        _deadline,
      );
      return {
        'availability': version == null ? 'unavailable' : 'collected',
        'source': 'WebViewEnvironment.getAvailableVersion (installed runtime)',
        'version': version,
      };
    }
    if (Platform.isAndroid) {
      final package = await InAppWebViewController.getCurrentWebViewPackage()
          .timeout(_deadline);
      return {
        'availability': package == null ? 'unavailable' : 'collected',
        'source': 'WebView.getCurrentWebViewPackage',
        'package': package?.toMap(),
      };
    }
    return {
      'availability': 'unsupported',
      'reason':
          'Capture the WebKit/WPE package version externally; UA is recorded separately.',
    };
  } catch (error) {
    return {'availability': 'unavailable', 'reason': error.toString()};
  }
}

class _ProbeSlot {
  _ProbeSlot(this.id, {this.background = false});
  final String id;
  final bool background;
  final created = Completer<InAppWebViewController>();
  final loaded = Completer<void>();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int loads = 0, sent = 0, received = 0, sentBytes = 0, receivedBytes = 0;

  void attach(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: webViewProbeHandler,
      callback: (JavaScriptHandlerFunctionData data) {
        final raw = data.args.single as String;
        received++;
        receivedBytes += utf8.encode(raw).length;
        final result = jsonDecode(raw) as Map<String, dynamic>;
        final reply = _pending.remove(result['id']);
        if (reply == null) {
          throw StateError('Unexpected or duplicate fixture reply.');
        }
        if (result['error'] != null) {
          reply.completeError(StateError(result['error'] as String));
        } else {
          reply.complete(result['value'] as Map<String, dynamic>);
        }
      },
    );
    created.complete(controller);
  }

  Future<Map<String, dynamic>> command(String action, [Object? value]) async {
    final controller = await created.future;
    final id = ++sent;
    final request = jsonEncode({'id': id, 'action': action, 'value': value});
    sentBytes += utf8.encode(request).length;
    final reply = Completer<Map<String, dynamic>>();
    _pending[id] = reply;
    try {
      final results = await Future.wait<Object?>([
        controller
            .evaluateJavascript(
              source: 'window.otzariaWebViewProbe.command($request);',
            )
            .timeout(_deadline),
        reply.future.timeout(_deadline),
      ]);
      return results.last as Map<String, dynamic>;
    } finally {
      _pending.remove(id);
    }
  }
}
