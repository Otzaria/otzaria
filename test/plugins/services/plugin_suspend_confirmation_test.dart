import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';

class _Repo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

class _Controller extends Fake implements InAppWebViewController {
  final calls = <String>[];
  final scripts = <String>[];
  Completer<void>? pauseGate;
  Completer<void>? resumeGate;
  Completer<void>? lowMemoryGate;
  Completer<void>? eventGate;
  Completer<void>? reloadGate;
  Completer<void>? deliveryGate;
  Object? deliveryError;
  String? heldTopic;
  Object? deliveryValue = true;
  bool rejectPause = false;
  bool rejectResume = false;
  bool cancelPauseOnResume = false;

  @override
  Future<void> pause() async {
    calls.add('pause');
    await pauseGate?.future;
    if (rejectPause) throw StateError('suspend refused');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    if (cancelPauseOnResume && pauseGate?.isCompleted == false) {
      pauseGate!.completeError(StateError('suspend cancelled'));
      pauseGate = null;
    }
    await resumeGate?.future;
    if (rejectResume) throw StateError('resume failed');
  }

  @override
  Future<void> setVisible({required bool visible}) async =>
      calls.add('visible:$visible');

  @override
  Future<void> setAllMediaPlaybackSuspended({required bool suspended}) async =>
      calls.add('media:$suspended');

  @override
  Future<void> setMemoryUsageTargetLevel(MemoryUsageTargetLevel level) async {
    calls.add('memory:${level.name()}');
    if (level == MemoryUsageTargetLevel.LOW) await lowMemoryGate?.future;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    if (heldTopic != null && source.contains(heldTopic!)) {
      await eventGate?.future;
    }
    return null;
  }

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const <String, dynamic>{},
    ContentWorld? contentWorld,
  }) async {
    await deliveryGate?.future;
    if (deliveryError != null) throw deliveryError!;
    return CallAsyncJavaScriptResult(value: deliveryValue);
  }

  @override
  Future<void> reload() async {
    calls.add('reload');
    await reloadGate?.future;
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async {}
}

class _Host implements PluginInstanceHost {
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
  final dispatcher = PluginRuntimeDispatcher.instance;
  final store = PluginRestoreStateStore.instance;
  const pluginId = 'suspend.confirmation.test';
  const PluginInstanceKey key = (pluginId: pluginId, instanceId: 'a');
  const PluginInstanceKey other = (pluginId: pluginId, instanceId: 'b');
  final controllers = <_Controller>[];

  void clearStore() {
    store.remove(key);
    store.remove(other);
    PluginUnsavedChangesRegistry.instance.removeInstance(key);
    for (var i = 0; i < 80; i++) {
      store.remove((pluginId: 'other.$i', instanceId: 'page'));
    }
  }

  Map<String, Object?> details([PluginInstanceKey target = key]) =>
      (dispatcher.describeForegroundResources()['instances']!
              as List<Map<String, Object?>>)
          .singleWhere((entry) => entry['instanceId'] == target.instanceId);

  Future<_Controller> visible({
    PluginInstanceKey target = key,
    int viewId = 0,
  }) async {
    final controller = _Controller();
    controllers.add(controller);
    dispatcher.registerController(
      pluginId,
      controller,
      instanceId: target.instanceId,
      viewId: viewId,
    );
    dispatcher.setVisiblePluginInstances({target}, viewId: viewId);
    await dispatcher.onForegroundInstanceReady(
      pluginId,
      instanceId: target.instanceId,
    );
    await pumpEventQueue();
    controller.calls.clear();
    controller.scripts.clear();
    return controller;
  }

  _Controller visibleInFakeAsync(FakeAsync async) {
    // Future completion is scheduled in its creation zone, so both lifecycle
    // queues must be created under the clock that drives this test.
    dispatcher.resetVisibilityForTesting();
    final controller = _Controller();
    controllers.add(controller);
    dispatcher.registerController(
      pluginId,
      controller,
      instanceId: 'a',
      viewId: 0,
    );
    dispatcher.setVisiblePluginInstances({key});
    var ready = false;
    unawaited(
      dispatcher.onForegroundInstanceReady(pluginId, instanceId: 'a').then((_) {
        ready = true;
      }),
    );
    async.flushMicrotasks();
    expect(
      ready,
      true,
      reason: 'The fixture must finish boot in its fake zone',
    );
    expect(details()['suspensionState'], 'active');
    controller.calls.clear();
    controller.scripts.clear();
    return controller;
  }

  setUp(() async {
    await dispatcher.prepareForAppRestart();
    dispatcher.resetVisibilityForTesting();
    dispatcher.repositoryForTesting = _Repo();
    dispatcher.discardLimitsOverride = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    clearStore();
  });

  tearDown(() async {
    for (final controller in controllers) {
      if (controller.pauseGate?.isCompleted == false) {
        controller.pauseGate!.complete();
      }
      if (controller.resumeGate?.isCompleted == false) {
        controller.resumeGate!.complete();
      }
      if (controller.lowMemoryGate?.isCompleted == false) {
        controller.lowMemoryGate!.complete();
      }
      if (controller.eventGate?.isCompleted == false) {
        controller.eventGate!.complete();
      }
      if (controller.deliveryGate?.isCompleted == false) {
        controller.deliveryGate!.complete();
      }
      if (controller.reloadGate?.isCompleted == false) {
        controller.reloadGate!.complete();
      }
    }
    controllers.clear();
    await dispatcher.prepareForAppRestart();
    await pumpEventQueue();
    dispatcher.resetVisibilityForTesting();
    dispatcher.discardLimitsOverride = null;
    dispatcher.repositoryForTesting = PluginRegistryRepository();
    clearStore();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Windows does not confirm suspension before native completion',
    () async {
      final controller = await visible();
      controller.pauseGate = Completer<void>();
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(controller.calls, contains('pause'));
      expect(details()['suspensionState'], 'suspendRequested');
      expect(details()['suspended'], false);
      expect(dispatcher.describeForegroundResources()['suspendRequested'], 1);

      controller.pauseGate!.complete();
      await pumpEventQueue();
      expect(details()['suspensionState'], 'suspendedConfirmed');
      expect(details()['suspended'], true);
      expect(details()['suspendConfirmed'], 1);
    },
  );

  test(
    'native refusal remains hidden and queues events without claiming success',
    () async {
      final controller = await visible();
      controller.rejectPause = true;
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(details()['suspensionState'], 'failed');
      expect(details()['hidden'], true);
      expect(details()['suspended'], false);
      expect(details()['suspendFailures'], 1);
      controller.scripts.clear();
      await dispatcher.dispatchEvent('theme.changed', {'mode': 'dark'});
      expect(controller.scripts, isEmpty);

      dispatcher.setVisiblePluginInstances({key});
      await pumpEventQueue();
      expect(details()['suspensionState'], 'active');
      expect(
        controller.scripts.any((script) => script.contains('theme.changed')),
        true,
      );
      expect(details()['lastResumeMicros'], greaterThanOrEqualTo(0));
    },
  );

  test('returning to a tab interrupts a pending native suspend', () async {
    final controller = await visible();
    controller.pauseGate = Completer<void>();
    controller.cancelPauseOnResume = true;
    dispatcher.setVisiblePluginInstances(const {});
    await pumpEventQueue();
    dispatcher.setVisiblePluginInstances({key});
    await pumpEventQueue();
    expect(details()['suspensionState'], 'active');
    expect(controller.calls, contains('resume'));
    expect(details()['suspendFailures'], 0);
  });

  test('hide, show, hide while suspension is pending ends suspended', () async {
    final controller = await visible();
    controller.pauseGate = Completer<void>();
    controller.cancelPauseOnResume = true;
    dispatcher.setVisiblePluginInstances(const {});
    await pumpEventQueue();
    dispatcher.setVisiblePluginInstances({key});
    dispatcher.setVisiblePluginInstances(const {});
    await pumpEventQueue();
    expect(details()['suspensionState'], 'suspendedConfirmed');
    expect(controller.calls.where((call) => call == 'pause'), hasLength(2));
  });

  test(
    'returning during memory trimming does not start a stale suspend',
    () async {
      final controller = await visible();
      controller.lowMemoryGate = Completer<void>();
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      dispatcher.setVisiblePluginInstances({key});
      controller.lowMemoryGate!.complete();
      await pumpEventQueue();
      expect(controller.calls, isNot(contains('pause')));
      expect(details()['suspensionState'], 'active');
    },
  );

  test(
    'late pause completion cannot suspend a replacement controller',
    () async {
      final old = await visible();
      old.pauseGate = Completer<void>();
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      final replacement = _Controller();
      controllers.add(replacement);
      dispatcher.registerController(pluginId, replacement, instanceId: 'a');
      dispatcher.setVisiblePluginInstances({key});
      final ready = dispatcher.onForegroundInstanceReady(
        pluginId,
        instanceId: 'a',
      );
      old.pauseGate!.complete();
      await ready;
      await pumpEventQueue();
      expect(details()['suspensionState'], 'active');
      expect(replacement.calls, isNot(contains('pause')));
      expect(details()['suspendConfirmed'], 0);
    },
  );

  test(
    'navigation cancels a pending pause before the new page boots',
    () async {
      final controller = await visible();
      controller.pauseGate = Completer<void>();
      controller.resumeGate = Completer<void>();
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(controller.calls, contains('pause'));

      dispatcher.resetEventOptions(pluginId, instanceId: 'a');
      await pumpEventQueue();
      expect(controller.calls, contains('resume'));
      expect(details()['suspensionState'], 'resumeRequested');
      controller.pauseGate!.complete();
      await pumpEventQueue();
      expect(details()['suspendConfirmed'], 0);

      dispatcher.setVisiblePluginInstances({key});
      final ready = dispatcher.onForegroundInstanceReady(
        pluginId,
        instanceId: 'a',
      );
      controller.resumeGate!.complete();
      await ready;
      await pumpEventQueue();
      expect(details()['suspensionState'], 'active');
      expect(details()['suspendConfirmed'], 0);
    },
  );

  test(
    'a page generation change during LOW prevents stale native pause',
    () async {
      final controller = await visible();
      controller.lowMemoryGate = Completer<void>();
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      dispatcher.resetEventOptions(pluginId, instanceId: 'a');
      dispatcher.setVisiblePluginInstances({key});
      controller.lowMemoryGate!.complete();
      await dispatcher.onForegroundInstanceReady(pluginId, instanceId: 'a');
      await pumpEventQueue();
      expect(controller.calls, isNot(contains('pause')));
      expect(details()['suspensionState'], 'active');
    },
  );

  test('failed resume retains queued state until a successful retry', () async {
    final controller = await visible();
    dispatcher.setVisiblePluginInstances(const {});
    await pumpEventQueue();
    await dispatcher.dispatchEvent('theme.changed', {'mode': 'dark'});
    controller.rejectResume = true;
    controller.scripts.clear();
    dispatcher.setVisiblePluginInstances({key});
    await pumpEventQueue();
    expect(details()['suspensionState'], 'failed');
    expect(controller.scripts, isEmpty);
    controller.rejectResume = false;
    dispatcher.setWindowMinimized(true);
    dispatcher.setWindowMinimized(false);
    await pumpEventQueue();
    expect(details()['suspensionState'], 'active');
    expect(
      controller.scripts.any((script) => script.contains('theme.changed')),
      true,
    );
  });

  test(
    'a missing native reply times out without permanently blocking lifecycle',
    () {
      fakeAsync((async) {
        final controller = visibleInFakeAsync(async);
        final gate = Completer<void>();
        controller.pauseGate = gate;
        try {
          dispatcher.setVisiblePluginInstances(const {});
          async.flushMicrotasks();
          expect(details()['suspensionState'], 'suspendRequested');
          async.elapse(const Duration(seconds: 6));
          async.flushMicrotasks();
          expect(details()['suspensionState'], 'failed');
          expect(gate.isCompleted, false);
          gate.complete();
          async.flushMicrotasks();
          expect(details()['suspensionState'], 'failed');
          dispatcher.setVisiblePluginInstances({key});
          async.flushMicrotasks();
          expect(details()['suspensionState'], 'active');
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          async.flushMicrotasks();
          dispatcher.resetVisibilityForTesting();
        }
      });
    },
  );

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    test(
      '$platform reports hidden without claiming that JavaScript is frozen',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final controller = await visible();
        dispatcher.setVisiblePluginInstances(const {});
        await pumpEventQueue();
        expect(details()['suspensionState'], 'hidden');
        expect(details()['suspended'], false);
        expect(
          controller.scripts.any(
            (script) => script.contains('plugin.suspended'),
          ),
          true,
        );
        if (platform == TargetPlatform.android) {
          expect(controller.calls, ['pause']);
        }
      },
    );
  }

  test('a stalled Linux event cannot block later lifecycle operations', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    fakeAsync((async) {
      final controller = visibleInFakeAsync(async);
      dispatcher.setVisiblePluginInstances(const {});
      async.flushMicrotasks();
      expect(details()['suspensionState'], 'hidden');
      controller.calls.clear();
      const topic = 'qa.stalled.targeted';
      final gate = Completer<void>();
      controller
        ..eventGate = gate
        ..heldTopic = topic;
      var deliveryFinished = false;
      try {
        unawaited(
          dispatcher
              .dispatchEventToPlugin(pluginId, topic, const {}, instanceId: 'a')
              .then((_) {
                deliveryFinished = true;
              }),
        );
        async.flushMicrotasks();
        expect(
          controller.scripts.any((source) => source.contains(topic)),
          true,
        );
        expect(details()['suspensionState'], 'active');
        dispatcher.setVisiblePluginInstances({key});
        async.flushMicrotasks();
        dispatcher.setVisiblePluginInstances(const {});
        async.flushMicrotasks();
        expect(deliveryFinished, false);
        expect(controller.calls, isNot(contains('visible:false')));

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(deliveryFinished, true);
        expect(gate.isCompleted, false);
        expect(details()['suspensionState'], 'hidden');
        expect(controller.calls, contains('visible:false'));
        gate.complete();
        async.flushMicrotasks();
        expect(details()['suspensionState'], 'hidden');
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        async.flushMicrotasks();
        dispatcher.resetVisibilityForTesting();
      }
    });
  });

  Future<void> recoveryCommand() => dispatcher.dispatchEventToPlugin(
    pluginId,
    'qa.recovery.targeted',
    const {'requestId': 'recovery-test'},
    instanceId: 'a',
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final outcome in ['no-page-world', 'no-bridge']) {
      for (final protection in ['missing', 'outdated', 'unsaved']) {
        test('${platform.name} keeps $protection state after $outcome', () {
          debugDefaultTargetPlatformOverride = platform;
          fakeAsync((async) {
            final controller = visibleInFakeAsync(async);
            try {
              dispatcher.setVisiblePluginInstances(const {});
              async.flushMicrotasks();
              controller.deliveryValue = outcome;
              if (protection != 'missing') {
                store.set(key, {'schemaVersion': 3, 'draft': 'saved draft'});
              }
              if (protection == 'outdated') {
                expect(
                  () => store.set(
                    key,
                    List.filled(
                      PluginRestoreStateStore.maxStateBytes,
                      'x',
                    ).join(),
                  ),
                  throwsArgumentError,
                );
              }
              final unsaved = PluginUnsavedChangesRegistry.instance;
              if (protection == 'unsaved') {
                unsaved.set(key, hasChanges: true, message: 'live draft');
              }
              final before = store.jsonOf(key);
              var finished = false;
              unawaited(recoveryCommand().then((_) => finished = true));
              async.flushMicrotasks();

              expect(finished, true);
              expect(controller.calls, isNot(contains('reload')));
              expect(
                dispatcher.controllerOf(pluginId, instanceId: 'a'),
                same(controller),
              );
              expect(details()['suspensionState'], 'active');
              expect(store.jsonOf(key), before);
              expect(unsaved.hasUnsavedChanges(key), protection == 'unsaved');
              expect(
                store.canDiscard(key),
                protection == 'unsaved',
              );
              expect(
                dispatcher.takeBootRestore(
                  pluginId,
                  instanceId: 'a',
                  firstBoot: true,
                )?['reason'],
                isNot('reloaded'),
              );
            } finally {
              async.flushMicrotasks();
              dispatcher.resetVisibilityForTesting();
            }
          });
        });
      }

      test(
        '${platform.name} pins current restore state across $outcome reload',
        () {
          debugDefaultTargetPlatformOverride = platform;
          fakeAsync((async) {
            final controller = visibleInFakeAsync(async);
            const snapshot = {
              'schemaVersion': 3,
              'revision': 7,
              'draft': 'saved',
            };
            try {
              dispatcher.setVisiblePluginInstances(const {});
              async.flushMicrotasks();
              store.set(key, snapshot);
              controller.deliveryValue = outcome;
              var finished = false;
              unawaited(recoveryCommand().then((_) => finished = true));
              async.flushMicrotasks();

              expect(finished, true);
              expect(
                controller.calls.where((call) => call == 'reload'),
                hasLength(1),
              );
              expect(details()['suspensionState'], 'hidden');
              for (var i = 0; i < 80; i++) {
                store.set(
                  (pluginId: 'other.$i', instanceId: 'page'),
                  {'value': i},
                );
              }
              expect(store.stateOf(key), snapshot);
              expect(
                dispatcher.takeBootRestore(
                  pluginId,
                  instanceId: 'a',
                  firstBoot: false,
                ),
                {'reason': 'reloaded', 'state': snapshot},
              );

              controller.deliveryValue = true;
              unawaited(
                dispatcher.onForegroundInstanceReady(pluginId, instanceId: 'a'),
              );
              async.flushMicrotasks();
              expect(
                controller.scripts.where(
                  (script) => script.contains('qa.recovery.targeted'),
                ),
                hasLength(1),
              );
              store.set(
                (pluginId: 'other.0', instanceId: 'page'),
                {'value': 80},
              );
              expect(
                store.has(key),
                false,
                reason: 'Boot releases the retention',
              );
            } finally {
              async.flushMicrotasks();
              dispatcher.resetVisibilityForTesting();
            }
          });
        },
      );
    }

    for (final reply in ['null', 'false', 'error']) {
      test(
        '${platform.name} preserves the live document after a $reply ack',
        () {
          debugDefaultTargetPlatformOverride = platform;
          fakeAsync((async) {
            final controller = visibleInFakeAsync(async);
            try {
              dispatcher.setVisiblePluginInstances(const {});
              async.flushMicrotasks();
              store.set(key, {'schemaVersion': 3, 'draft': 'before command'});
              controller.deliveryValue = reply == 'false' ? false : null;
              if (reply == 'error') {
                controller.deliveryError = StateError('lost ack');
              }
              var finished = false;
              unawaited(recoveryCommand().then((_) => finished = true));
              async.flushMicrotasks();

              expect(finished, true);
              expect(controller.calls, isNot(contains('reload')));
              expect(details()['suspensionState'], 'active');
              expect(store.stateOf(key), {
                'schemaVersion': 3,
                'draft': 'before command',
              });

              unawaited(
                dispatcher.onForegroundInstanceReady(pluginId, instanceId: 'a'),
              );
              async.flushMicrotasks();
              expect(
                controller.scripts.where(
                  (script) => script.contains('qa.recovery.targeted'),
                ),
                hasLength(1),
                reason: 'The failed acknowledgment does not erase redelivery',
              );
            } finally {
              async.flushMicrotasks();
              dispatcher.resetVisibilityForTesting();
            }
          });
        },
      );
    }

    test(
      '${platform.name} ignores a late preflight reply after delivery timeout',
      () {
        debugDefaultTargetPlatformOverride = platform;
        fakeAsync((async) {
          final controller = visibleInFakeAsync(async);
          final gate = Completer<void>();
          try {
            dispatcher.setVisiblePluginInstances(const {});
            async.flushMicrotasks();
            store.set(key, {'schemaVersion': 3, 'draft': 'before command'});
            controller
              ..deliveryGate = gate
              ..deliveryValue = 'no-page-world';
            var finished = false;
            unawaited(recoveryCommand().then((_) => finished = true));
            async.flushMicrotasks();
            expect(finished, false);

            async.elapse(const Duration(seconds: 3));
            async.flushMicrotasks();
            expect(finished, true);
            expect(controller.calls, isNot(contains('reload')));
            expect(details()['suspensionState'], 'active');
            gate.complete();
            async.flushMicrotasks();
            expect(controller.calls, isNot(contains('reload')));
            expect(details()['suspensionState'], 'active');
          } finally {
            if (!gate.isCompleted) gate.complete();
            async.flushMicrotasks();
            dispatcher.resetVisibilityForTesting();
          }
        });
      },
    );
  }

  for (final replacement in ['controller', 'document']) {
    test(
      'a stale $replacement reply cannot retain or reload its successor',
      () {
        fakeAsync((async) {
          final controller = visibleInFakeAsync(async);
          final gate = Completer<void>();
          try {
            dispatcher.setVisiblePluginInstances(const {});
            async.flushMicrotasks();
            store.set(key, {'schemaVersion': 1, 'draft': 'old'});
            controller
              ..deliveryGate = gate
              ..deliveryValue = 'no-page-world';
            var finished = false;
            unawaited(recoveryCommand().then((_) => finished = true));
            async.flushMicrotasks();
            expect(finished, false);

            var successor = controller;
            if (replacement == 'controller') {
              successor = _Controller();
              controllers.add(successor);
              dispatcher.registerController(
                pluginId,
                successor,
                instanceId: 'a',
              );
            } else {
              dispatcher.resetEventOptions(pluginId, instanceId: 'a');
            }
            const current = {'schemaVersion': 2, 'draft': 'new'};
            store.set(key, current);
            gate.complete();
            async.flushMicrotasks();
            expect(finished, true);
            expect(controller.calls, isNot(contains('reload')));
            expect(successor.calls, isNot(contains('reload')));
            expect(
              dispatcher.controllerOf(pluginId, instanceId: 'a'),
              same(successor),
            );
            expect(store.stateOf(key), current);
            for (var i = 0; i < 80; i++) {
              store.set(
                (pluginId: 'other.$i', instanceId: 'page'),
                {'value': i},
              );
            }
            expect(
              store.has(key),
              false,
              reason: 'A stale reply must not pin state',
            );
          } finally {
            if (!gate.isCompleted) gate.complete();
            async.flushMicrotasks();
            dispatcher.resetVisibilityForTesting();
          }
        });
      },
    );
  }

  test('a new recovery snapshot replaces an invalidated retention token', () {
    fakeAsync((async) {
      final controller = visibleInFakeAsync(async);
      try {
        dispatcher.setVisiblePluginInstances(const {});
        async.flushMicrotasks();
        store.set(key, {'schemaVersion': 1});
        controller.deliveryValue = 'no-page-world';
        unawaited(recoveryCommand());
        async.flushMicrotasks();
        expect(
          controller.calls.where((call) => call == 'reload'),
          hasLength(1),
        );

        store.remove(key);
        const current = {'schemaVersion': 2, 'revision': 9, 'draft': 'current'};
        store.set(key, current);
        unawaited(recoveryCommand());
        async.flushMicrotasks();
        expect(
          controller.calls.where((call) => call == 'reload'),
          hasLength(2),
        );
        for (var i = 0; i < 80; i++) {
          store.set((pluginId: 'other.$i', instanceId: 'page'), {'value': i});
        }
        expect(store.stateOf(key), current);
      } finally {
        async.flushMicrotasks();
        dispatcher.resetVisibilityForTesting();
      }
    });
  });

  test('a missing reload reply cannot block a later resume', () {
    fakeAsync((async) {
      final controller = visibleInFakeAsync(async);
      dispatcher.setVisiblePluginInstances(const {});
      async.flushMicrotasks();
      expect(details()['suspensionState'], 'suspendedConfirmed');
      final gate = Completer<void>();
      controller
        ..reloadGate = gate
        ..deliveryValue = 'no-page-world';
      store.set(key, {'schemaVersion': 1});
      var deliveryFinished = false;
      try {
        unawaited(
          dispatcher
              .dispatchEventToPlugin(
                pluginId,
                'qa.reload.targeted',
                const {},
                instanceId: 'a',
              )
              .then((_) {
                deliveryFinished = true;
              }),
        );
        async.flushMicrotasks();
        expect(controller.calls, contains('reload'));
        dispatcher.setVisiblePluginInstances({key});
        async.flushMicrotasks();
        expect(deliveryFinished, false);
        expect(details()['suspensionState'], 'hidden');

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(deliveryFinished, true);
        expect(gate.isCompleted, false);
        expect(details()['suspensionState'], 'active');
        gate.complete();
        async.flushMicrotasks();
        expect(details()['suspensionState'], 'active');
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        async.flushMicrotasks();
        dispatcher.resetVisibilityForTesting();
      }
    });
  });

  test('hiding a secondary window leaves the main window running', () async {
    final a = await visible();
    final b = await visible(target: other, viewId: 7);
    dispatcher.setWindowShown(false, viewId: 7);
    await pumpEventQueue();
    expect(a.calls, isEmpty);
    expect(b.calls, contains('pause'));
    expect(details()['suspensionState'], 'active');
    expect(details(other)['suspensionState'], 'suspendedConfirmed');
  });

  test('a slow suspend cannot delay resuming a different tab', () async {
    const PluginInstanceKey third = (pluginId: pluginId, instanceId: 'c');
    final c = await visible(target: third);
    final a = await visible();
    a.pauseGate = Completer<void>();
    await visible(target: other);
    expect(details()['suspensionState'], 'suspendRequested');
    c.calls.clear();

    dispatcher.setVisiblePluginInstances({third});
    await pumpEventQueue();

    expect(a.pauseGate!.isCompleted, false);
    expect(c.calls, contains('resume'));
    expect(details(third)['suspensionState'], 'active');
    a.pauseGate!.complete();
  });

  test(
    'discard retains the only state copy including the plugin schema version',
    () async {
      await visible();
      final host = _Host();
      dispatcher.registerInstanceHost(pluginId, host, instanceId: 'a');
      store.set(key, {'schemaVersion': 2, 'draft': 'important'});
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 1);
      for (var i = 0; i < 80; i++) {
        store.set(
          (pluginId: 'other.$i', instanceId: 'page'),
          {'schemaVersion': 1},
        );
      }
      expect(
        dispatcher.takeBootRestore(pluginId, instanceId: 'a', firstBoot: false),
        {
          'reason': 'discarded',
          'state': {'schemaVersion': 2, 'draft': 'important'},
        },
      );
    },
  );

  test(
    'a rejected state update blocks eviction of the stale snapshot',
    () async {
      await visible();
      final host = _Host();
      dispatcher.registerInstanceHost(pluginId, host, instanceId: 'a');
      store.set(key, {'schemaVersion': 1});
      expect(() => store.set(key, 'x' * (65 * 1024)), throwsArgumentError);
      dispatcher.setVisiblePluginInstances(const {});
      await pumpEventQueue();
      expect(details()['firstBlockingReason'], 'outdatedRestoreState');
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 0);
      store.set(key, {'schemaVersion': 2});
      await dispatcher.checkDiscard(memoryPressure: true);
      expect(host.releases, 1);
    },
  );
}
