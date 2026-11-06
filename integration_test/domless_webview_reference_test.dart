import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/plugin_network_permission_mode.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_webview_diagnostics.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:window_manager/window_manager.dart';

import '../tool/perf_probe/domless_runtime/fixture_services.dart';
import '../tool/perf_probe/domless_runtime/domless_process.dart';

const _fixtureJson = String.fromEnvironment('OTZARIA_DOMLESS_FIXTURE');
const _nativeExecutable = String.fromEnvironment('OTZARIA_DOMLESS_EXECUTABLE');
const _nativeEnvironment = String.fromEnvironment(
  'OTZARIA_DOMLESS_ENVIRONMENT',
);
const _native = _nativeExecutable != '';

Future<HttpServer> _documentServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<!doctype html><html><head><meta charset="utf-8"></head><body></body></html>',
    );
    unawaited(request.response.close());
  });
  return server;
}

Future<Map<String, Object?>> _memory([
  List<DomlessProcess> native = const [],
]) async {
  final sample = await sampleProcessTree(
    webViewProcesses: DeveloperDiagnostics.instance.webViewProcessLister,
  );
  return {
    'hostAndWebView':
        sample?.toJson() ??
        {'unavailable': 'No process-tree sampler on this platform'},
    if (native.isNotEmpty)
      'nativeChildren': await Future.wait(
        native.map(
          (process) async => {
            'pid': process.pid,
            'pluginId': process.pluginId,
            ...await process.stats(),
          },
        ),
      ),
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('same pinned store workload in a selected reference backend', (
    tester,
  ) async {
    final fixture = jsonDecode(_fixtureJson) as Map<String, dynamic>;
    if (_native) {
      expect(
        Platform.isWindows || Platform.isLinux || Platform.isMacOS,
        isTrue,
        reason: 'The experiment subprocess is not a mobile runtime package',
      );
      expect(_nativeEnvironment, isNotEmpty);
    }
    final pins = fixture['auditedArchiveSha256'] ?? fixture['archiveSha256'];
    expect(
      pins,
      '2701902bd81baf006b9d73d00f8e125de5a9abdd251ea42e6b6fee52542b8945',
    );
    final diagnostics = DeveloperDiagnostics.instance;
    final originalLister = diagnostics.webViewProcessLister;
    addTearDown(() => diagnostics.webViewProcessLister = originalLister);
    diagnostics.webViewProcessLister = null;
    registerPluginWebViewDiagnostics();
    final profile = await Directory.systemTemp.createTemp(
      'domless_webview_reference_',
    );
    AppPaths.debugOverrideDataRootPath(profile.path);
    final originalResolver = PluginNetworkAccessResolver.instance;
    PluginNetworkAccessResolver.instance = PluginNetworkAccessResolver(
      client: MockClient(
        (_) async => http.Response(
          'https://otzaria.org\n',
          200,
          headers: {'content-type': 'text/plain'},
        ),
      ),
    );
    PluginNetworkPermissionMode.debugSetAppVersion('1.0.0');
    final servers = await Future.wait(
      List.generate(_native ? 0 : 10, (_) => _documentServer()),
    );
    final allNative = <DomlessProcess>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await Future.wait(allNative.map((process) => process.close()));
      await WebViewEnvironmentHolder.disposeForAppRestart();
      await Future.wait(servers.map((server) => server.close(force: true)));
      PluginNetworkAccessResolver.instance = originalResolver;
      PluginNetworkPermissionMode.debugSetAppVersion(null);
      AppPaths.debugOverrideDataRootPath(null);
      try {
        await profile.delete(recursive: true);
      } on FileSystemException {
        /* Native profile handles may close later. */
      }
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (desktop) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1000, 700));
      await windowManager.show();
      await windowManager.focus();
      await const MethodChannel('otzaria/splash').invokeMethod<void>('close');
      final revealDeadline = DateTime.now().add(const Duration(seconds: 10));
      while ((!await windowManager.isVisible() ||
              (Platform.isMacOS && await windowManager.getOpacity() < 0.99)) &&
          DateTime.now().isBefore(revealDeadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(await windowManager.isVisible(), isTrue);
      expect(await windowManager.isMinimized(), isFalse);
      if (Platform.isMacOS) {
        expect(await windowManager.getOpacity(), greaterThanOrEqualTo(0.99));
      }
    }
    final environmentClock = Stopwatch()..start();
    if (!_native) await WebViewEnvironmentHolder.initialize();
    final environmentMs = environmentClock.elapsedMicroseconds / 1000;
    final records = <Map<String, Object?>>[];
    for (final count in [1, 5, 10]) {
      for (var repeat = 0; repeat < 3; repeat++) {
        final baseline = await _memory();
        final services = List.generate(
          count,
          (index) => FixtureServices(
            fixturePlugin(fixture, id: 'fixture.measure.$index'),
            FixtureRegistry(),
            {},
          ),
        );
        final handlers = services
            .map(
              (service) => PluginBridgeHandler(
                service.plugin,
                adapter: service,
                registry: service.registry,
              ),
            )
            .toList();
        final loaded = List.generate(count, (_) => Completer<void>());
        final booting = List.filled(count, false);
        final starts = List.filled(count, 0.0);
        final nativeByIndex = List<DomlessProcess?>.filled(count, null);
        final nativeStarts = <Future<void>>[];
        final clock = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          unawaited(
            services[i].done.future.then((_) {
              starts[i] = clock.elapsedMicroseconds / 1000;
            }),
          );
          if (_native) {
            nativeStarts.add(() async {
              final process = await DomlessProcess.start(
                executable: _nativeExecutable,
                pluginId: services[i].plugin.pluginId,
                rpc: (request, sink, cancellation) async {
                  unawaited(
                    cancellation.whenCancelled.then(
                      (_) => services[i].cancelOutstanding(),
                    ),
                  );
                  return handlers[i].handleRpc([request], eventSink: sink);
                },
              );
              nativeByIndex[i] = process;
              allNative.add(process);
              await process.evaluate(_nativeEnvironment);
              await process.evaluate(pluginBackgroundSdkStubScript);
              for (final source in fixture['scripts'] as List) {
                await process.evaluate(source as String);
              }
              await process.evaluate(
                buildPluginBootScript(
                  nonceJson: jsonEncode(handlers[i].bridgeNonce),
                  payloadJson: jsonEncode({
                    'app': fixtureAppContext,
                    'permissions': withBaselinePermissions(
                      services[i].plugin.manifest.permissions,
                    ),
                  }),
                  rpcTransport: '__otzariaNativeRpc',
                ),
              );
              loaded[i].complete();
            }());
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                for (var i = 0; !_native && i < count; i++)
                  Offstage(
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: InAppWebView(
                        key: ValueKey('$count-$repeat-$i'),
                        webViewEnvironment:
                            WebViewEnvironmentHolder.environment,
                        initialUrlRequest: URLRequest(
                          url: WebUri(
                            'http://127.0.0.1:${servers[i].port}/$count/$repeat/$i',
                          ),
                        ),
                        initialUserScripts: UnmodifiableListView([
                          UserScript(
                            source: pluginBackgroundSdkStubScript,
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_START,
                          ),
                        ]),
                        onWebViewCreated: handlers[i].register,
                        onLoadStop: (controller, _) async {
                          if (booting[i]) return;
                          booting[i] = true;
                          try {
                            await controller.evaluateJavascript(
                              source: 'localStorage.clear();',
                            );
                            for (final source in fixture['scripts'] as List) {
                              await controller.evaluateJavascript(
                                source: source as String,
                              );
                            }
                            await controller.evaluateJavascript(
                              source: buildPluginBootScript(
                                nonceJson: jsonEncode(handlers[i].bridgeNonce),
                                payloadJson: jsonEncode({
                                  'app': fixtureAppContext,
                                  'permissions': withBaselinePermissions(
                                    services[i].plugin.manifest.permissions,
                                  ),
                                }),
                              ),
                            );
                            loaded[i].complete();
                          } catch (error, stack) {
                            loaded[i].completeError(error, stack);
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        final complete = Future.wait([
          ...nativeStarts,
          ...loaded.map((item) => item.future),
          ...services.map((service) => service.done.future),
        ]);
        await complete.timeout(const Duration(seconds: 30));
        final nativeProcesses = nativeByIndex
            .whereType<DomlessProcess>()
            .toList(growable: false);
        expect(nativeProcesses, hasLength(_native ? count : 0));
        for (final service in services) {
          expect(service.notifications.single['tapPayload'], {
            'updates': 1,
            'newPlugins': 0,
          });
          expect(
            service.requests.where(
              (method) => method == 'plugin.backgroundDone',
            ),
            hasLength(1),
          );
        }
        final beforeQuiet = await _memory(nativeProcesses);
        final cpuBefore = await Future.wait(
          nativeProcesses.map((process) => process.cpuSeconds()),
        );
        final quiet = Stopwatch()..start();
        await Future<void>.delayed(const Duration(seconds: 1));
        final cpuAfter = await Future.wait(
          nativeProcesses.map((process) => process.cpuSeconds()),
        );
        final quietSeconds = quiet.elapsedMicroseconds / 1000000;
        final afterQuiet = await _memory(nativeProcesses);
        final record = <String, Object?>{
          'backend': _native
              ? 'QuickJS-NG experiment subprocesses'
              : 'existing WebView, hidden 1x1 fixture hosts',
          'instances': count,
          'repeat': repeat,
          'hostPid': pid,
          'instanceOrder': [
            for (var i = 0; i < count; i++)
              {
                'instanceId':
                    '${_native ? 'native' : 'webview'}:$count:$repeat:$i',
                'instanceIndex': i,
                'pluginId': services[i].plugin.pluginId,
                'nativePid': nativeByIndex[i]?.pid,
              },
          ],
          'startupToBackgroundDoneMs': starts,
          'baseline': baseline,
          'beforeQuiet': beforeQuiet,
          'afterQuiet': afterQuiet,
          'quietSeconds': quietSeconds,
          if (_native)
            'nativeCpuSecondsDuringQuiet': [
              for (var i = 0; i < nativeProcesses.length; i++)
                if (cpuBefore[i] != null && cpuAfter[i] != null)
                  cpuAfter[i]! - cpuBefore[i]!
                else
                  null,
            ],
          'idleCpu': {
            'unavailable':
                'Capture the full process tree with the platform profiler; no polling during quiet',
          },
        };
        records.add(record);
        debugPrint('OTZARIA_DOMLESS_REFERENCE ${jsonEncode(record)}');
        await Future.wait(nativeProcesses.map((process) => process.close()));
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
    binding.reportData = {
      'schemaVersion': 3,
      'hostPid': pid,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'buildMode': kProfileMode
          ? 'profile'
          : (kReleaseMode ? 'release' : 'debug'),
      'fixtureSha256': pins,
      'backend': _native ? 'quickjs-ng' : 'webview',
      'environmentInitMs': environmentMs,
      'comparisonReady': false,
      'scope':
          'Same JS, SDK, host permission gate and service data. Pair native profile measurements and complete platform CPU collection before a savings comparison.',
      'samples': records,
    };
  }, skip: _fixtureJson.isEmpty);
}
