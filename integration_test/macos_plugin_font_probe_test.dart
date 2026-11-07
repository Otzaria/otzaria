import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart'
    show buildPluginTabWebViewSettings;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/app_fonts.dart';

import '../test/helpers/memory_settings_cache.dart';
import 'support/macos_font_probe.dart';
import 'support/webview_probe_window.dart';

const _mode = String.fromEnvironment(
  'OTZARIA_FONT_PROBE_TRANSPORT',
  defaultValue: 'data',
);
const _count = int.fromEnvironment(
  'OTZARIA_FONT_PROBE_INSTANCES',
  defaultValue: 1,
);
const _pluginId = 'font.probe';
const _origin = 'otzaria-plugin://$_pluginId';

const _measureJs = r'''
var started = performance.now();
var progress = window.__otzariaFontProbeRendering = {
  documentId: document.__otzariaFontDocumentId, owner: document.__otzariaFontBootAttempt,
  startedAtEpochMilliseconds: Date.now(), events: [], droppedEvents: 0
};
function mark(phase, key) {
  progress.phase = phase;
  progress.elapsedMilliseconds = performance.now() - started;
  if (progress.events.length === 40) { progress.droppedEvents++; return; }
  progress.events.push({phase: phase, fontKey: key || null,
    elapsedMilliseconds: progress.elapsedMilliseconds, visibilityState: document.visibilityState});
}
mark('started');
var samples = [];
function render(family, weight) {
  var canvas = document.createElement('canvas');
  canvas.width = 650; canvas.height = 80;
  var ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 650, 80);
  ctx.font = weight + ' 28px "' + family + '"';
  ctx.fillStyle = '#000'; ctx.textBaseline = 'top';
  var text = 'שלום עולם אבגדה ABC 012345';
  ctx.fillText(text, 8, 8);
  var pixels = ctx.getImageData(0, 0, 650, 80).data;
  var hash = 2166136261, ink = 0;
  for (var i = 0; i < pixels.length; i++) {
    hash = Math.imul(hash ^ pixels[i], 16777619) >>> 0;
    if (i % 4 === 0 && pixels[i] < 128) ink++;
  }
  return {width: ctx.measureText(text).width, pixelHash: hash.toString(16), inkPixels: ink};
}
for (var spec of specs) {
  var target = spec.weight + ' 28px "' + spec.family + '"';
  mark('font-load-started', spec.key);
  var faces = await document.fonts.load(target, 'אבג ABC 012');
  mark('font-load-completed', spec.key);
  var span = document.createElement('span');
  span.textContent = 'שלום עולם אבגדה ABC 012345';
  span.style.cssText = 'display:block;white-space:nowrap;font:' + spec.weight + ' 18px "' + spec.family + '"';
  document.body.appendChild(span);
  mark('canvas-started', spec.key);
  samples.push({key: spec.key, family: spec.family, weight: spec.weight,
    loadedFaces: faces.map(f => ({family: f.family, weight: f.weight, status: f.status})),
    ...render(spec.family, spec.weight)});
  mark('canvas-completed', spec.key);
}
mark('frames-requested');
await new Promise(resolve => requestAnimationFrame(() => {
  mark('frame-1');
  requestAnimationFrame(() => { mark('frame-2'); resolve(); });
}));
mark('fallback-started');
var fallback = render('monospace', '400');
mark('fallback-completed');
mark('completed');
return {samples: samples, fallbackControl: fallback, renderingProgress: progress,
  visible: document.visibilityState === 'visible',
  bootCount: window.fontProbeBootCount, bootTheme: window.fontProbeBootTheme,
  readyFacesAtBoot: window.fontProbeReadyFacesAtBoot,
  viewport: {width: innerWidth, height: innerHeight, dpr: devicePixelRatio},
  userAgent: navigator.userAgent};
''';

void main() {
  final binding = initializeMacosFontProbeBinding();
  testWidgets(
    'macOS plugin font transport probe',
    (tester) async {
      expect(['data', 'scheme'], contains(_mode));
      expect([1, 5, 10], contains(_count));
      expect(pluginMacFontSchemeEnabled, isTrue);
      Settings.init(cacheProvider: MemorySettingsCache());
      final scanClock = Stopwatch()..start();
      await AppFonts.warmUpSystemFontsCache().timeout(
        const Duration(seconds: 45),
      );
      scanClock.stop();
      final candidates =
          AppFonts.availableFonts
              .where((font) => !AppFonts.fontPaths.containsKey(font.value))
              .map((font) => AppFonts.pluginSystemFamilyFaces(font.value))
              .whereType<SystemFontFamilyFaces>()
              .where(
                (face) => File(face.regularPath).lengthSync() < 2 * 1024 * 1024,
              )
              .toList()
            ..sort((a, b) => a.family.compareTo(b.family));
      expect(
        candidates,
        isNotEmpty,
        reason:
            'A readable installed Hebrew TTF/OTF is required for system-font coverage',
      );
      final system = candidates.first;
      final theme = <String, dynamic>{
        'typography': {
          'fontFamily': system.family,
          'commentatorsFontFamily': 'FrankRuhlCLM',
          'uiFontFamily': 'Rubik',
          'fontSize': 28,
        },
      };
      final specs = [
        {'key': 'system-regular', 'family': system.family, 'weight': '400'},
        {'key': 'system-bold', 'family': system.family, 'weight': '700'},
        {'key': 'bundled-regular', 'family': 'FrankRuhlCLM', 'weight': '400'},
        {'key': 'bundled-bold', 'family': 'FrankRuhlCLM', 'weight': '700'},
        {'key': 'variable-light', 'family': 'Rubik', 'weight': '300'},
        {'key': 'variable-bold', 'family': 'Rubik', 'weight': '700'},
      ];
      final root = await Directory.systemTemp.createTemp('otzaria-font-probe-');
      final scene = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(() async {
        scene.value = const SizedBox.shrink();
        await root.delete(recursive: true);
        scene.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<Widget>(
            valueListenable: scene,
            builder: (context, child, _) => child,
          ),
        ),
      );
      final window = await prepareWebViewProbeWindow(
        platform: Platform.operatingSystem,
        pumpFrame: () => tester.pump(),
      );
      final cases = <Map<String, Object?>>[];
      final report = <String, Object?>{
        'schemaVersion': 1,
        'requestedTransport': _mode,
        'instances': _count,
        'pid': pid,
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'dartVersion': Platform.version,
        'hostKind': 'visible-flutter-platform-view',
        'window': window,
        'systemFont': {
          'family': system.family,
          'hasBoldFile': system.boldPath != null,
          'hasWeightAxis': system.hasWeightAxis,
          'regularFileBytes': File(system.regularPath).lengthSync(),
          'discoveryMicroseconds': scanClock.elapsedMicroseconds,
        },
        'hostRssBeforeBytes': ProcessInfo.currentRss,
        'engineMemory': {
          'availability': 'unsupported',
          'reason':
              'WKWebView child-process memory is not exposed by this probe.',
        },
        'engineCpu': {
          'availability': 'unsupported',
          'reason':
              'No WKWebView process CPU sampler is available in this probe.',
        },
        'hardwareCompleteness':
            'Window readiness is recorded separately. Canvas rendering is checked only in completed cases; physical display, GPU pipeline and WKWebView process topology are not measured.',
        'framePolicy': binding.framePolicy.name,
        'status': 'running',
        'byteDefinitions': {
          'bootJavascriptUtf8Bytes':
              'UTF-8 bytes of the exact evaluateJavascript boot source submitted to the controller.',
          'javascriptUtf8Bytes':
              'UTF-8 bytes of submitted font callAsyncJavaScript function bodies.',
          'argumentJsonUtf8Bytes':
              'UTF-8 JSON length of submitted font arguments; excludes native protocol envelopes and copies.',
          'cssUtf8Bytes':
              'CSS included in argumentJsonUtf8Bytes; do not add this field a second time.',
          'schemeResponseBytes':
              'Sum of byte arrays returned by this document lease to custom-scheme callbacks; no assumed cache sharing.',
        },
        'control':
            'Both data and scheme use the experimental bounded pre-boot verifier. The default production Apple path is unchanged and is not this timing control.',
        'decision': 'keep-default-off',
        'ios': 'disabled-unvalidated',
        'cases': cases,
      };
      binding.reportData = {'fontProbe': report};

      for (final scenario in ['normal', 'font-src-data', 'style-src-none']) {
        final baseCsp = buildPluginContentSecurityPolicy(
          pluginId: _pluginId,
          policy: PluginNetworkPolicy.none,
          fileServerPort: 1,
        );
        final csp = switch (scenario) {
          'font-src-data' => '$baseCsp; font-src data:',
          'style-src-none' => "$baseCsp; style-src 'none'",
          _ => baseCsp,
        };
        await File('${root.path}/$scenario.html').writeAsString('''
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="$csp"></head><body>
<script>
window.fontProbeBootCount = 0;
window.addEventListener('plugin.boot', e => {window.fontProbeBootTheme = e.detail.theme;});
window.addEventListener('plugin.ready', () => {
  window.fontProbeBootCount++;
  window.fontProbeReadyFacesAtBoot = Array.from(document.fonts).filter(f => f.status === 'loaded').map(f => ({family:f.family,weight:f.weight}));
});
</script></body></html>
''');
        final completed = List.generate(
          _count,
          (_) => Completer<MacosFontProbeResult>(),
        );
        final progress = List.generate(_count, FontProbeViewProgress.new);
        final entry = <String, Object?>{
          'scenario': scenario,
          'status': 'running',
          'cleanupStatus': 'pending',
          'views': progress.map((p) => p.report).toList(),
        };
        cases.add(entry);
        Widget grid({bool closeFirst = false}) => Scaffold(
          body: Wrap(
            children: [
              for (var i = closeFirst ? 1 : 0; i < _count; i++)
                SizedBox(
                  key: ValueKey('$scenario-$i'),
                  width: 320,
                  height: 150,
                  child: MacosFontProbeView(
                    key: ValueKey('$scenario-$i'),
                    root: root.path,
                    scenario: scenario,
                    csp: csp,
                    theme: theme,
                    specs: specs,
                    index: i,
                    completed: completed[i],
                    progress: progress[i],
                  ),
                ),
            ],
          ),
        );
        Object? caseError;
        StackTrace? caseStack;
        try {
          final batch = Future.wait(
            completed.map((c) => c.future),
            eagerError: true,
          ).timeout(const Duration(seconds: 60));
          scene.value = grid();
          final results = await batch;
          entry['hostRssAfterBytes'] = ProcessInfo.currentRss;
          for (final result in results) {
            final r = result.report;
            expect(r['bootAcknowledged'], isTrue);
            expect((r['rendering'] as Map)['bootCount'], 1);
            expect((r['rendering'] as Map)['visible'], isTrue);
            expect((r['rendering'] as Map)['bootTheme'], theme);
            if (scenario == 'style-src-none') {
              expect((r['preparation'] as Map)['ready'], isFalse);
              expect(
                ((r['preparation'] as Map)['outcome'] as Map)['reason'],
                'style-blocked',
              );
            } else {
              expect((r['preparation'] as Map)['ready'], isTrue);
              final samples = (r['rendering'] as Map)['samples'] as List;
              for (final sample in samples.cast<Map>()) {
                expect(sample['inkPixels'], greaterThan(0));
                expect(sample['loadedFaces'], isNotEmpty);
                expect(
                  (sample['loadedFaces'] as List).every(
                    (f) => f['status'] == 'loaded',
                  ),
                  isTrue,
                );
              }
              expect(
                samples[2]['pixelHash'],
                isNot(samples[3]['pixelHash']),
                reason: 'separate bold face must render differently',
              );
              expect(
                samples[4]['pixelHash'],
                isNot(samples[5]['pixelHash']),
                reason: 'variable wght axis must render differently',
              );
              expect(
                samples.any(
                  (s) =>
                      s['pixelHash'] !=
                      (r['rendering'] as Map)['fallbackControl']['pixelHash'],
                ),
                isTrue,
              );
              if (scenario == 'font-src-data') {
                expect((r['preparation'] as Map)['transport'], 'data');
                if (_mode == 'scheme') {
                  expect((r['preparation'] as Map)['schemeFailure'], isNotNull);
                }
              }
              expect(r['screenshotBase64'], isNotEmpty);
            }
          }
          if (_count > 1 && scenario == 'normal') {
            scene.value = grid(closeFirst: true);
            await progress.first.whenDisposed.timeout(
              const Duration(seconds: 10),
            );
            expect(results.first.lease.isActive, isFalse);
            expect(results.last.lease.isActive, isTrue);
            final survivor = await progress.last.observe(
              'survivor-font-load',
              () => results.last.controller.callAsyncJavaScript(
                functionBody:
                    'return (await document.fonts.load(target)).map(f => f.status);',
                arguments: {'target': '16px "${system.family}"'},
              ),
            );
            expect(survivor?.value, isNotEmpty);
            expect(
              (survivor!.value as List).every((s) => s == 'loaded'),
              isTrue,
            );
            entry['survivorAfterClosingFirst'] = survivor.value;
            if (_mode == 'scheme' &&
                (results.last.report['preparation'] as Map)['transport'] ==
                    'scheme') {
              entry['freshSchemeAfterClosingFirst'] = await progress.last
                  .observe(
                    'fresh-survivor-font-load',
                    () => _loadFreshSurvivorFont(results.last),
                  );
            } else {
              entry['freshSchemeAfterClosingFirst'] = {
                'availability': 'not-run',
                'reason': _mode == 'data'
                    ? 'data-control'
                    : 'normal-scheme-unavailable',
              };
            }
          }
          entry['status'] = 'passed';
        } catch (error, stack) {
          entry['status'] = 'failed';
          entry['error'] = error.toString();
          report['status'] = 'failed';
          for (final item in progress) {
            if (item.isActive && item.report['status'] != 'completed') {
              item.fail(error, stack);
            }
          }
          caseError = error;
          caseStack = stack;
          await Future.wait(progress.map((p) => p.captureFailureSnapshot()));
        } finally {
          scene.value = const SizedBox.shrink();
          try {
            await Future.wait(
              progress.map((p) => p.whenDisposed),
            ).timeout(const Duration(seconds: 10));
            entry['cleanupStatus'] = 'completed';
          } catch (error, stack) {
            entry['cleanupStatus'] = 'failed';
            entry['cleanupError'] = error.toString();
            entry['status'] = 'failed';
            report['status'] = 'failed';
            caseError ??= error;
            caseStack ??= stack;
          }
        }
        if (caseError != null) Error.throwWithStackTrace(caseError, caseStack!);
      }
      report['status'] = 'passed';
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<Map<String, Object?>> _loadFreshSurvivorFont(
  MacosFontProbeResult survivor,
) async {
  final lease = survivor.lease;
  final requests = lease.requestCount;
  final responses = lease.responseCount;
  final bytes = lease.responseBytes;
  var loaderReads = 0;
  final url = lease.register('post-close-survivor', () async {
    loaderReads++;
    final data = await rootBundle.load(AppFonts.fontPaths['FrankRuhlCLM']!);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });
  expect(loaderReads, 0);
  final result = await survivor.controller
      .callAsyncJavaScript(
        functionBody: r'''
if (document.__otzariaFontBootAttempt !== owner) return {loaded: false, reason: 'stale-document'};
var face = new FontFace('OtzariaLeaseSurvivor', 'url(' + JSON.stringify(url) + ')');
document.fonts.add(face);
try {
  await face.load();
  return {loaded: document.__otzariaFontBootAttempt === owner && document.fonts.has(face) && face.status === 'loaded', status: face.status};
} finally {
  document.fonts.delete(face);
}
''',
        arguments: {'url': url, 'owner': lease.id},
      )
      .timeout(const Duration(seconds: 5));
  expect(result?.error, isNull);
  expect(result?.value, isA<Map>());
  final value = result!.value as Map;
  expect(value['loaded'], isTrue);
  final requestDelta = lease.requestCount - requests;
  final responseDelta = lease.responseCount - responses;
  final responseBytesDelta = lease.responseBytes - bytes;
  expect(loaderReads, greaterThan(0));
  expect(requestDelta, greaterThan(0));
  expect(responseDelta, greaterThan(0));
  expect(responseBytesDelta, greaterThan(0));
  return {
    'availability': 'verified',
    'loaderReads': loaderReads,
    'requestDelta': requestDelta,
    'responseDelta': responseDelta,
    'responseBytesDelta': responseBytesDelta,
    'faceStatus': value['status'],
  };
}

class MacosFontProbeResult {
  MacosFontProbeResult(this.controller, this.lease, this.report);
  final InAppWebViewController controller;
  final PluginFontSchemeLease lease;
  final Map<String, Object?> report;
}

class MacosFontProbeView extends StatefulWidget {
  const MacosFontProbeView({
    super.key,
    required this.root,
    required this.scenario,
    required this.csp,
    required this.theme,
    required this.specs,
    required this.index,
    required this.completed,
    required this.progress,
  });
  final String root;
  final String scenario;
  final String csp;
  final Map<String, dynamic> theme;
  final List<Map<String, String>> specs;
  final int index;
  final Completer<MacosFontProbeResult> completed;
  final FontProbeViewProgress progress;
  @override
  State<MacosFontProbeView> createState() => _MacosFontProbeViewState();
}

class _MacosFontProbeViewState extends State<MacosFontProbeView> {
  final _fontOwner = PluginFontSchemeOwner();
  bool _started = false;

  bool get _current => mounted && widget.progress.isActive;

  void _fail(Object error, StackTrace stack) {
    widget.progress.fail(error, stack);
    if (!widget.completed.isCompleted) {
      widget.completed.completeError(error, stack);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.progress.mounted();
  }

  @override
  void dispose() {
    _fontOwner.attach(null);
    widget.progress.dispose();
    if (!widget.completed.isCompleted) {
      widget.completed.completeError(
        StateError('Font probe view disposed before completion'),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InAppWebView(
    initialUrlRequest: URLRequest(
      url: WebUri('$_origin/${widget.scenario}.html'),
    ),
    initialSettings: buildPluginTabWebViewSettings(
      isDevelopment: false,
      contentBlockers: buildPluginContentBlockers(
        pluginId: _pluginId,
        policy: PluginNetworkPolicy.none,
        fileServerPort: 1,
      ),
    )..incognito = true,
    initialUserScripts: UnmodifiableListView([
      UserScript(
        source: pluginSdkStubScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: pluginFontDocumentMarkerJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]),
    onWebViewCreated: (controller) {
      if (!_current) return;
      widget.progress.record('controller-created', {
        'nativeViewId': controller.getViewId(),
      });
      _fontOwner.attach(controller.platform);
    },
    shouldOverrideUrlLoading: (controller, navigation) async {
      if (!_current) return NavigationActionPolicy.CANCEL;
      final url = navigation.request.url?.rawValue;
      final allowed =
          navigation.isForMainFrame &&
          url == '$_origin/${widget.scenario}.html';
      widget.progress.record('navigation-decision', {
        'url': url,
        'isForMainFrame': navigation.isForMainFrame,
        'policy': allowed ? 'allow' : 'cancel',
      });
      if (!allowed) {
        _fail(
          StateError('Unexpected font probe navigation: $url'),
          StackTrace.current,
        );
      }
      return allowed
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    },
    onLoadStart: (controller, url) {
      if (!_current) return;
      widget.progress.record('load-start', {'url': url?.rawValue});
      _fontOwner.release(controller: controller.platform);
    },
    onLoadResourceWithCustomScheme: (controller, request) async {
      if (!_current) return null;
      widget.progress.record('scheme-request', {'url': request.url.rawValue});
      try {
        final response = await servePluginAsset(
          url: request.url,
          pluginId: _pluginId,
          rootPath: widget.root,
          fontLease: _fontOwner.lease,
          contentSecurityPolicy: widget.csp,
        );
        if (!_current) return null;
        widget.progress.record('scheme-response', {
          'url': request.url.rawValue,
          'bytes': response?.data.length,
          'contentType': response?.contentType,
        });
        return response;
      } catch (error, stack) {
        _fail(error, stack);
        rethrow;
      }
    },
    onReceivedError: (controller, request, error) {
      if (!_current) return;
      widget.progress.record('navigation-error', {
        'url': request.url.rawValue,
        'isForMainFrame': request.isForMainFrame,
        'type': error.type.toNativeValue(),
        'description': error.description,
      });
      if (request.isForMainFrame == true ||
          request.url.rawValue == '$_origin/${widget.scenario}.html') {
        _fail(StateError(error.description), StackTrace.current);
      }
    },
    onWebContentProcessDidTerminate: (controller) {
      if (!_current) return;
      _fail(
        StateError('WKWebView content process terminated'),
        StackTrace.current,
      );
    },
    onLoadStop: (controller, url) async {
      if (!_current || _started) return;
      _started = true;
      final progress = widget.progress;
      progress.record('load-stop', {'url': url?.rawValue});
      try {
        if (url?.rawValue != '$_origin/${widget.scenario}.html') {
          throw StateError('Unexpected font probe document: $url');
        }
        final lease = _fontOwner.begin(
          controller: controller.platform,
          origin: _origin,
        );
        if (lease == null) {
          throw StateError('Font probe controller is not attached');
        }
        final loadedAt = progress.elapsedMicroseconds;
        final preparation = await progress.observe(
          'font-preparation',
          () => preparePluginFontExperiment(
            controller,
            lease: lease,
            theme: widget.theme,
            isCurrent: () => _current && identical(_fontOwner.lease, lease),
            useScheme: _mode == 'scheme',
          ),
        );
        progress.report.addAll({
          'documentLoadMicroseconds': loadedAt,
          'fontReadyFromViewCreationMicroseconds': preparation.ready
              ? progress.elapsedMicroseconds
              : null,
          'preparation': preparation.toJson(),
        });
        progress.registerFailureSnapshot(() async {
          if (!mounted ||
              !identical(_fontOwner.lease, lease) ||
              !lease.isActive) {
            throw StateError('Font probe snapshot owner is no longer current');
          }
          final box = context.findRenderObject();
          if (box is RenderBox && box.hasSize) {
            final position = box.localToGlobal(Offset.zero);
            progress.record('failure-widget-bounds', {
              'x': position.dx,
              'y': position.dy,
              'width': box.size.width,
              'height': box.size.height,
            });
          }
          return await controller.evaluateJavascript(
                source: buildFontProbeFailureSnapshotScript(
                  documentId: preparation.documentId,
                  owner: lease.id,
                ),
              )
              as String?;
        });
        final boot = await progress.observe(
          'boot',
          () => preparation.evaluateBoot(
            controller,
            source: buildPluginBootScript(
              nonceJson: jsonEncode('font-probe'),
              payloadJson: jsonEncode({
                'plugin': {'id': _pluginId},
                'app': {'platform': 'macos', 'runMode': 'foreground'},
                'theme': widget.theme,
                'permissions': [],
              }),
            ),
            isCurrent: () => _current && identical(_fontOwner.lease, lease),
          ),
        );
        progress.report.addAll({
          'bootJavascriptUtf8Bytes': boot.javascriptUtf8Bytes,
          'bootAcknowledged': true,
          'schemeBytesAtBoot': lease.responseBytes,
        });
        progress.report['renderingRequestedAtEpochMilliseconds'] =
            DateTime.now().millisecondsSinceEpoch;
        final rendering = await progress.observe(
          'rendering',
          () => controller.callAsyncJavaScript(
            functionBody: widget.scenario == 'style-src-none'
                ? 'return {bootCount: window.fontProbeBootCount, bootTheme: window.fontProbeBootTheme, visible: document.visibilityState === "visible", samples: []};'
                : _measureJs,
            arguments: {'specs': widget.specs},
          ),
        );
        if (rendering?.error != null || rendering?.value is! Map) {
          throw StateError('Font rendering probe failed: ${rendering?.error}');
        }
        progress.report.addAll({
          'schemeResponseBytes': lease.responseBytes,
          'schemeRequests': lease.requestCount,
          'schemeResponses': lease.responseCount,
          'rendering': Map<String, dynamic>.from(rendering!.value as Map),
        });
        final screenshot = widget.scenario == 'style-src-none'
            ? null
            : await progress.observe(
                'screenshot',
                () => controller.takeScreenshot(),
              );
        progress.report['screenshotBase64'] = screenshot == null
            ? null
            : base64Encode(screenshot);
        progress.complete();
        widget.completed.complete(
          MacosFontProbeResult(controller, lease, progress.report),
        );
      } catch (error, stack) {
        _fail(error, stack);
      }
    },
  );
}
