import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';

import '../../../integration_test/support/ios_font_probe.dart';
import '../../../integration_test/support/ios_font_probe_case.dart';
import '../../../integration_test/support/ios_font_probe_report.dart';
import '../../../integration_test/support/macos_font_probe.dart';

void main() {
  test(
    'startup checkpoint binds the native process and build generation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        expect(request.uri.path, '/checkpoint');
        expect(request.headers.value('X-Apple-Quiet-Token'), 'token');
        received.complete(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.write('{}');
        await request.response.close();
      });
      await HttpOverrides.runWithHttpOverrides(
        () => notifyIosFontProbeStarted(
          coordinator: 'http://127.0.0.1:${server.port}',
          token: 'token',
          generation: 'fresh-generation',
          nativeFork: 'native-pin',
          firstFrameRasterized: true,
        ),
        _LoopbackHttpOverrides(),
      );
      final body = await received.future.timeout(const Duration(seconds: 2));
      expect(body['hostPid'], pid);
      expect(body['hostExecutable'], Platform.resolvedExecutable);
      expect(body['appBootToken'], startsWith('$pid-'));
      expect(body['runId'], 'fresh-generation');
      expect(body['nativeFork'], 'native-pin');
      expect(body['firstFrameRasterized'], isTrue);
    },
  );

  test(
    'startup cannot be certified before the first rasterized frame',
    () async {
      await expectLater(
        notifyIosFontProbeStarted(
          coordinator: 'not-a-network-url',
          token: 'token',
          generation: 'generation',
          nativeFork: 'pin',
          firstFrameRasterized: false,
        ),
        throwsStateError,
      );
    },
  );

  test('a rejected startup checkpoint cannot be ignored', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });
    await expectLater(
      HttpOverrides.runWithHttpOverrides(
        () => notifyIosFontProbeStarted(
          coordinator: 'http://127.0.0.1:${server.port}',
          token: 'wrong',
          generation: 'generation',
          nativeFork: 'pin',
          firstFrameRasterized: true,
        ),
        _LoopbackHttpOverrides(),
      ),
      throwsStateError,
    );
  });

  test('all eighteen cases retain default-off production policy', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final cases = iosFontProbeCases.toList();
    expect(cases, hasLength(18));
    expect(cases.map((c) => c.id).toSet(), hasLength(18));
    expect(pluginMacFontSchemeEnabled, isFalse);
    final production = buildPluginContentBlockers(
      pluginId: iosFontProbePluginId,
      policy: PluginNetworkPolicy.none,
      fileServerPort: 1,
    ).map((b) => b.toMap()).toList();
    expect(production, hasLength(13));
    expect(pluginAssetSchemeEnabled, Platform.isMacOS);
    // The real host's dart:io policy is independent of the widget override.
    expect(
      (production[4]['trigger'] as Map)['url-filter'],
      pluginAssetSchemeEnabled
          ? r'^otzaria-plugin://ios\.font\.probe/'
          : '^file:',
    );
    final baseSettings = buildPluginTabWebViewSettings(isDevelopment: false);
    for (final config in cases) {
      final policy = config.policyReport;
      final rules = config.blockers.map((b) => b.toMap()).toList();
      expect(rules.take(production.length).toList(), production);
      expect(rules.length, production.length + (config.route.lab ? 1 : 0));
      if (config.route.lab) {
        expect(rules.last, {
          'trigger': {
            'url-filter': r'^otzaria-plugin://ios\.font\.probe/',
            'url-filter-is-case-sensitive': true,
          },
          'action': {'type': 'ignore-previous-rules'},
        });
      }
      expect(config.settings.allowFileAccessFromFileURLs, isFalse);
      expect(config.settings.allowUniversalAccessFromFileURLs, isFalse);
      expect(config.settings.allowingReadAccessTo, isNull);
      expect(config.settings.useShouldOverrideUrlLoading, isTrue);
      expect(config.settings.cacheEnabled, baseSettings.cacheEnabled);
      expect(config.settings.incognito, isTrue);
      expect(
        config.settings.resourceCustomSchemes,
        config.registersScheme ? ['otzaria-plugin'] : isEmpty,
      );
      expect(
        policy['schemeRegistration'],
        config.registersScheme ? 'experiment-added' : 'production',
      );
      final original = config.documentUrl('/tmp/a path');
      final replacement = config.documentUrl('/tmp/a path', navigation: true);
      expect(
        Uri.parse(original).scheme,
        config.route.file ? 'file' : 'otzaria-plugin',
      );
      expect(original.endsWith('/${config.id}.html'), isTrue);
      expect(replacement, original.replaceFirst('.html', '-navigation.html'));
      expect(config.html, contains('content="${config.csp}"'));
    }
  });

  test('CSP controls isolate font denial and complete style denial', () {
    for (final route in IosFontProbeRoute.values) {
      for (final scheme in [false, true]) {
        final normal = IosFontProbeCase(route, 'normal', scheme);
        expect(
          IosFontProbeCase(route, 'font-src-data', scheme).csp,
          '${normal.csp}; font-src data:',
        );
        expect(
          IosFontProbeCase(route, 'style-src-none', scheme).csp,
          "${normal.csp}; style-src 'none'",
        );
      }
    }
  });

  test('case completes only after disposal', () async {
    final view = FontProbeViewProgress(0)..mounted();
    final entry = <String, Object?>{}, report = <String, Object?>{};
    await runIosFontProbeCase(
      entry: entry,
      report: report,
      progress: [view],
      run: () async => view.complete(),
      unmount: view.dispose,
    );
    expect(entry['status'], 'completed');
    expect(entry['cleanupStatus'], 'completed');
    expect(view.report['disposed'], isTrue);
  });

  test('original failure and stack survive failed cleanup', () async {
    final view = FontProbeViewProgress(0)..mounted();
    final original = StateError('first native failure');
    final stack = StackTrace.fromString('native-original-stack');
    final entry = <String, Object?>{}, report = <String, Object?>{};
    try {
      await runIosFontProbeCase(
        entry: entry,
        report: report,
        progress: [view],
        run: () async => Error.throwWithStackTrace(original, stack),
        unmount: () => throw StateError('cleanup failure'),
      );
      fail('the original native failure must escape');
    } catch (error, actualStack) {
      expect(error, same(original));
      expect(actualStack.toString(), stack.toString());
    }
    expect(entry['error'], contains('first native failure'));
    expect(entry['cleanupError'], contains('cleanup failure'));
    expect(entry['cleanupStatus'], 'failed');
    expect(report['status'], 'failed');
    expect((view.report['failureSnapshot'] as Map)['status'], 'not-registered');
    view.dispose();
  });

  test(
    'native failure survives a disposal deadline and a late reply',
    () async {
      final view = FontProbeViewProgress(0)..mounted();
      final response = Completer<int>();
      final entry = <String, Object?>{}, report = <String, Object?>{};
      await expectLater(
        runIosFontProbeCase(
          entry: entry,
          report: report,
          progress: [view],
          run: () => view.observe(
            'rendering',
            () => response.future,
            timeout: const Duration(milliseconds: 2),
          ),
          unmount: () {},
          cleanupTimeout: const Duration(milliseconds: 2),
        ),
        throwsA(
          isA<TimeoutException>().having(
            (e) => e.message,
            'first error',
            contains('rendering'),
          ),
        ),
      );
      response.complete(1);
      await pumpEventQueue();
      expect(entry['status'], 'failed');
      expect(entry['cleanupStatus'], 'failed');
      expect(
        (view.report['operations'] as List).single['lateResponse'],
        isTrue,
      );
      view.dispose();
    },
  );

  test('late failure cannot turn into a completed case', () async {
    final view = FontProbeViewProgress(0)..mounted();
    final entry = <String, Object?>{}, report = <String, Object?>{};
    await expectLater(
      runIosFontProbeCase(
        entry: entry,
        report: report,
        progress: [view],
        run: () async {
          view.complete();
          view.fail(StateError('late native error'), StackTrace.current);
        },
        unmount: view.dispose,
      ),
      throwsStateError,
    );
    expect(report['status'], 'failed');
    expect(entry['status'], 'failed');
  });

  test(
    'failure snapshots precede disposal and retain diagnostics failure',
    () async {
      final view = FontProbeViewProgress(0)..mounted();
      var capturedBeforeDisposal = false;
      view.registerFailureSnapshot(() async {
        capturedBeforeDisposal = view.report['disposed'] != true;
        throw StateError('snapshot failed');
      });
      final original = StateError('native error');
      await expectLater(
        runIosFontProbeCase(
          entry: {},
          report: {},
          progress: [view],
          run: () async => throw original,
          unmount: view.dispose,
        ),
        throwsA(same(original)),
      );
      expect(capturedBeforeDisposal, isTrue);
      expect((view.report['failureSnapshot'] as Map)['status'], 'failed');
    },
  );

  group('framework artifact writer', () {
    late Directory output;
    setUp(
      () async => output = await Directory.systemTemp.createTemp(
        'ios-font-report-test-',
      ),
    );
    tearDown(() async => output.delete(recursive: true));

    Map<String, dynamic> data({
      String id = 'case',
      String? encoded,
      bool duplicate = false,
    }) => {
      'iosFontProbe': {
        'cases': [
          {
            'id': id,
            'views': [
              for (var i = 0; i < (duplicate ? 2 : 1); i++)
                {
                  'index': 0,
                  'screenshotBase64': encoded ?? base64Encode([1, 2, 3]),
                },
            ],
          },
        ],
      },
    };

    test(
      'failed framework verdict remains failed after successful extraction',
      () async {
        final original = data();
        final response = Response.someTestsFailed([
          Failure('probe', 'native failed'),
        ], data: original);
        final raw = response.toJson();
        await writeIosFontProbeReport(output, response);
        expect(
          await File('${output.path}/framework-response.json').readAsString(),
          raw,
        );
        final report = jsonDecode(
          await File('${output.path}/report.json').readAsString(),
        );
        expect(report['framework']['allTestsPassed'], isFalse);
        expect(report['framework']['failures'], isNotEmpty);
        expect(await File('${output.path}/case-0.png').readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect(jsonEncode(original), contains('screenshotBase64'));
        expect(jsonEncode(report['data']), isNot(contains('screenshotBase64')));
      },
    );

    for (final corrupt in ['malformed', 'unsafe-name', 'duplicate']) {
      test(
        '$corrupt preserves raw and partial evidence without a final report',
        () async {
          final response = Response.allTestsPassed(
            data: data(
              id: corrupt == 'unsafe-name' ? '../escape' : 'case',
              encoded: corrupt == 'malformed' ? 'not base64!' : null,
              duplicate: corrupt == 'duplicate',
            ),
          );
          await expectLater(
            writeIosFontProbeReport(output, response),
            throwsFormatException,
          );
          expect(
            await File('${output.path}/framework-response.json').readAsString(),
            response.toJson(),
          );
          expect(
            await File('${output.path}/report.partial.json').exists(),
            isTrue,
          );
          expect(await File('${output.path}/report.json').exists(), isFalse);
        },
      );
    }
  });
}

class _LoopbackHttpOverrides extends HttpOverrides {}
