import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/plugin_network_permission_mode.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';

import '../../../tool/perf_probe/domless_runtime/domless_process.dart';
import '../../../tool/perf_probe/domless_runtime/fixture_services.dart';

final _cache = Platform.environment['OTZARIA_DOMLESS_CACHE'];
const _directory = 'tool/perf_probe/domless_runtime';
const _seenKey = 'otzaria_store_bg_seen_ids_v1';
String get _executable =>
    '$_cache/build/${Platform.isWindows ? 'Release/otzaria_domless_probe.exe' : 'otzaria_domless_probe'}';

class _EmptyLimiter extends RateLimiter {
  @override
  bool consume() => false;
}

class _Instance {
  _Instance(this.process, this.handler, this.services, this.startClock);
  final DomlessProcess process;
  final PluginBridgeHandler handler;
  final FixtureServices services;
  final Stopwatch startClock;
}

Future<_Instance> _start({
  String? id,
  FixtureRegistry? registry,
  Map<String, Map<String, dynamic>>? storage,
  PluginLazyActivationService? lazy,
  Object? token,
  bool store = false,
  String? nonce,
  RateLimiter? rateLimiter,
}) async {
  final fixture =
      jsonDecode(await File('$_cache/fixture.json').readAsString()) as Map;
  final plugin = fixturePlugin(Map<String, dynamic>.from(fixture), id: id);
  registry ??= FixtureRegistry();
  final granted = <String>[];
  for (final permission in plugin.manifest.permissions) {
    if (await registry.getPermission(plugin.pluginId, permission) == true) {
      granted.add(permission);
    }
  }
  if (store && !granted.contains(pluginRunOnStartupPermission)) {
    throw StateError('Background startup permission is not granted');
  }
  final services = FixtureServices(plugin, registry, storage ?? {});
  final handler = PluginBridgeHandler(
    plugin,
    adapter: services,
    registry: registry,
    rateLimiter: rateLimiter,
    onWorkStarted: lazy == null
        ? null
        : () => lazy.beginWork(plugin.pluginId, runtimeToken: token),
  );
  final environment = await File('$_directory/environment.js').readAsString();
  final startClock = Stopwatch()..start();
  final process = await DomlessProcess.start(
    executable: _executable,
    pluginId: plugin.pluginId,
    rpc: (request, sink, cancellation) async {
      unawaited(
        cancellation.whenCancelled.then((_) => services.cancelOutstanding()),
      );
      return handler.handleRpc([request], eventSink: sink);
    },
  );
  addTearDown(process.close);
  await process.evaluate(environment);
  await process.evaluate(pluginBackgroundSdkStubScript);
  if (store) {
    for (final source in fixture['scripts'] as List) {
      await process.evaluate(source as String);
    }
  }
  await process.evaluate(
    buildPluginBootScript(
      nonceJson: jsonEncode(nonce ?? handler.bridgeNonce),
      payloadJson: jsonEncode({
        'app': fixtureAppContext,
        'permissions': withBaselinePermissions(granted),
      }),
      rpcTransport: '__otzariaNativeRpc',
    ),
  );
  return _Instance(process, handler, services, startClock);
}

var _resultSequence = 0;
Future<dynamic> _asyncValue(DomlessProcess process, String expression) async {
  final name = '__probeResult${++_resultSequence}';
  await process.evaluate(
    'Promise.resolve($expression).then(value => globalThis.$name = {value}, error => globalThis.$name = {error: String(error)}); void 0;',
  );
  for (var attempt = 0; attempt < 100; attempt++) {
    final result = await process.evaluate('globalThis.$name || null');
    if (result != null) {
      await process.evaluate('delete globalThis.$name');
      return result['value'] ?? result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Async guest result did not complete');
}

Future<dynamic> _call(
  DomlessProcess process,
  String method, [
  Map<String, dynamic> payload = const {},
]) => _asyncValue(
  process,
  'Otzaria.call(${jsonEncode(method)}, ${jsonEncode(payload)})',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = _cache == null
      ? 'Opt in with prepare.py and OTZARIA_DOMLESS_CACHE'
      : false;
  group('bounded native DOM-free experiment', () {
    late PluginNetworkAccessResolver originalResolver;
    setUp(() {
      originalResolver = PluginNetworkAccessResolver.instance;
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
    });
    tearDown(() {
      PluginNetworkAccessResolver.instance = originalResolver;
      PluginNetworkPermissionMode.debugSetAppVersion(null);
    });

    test(
      'unchanged store background streams catalog, reports update, and finishes',
      () async {
        final instance = await _start(store: true);
        await instance.services.done.future.timeout(const Duration(seconds: 5));
        expect(instance.services.notifications.single['tapPayload'], {
          'updates': 1,
          'newPlugins': 0,
        });
        expect(
          await instance.process.evaluate(
            'JSON.parse(localStorage.getItem("$_seenKey"))',
          ),
          ['demo', 'new'],
        );
        expect(
          instance.services.requests.where((r) => r == 'plugin.backgroundDone'),
          hasLength(1),
        );
        expect(instance.process.canFallbackWithoutReplay, isFalse);
        expect((await instance.process.stats())['pendingRpc'], 0);
      },
    );

    test(
      'startup permission is checked before creating a background engine',
      () async {
        final registry = FixtureRegistry()
          ..denied.add('otzaria.plugins_directory:app.run_on_startup');
        await expectLater(
          _start(store: true, registry: registry),
          throwsStateError,
        );
      },
    );

    test(
      'real nonce and permission gate reject before fixture side effects',
      () async {
        final registry = FixtureRegistry();
        final instance = await _start(id: 'fixture.one', registry: registry);
        final raw = await _asyncValue(
          instance.process,
          '__otzariaNativeRpc({method:"notifications.showInApp",payload:{},nonce:"wrong"})',
        );
        expect(raw['error']['code'], 'error.forbidden');
        expect(
          (await _asyncValue(
            instance.process,
            '__otzariaNativeRpc(null)',
          ))['error']['code'],
          'error.invalid_params',
        );
        registry.denied.add('fixture.one:notifications.send');
        expect(
          (await _call(
            instance.process,
            'notifications.showInApp',
          ))['error']['code'],
          'permission_denied',
        );
        expect(
          (await _call(
            instance.process,
            'reader.getCurrentRef',
          ))['error']['code'],
          'permission_denied',
        );
        expect(
          (await _call(instance.process, 'not.aMethod'))['error']['code'],
          'error.unknown_method',
        );
        expect(instance.services.calls, 0);
        registry.denied.clear();
        expect(
          (await _call(instance.process, 'notifications.showInApp'))['success'],
          isTrue,
        );
        registry.denied.add('fixture.one:notifications.send');
        expect(
          (await _call(
            instance.process,
            'notifications.showInApp',
          ))['error']['code'],
          'permission_denied',
        );
        expect(instance.services.notifications, hasLength(1));
      },
    );

    test(
      'network grants, manifest and official allowlist stay in the host gate',
      () async {
        final registry = FixtureRegistry();
        final instance = await _start(registry: registry);
        registry.denied.add('${instance.process.pluginId}:network.access');
        final denied = await _asyncValue(
          instance.process,
          '(async () => { try { for await (const c of Otzaria.call("network.fetchStream",{url:"https://otzaria.org/api/plugins"})) {} } catch (e) { return String(e); } })()',
        );
        expect(denied, contains('permissionMissing'));
        registry.denied.clear();
        final outside = await _asyncValue(
          instance.process,
          '(async () => { try { for await (const c of Otzaria.call("network.fetchStream",{url:"https://example.com"})) {} } catch (e) { return String(e); } })()',
        );
        expect(outside, contains('notAllowlisted'));
        expect(instance.services.networkStarted.isCompleted, isFalse);
      },
    );

    test(
      'separate runtimes and host identity isolate localStorage and RPC storage',
      () async {
        final storage = <String, Map<String, dynamic>>{};
        final registry = FixtureRegistry();
        final a = await _start(
          id: 'fixture.a',
          storage: storage,
          registry: registry,
        );
        final b = await _start(
          id: 'fixture.b',
          storage: storage,
          registry: registry,
        );
        await a.process.evaluate(
          'localStorage.setItem("secret","a"); globalThis.secret = "a"',
        );
        await _call(a.process, 'storage.set', {
          'key': 'secret',
          'value': 'a',
          'pluginId': 'fixture.b',
        });
        expect(
          await b.process.evaluate(
            '[localStorage.getItem("secret"),typeof secret]',
          ),
          [null, 'undefined'],
        );
        expect(
          (await _call(b.process, 'storage.get', {
            'key': 'secret',
            'pluginId': 'fixture.a',
          }))['data'],
          isNull,
        );
        expect(storage.keys, ['fixture.a']);
        expect(registry.identities.toSet(), {'fixture.a', 'fixture.b'});
        final forged = await _asyncValue(
          b.process,
          '__otzariaNativeRpc({method:"storage.get",payload:{key:"secret"},nonce:${jsonEncode(a.handler.bridgeNonce)}})',
        );
        expect(forged['error']['code'], 'error.forbidden');
      },
    );

    test(
      'async replies resolve the right calls without changing work ownership',
      () async {
        final lazy = PluginLazyActivationService.forTesting(
          hasEssentialState: (_) => false,
        );
        const id = 'fixture.async';
        lazy.syncPlugin(id, broadcastTopics: const {}, scheduleStartup: false);
        final token = lazy.attachBackgroundInstance(id);
        final instance = await _start(id: id, lazy: lazy, token: token);
        final first = Completer<dynamic>();
        final second = Completer<dynamic>();
        instance.services.rpcOverride = (_, args) =>
            args['key'] == 'first' ? first.future : second.future;
        await instance.process.evaluate(
          'globalThis.results=[]; Otzaria.call("storage.get",{key:"first"}).then(r=>results.push(r.data)); Otzaria.call("storage.get",{key:"second"}).then(r=>results.push(r.data)); void 0;',
        );
        for (var i = 0; instance.process.activeRpcCount < 2 && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(lazy.isBusy(id), isTrue);
        expect(lazy.canTeardown(id), isFalse);
        second.complete('second');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(lazy.isBusy(id), isTrue);
        first.complete('first');
        expect(
          await _asyncValue(
            instance.process,
            'Promise.all([]).then(()=>results)',
          ),
          ['second', 'first'],
        );
        expect(lazy.isBusy(id), isFalse);
        lazy.onBackgroundInstanceClosed(id, runtimeToken: token);
        lazy.removePlugin(id);
      },
    );

    test(
      'iterator return cancels its pending host stream exactly once',
      () async {
        final instance = await _start();
        instance.services.holdNetwork = true;
        final result = _asyncValue(
          instance.process,
          '(async()=>{for await(const chunk of Otzaria.call("network.fetchStream",{url:"https://otzaria.org/api/plugins"})){break;} return "cancelled";})()',
        );
        await instance.services.cancelled.future.timeout(
          const Duration(seconds: 5),
        );
        expect(await result, 'cancelled');
        expect(instance.services.cancellations, hasLength(1));
        expect((await instance.process.stats())['pendingRpc'], 0);
      },
    );

    test(
      'closing cancels host work and late replies cannot reach a new instance',
      () async {
        final old = await _start(id: 'fixture.reused');
        old.services.holdNetwork = true;
        await old.process.evaluate(
          '(async()=>{try {for await(const chunk of Otzaria.call("network.fetchStream",{url:"https://otzaria.org/api/plugins"})) {}} catch(e) {}})(); void 0;',
        );
        await old.services.networkStarted.future.timeout(
          const Duration(seconds: 5),
        );
        await old.process.close();
        expect(old.services.cancelled.isCompleted, isTrue);
        old.services.releaseNetwork.complete();
        final fresh = await _start(id: 'fixture.reused');
        expect((await fresh.process.stats())['pendingRpc'], 0);
        expect(fresh.services.requests, isEmpty);
        expect(fresh.process.canFallbackWithoutReplay, isTrue);
      },
    );

    test(
      'unsupported browser APIs are absent and local storage has a hard quota',
      () async {
        final instance = await _start();
        expect(
          await instance.process.evaluate(
            '[typeof document,typeof fetch,typeof setTimeout,typeof URL,typeof process,typeof std,typeof os]',
          ),
          List.filled(7, 'undefined'),
        );
        final result = await instance.process.evaluate(
          '(()=>{try {localStorage.setItem("x","x".repeat(65536));} catch(e){return String(e);}})()',
        );
        expect(result, contains('experiment.storage_quota'));
        expect(await instance.process.evaluate('localStorage.length'), 0);
      },
    );

    for (final entry in <String, String>{
      'turn_deadline': 'while(true) {}',
      'job_budget':
          'function again(){Promise.resolve().then(again)}; again(); void 0;',
      'evaluation_exception':
          'globalThis.exhaust = new Uint8Array(32*1024*1024); true;',
    }.entries) {
      test('native resource limit terminates ${entry.key}', () async {
        final instance = await _start();
        final command = instance.process.evaluate(entry.value);
        if (entry.key == 'job_budget') {
          await command;
        } else {
          await expectLater(command, throwsStateError);
        }
        expect(
          await instance.process.failed.timeout(const Duration(seconds: 5)),
          entry.key,
        );
        await instance.process.close();
      });
    }

    test('throttle is retained and stream cancellation stays exempt', () async {
      final instance = await _start(rateLimiter: _EmptyLimiter());
      expect(
        (await _call(
          instance.process,
          'notifications.showInApp',
        ))['error']['code'],
        'error.rate_limited',
      );
      expect(instance.services.notifications, isEmpty);
      final cancelled = await _asyncValue(
        instance.process,
        '__otzariaNativeRpc({method:"network.fetchStream",payload:{__cancelStreamId:"fixture-stream"},nonce:${jsonEncode(instance.handler.bridgeNonce)}})',
      );
      expect(cancelled['success'], isTrue);
      expect(instance.services.cancellations, ['fixture-stream']);
    });

    test('native stack budget fails closed', () async {
      final instance = await _start();
      await expectLater(
        instance.process.evaluate(
          'function recurse(){return 1 + recurse()} recurse();',
        ),
        throwsStateError,
      );
      expect(await instance.process.failed, 'evaluation_exception');
    });

    test('oversized host commands close without an unhandled future', () async {
      final instance = await _start();
      await expectLater(
        instance.process.evaluate(' ' * (1024 * 1024)),
        throwsStateError,
      );
      expect(await instance.process.failed, 'host_input_size');
    });

    for (final abruptExit in [false, true]) {
      test(
        'queued writes settle after ${abruptExit ? 'process exit' : 'guest failure'} and repeated close',
        () async {
          for (var repeat = 0; repeat < 3; repeat++) {
            final rpcStarted = Completer<void>();
            final releaseRpc = Completer<dynamic>();
            late ProbeCancellation cancellation;
            var cancellations = 0;
            final process = await DomlessProcess.start(
              executable: _executable,
              pluginId: 'fixture.failure.$repeat',
              rpc: (_, _, token) {
                cancellation = token;
                unawaited(token.whenCancelled.then((_) => cancellations++));
                rpcStarted.complete();
                return releaseRpc.future;
              },
            );
            addTearDown(process.close);
            await process.evaluate(
              '__otzariaNativeRpc({}).catch(()=>{}); void 0;',
            );
            await rpcStarted.future.timeout(const Duration(seconds: 5));
            Future<bool> outcome(String source) => process
                .evaluate(source)
                .then(
                  (_) => true,
                  onError: (Object error) {
                    expect(error, isA<StateError>());
                    return false;
                  },
                );
            if (abruptExit) {
              // Queue writes before Dart observes exit, after the reader is gone.
              expect(
                Process.killPid(process.pid, ProcessSignal.sigkill),
                isTrue,
              );
            }
            final pending = <Future<bool>>[
              if (!abruptExit) outcome('throw Error("guest failure")'),
              for (var i = 0; i < 100; i++) outcome('/*${'x' * 16000}*/ 42'),
            ];
            Future<void>? closing;
            if (abruptExit) {
              closing = process.close();
            }
            final results = await Future.wait(pending).timeout(
              const Duration(seconds: 5),
            );
            expect(results, contains(false));
            closing ??= process.close();
            expect(identical(closing, process.close()), isTrue);
            await closing.timeout(const Duration(seconds: 6));
            await cancellation.whenCancelled;
            expect(cancellations, 1);
            releaseRpc.complete(null);
            await Future<void>.delayed(Duration.zero);
            expect(process.activeRpcCount, 0);
            await expectLater(process.evaluate('42'), throwsStateError);
          }
        },
      );
    }

    test(
      'lazy callback starts only on an event and respects keepAlive',
      () async {
        const id = 'fixture.lazy';
        final lazy = PluginLazyActivationService.forTesting(
          hasEssentialState: (_) => false,
        )..idleDelayOverride = const Duration(milliseconds: 20);
        final active = Completer<_Instance>();
        final deactivated = Completer<void>();
        Object? token;
        var starts = 0;
        lazy.deliverOverride = (_, _, _) async {};
        lazy.backgroundActivator = (_) async {
          starts++;
          token = lazy.attachBackgroundInstance(id);
          final instance = await _start(id: id, lazy: lazy, token: token);
          lazy.trackIdleTeardown(id);
          await lazy.onBackgroundInstanceReady(id, runtimeToken: token);
          active.complete(instance);
        };
        lazy.backgroundDeactivator = (_) {
          if (!deactivated.isCompleted) deactivated.complete();
        };
        addTearDown(() => lazy.removePlugin(id));
        lazy.syncPlugin(
          id,
          broadcastTopics: const {},
          scheduleStartup: false,
          keepAlive: true,
        );
        expect(starts, 0);
        expect(lazy.queueTargetedEvent(id, 'fixture.trigger', {}), isTrue);
        final instance = await active.future.timeout(
          const Duration(seconds: 5),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(starts, 1);
        expect(deactivated.isCompleted, isFalse);
        lazy.syncPlugin(
          id,
          broadcastTopics: const {},
          scheduleStartup: false,
          keepAlive: false,
        );
        await deactivated.future.timeout(const Duration(seconds: 2));
        await instance.process.close();
        lazy.onBackgroundInstanceClosed(id, runtimeToken: token);
      },
    );

    test('pending RPC and payload budgets reject before unbounded work', () async {
      final instance = await _start();
      final hold = Completer<dynamic>();
      instance.services.rpcOverride = (_, _) => hold.future;
      final result = await instance.process.evaluate(
        '(()=>{let count=0; try {for(let i=0;i<100;i++){__otzariaNativeRpc({method:"storage.get",payload:{},nonce:${jsonEncode(instance.handler.bridgeNonce)}}).catch(()=>{}); count++;}} catch(e){return {count,error:String(e)};}})()',
      );
      expect(result['count'], 64);
      expect(result['error'], contains('pending_rpc_limit'));
      await instance.process.close();
      hold.complete(null);
      final another = await _start();
      expect(
        await another.process.evaluate(
          '(()=>{try{__otzariaNativeRpc({value:"x".repeat(65536)})}catch(e){return String(e)}})()',
        ),
        contains('rpc_size_limit'),
      );
      expect(another.services.calls, 0);
    });

    test('measure the same store workload at 1, 5 and 10 instances', () async {
      final samples = <Map<String, dynamic>>[];
      for (final count in [1, 5, 10]) {
        for (var repeat = 0; repeat < 3; repeat++) {
          final starts = List.filled(count, 0.0);
          final instances = await Future.wait(
            List.generate(count, (index) async {
              final instance = await _start(
                id: 'fixture.measure.$index',
                store: true,
              );
              await instance.services.done.future.timeout(
                const Duration(seconds: 5),
              );
              starts[index] = instance.startClock.elapsedMicroseconds / 1000;
              expect(instance.services.notifications.single['tapPayload'], {
                'updates': 1,
                'newPlugins': 0,
              });
              return instance;
            }),
          );
          final before = await Future.wait(
            instances.map((instance) => instance.process.stats()),
          );
          final cpuBefore = await Future.wait(
            instances.map((instance) => instance.process.cpuSeconds()),
          );
          final quiet = Stopwatch()..start();
          await Future<void>.delayed(const Duration(seconds: 1));
          final cpuAfter = await Future.wait(
            instances.map((instance) => instance.process.cpuSeconds()),
          );
          final quietSeconds = quiet.elapsedMicroseconds / 1000000;
          final after = await Future.wait(
            instances.map((instance) => instance.process.stats()),
          );
          samples.add({
            'instances': count,
            'repeat': repeat,
            'hostPid': pid,
            'instanceOrder': [
              for (var i = 0; i < count; i++)
                {
                  'instanceId': 'native:$count:$repeat:$i',
                  'instanceIndex': i,
                  'pluginId': instances[i].process.pluginId,
                  'nativePid': instances[i].process.pid,
                },
            ],
            'startupToBackgroundDoneMs': starts,
            'before': before,
            'after': after,
            'cpuBefore': cpuBefore,
            'cpuAfter': cpuAfter,
            'quietSeconds': quietSeconds,
            'nativeCpuSecondsDuringQuiet': [
              for (var i = 0; i < count; i++)
                if (cpuBefore[i] != null && cpuAfter[i] != null)
                  cpuAfter[i]! - cpuBefore[i]!
                else
                  null,
            ],
          });
          await Future.wait(
            instances.map((instance) => instance.process.close()),
          );
        }
      }
      await File('$_cache/native-measurements.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 3,
          'hostPid': pid,
          'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'os': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'dartVersion': Platform.version,
          'processors': Platform.numberOfProcessors,
          'scope':
              'Native child processes only; Flutter test host excluded. Cold native instances, warm shared test host/cache. Service fixtures, no application savings comparison.',
          'samples': samples,
        }),
      );
    }, skip: Platform.environment['OTZARIA_DOMLESS_MEASURE'] != '1');
  }, skip: skip);
}
