import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:path_provider/path_provider.dart';

import '../test/helpers/memory_settings_cache.dart';
import 'support/apple_font_probe_view.dart';
import 'support/ios_font_probe.dart';
import 'support/ios_simulator_vm_service.dart';
import 'support/ios_font_probe_case.dart';
import 'support/ios_font_probe_report.dart';
import 'support/macos_font_probe.dart';

/// Per-count values arrive at launch (SIMCTL_CHILD_*), so one build serves
/// every view count.
String _launchValue(String name, String compiled) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? compiled : value;
}

final _count = int.parse(
  _launchValue(
    'OTZARIA_FONT_PROBE_INSTANCES',
    const String.fromEnvironment(
      'OTZARIA_FONT_PROBE_INSTANCES',
      defaultValue: '1',
    ),
  ),
);
final _coordinator = _launchValue(
  'IOS_FONT_PROBE_COORDINATOR',
  const String.fromEnvironment('IOS_FONT_PROBE_COORDINATOR'),
);
final _generation = _launchValue(
  'IOS_FONT_PROBE_GENERATION',
  const String.fromEnvironment('IOS_FONT_PROBE_GENERATION'),
);
const _buildId = String.fromEnvironment('IOS_FONT_PROBE_BUILD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  pinIosSimulatorSemantics(binding);
  if (Platform.isIOS &&
      const bool.fromEnvironment('OTZARIA_IOS_FONT_PROBE_EXPORT')) {
    // Physical release has no VM service/Flutter Driver. The fixture alone can
    // export its actual framework result for Xcode's Download Container action.
    unawaited(
      binding.allTestsPassed.future
          .then((passed) async {
            final documents = await getApplicationDocumentsDirectory();
            final root = Directory('${documents.path}/ios-font-compatibility');
            await root.create(recursive: true);
            final output = await root.createTemp('run-');
            final response = passed
                ? Response.allTestsPassed(data: binding.reportData)
                : Response.someTestsFailed(
                    binding.failureMethodsDetails,
                    data: binding.reportData,
                  );
            try {
              await writeIosFontProbeReport(output, response);
              await File('${output.path}/export-complete.txt').writeAsString(
                'frameworkAllTestsPassed=$passed\n',
                flush: true,
              );
              debugPrint('iOS font compatibility export: ${output.path}');
            } catch (error, stack) {
              await File('${output.path}/export-error.txt').writeAsString(
                '$error\n$stack',
                flush: true,
              );
              debugPrint('iOS font compatibility export FAILED: $error');
            }
          })
          .catchError((Object error, StackTrace stack) {
            debugPrint(
              'iOS font compatibility export unavailable: $error\n$stack',
            );
          }),
    );
  }
  testWidgets(
    'iOS plugin font origin and policy compatibility',
    (tester) async {
      final cases = <Map<String, Object?>>[];
      final report = <String, Object?>{
        'schemaVersion': 1,
        'status': 'running',
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
        'buildMode': kReleaseMode
            ? 'release'
            : (kProfileMode ? 'profile' : 'debug'),
        'deviceKind': const String.fromEnvironment(
          'OTZARIA_IOS_FONT_PROBE_DEVICE',
        ),
        'sourceCommit': const String.fromEnvironment(
          'OTZARIA_IOS_FONT_PROBE_SOURCE',
        ),
        'startupGeneration': _generation,
        'buildId': _buildId,
        'lockSha256': const String.fromEnvironment(
          'OTZARIA_IOS_FONT_PROBE_LOCK_SHA256',
        ),
        'instances': _count,
        'pid': pid,
        'framePolicy': binding.framePolicy.name,
        'frameDriver': 'fullyLive-value-notifier',
        'hostKind': 'visible-flutter-platform-view',
        'hostRssBeforeBytes': ProcessInfo.currentRss,
        'engineMemory': {'availability': 'unsupported'},
        'engineCpu': {'availability': 'unsupported'},
        'crossViewCacheSharing': {'availability': 'not-measured'},
        'decision': 'keep-default-off',
        'productionIosExperimentEnabled': pluginMacFontSchemeEnabled,
        'theme': iosFontProbeTheme,
        'physicalProfile': kProfileMode ? 'this-run' : 'notRun',
        'physicalRelease': kReleaseMode ? 'this-run' : 'notRun',
        'cases': cases,
      };
      binding.reportData = {'iosFontProbe': report};
      expect([1, 5, 10], contains(_count));
      expect(pluginMacFontSchemeEnabled, isFalse);
      Settings.init(cacheProvider: MemorySettingsCache());
      final createdRoot = await Directory.systemTemp.createTemp(
        'otzaria-ios-font-probe-',
      );
      final root = Directory(await createdRoot.resolveSymbolicLinks());
      final host = ValueNotifier<Widget>(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<Widget>(
              valueListenable: host,
              builder: (context, child, _) => child,
            ),
          ),
        ),
      );
      addTearDown(() async {
        host.dispose();
        await root.delete(recursive: true);
      });
      await binding.waitUntilFirstFrameRasterized;
      report['startupFirstFrameRasterized'] = binding.firstFrameRasterized;
      await notifyIosFontProbeStarted(
        coordinator: _coordinator,
        token: _launchValue(
          'IOS_FONT_PROBE_TOKEN',
          const String.fromEnvironment('IOS_FONT_PROBE_TOKEN'),
        ),
        generation: _generation,
        nativeFork: const String.fromEnvironment('IOS_FONT_PROBE_NATIVE_FORK'),
        buildId: _buildId,
        firstFrameRasterized: binding.firstFrameRasterized,
        vmService: _coordinator.isEmpty
            ? const {}
            : await iosSimulatorVmService(),
      );
      for (final config in iosFontProbeCases) {
        final completed = List.generate(
          _count,
          (_) => Completer<AppleFontProbeResult>(),
        );
        final progress = List.generate(_count, FontProbeViewProgress.new);
        final entry = <String, Object?>{
          'id': config.id,
          'scenario': config.scenario,
          'requestedTransport': config.transport,
          'policy': config.policyReport,
          'status': 'running',
          'views': progress.map((p) => p.report).toList(),
        };
        cases.add(entry);
        Widget grid({bool closeFirst = false}) => SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = _count == 1 ? 1 : 2;
              final rows = (_count / columns).ceil();
              return Wrap(
                children: [
                  for (var i = closeFirst ? 1 : 0; i < _count; i++)
                    SizedBox(
                      key: ValueKey('${config.id}-$i'),
                      width: box.maxWidth / columns,
                      height: box.maxHeight / rows,
                      child: AppleFontProbeView(
                        root: root.path,
                        scenario: config.scenario,
                        csp: config.csp,
                        theme: iosFontProbeTheme,
                        specs: iosFontProbeSpecs,
                        index: i,
                        completed: completed[i],
                        progress: progress[i],
                        documentUrl: config.documentUrl(root.path),
                        fontOrigin: iosFontProbeOrigin,
                        pluginId: iosFontProbePluginId,
                        appPlatform: 'ios',
                        useScheme: config.useScheme,
                        settings: config.settings,
                        capturePolicyDiagnostics: true,
                        navigationUrl: config.documentUrl(
                          root.path,
                          navigation: true,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
        await runIosFontProbeCase(
          entry: entry,
          report: report,
          progress: progress,
          unmount: () => host.value = const SizedBox.shrink(),
          run: () async {
            for (final suffix in ['', '-navigation']) {
              await File(
                '${root.path}/${config.id}$suffix.html',
              ).writeAsString(config.html);
            }
            // Subscribe before mounting. fullyLive schedules the actual platform
            // frames; no guarded WidgetTester.pump is left pending on a deadline.
            final pending = Future.wait(
              completed.map((c) => c.future),
              eagerError: true,
            );
            host.value = grid();
            // Simulator WebContent sometimes stalls 30-50s before the first
            // navigation of a fresh batch.
            final results = await pending.timeout(const Duration(seconds: 150));
            entry['hostRssAfterBytes'] = ProcessInfo.currentRss;
            for (final result in results) {
              final prep = result.preparation;
              final rendering = result.report['rendering'] as Map;
              expect(result.report['bootAcknowledged'], isTrue);
              expect(rendering['bootCount'], 1);
              expect(rendering['bootTheme'], iosFontProbeTheme);
              expect(rendering['visible'], isTrue);
              expect(prep.documentBound, isTrue);
              if (config.scenario == 'style-src-none') {
                expect(prep.ready, isFalse);
                expect(prep.outcome['reason'], 'style-blocked');
              } else {
                expect(prep.ready, isTrue);
                expect(prep.outcome['reason'], 'loaded');
                if (!config.useScheme || config.scenario == 'font-src-data') {
                  expect(prep.transport, 'data');
                }
                // A deadline/incomplete run must not masquerade as incompatibility.
                if (config.useScheme && prep.transport == 'data') {
                  expect(prep.schemeFailure, 'font-load-failed');
                }
                final samples = rendering['samples'] as List;
                expect(samples, hasLength(iosFontProbeSpecs.length));
                for (final sample in samples.cast<Map>()) {
                  expect(sample['loadedFaces'], isNotEmpty);
                  expect(
                    (sample['loadedFaces'] as List).every(
                      (f) => f['status'] == 'loaded',
                    ),
                    isTrue,
                  );
                  expect(sample['inkPixels'], greaterThan(0));
                }
                expect(samples[0]['pixelHash'], isNot(samples[1]['pixelHash']));
                expect(samples[2]['pixelHash'], isNot(samples[3]['pixelHash']));
                expect(result.report['screenshotBase64'], isNotEmpty);
              }
            }
            if (_count > 1 && config.scenario == 'normal') {
              host.value = grid(closeFirst: true);
              await progress.first.whenDisposed.timeout(
                const Duration(seconds: 10),
              );
              expect(results.first.lease.isActive, isFalse);
              expect(results.last.lease.isActive, isTrue);
              entry['peerClose'] = {
                'closedLeaseInactive': !results.first.lease.isActive,
                'survivorLeaseActive': results.last.lease.isActive,
                'closedOwner': results.first.lease.id,
                'survivorOwner': results.last.lease.id,
              };
              entry['freshOwnedFontAfterClosingFirst'] = await progress.last
                  .observe(
                    'fresh-survivor-font-load',
                    () async => results.last.preparation.transport == 'scheme'
                        ? {
                            ...await loadFreshAppleSurvivorFont(results.last),
                            'transport': 'scheme',
                            'owner': results.last.lease.id,
                            'documentId': results.last.preparation.documentId,
                          }
                        : loadFreshAppleDataSurvivorFont(results.last),
                  );
            }
            // Every route exercises real navigation; the previous owner's guarded
            // SDK source must not execute on the replacement document.
            entry['navigation'] = await progress.last.observe(
              'navigation-ownership',
              () => _navigateAndRejectOldBoot(
                results.last,
                progress.last,
                config.documentUrl(root.path, navigation: true),
              ),
            );
          },
        );
      }
      report['status'] = 'completed';
    },
    skip: !Platform.isIOS,
    timeout: const Timeout(Duration(minutes: 19)),
  );
}

Future<Map<String, Object?>> _navigateAndRejectOldBoot(
  AppleFontProbeResult previous,
  FontProbeViewProgress progress,
  String url,
) async {
  void requireActive() {
    if (!progress.isActive) throw StateError('Navigation observation ended');
  }

  requireActive();
  await previous.controller
      .loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      )
      .timeout(const Duration(seconds: 5));
  requireActive();
  Map? next;
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 5)) {
    final current = await previous.controller.callAsyncJavaScript(
      functionBody: '''
return {href: location.href, documentId: document.__otzariaFontDocumentId,
  bootCount: window.fontProbeBootCount};
''',
    );
    requireActive();
    final value = current?.value;
    if (current?.error == null &&
        value is Map &&
        value['href'] == url &&
        value['documentId'] is String &&
        value['documentId'] != previous.preparation.documentId &&
        value['bootCount'] == 0) {
      next = value;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    requireActive();
  }
  expect(next, isNotNull, reason: 'replacement document did not become ready');
  expect(previous.lease.isActive, isFalse);
  final stale = await previous.controller.evaluateJavascript(
    source: previous.preparation.guardBoot(
      '(window.fontProbeStaleEffect = true, [])',
    ),
  );
  requireActive();
  expect(stale, isA<Map>());
  expect((stale as Map)['booted'], isFalse);
  expect(stale['reason'], 'stale-document');
  final current = await previous.controller.callAsyncJavaScript(
    functionBody: '''
return {documentId: document.__otzariaFontDocumentId,
  bootCount: window.fontProbeBootCount, staleEffect: window.fontProbeStaleEffect === true};
''',
  );
  requireActive();
  expect(current?.error, isNull);
  expect(current?.value, isA<Map>());
  final after = Map<String, dynamic>.from(current!.value as Map);
  expect(after['documentId'], next!['documentId']);
  expect(after['bootCount'], 0);
  expect(after['staleEffect'], isFalse);
  return {
    'requestedUrl': url,
    'observedUrl': next['href'],
    'oldDocumentId': previous.preparation.documentId,
    'oldOwner': previous.preparation.owner,
    'oldLeaseInactive': !previous.lease.isActive,
    'newDocument': after,
    'rejectedBoot': Map<String, dynamic>.from(stale),
  };
}
