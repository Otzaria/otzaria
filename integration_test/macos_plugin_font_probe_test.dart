import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
  var faces = await document.fonts.load(target, 'אבג ABC 012');
  var span = document.createElement('span');
  span.textContent = 'שלום עולם אבגדה ABC 012345';
  span.style.cssText = 'display:block;white-space:nowrap;font:' + spec.weight + ' 18px "' + spec.family + '"';
  document.body.appendChild(span);
  samples.push({key: spec.key, family: spec.family, weight: spec.weight,
    loadedFaces: faces.map(f => ({family: f.family, weight: f.weight, status: f.status})),
    ...render(spec.family, spec.weight)});
}
await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
return {samples: samples, fallbackControl: render('monospace', '400'),
  visible: document.visibilityState === 'visible',
  bootCount: window.fontProbeBootCount, bootTheme: window.fontProbeBootTheme,
  readyFacesAtBoot: window.fontProbeReadyFacesAtBoot,
  viewport: {width: innerWidth, height: innerHeight, dpr: devicePixelRatio},
  userAgent: navigator.userAgent};
''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
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
            'CI window and canvas rendering verified; physical display, GPU pipeline and WKWebView process topology are not measured.',
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
          (_) => Completer<_ProbeResult>(),
        );
        Widget grid({bool closeFirst = false}) => MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (var i = closeFirst ? 1 : 0; i < _count; i++)
                  SizedBox(
                    key: ValueKey('$scenario-$i'),
                    width: 320,
                    height: 150,
                    child: _FontProbeView(
                      key: ValueKey('$scenario-$i'),
                      root: root.path,
                      scenario: scenario,
                      csp: csp,
                      theme: theme,
                      specs: specs,
                      index: i,
                      completed: completed[i],
                    ),
                  ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(grid());
        final results = await _pumpUntil(
          tester,
          Future.wait(completed.map((c) => c.future)),
        );
        final entry = <String, Object?>{
          'scenario': scenario,
          'views': results.map((r) => r.report).toList(),
          'hostRssAfterBytes': ProcessInfo.currentRss,
        };
        cases.add(entry);
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
          await tester.pumpWidget(grid(closeFirst: true));
          expect(results.first.lease.isActive, isFalse);
          expect(results.last.lease.isActive, isTrue);
          final survivor = await results.last.controller.callAsyncJavaScript(
            functionBody:
                'return (await document.fonts.load(target)).map(f => f.status);',
            arguments: {'target': '16px "${system.family}"'},
          );
          expect(survivor?.value, isNotEmpty);
          expect((survivor!.value as List).every((s) => s == 'loaded'), isTrue);
          entry['survivorAfterClosingFirst'] = survivor.value;
          if (_mode == 'scheme' &&
              (results.last.report['preparation'] as Map)['transport'] ==
                  'scheme') {
            entry['freshSchemeAfterClosingFirst'] = await _pumpUntil(
              tester,
              _loadFreshSurvivorFont(results.last),
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
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<Map<String, Object?>> _loadFreshSurvivorFont(
  _ProbeResult survivor,
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

Future<T> _pumpUntil<T>(WidgetTester tester, Future<T> future) async {
  T? value;
  Object? error;
  StackTrace? stack;
  var done = false;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stack = s;
      done = true;
    },
  );
  final watch = Stopwatch()..start();
  while (!done && watch.elapsed < const Duration(seconds: 60)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!done) throw TimeoutException('Font probe did not finish');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

class _ProbeResult {
  _ProbeResult(this.controller, this.lease, this.report);
  final InAppWebViewController controller;
  final PluginFontSchemeLease lease;
  final Map<String, Object?> report;
}

class _FontProbeView extends StatefulWidget {
  const _FontProbeView({
    super.key,
    required this.root,
    required this.scenario,
    required this.csp,
    required this.theme,
    required this.specs,
    required this.index,
    required this.completed,
  });
  final String root;
  final String scenario;
  final String csp;
  final Map<String, dynamic> theme;
  final List<Map<String, String>> specs;
  final int index;
  final Completer<_ProbeResult> completed;
  @override
  State<_FontProbeView> createState() => _FontProbeViewState();
}

class _FontProbeViewState extends State<_FontProbeView> {
  final _clock = Stopwatch()..start();
  final _fontOwner = PluginFontSchemeOwner();
  bool _started = false;

  @override
  void dispose() {
    _fontOwner.attach(null);
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
    onWebViewCreated: (controller) => _fontOwner.attach(controller.platform),
    onLoadStart: (controller, url) =>
        _fontOwner.release(controller: controller.platform),
    onLoadResourceWithCustomScheme: (controller, request) => servePluginAsset(
      url: request.url,
      pluginId: _pluginId,
      rootPath: widget.root,
      fontLease: _fontOwner.lease,
      contentSecurityPolicy: widget.csp,
    ),
    onLoadStop: (controller, url) async {
      if (_started) return;
      _started = true;
      final lease = _fontOwner.begin(
        controller: controller.platform,
        origin: _origin,
      )!;
      try {
        final loadedAt = _clock.elapsedMicroseconds;
        final preparation = await preparePluginFontExperiment(
          controller,
          lease: lease,
          theme: widget.theme,
          isCurrent: () => mounted && identical(_fontOwner.lease, lease),
          useScheme: _mode == 'scheme',
        );
        final readyAt = preparation.ready ? _clock.elapsedMicroseconds : null;
        final boot = await preparation.evaluateBoot(
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
          isCurrent: () => mounted && identical(_fontOwner.lease, lease),
        );
        final schemeAtBoot = lease.responseBytes;
        final rendering = await controller
            .callAsyncJavaScript(
              functionBody: widget.scenario == 'style-src-none'
                  ? 'return {bootCount: window.fontProbeBootCount, bootTheme: window.fontProbeBootTheme, visible: document.visibilityState === "visible", samples: []};'
                  : _measureJs,
              arguments: {'specs': widget.specs},
            )
            .timeout(const Duration(seconds: 10));
        if (rendering?.error != null || rendering?.value is! Map) {
          throw StateError('Font rendering probe failed: ${rendering?.error}');
        }
        final screenshot = widget.scenario == 'style-src-none'
            ? null
            : await controller.takeScreenshot();
        widget.completed.complete(
          _ProbeResult(controller, lease, {
            'index': widget.index,
            'documentLoadMicroseconds': loadedAt,
            'fontReadyFromViewCreationMicroseconds': readyAt,
            'preparation': preparation.toJson(),
            'bootJavascriptUtf8Bytes': boot.javascriptUtf8Bytes,
            'bootAcknowledged': true,
            'schemeBytesAtBoot': schemeAtBoot,
            'schemeResponseBytes': lease.responseBytes,
            'schemeRequests': lease.requestCount,
            'schemeResponses': lease.responseCount,
            'rendering': Map<String, dynamic>.from(rendering!.value as Map),
            'screenshotBase64': screenshot == null
                ? null
                : base64Encode(screenshot),
          }),
        );
      } catch (error, stack) {
        if (!widget.completed.isCompleted) {
          widget.completed.completeError(error, stack);
        }
      }
    },
  );
}
