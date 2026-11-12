import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';

class _Controller extends Fake implements InAppWebViewController {
  int calls = 0;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    calls++;
    return null;
  }

  @override
  Future<void> pause() async => calls++;

  @override
  Future<void> resume() async => calls++;

  @override
  Future<void> setMemoryUsageTargetLevel(MemoryUsageTargetLevel level) async =>
      calls++;

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async => calls++;
}

class _Host implements PluginInstanceHost {
  bool allowed = true;
  int releases = 0;

  @override
  bool get canDiscard => allowed;

  @override
  void releaseWebView() => releases++;

  @override
  void restoreWebView() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = PluginRuntimeDispatcher.instance;
  const pluginId = 'discard.diagnostics.test';
  const PluginInstanceKey key = (pluginId: pluginId, instanceId: 'page');
  final store = PluginRestoreStateStore.instance;
  final unsaved = PluginUnsavedChangesRegistry.instance;
  late DateTime now;
  late _Controller controller;
  late _Host host;

  setUp(() async {
    await dispatcher.prepareForAppRestart();
    dispatcher.resetVisibilityForTesting();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    now = DateTime.utc(2026, 1, 1);
    dispatcher.clock = () => now;
    dispatcher.discardLimitsOverride = const PluginDiscardLimits(
      maxLiveSuspended: 0,
      maxSuspendedAge: Duration.zero,
    );
    store.remove(key);
    unsaved.removeInstance(key);
    controller = _Controller();
    host = _Host();
    dispatcher.registerController(
      pluginId,
      controller,
      instanceId: key.instanceId,
    );
    dispatcher.registerInstanceHost(pluginId, host, instanceId: key.instanceId);
    // A ready page that is not visible is immediately suspended.
    await dispatcher.onForegroundInstanceReady(
      pluginId,
      instanceId: key.instanceId,
    );
    store.set(key, {'privateDocument': 'DO_NOT_LOG_THIS_STATE'});
    controller.calls = 0;
  });

  tearDown(() async {
    unsaved.removeInstance(key);
    store.remove(key);
    dispatcher.unregisterInstanceHost(pluginId, instanceId: key.instanceId);
    await dispatcher.prepareForAppRestart();
    dispatcher.resetVisibilityForTesting();
    dispatcher.clock = DateTime.now;
    dispatcher.discardLimitsOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  Map<String, Object?> details(Map<String, Object?> snapshot) =>
      (snapshot['instances']! as List<Map<String, Object?>>).single;

  test('reports eligibility and suspension time without controller calls', () {
    now = now.add(const Duration(seconds: 42));
    final snapshot = dispatcher.describeForegroundResources();
    expect(snapshot['live'], 1);
    expect(snapshot['suspended'], 1);
    expect(snapshot['discardCandidates'], 1);
    expect(snapshot['eligible'], 1);
    expect(snapshot['exempt'], 0);
    expect(
      details(snapshot)['suspendedAt'],
      DateTime.utc(2026, 1, 1).toIso8601String(),
    );
    expect(details(snapshot)['restoreAvailable'], true);
    expect(details(snapshot), isNot(contains('firstBlockingReason')));
    expect(controller.calls, 0);
    expect(jsonEncode(snapshot), isNot(contains('DO_NOT_LOG_THIS_STATE')));
  });

  test(
    'the reported blocker is the same guard used by actual eviction',
    () async {
      unsaved.set(key, hasChanges: true, message: 'DO_NOT_LOG_THIS_MESSAGE');
      var snapshot = dispatcher.describeForegroundResources();
      expect(details(snapshot)['firstBlockingReason'], 'unsavedChanges');
      expect(snapshot['firstBlockerCounts'], {'unsavedChanges': 1});
      expect(snapshot['eligible'], 0);
      expect(snapshot['exempt'], 1);
      expect(jsonEncode(snapshot), isNot(contains('DO_NOT_LOG_THIS_MESSAGE')));
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 0);

      unsaved.removeInstance(key);
      now = now.add(const Duration(seconds: 5));
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 1);
      snapshot = dispatcher.describeForegroundResources();
      expect(snapshot['released'], 1);
      expect(snapshot['live'], 0);
      expect(snapshot['eligible'], 0);
      expect(details(snapshot)['lastDiscardedAt'], now.toIso8601String());
    },
  );

  test('missing snapshots and host restrictions remain exemptions', () async {
    store.remove(key);
    expect(
      details(dispatcher.describeForegroundResources())['firstBlockingReason'],
      'noRestoreState',
    );
    await dispatcher.checkDiscard(memoryPressure: true);
    expect(host.releases, 0);

    store.set(key, {});
    host.allowed = false;
    expect(
      details(dispatcher.describeForegroundResources())['firstBlockingReason'],
      'hostDisallowsDiscard',
    );
    await dispatcher.checkDiscard(memoryPressure: true);
    expect(host.releases, 0);
  });

  test(
    'in-flight RPC prevents eviction and releasing it updates diagnostics',
    () async {
      final finish = dispatcher.beginInstanceWork(
        pluginId,
        instanceId: key.instanceId,
      );
      expect(
        details(
          dispatcher.describeForegroundResources(),
        )['firstBlockingReason'],
        'busyRpc',
      );
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 0);
      finish();
      expect(dispatcher.describeForegroundResources()['eligible'], 1);
    },
  );

  test(
    'a visible page is not eligible and background instances are excluded',
    () async {
      dispatcher.setVisiblePluginInstances({key});
      await pumpEventQueue();
      dispatcher.registerController(
        pluginId,
        _Controller(),
        instanceId: PluginInstanceIds.background,
      );
      final snapshot = dispatcher.describeForegroundResources();
      expect(snapshot['registered'], 1);
      expect(snapshot['live'], 1);
      expect(snapshot['discardCandidates'], 0);
      expect(snapshot['eligible'], 0);
    },
  );

  test('idle time and clock changes do not churn context records', () {
    final first = jsonEncode(dispatcher.describeForegroundResources());
    now = now.add(const Duration(hours: 2));
    expect(jsonEncode(dispatcher.describeForegroundResources()), first);
    now = now.subtract(const Duration(days: 2));
    expect(jsonEncode(dispatcher.describeForegroundResources()), first);
    expect(controller.calls, 0);
  });

  test(
    'details are bounded while counts still cover every foreground view',
    () {
      for (var i = 0; i < 110; i++) {
        dispatcher.registerController('extra.$i', _Controller());
      }
      final snapshot = dispatcher.describeForegroundResources();
      expect(snapshot['registered'], 111);
      expect(snapshot['live'], 111);
      expect(snapshot['instances'], hasLength(100));
      expect(snapshot['detailsTruncated'], true);
    },
  );
}
