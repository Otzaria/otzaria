import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

void main() {
  late PluginLazyActivationService service;
  late Map<String, Object?> settings;
  late List<String> activations;
  late List<(String pluginId, String topic, Map<String, dynamic> payload)>
  delivered;

  setUp(() {
    settings = {};
    service = PluginLazyActivationService.forTesting(
      conditionEvaluator: PluginConditionEvaluator.forTesting(
        settingReader: (key) => settings[key],
      ),
    )..startupDelayOverride = Duration.zero;
    activations = [];
    delivered = [];
    service.backgroundActivator = (pluginId) async {
      activations.add(pluginId);
    };
    service.deliverOverride = (pluginId, topic, payload) async {
      delivered.add((pluginId, topic, payload));
    };
  });

  test('targeted event on a non-activatable plugin is rejected', () {
    expect(service.queueTargetedEvent('p1', 'click', {}), isFalse);
    expect(activations, isEmpty);
  });

  test('targeted events queue, activate once, and flush in order', () async {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
    );

    expect(service.queueTargetedEvent('p1', 'click', {'n': 1}), isTrue);
    expect(service.queueTargetedEvent('p1', 'click', {'n': 2}), isTrue);
    expect(activations, ['p1']);
    expect(delivered, isEmpty);

    await service.onBackgroundInstanceReady('p1');
    expect(delivered.map((e) => e.$3['n']), [1, 2]);

    // ריקון חוזר — התור כבר ריק.
    await service.onBackgroundInstanceReady('p1');
    expect(delivered, hasLength(2));
  });

  test('early ready consumes deferred startup and permits backgroundDone', () {
    fakeAsync((clock) {
      final deactivations = <String>[];
      service.startupDelayOverride = const Duration(seconds: 8);
      service.idleDelayOverride = const Duration(minutes: 3);
      service.backgroundDeactivator = deactivations.add;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: true,
      );
      service.trackIdleTeardown('p1');
      service.queueTargetedEvent('p1', 'app.startup', {});
      final runtime = service.attachBackgroundInstance('p1');
      unawaited(service.onBackgroundInstanceReady('p1', runtimeToken: runtime));
      clock.flushMicrotasks();

      clock.elapse(const Duration(seconds: 8));
      expect(
        service.requestImmediateTeardown('p1', runtimeToken: runtime),
        isTrue,
      );
      clock.elapse(const Duration(milliseconds: 299));
      expect(deactivations, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(
        deactivations,
        ['p1'],
        reason:
            'bootPending=${service.isBootPending('p1')}, activations=$activations',
      );
      expect(activations, ['p1']);
      expect(service.isBootPending('p1'), isFalse);
    });
  });

  test(
    'an early activation failure preserves the deferred startup attempt',
    () {
      fakeAsync((clock) {
        service.startupDelayOverride = const Duration(seconds: 8);
        service.backgroundActivator = (pluginId) async {
          activations.add(pluginId);
          if (activations.length == 1) {
            throw StateError('Early activation failed');
          }
        };
        service.syncPlugin(
          'p1',
          broadcastTopics: const {},
          scheduleStartup: true,
        );
        service.queueTargetedEvent('p1', 'click', {});
        clock.flushMicrotasks();
        expect(service.isBootPending('p1'), isFalse);
        clock.elapse(const Duration(seconds: 8));
        expect(activations, ['p1', 'p1']);
        expect(service.isBootPending('p1'), isTrue);
      });
    },
  );

  test('stale ready cannot consume deferred startup for a replacement', () {
    fakeAsync((clock) {
      service.startupDelayOverride = const Duration(seconds: 8);
      service.backgroundActivator = (pluginId) async {
        activations.add(pluginId);
        if (activations.length == 1) {
          throw StateError('Early activation failed');
        }
      };
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: true,
      );
      service.queueTargetedEvent('p1', 'click', {});
      final original = service.attachBackgroundInstance('p1');
      clock.flushMicrotasks();
      service.attachBackgroundInstance('p1');
      unawaited(
        service.onBackgroundInstanceReady('p1', runtimeToken: original),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 8));
      expect(activations, ['p1', 'p1']);
      expect(service.isBootPending('p1'), isTrue);
    });
  });

  test('broadcast wakes only declared topics without a usable instance', () {
    service.syncPlugin(
      'declared',
      broadcastTopics: const {'reader.sectionContentChanged'},
      scheduleStartup: false,
    );
    service.syncPlugin(
      'other-topic',
      broadcastTopics: const {'theme.changed'},
      scheduleStartup: false,
    );
    service.syncPlugin(
      'alive',
      broadcastTopics: const {'reader.sectionContentChanged'},
      scheduleStartup: false,
    );

    service.onBroadcast(
      'reader.sectionContentChanged',
      {},
      hasUsableInstance: (pluginId) => pluginId == 'alive',
    );

    expect(activations, ['declared']);
  });

  for (final revoke in [false, true]) {
    test(
      'late ready after ${revoke ? "revocation" : "crash"} preserves retry queue',
      () async {
        final deactivations = <String>[];
        service.backgroundDeactivator = deactivations.add;
        service.syncPlugin(
          'p1',
          broadcastTopics: const {},
          scheduleStartup: false,
        );
        service.queueTargetedEvent('p1', 'click', {'n': 1});
        final oldGeneration = service.activationGeneration('p1');
        if (revoke) {
          service.removePlugin('p1');
          service.syncPlugin(
            'p1',
            broadcastTopics: const {},
            scheduleStartup: false,
          );
        } else {
          service.onBackgroundProcessGone('p1', generation: oldGeneration);
        }
        service.queueTargetedEvent('p1', 'click', {'n': 2});
        final newGeneration = service.activationGeneration('p1');
        final deactivationsBeforeReady = deactivations.length;
        final runtime = service.attachBackgroundInstance('p1');

        await service.onBackgroundInstanceReady(
          'p1',
          generation: oldGeneration,
          runtimeToken: runtime,
          isCurrent: () => true,
        );
        expect(service.isBootPending('p1'), isTrue);
        expect(deactivations, hasLength(deactivationsBeforeReady));
        expect(delivered, isEmpty);
        await service.onBackgroundInstanceReady(
          'p1',
          generation: newGeneration,
          runtimeToken: runtime,
          isCurrent: () => true,
        );
        expect(delivered.map((event) => event.$3['n']), [2]);
      },
    );
  }

  test(
    'crash while flushing stops remaining events from the old generation',
    () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      service.deliverOverride = (pluginId, topic, payload) async {
        delivered.add((pluginId, topic, payload));
        if (payload['n'] == 1) {
          entered.complete();
          await gate.future;
        }
      };
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
      );
      service.queueTargetedEvent('p1', 'click', {'n': 1});
      service.queueTargetedEvent('p1', 'click', {'n': 2});
      final oldGeneration = service.activationGeneration('p1');
      final flushing = service.onBackgroundInstanceReady(
        'p1',
        generation: oldGeneration,
      );
      await entered.future;
      service.onBackgroundProcessGone('p1', generation: oldGeneration);
      service.queueTargetedEvent('p1', 'click', {'n': 3});
      gate.complete();
      await flushing;

      expect(delivered.map((event) => event.$3['n']), [1]);
      expect(service.isBootPending('p1'), isTrue);
      await service.onBackgroundInstanceReady(
        'p1',
        generation: service.activationGeneration('p1'),
      );
      expect(delivered.map((event) => event.$3['n']), [1, 3]);
    },
  );
  for (final replaceRuntime in [false, true]) {
    test(
      '${replaceRuntime ? "runtime" : "page"} replacement stops pending event flush',
      () async {
        service.syncPlugin(
          'p1',
          broadcastTopics: const {},
          scheduleStartup: false,
        );
        final oldOwner = service.attachBackgroundInstance('p1');
        var pageCurrent = true;
        final firstDelivery = Completer<void>();
        service.deliverOverride = (pluginId, topic, payload) async {
          delivered.add((pluginId, topic, payload));
          await firstDelivery.future;
        };
        service.queueTargetedEvent('p1', 'click', {'n': 1});
        service.queueTargetedEvent('p1', 'click', {'n': 2});
        final flush = service.onBackgroundInstanceReady(
          'p1',
          generation: service.activationGeneration('p1'),
          runtimeToken: oldOwner,
          isCurrent: () => pageCurrent,
        );
        final newOwner = replaceRuntime
            ? service.attachBackgroundInstance('p1')
            : oldOwner;
        if (!replaceRuntime) pageCurrent = false;
        firstDelivery.complete();
        await flush;
        expect(delivered.map((event) => event.$3['n']), [1]);
        service.onBackgroundInstanceClosed('p1', runtimeToken: newOwner);
      },
    );
  }

  test('app.startup fires once per session, even after re-sync', () async {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(activations, ['p1']);

    await service.onBackgroundInstanceReady('p1');
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(activations, ['p1']);
  });

  test('removed plugin is not activated by a scheduled app.startup', () async {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: true,
    );
    service.removePlugin('p1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(activations, isEmpty);
  });

  test('scheduled startup cannot revive a later eligibility generation', () {
    fakeAsync((async) {
      service.startupDelayOverride = const Duration(seconds: 8);
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: true,
      );
      service.removePlugin('p1');
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
      );
      async.elapse(const Duration(seconds: 8));
      expect(activations, isEmpty);
      service.removePlugin('p1');
    });
  });

  test(
    'revocation invalidates an activation already waiting on init',
    () async {
      final initGate = Completer<void>();
      var attachedAfterInit = false;
      service.backgroundActivator = (pluginId) async {
        final generation = service.activationGeneration(pluginId);
        await initGate.future;
        attachedAfterInit = service.trackIdleTeardown(
          pluginId,
          generation: generation,
        );
      };
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
      );

      service.queueTargetedEvent('p1', 'click', {});
      service.removePlugin('p1');
      initGate.complete();
      await Future<void>.delayed(Duration.zero);

      expect(attachedAfterInit, isFalse);
      expect(service.isBootPending('p1'), isFalse);
    },
  );

  group('idle teardown', () {
    late List<String> deactivations;

    setUp(() {
      deactivations = [];
      service.idleDelayOverride = const Duration(milliseconds: 30);
      service.backgroundDeactivator = deactivations.add;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
      );
    });

    test('an idle tracked instance is torn down after the delay', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
    });

    test('activity resets the idle timer', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        service.notifyActivity('p1');
      }
      expect(deactivations, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
    });

    test('keepAlive prevents idle teardown until it is revoked', () async {
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
        keepAlive: true,
      );
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(deactivations, isEmpty);

      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
    });

    test('backgroundDone still tears down a keepAlive instance', () async {
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
        keepAlive: true,
      );
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      expect(service.requestImmediateTeardown('p1'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(deactivations, ['p1']);
    });

    test('an untracked (eager) instance is never torn down', () async {
      await service.onBackgroundInstanceReady('p1');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, isEmpty);
    });

    test('closing the instance cancels the timer', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');
      service.onBackgroundInstanceClosed('p1');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, isEmpty);
    });

    test('removePlugin tears down a tracked running instance', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      service.removePlugin('p1');

      expect(deactivations, ['p1']);
    });

    test('removePlugin does not deactivate an untracked plugin', () {
      service.removePlugin('p1');
      expect(deactivations, isEmpty);
    });

    test('a busy instance (RPC in flight) is not torn down', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      final finish = service.beginWork('p1');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(deactivations, isEmpty, reason: 'RPC ארוך באמצע — אסור לקטוע');

      finish();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
    });

    test('nested RPCs keep the instance busy until the last ends', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      final finishFirst = service.beginWork('p1');
      final finishLast = service.beginWork('p1');
      finishFirst();
      finishFirst();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(deactivations, isEmpty);

      finishLast();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
    });

    test(
      'backgroundDone tears down immediately, without the idle wait',
      () async {
        // שעון ארוך בכוונה — הכיבוי חייב להגיע מהבקשה המפורשת, לא מהשעון.
        service.idleDelayOverride = const Duration(seconds: 30);
        service.trackIdleTeardown('p1');
        await service.onBackgroundInstanceReady('p1');

        expect(service.requestImmediateTeardown('p1'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(deactivations, ['p1']);
      },
    );

    test('backgroundDone on an untracked instance is a safe no-op', () async {
      expect(service.requestImmediateTeardown('p1'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(deactivations, isEmpty);
    });

    test(
      'backgroundDone closes after its slow originating RPC completes',
      () async {
        // Under a slow native WebView callback the RPC may still be in flight
        // after the 300ms acknowledgement grace period. Do not wait 3 minutes.
        service.idleDelayOverride = const Duration(minutes: 3);
        service.trackIdleTeardown('p1');
        final runtime = service.attachBackgroundInstance('p1');
        await service.onBackgroundInstanceReady('p1', runtimeToken: runtime);
        final finishOriginal = service.beginWork('p1', runtimeToken: runtime);

        expect(
          service.requestImmediateTeardown('p1', runtimeToken: runtime),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 420));
        expect(deactivations, isEmpty, reason: 'Do not dispose an active RPC');

        finishOriginal();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        expect(deactivations, ['p1']);
        service.onBackgroundInstanceClosed('p1', runtimeToken: runtime);
      },
    );

    test('deferred backgroundDone cannot terminate a replacement runtime', () {
      fakeAsync((async) {
        service.idleDelayOverride = const Duration(minutes: 3);
        service.trackIdleTeardown('p1');
        final original = service.attachBackgroundInstance('p1');
        final finishOriginal = service.beginWork('p1', runtimeToken: original);
        expect(
          service.requestImmediateTeardown('p1', runtimeToken: original),
          isTrue,
        );
        async.elapse(const Duration(milliseconds: 350));
        expect(deactivations, isEmpty);

        // The old RPC resolves after its owner has been closed/replaced.
        service.onBackgroundInstanceClosed('p1', runtimeToken: original);
        final replacement = service.attachBackgroundInstance('p1');
        service.trackIdleTeardown('p1');
        finishOriginal();
        async.elapse(const Duration(seconds: 1));
        expect(deactivations, isEmpty);
        service.onBackgroundInstanceClosed('p1', runtimeToken: replacement);
      });
    });

    test('backgroundDone defers when new work started meanwhile', () async {
      service.idleDelayOverride = const Duration(milliseconds: 50);
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');

      expect(service.requestImmediateTeardown('p1'), isTrue);
      final finish = service.beginWork('p1');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(deactivations, isEmpty, reason: 'RPC חדש נפתח — לא קוטעים');

      finish();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(deactivations, ['p1'], reason: 'ומשם — השעון הרגיל');
    });

    test(
      'backgroundDone from a closed instance cannot close its replacement',
      () {
        fakeAsync((async) {
          service.idleDelayOverride = const Duration(seconds: 30);
          service.trackIdleTeardown('p1');
          unawaited(service.onBackgroundInstanceReady('p1'));
          async.flushMicrotasks();
          expect(service.requestImmediateTeardown('p1'), isTrue);
          service.onBackgroundInstanceClosed('p1');
          service.trackIdleTeardown('p1');
          unawaited(service.onBackgroundInstanceReady('p1'));
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 400));
          expect(deactivations, isEmpty);
          service.onBackgroundInstanceClosed('p1');
        });
      },
    );

    test('unsaved background state blocks idle and explicit teardown', () {
      const key = (pluginId: 'p1', instanceId: PluginInstanceIds.background);
      final unsaved = PluginUnsavedChangesRegistry.instance;
      fakeAsync((async) {
        service.idleDelayOverride = const Duration(seconds: 1);
        service.trackIdleTeardown('p1');
        unawaited(service.onBackgroundInstanceReady('p1'));
        async.flushMicrotasks();
        unsaved.set(key, hasChanges: true);
        try {
          expect(service.canTeardown('p1'), isFalse);
          expect(service.requestImmediateTeardown('p1'), isTrue);
          async.elapse(const Duration(seconds: 4));
          expect(deactivations, isEmpty);
          unsaved.removeInstance(key);
          async.elapse(const Duration(seconds: 1));
          expect(deactivations, ['p1']);
        } finally {
          unsaved.removeInstance(key);
          service.onBackgroundInstanceClosed('p1');
        }
      });
    });

    test(
      'protected sessions defer idle teardown until protection is cleared',
      () {
        fakeAsync((async) {
          var protected = true;
          final protectedService =
              PluginLazyActivationService.forTesting(
                  hasEssentialState: (_) => protected,
                )
                ..idleDelayOverride = const Duration(seconds: 1)
                ..backgroundDeactivator = deactivations.add;
          protectedService.trackIdleTeardown('p1');
          unawaited(protectedService.onBackgroundInstanceReady('p1'));
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 3));
          expect(deactivations, isEmpty);
          protected = false;
          async.elapse(const Duration(seconds: 1));
          expect(deactivations, ['p1']);
          protectedService.onBackgroundInstanceClosed('p1');
        });
      },
    );

    test('an unfinished boot is protected after its initial RPC completed', () {
      fakeAsync((async) {
        service.idleDelayOverride = const Duration(seconds: 1);
        service.queueTargetedEvent('p1', 'click', {});
        service.trackIdleTeardown('p1');
        service.beginWork('p1')();
        async.elapse(const Duration(seconds: 3));
        expect(service.isBootPending('p1'), isTrue);
        expect(deactivations, isEmpty);
        unawaited(service.onBackgroundInstanceReady('p1'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        expect(deactivations, ['p1']);
        service.onBackgroundInstanceClosed('p1');
      });
    });

    test('a torn-down plugin can be re-activated by the next click', () async {
      service.trackIdleTeardown('p1');
      await service.onBackgroundInstanceReady('p1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(deactivations, ['p1']);
      service.onBackgroundInstanceClosed('p1');

      expect(service.queueTargetedEvent('p1', 'click', {}), isTrue);
      expect(activations, contains('p1'));
    });
  });

  test('queueIfBootPending queues only while a boot is in flight', () async {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
    );

    expect(service.queueIfBootPending('p1', 'click', {'n': 0}), isFalse);

    service.queueTargetedEvent('p1', 'click', {'n': 1});
    expect(service.isBootPending('p1'), isTrue);
    expect(service.queueIfBootPending('p1', 'click', {'n': 2}), isTrue);

    await service.onBackgroundInstanceReady('p1');
    expect(delivered.map((e) => e.$3['n']), [1, 2]);
    expect(service.isBootPending('p1'), isFalse);
  });

  test('failed activation drops the pending queue and allows retry', () async {
    service.backgroundActivator = (pluginId) async {
      activations.add(pluginId);
      throw StateError('no runtime');
    };
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
    );

    service.queueTargetedEvent('p1', 'click', {'n': 1});
    await Future<void>.delayed(Duration.zero);
    await service.onBackgroundInstanceReady('p1');
    expect(delivered, isEmpty);

    // הפעלה חוזרת אפשרית אחרי הכשל.
    service.queueTargetedEvent('p1', 'click', {'n': 2});
    expect(activations, hasLength(2));
  });

  test('failed background boot clears pending state and allows retry', () {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
    );

    service.queueTargetedEvent('p1', 'click', {'n': 1});
    expect(service.isBootPending('p1'), isTrue);

    service.onBackgroundInstanceFailed('p1');
    expect(service.isBootPending('p1'), isFalse);

    service.queueTargetedEvent('p1', 'click', {'n': 2});
    expect(activations, ['p1', 'p1']);
  });

  test('late close from a failed generation does not cancel its retry', () {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
    );
    final failedGeneration = service.activationGeneration('p1');
    service.queueTargetedEvent('p1', 'click', {'n': 1});

    service.onBackgroundInstanceFailed(
      'p1',
      generation: failedGeneration,
    );
    expect(service.activationGeneration('p1'), failedGeneration + 1);
    service.queueTargetedEvent('p1', 'click', {'n': 2});
    expect(service.isBootPending('p1'), isTrue);

    service.onBackgroundInstanceClosed(
      'p1',
      generation: failedGeneration,
    );

    expect(service.isBootPending('p1'), isTrue);
    expect(activations, ['p1', 'p1']);
  });

  test(
    'work from a crashed background page cannot finish its replacement job',
    () {
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: false,
      );
      final oldGeneration = service.activationGeneration('p1');
      service.trackIdleTeardown('p1', generation: oldGeneration);
      final finishOld = service.beginWork('p1');

      service.onBackgroundProcessGone('p1', generation: oldGeneration);
      expect(service.isBusy('p1'), isFalse);
      final newGeneration = service.activationGeneration('p1');
      expect(newGeneration, oldGeneration + 1);
      service.trackIdleTeardown('p1', generation: newGeneration);
      final finishNew = service.beginWork('p1');

      service.onBackgroundInstanceClosed('p1', generation: oldGeneration);
      finishOld();
      expect(service.isBusy('p1'), isTrue);
      finishNew();
      expect(service.isBusy('p1'), isFalse);
      service.removePlugin('p1');
    },
  );

  test('a late RPC completion after normal close cannot finish a new job', () {
    service.trackIdleTeardown('p1');
    final finishOld = service.beginWork('p1');
    service.onBackgroundInstanceClosed('p1');
    service.trackIdleTeardown('p1');
    final finishNew = service.beginWork('p1');
    finishOld();
    finishOld();
    expect(service.isBusy('p1'), isTrue);
    finishNew();
    expect(service.isBusy('p1'), isFalse);
    service.onBackgroundInstanceClosed('p1');
  });

  test(
    'same-generation replacement owns teardown before its controller exists',
    () {
      fakeAsync((async) {
        service.syncPlugin(
          'p1',
          broadcastTopics: const {},
          scheduleStartup: false,
        );
        final generation = service.activationGeneration('p1');
        service.trackIdleTeardown('p1', generation: generation);
        final oldOwner = service.attachBackgroundInstance('p1');
        final finishOld = service.beginWork('p1', runtimeToken: oldOwner);
        expect(
          service.requestImmediateTeardown('p1', runtimeToken: oldOwner),
          isTrue,
        );
        final newOwner = service.attachBackgroundInstance('p1');
        final finishNew = service.beginWork('p1', runtimeToken: newOwner);

        service.onBackgroundInstanceClosed(
          'p1',
          generation: generation,
          runtimeToken: oldOwner,
        );
        service.onBackgroundInstanceFailed(
          'p1',
          generation: generation,
          runtimeToken: oldOwner,
        );
        finishOld();
        service.beginWork('p1', runtimeToken: oldOwner)();
        expect(service.isBusy('p1'), isTrue);
        expect(service.activationGeneration('p1'), generation);
        expect(
          service.requestImmediateTeardown('p1', runtimeToken: oldOwner),
          isFalse,
        );
        finishNew();
        expect(service.isBusy('p1'), isFalse);
        service.onBackgroundInstanceClosed('p1', runtimeToken: newOwner);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  group('תנאי when על נושאי הפעלה', () {
    PluginWhenCondition darkModeIs(bool value) => PluginWhenCondition.fromJson({
      'setting': {'key': SettingsRepository.keyDarkMode, 'equals': value},
    });

    test('אירוע ממוקד נזרק כשהתנאי לא מתקיים', () {
      settings[SettingsRepository.keyDarkMode] = false;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
        activationConditions: {
          'reader.sectionContentChanged': darkModeIs(true),
        },
      );

      expect(
        service.queueTargetedEvent('p1', 'reader.sectionContentChanged', {}),
        isFalse,
      );
      expect(activations, isEmpty);
    });

    test('אותו אירוע עובר כשהתנאי מתקיים', () {
      settings[SettingsRepository.keyDarkMode] = true;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
        activationConditions: {
          'reader.sectionContentChanged': darkModeIs(true),
        },
      );

      expect(
        service.queueTargetedEvent('p1', 'reader.sectionContentChanged', {}),
        isTrue,
      );
      expect(activations, ['p1']);
    });

    test('isActivationBlocked רק כשיש תנאי לנושא והוא אינו מתקיים', () {
      settings[SettingsRepository.keyDarkMode] = false;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
        activationConditions: {
          'reader.sectionContentChanged': darkModeIs(true),
        },
      );

      expect(
        service.isActivationBlocked('p1', 'reader.sectionContentChanged'),
        isTrue,
      );
      expect(service.isActivationBlocked('p1', 'click'), isFalse);
      expect(
        service.isActivationBlocked('other', 'reader.sectionContentChanged'),
        isFalse,
      );

      settings[SettingsRepository.keyDarkMode] = true;
      expect(
        service.isActivationBlocked('p1', 'reader.sectionContentChanged'),
        isFalse,
      );
    });

    test('נושא אחר באותו תוסף אינו משתנה', () {
      settings[SettingsRepository.keyDarkMode] = false;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
        activationConditions: {
          'reader.sectionContentChanged': darkModeIs(true),
        },
      );

      expect(service.queueTargetedEvent('p1', 'click', {}), isTrue);
      expect(activations, ['p1']);
    });

    test('שידור חסום לתוסף שתנאיו לא מתקיים', () {
      settings[SettingsRepository.keyDarkMode] = false;
      service.syncPlugin(
        'blocked',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
        activationConditions: {
          'reader.sectionContentChanged': darkModeIs(true),
        },
      );
      service.syncPlugin(
        'free',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
      );

      service.onBroadcast(
        'reader.sectionContentChanged',
        {},
        hasUsableInstance: (_) => false,
      );

      expect(activations, ['free']);
    });

    test('מנוע חי אינו עובר דרך השער כלל', () {
      settings[SettingsRepository.keyDarkMode] = false;
      service.syncPlugin(
        'alive',
        broadcastTopics: const {'reader.sectionContentChanged'},
        scheduleStartup: false,
        activationConditions: {
          'reader.sectionContentChanged': darkModeIs(true),
        },
      );

      var asked = false;
      service.onBroadcast(
        'reader.sectionContentChanged',
        {},
        hasUsableInstance: (_) {
          asked = true;
          return true;
        },
      );

      // השער יושב אחרי בדיקת המופע החי, ולכן אינו משפיע עליו.
      expect(asked, isTrue);
      expect(activations, isEmpty);
    });

    test('app.startup עם תנאי שאינו מתקיים אינו מעיר', () async {
      settings[SettingsRepository.keyDarkMode] = false;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: true,
        activationConditions: {'app.startup': darkModeIs(true)},
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(activations, isEmpty);
    });

    test('app.startup נבדק ברגע ירי הטיימר', () async {
      settings[SettingsRepository.keyDarkMode] = true;
      service.syncPlugin(
        'p1',
        broadcastTopics: const {},
        scheduleStartup: true,
        activationConditions: {'app.startup': darkModeIs(true)},
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(activations, ['p1']);
    });
  });

  void crashLoop(int times) {
    for (var i = 0; i < times; i++) {
      service.queueTargetedEvent('p1', 'click', {});
      service.onBackgroundProcessGone('p1');
    }
  }

  test('שלוש נפילות תהליך בעשר דקות — התוסף לא מוער עוד', () {
    service.syncPlugin('p1', broadcastTopics: const {}, scheduleStartup: false);
    crashLoop(2);
    expect(service.isFailureBlocked('p1'), isFalse);
    crashLoop(1);

    expect(service.isFailureBlocked('p1'), isTrue);
    expect(service.queueTargetedEvent('p1', 'click', {}), isFalse);
    expect(activations, hasLength(3));
  });

  test('כשל boot רגיל אינו נספר כנפילה', () {
    service.syncPlugin('p1', broadcastTopics: const {}, scheduleStartup: false);
    for (var i = 0; i < 5; i++) {
      service.queueTargetedEvent('p1', 'click', {});
      service.onBackgroundInstanceFailed('p1');
    }
    expect(service.isFailureBlocked('p1'), isFalse);
  });

  test('נפילות מפוזרות מעבר לחלון אינן חוסמות', () {
    var now = DateTime(2026, 10, 21, 12);
    service.clock = () => now;
    service.syncPlugin('p1', broadcastTopics: const {}, scheduleStartup: false);
    for (var i = 0; i < 4; i++) {
      crashLoop(1);
      now = now.add(const Duration(minutes: 6));
    }
    expect(service.isFailureBlocked('p1'), isFalse);
  });

  test('הסרה או השבתה מאפסות את החסימה', () {
    service.syncPlugin('p1', broadcastTopics: const {}, scheduleStartup: false);
    crashLoop(3);
    service.removePlugin('p1');
    expect(service.isFailureBlocked('p1'), isFalse);
  });

  test('גרסה חדשה מאפסת את החסימה, וסנכרון חוזר באותה גרסה לא', () {
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
      version: '1.0.0',
    );
    crashLoop(3);
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
      version: '1.0.0',
    );
    expect(service.isFailureBlocked('p1'), isTrue);
    service.syncPlugin(
      'p1',
      broadcastTopics: const {},
      scheduleStartup: false,
      version: '1.0.1',
    );
    expect(service.isFailureBlocked('p1'), isFalse);
  });
}
