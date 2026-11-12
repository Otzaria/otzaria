import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';

PluginInstanceKey _k(String id) => (pluginId: 'p', instanceId: id);

final _t0 = DateTime(2026, 10, 21, 12);

PluginDiscardCandidate _c(String id, int minutesAgo, {bool exempt = false}) =>
    PluginDiscardCandidate(
      key: _k(id),
      suspendedAt: _t0.subtract(Duration(minutes: minutesAgo)),
      exempt: exempt,
    );

const _limits = PluginDiscardLimits(
  maxLiveSuspended: 2,
  maxSuspendedAge: Duration(minutes: 30),
);

class _EnabledRepository extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
}

class _RedeliveryController extends Fake implements InAppWebViewController {
  final deliveryStarted = Completer<void>();
  final deliveryReply = Completer<void>();
  int calls = 0;

  @override
  Future<void> setVisible({required bool visible}) async => calls++;

  @override
  Future<void> setAllMediaPlaybackSuspended({required bool suspended}) async =>
      calls++;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    calls++;
    if (source.contains('reader.context_menu_item_clicked')) {
      if (!deliveryStarted.isCompleted) deliveryStarted.complete();
      await deliveryReply.future;
    }
    return null;
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async => calls++;
}

class _DiscardHost implements PluginInstanceHost {
  int releases = 0;

  @override
  bool get canDiscard => true;

  @override
  void releaseWebView() => releases++;

  @override
  void restoreWebView() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('בתוך התקרה ובתוך הגיל — אין פינוי', () {
    expect(
      pickDiscardVictims([_c('a', 1), _c('b', 5)], now: _t0, limits: _limits),
      isEmpty,
    );
  });

  test('מעבר לתקרה — הוותיק ביותר מפונה', () {
    expect(
      pickDiscardVictims(
        [_c('new', 1), _c('old', 10), _c('mid', 5)],
        now: _t0,
        limits: _limits,
      ),
      [_k('old')],
    );
  });

  test('מושהה יותר מהגיל המרבי — מפונה גם בתוך התקרה', () {
    expect(
      pickDiscardVictims([_c('a', 31), _c('b', 1)], now: _t0, limits: _limits),
      [_k('a')],
    );
  });

  test('מוחרג אינו מפונה, אבל נספר בתקרה', () {
    expect(
      pickDiscardVictims(
        [_c('x', 50, exempt: true), _c('y', 20, exempt: true), _c('z', 1)],
        now: _t0,
        limits: _limits,
      ),
      [_k('z')],
    );
  });

  test('לחץ זיכרון — כל מי שמותר, מהוותיק', () {
    expect(
      pickDiscardVictims(
        [_c('a', 1), _c('b', 2, exempt: true), _c('c', 3)],
        now: _t0,
        limits: _limits,
        memoryPressure: true,
      ),
      [_k('c'), _k('a')],
    );
  });

  test('ישן וגם מעבר לתקרה — לא נספר פעמיים', () {
    expect(
      pickDiscardVictims(
        [_c('a', 40), _c('b', 3), _c('c', 2), _c('d', 1)],
        now: _t0,
        limits: _limits,
      ),
      [_k('a'), _k('b')],
    );
  });

  test('מגבלות לפי פלטפורמה', () {
    final windows = PluginDiscardLimits.forPlatform(TargetPlatform.windows);
    expect(windows.maxLiveSuspended, 6);
    expect(windows.maxSuspendedAge, const Duration(minutes: 60));
    final android = PluginDiscardLimits.forPlatform(TargetPlatform.android);
    expect(android.maxLiveSuspended, 2);
    expect(android.maxSuspendedAge, const Duration(minutes: 15));
    final mac = PluginDiscardLimits.forPlatform(TargetPlatform.macOS);
    expect(mac.maxLiveSuspended, 3);
    expect(mac.maxSuspendedAge, const Duration(minutes: 30));
  });

  test(
    'fresh redelivery blocks discard but expired backups do not pin the host',
    () async {
      final dispatcher = PluginRuntimeDispatcher.instance;
      final store = PluginRestoreStateStore.instance;
      const pluginId = 'discard.redelivery.test';
      const PluginInstanceKey key = (pluginId: pluginId, instanceId: 'page');
      const savedState = {'schemaVersion': 2, 'selection': 42};
      final previousClock = dispatcher.clock;
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final controller = _RedeliveryController();
      final host = _DiscardHost();
      var now = _t0;
      await dispatcher.prepareForAppRestart();
      dispatcher.resetVisibilityForTesting();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      dispatcher.clock = () => now;
      dispatcher.repositoryForTesting = _EnabledRepository();
      store.remove(key);
      addTearDown(() async {
        if (!controller.deliveryReply.isCompleted) {
          controller.deliveryReply.complete();
        }
        await pumpEventQueue();
        dispatcher.unregisterInstanceHost(pluginId, instanceId: key.instanceId);
        await dispatcher.prepareForAppRestart();
        dispatcher.resetVisibilityForTesting();
        dispatcher.clock = previousClock;
        dispatcher.repositoryForTesting = PluginRegistryRepository();
        debugDefaultTargetPlatformOverride = previousPlatform;
        store.remove(key);
      });
      dispatcher.registerController(
        pluginId,
        controller,
        instanceId: key.instanceId,
      );
      dispatcher.registerInstanceHost(
        pluginId,
        host,
        instanceId: key.instanceId,
      );
      store.set(key, savedState);
      dispatcher.setVisiblePluginInstances({key});
      await dispatcher.onForegroundInstanceReady(
        pluginId,
        instanceId: key.instanceId,
      );
      await pumpEventQueue();
      dispatcher.setVisiblePluginInstances({});
      await pumpEventQueue();

      final delivery = dispatcher.dispatchEventToPlugin(
        pluginId,
        'reader.context_menu_item_clicked',
        const {'id': 'action'},
        instanceId: key.instanceId,
      );
      await controller.deliveryStarted.future;
      // A visible recipient needs no hidden-event grace period. Hide it only
      // after delivery completes, leaving the redelivery backup as the guard.
      dispatcher.setVisiblePluginInstances({key});
      controller.deliveryReply.complete();
      await delivery;
      await pumpEventQueue();
      dispatcher.setVisiblePluginInstances({});
      await pumpEventQueue();

      Map<String, Object?> details() =>
          (dispatcher.describeForegroundResources()['instances']!
                  as List<Map<String, Object?>>)
              .single;
      expect(details()['firstBlockingReason'], 'pendingRedelivery');
      expect(details()['discardEligible'], false);
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 0);

      final callsBeforeDiagnostics = controller.calls;
      now = _t0.add(const Duration(seconds: 31));
      expect(details()['discardEligible'], true);
      expect(details()['firstBlockingReason'], isNull);
      expect(host.releases, 0);
      expect(controller.calls, callsBeforeDiagnostics);
      // Reading diagnostics must not prune backups, even after they expire.
      now = _t0;
      expect(details()['firstBlockingReason'], 'pendingRedelivery');

      now = _t0.add(const Duration(seconds: 31));
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 1);
      expect(store.stateOf(key), savedState);
    },
  );
}
