import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart'
    show buildPluginTabWebViewSettings;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/app_fonts.dart';

import '../test/helpers/memory_settings_cache.dart';
import 'support/apple_font_probe_view.dart';
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
) => loadFreshAppleSurvivorFont(survivor);

typedef MacosFontProbeResult = AppleFontProbeResult;

class MacosFontProbeView extends AppleFontProbeView {
  MacosFontProbeView({
    super.key,
    required super.root,
    required super.scenario,
    required super.csp,
    required super.theme,
    required super.specs,
    required super.index,
    required super.completed,
    required super.progress,
  }) : super(
         documentUrl: '$_origin/$scenario.html',
         fontOrigin: _origin,
         pluginId: _pluginId,
         appPlatform: 'macos',
         useScheme: _mode == 'scheme',
         settings: buildPluginTabWebViewSettings(
           isDevelopment: false,
           contentBlockers: buildPluginContentBlockers(
             pluginId: _pluginId,
             policy: PluginNetworkPolicy.none,
             fileServerPort: 1,
           ),
         )..incognito = true,
       );
}
