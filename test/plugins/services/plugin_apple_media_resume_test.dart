import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

class _Repository extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

class _AppleController extends Fake implements InAppWebViewController {
  final mediaCalls = <bool>[];
  final scripts = <String>[];
  final trace = <String>[];
  final pendingResumes = <Completer<void>>[];
  final pendingSuspends = <Completer<void>>[];
  Completer<void>? javascriptGate;
  bool holdResume = false;
  bool holdSuspend = false;
  bool completeResumeOnJavascript = false;
  bool rejectResume = false;
  bool rejectJavascript = false;
  bool throwJavascriptSynchronously = false;
  int mediaDepth = 0;
  int maximumMediaDepth = 0;

  bool delivered(String text) => scripts.any((source) => source.contains(text));
  int get warmups => scripts.where((source) => source == 'void 0;').length;

  @override
  Future<void> setAllMediaPlaybackSuspended({required bool suspended}) async {
    mediaCalls.add(suspended);
    trace.add('media.request:$suspended');
    // WebKit changes its suspension counter before the asynchronous reply.
    if (suspended) {
      mediaDepth++;
      if (mediaDepth > maximumMediaDepth) maximumMediaDepth = mediaDepth;
    } else if (mediaDepth > 0) {
      mediaDepth--;
    }
    if (!suspended && rejectResume) throw StateError('Native media failure');
    if (suspended ? holdSuspend : holdResume) {
      final reply = Completer<void>();
      (suspended ? pendingSuspends : pendingResumes).add(reply);
      await reply.future;
    }
    trace.add('media.reply:$suspended');
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) {
    scripts.add(source);
    if (source.contains('plugin.resumed')) {
      trace.add('event.resumed');
    } else if (source.contains('theme.changed')) {
      trace.add('event.state');
    } else if (source.contains('reader.context_menu_item_clicked')) {
      trace.add('event.command');
    } else if (source == 'void 0;') {
      trace.add('wake.request');
    }
    if (throwJavascriptSynchronously) {
      throw StateError('Synchronous JavaScript failure');
    }
    return Future<dynamic>.sync(() async {
      await javascriptGate?.future;
      if (rejectJavascript) throw StateError('JavaScript failure');
      if (completeResumeOnJavascript) completeResumes();
      return null;
    });
  }

  void completeResumes({Object? error}) {
    for (final reply in pendingResumes) {
      if (reply.isCompleted) continue;
      if (error == null) {
        reply.complete();
      } else {
        reply.completeError(error);
      }
    }
  }

  void releaseAll() {
    rejectJavascript = false;
    throwJavascriptSynchronously = false;
    if (javascriptGate?.isCompleted == false) javascriptGate!.complete();
    completeResumes();
    for (final reply in pendingSuspends) {
      if (!reply.isCompleted) reply.complete();
    }
  }

  void clearObservations() {
    mediaCalls.clear();
    scripts.clear();
    trace.clear();
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = PluginRuntimeDispatcher.instance;
  const pluginId = 'apple.media.resume.test';
  const PluginInstanceKey key = (pluginId: pluginId, instanceId: 'page');
  final controllers = <_AppleController>[];

  Map<String, Object?> details() =>
      (dispatcher.describeForegroundResources()['instances']!
              as List<Map<String, Object?>>)
          .singleWhere((entry) => entry['pluginId'] == pluginId);

  Future<void> command([String nonce = 'command-one']) =>
      dispatcher.dispatchEventToPlugin(
        pluginId,
        'reader.context_menu_item_clicked',
        {'probeNonce': nonce},
        instanceId: key.instanceId,
      );

  void hide(FakeAsync clock) {
    dispatcher.setVisiblePluginInstances(const {});
    clock.flushMicrotasks();
  }

  void queueTheme(FakeAsync clock) {
    unawaited(dispatcher.dispatchEvent('theme.changed', {'mode': 'dark'}));
    clock.flushMicrotasks();
  }

  void runWithClock(void Function(FakeAsync, _AppleController) body) {
    fakeAsync((clock) {
      // Both lifecycle queues must be created in the zone driven by this clock.
      dispatcher.resetVisibilityForTesting();
      final controller = _AppleController();
      controllers.add(controller);
      dispatcher.registerController(
        pluginId,
        controller,
        instanceId: key.instanceId,
        viewId: 0,
      );
      dispatcher.setVisiblePluginInstances({key});
      var ready = false;
      unawaited(
        dispatcher
            .onForegroundInstanceReady(pluginId, instanceId: key.instanceId)
            .then((_) => ready = true),
      );
      clock.flushMicrotasks();
      expect(ready, isTrue);
      expect(details()['suspensionState'], 'active');
      controller.clearObservations();
      try {
        body(clock, controller);
      } finally {
        for (final controller in controllers) {
          controller.releaseAll();
        }
        clock.flushMicrotasks();
        unawaited(dispatcher.prepareForAppRestart());
        clock.flushMicrotasks();
        dispatcher.resetVisibilityForTesting();
      }
    });
    dispatcher.resetVisibilityForTesting();
  }

  setUp(() async {
    await dispatcher.prepareForAppRestart();
    dispatcher.resetVisibilityForTesting();
    dispatcher.repositoryForTesting = _Repository();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    controllers.clear();
  });

  tearDown(() async {
    await dispatcher.prepareForAppRestart();
    dispatcher.resetVisibilityForTesting();
    dispatcher.repositoryForTesting = PluginRegistryRepository();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test('$platform wakes a hidden command and preserves event ordering', () {
      debugDefaultTargetPlatformOverride = platform;
      runWithClock((clock, controller) {
        hide(clock);
        expect(details()['suspensionState'], 'hidden');
        queueTheme(clock);
        controller.holdResume = true;
        controller.completeResumeOnJavascript = true;
        var delivered = false;
        unawaited(command().then((_) => delivered = true));
        clock.flushMicrotasks();

        expect(delivered, isTrue);
        expect(controller.warmups, 1);
        expect(controller.mediaCalls, [true, false]);
        expect(controller.mediaDepth, 0);
        expect(details()['suspensionState'], 'active');
        expect(controller.delivered('command-one'), isTrue);
        final order = controller.trace;
        expect(
          order.indexOf('media.request:false'),
          lessThan(order.indexOf('wake.request')),
        );
        expect(
          order.indexOf('media.reply:false'),
          lessThan(order.indexOf('event.resumed')),
        );
        expect(
          order.indexOf('event.resumed'),
          lessThan(order.indexOf('event.state')),
        );
        expect(
          order.indexOf('event.state'),
          lessThan(order.indexOf('event.command')),
        );
      });
    });

    test('$platform visible resume does not inject the hidden wake-up', () {
      debugDefaultTargetPlatformOverride = platform;
      runWithClock((clock, controller) {
        hide(clock);
        controller.holdResume = true;
        dispatcher.setVisiblePluginInstances({key});
        clock.flushMicrotasks();
        expect(controller.warmups, 0);
        expect(details()['suspensionState'], 'resumeRequested');
        expect(controller.delivered('plugin.resumed'), isFalse);
        controller.completeResumes();
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'active');
        expect(controller.delivered('plugin.resumed'), isTrue);
        expect(controller.mediaCalls, [true, false]);
      });
    });
  }

  test('a successful JS wake cannot substitute for media completion', () {
    runWithClock((clock, controller) {
      hide(clock);
      queueTheme(clock);
      controller.holdResume = true;
      var completed = false;
      unawaited(command().then((_) => completed = true));
      clock.flushMicrotasks();
      expect(controller.warmups, 1);
      expect(completed, isFalse);
      expect(details()['suspensionState'], 'resumeRequested');
      expect(controller.delivered('plugin.resumed'), isFalse);
      expect(controller.delivered('theme.changed'), isFalse);
      expect(controller.delivered('command-one'), isFalse);

      controller.completeResumes();
      clock.flushMicrotasks();
      expect(completed, isTrue);
      expect(controller.delivered('command-one'), isTrue);
      expect(details()['suspensionState'], 'active');
    });
  });

  test('a missing media reply stays failed after its six-second deadline', () {
    runWithClock((clock, controller) {
      hide(clock);
      queueTheme(clock);
      controller.holdResume = true;
      var completed = false;
      unawaited(command().then((_) => completed = true));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      expect(completed, isFalse);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(completed, isTrue);
      expect(details()['suspensionState'], 'failed');
      expect(controller.delivered('plugin.resumed'), isFalse);
      expect(controller.delivered('theme.changed'), isFalse);
      expect(controller.delivered('command-one'), isFalse);
      expect(controller.mediaCalls, [true, false]);
      expect(controller.mediaDepth, 0);

      controller.completeResumes();
      clock.flushMicrotasks();
      expect(details()['suspensionState'], 'failed');
      controller.holdResume = false;
      dispatcher.setVisiblePluginInstances({key});
      clock.flushMicrotasks();
      expect(details()['suspensionState'], 'active');
      expect(controller.delivered('theme.changed'), isTrue);
    });
  });

  test(
    'native resume failure keeps queued state for a later visible retry',
    () {
      runWithClock((clock, controller) {
        hide(clock);
        queueTheme(clock);
        controller.rejectResume = true;
        unawaited(command());
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'failed');
        expect(controller.delivered('command-one'), isFalse);
        expect(controller.delivered('plugin.resumed'), isFalse);
        expect(controller.delivered('theme.changed'), isFalse);

        controller.rejectResume = false;
        dispatcher.setVisiblePluginInstances({key});
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'active');
        expect(controller.delivered('theme.changed'), isTrue);
      });
    },
  );

  for (final synchronous in [false, true]) {
    test(
      'JS failure (synchronous=$synchronous) observes the pending media error',
      () {
        runWithClock((clock, controller) {
          hide(clock);
          queueTheme(clock);
          controller.holdResume = true;
          controller.rejectJavascript = !synchronous;
          controller.throwJavascriptSynchronously = synchronous;
          var completed = false;
          unawaited(command().then((_) => completed = true));
          clock.flushMicrotasks();
          expect(completed, isTrue);
          expect(details()['suspensionState'], 'failed');
          expect(controller.delivered('command-one'), isFalse);
          expect(controller.delivered('theme.changed'), isFalse);
          controller.completeResumes(error: StateError('Late native failure'));
          clock.flushMicrotasks();
          expect(details()['suspensionState'], 'failed');

          controller.rejectJavascript = false;
          controller.throwJavascriptSynchronously = false;
          controller.holdResume = false;
          dispatcher.setVisiblePluginInstances({key});
          clock.flushMicrotasks();
          expect(controller.delivered('theme.changed'), isTrue);
        });
      },
    );
  }

  test(
    'a timed-out suspend is balanced by one resume, without retrying pause',
    () {
      runWithClock((clock, controller) {
        controller.holdSuspend = true;
        hide(clock);
        expect(details()['suspensionState'], 'suspendRequested');
        clock.elapse(const Duration(seconds: 6));
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'failed');
        expect(controller.mediaDepth, 1);
        controller.holdResume = true;
        controller.completeResumeOnJavascript = true;
        unawaited(command());
        clock.flushMicrotasks();
        expect(controller.delivered('command-one'), isTrue);
        expect(controller.mediaCalls, [true, false]);
        expect(controller.mediaDepth, 0);
        controller.releaseAll();
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'active');
      });
    },
  );

  for (final replaceController in [false, true]) {
    test(
      'stale resume cannot deliver after replacement=$replaceController',
      () {
        runWithClock((clock, controller) {
          hide(clock);
          controller.holdResume = true;
          controller.javascriptGate = Completer<void>();
          unawaited(command());
          clock.flushMicrotasks();
          expect(details()['suspensionState'], 'resumeRequested');
          _AppleController? replacement;
          if (replaceController) {
            replacement = _AppleController();
            controllers.add(replacement);
            dispatcher.registerController(
              pluginId,
              replacement,
              instanceId: key.instanceId,
            );
          } else {
            dispatcher.resetEventOptions(pluginId, instanceId: key.instanceId);
            clock.flushMicrotasks();
          }
          controller.releaseAll();
          clock.flushMicrotasks();
          expect(controller.delivered('command-one'), isFalse);
          expect(controller.delivered('plugin.resumed'), isFalse);
          expect(details()['suspensionState'], 'active');
          if (replacement != null) {
            expect(replacement.scripts, isEmpty);
            expect(replacement.mediaCalls, isEmpty);
          }
        });
      },
    );
  }

  test(
    'concurrent show waits for the hidden resume and preserves its command',
    () {
      runWithClock((clock, controller) {
        hide(clock);
        controller.holdResume = true;
        controller.javascriptGate = Completer<void>();
        unawaited(command());
        clock.flushMicrotasks();
        dispatcher.setVisiblePluginInstances({key});
        clock.flushMicrotasks();
        expect(controller.mediaCalls, [true, false]);
        expect(controller.delivered('command-one'), isFalse);

        controller.holdResume = false;
        controller.releaseAll();
        clock.flushMicrotasks();
        expect(controller.delivered('command-one'), isTrue);
        expect(details()['suspensionState'], 'active');
        expect(controller.warmups, 1);
        expect(controller.mediaDepth, 0);
        expect(controller.maximumMediaDepth, 1);
      });
    },
  );

  test('hidden navigation reset also waits for the genuine media reply', () {
    runWithClock((clock, controller) {
      hide(clock);
      controller.holdResume = true;
      dispatcher.resetEventOptions(pluginId, instanceId: key.instanceId);
      clock.flushMicrotasks();
      expect(controller.warmups, 1);
      expect(details()['suspensionState'], 'resumeRequested');
      controller.completeResumes();
      clock.flushMicrotasks();
      expect(details()['suspensionState'], 'active');
      expect(controller.delivered('plugin.resumed'), isFalse);
      expect(controller.mediaCalls, [true, false]);
    });
  });

  test('two commands queued during one wake each reach the same live page', () {
    runWithClock((clock, controller) {
      hide(clock);
      controller.holdResume = true;
      controller.javascriptGate = Completer<void>();
      unawaited(command());
      unawaited(command('command-two'));
      clock.flushMicrotasks();
      expect(controller.mediaCalls, [true, false]);
      expect(controller.delivered('command-one'), isFalse);
      expect(controller.delivered('command-two'), isFalse);

      controller.completeResumeOnJavascript = true;
      controller.javascriptGate!.complete();
      clock.flushMicrotasks();
      for (final nonce in ['command-one', 'command-two']) {
        expect(
          controller.scripts.where((source) => source.contains(nonce)),
          hasLength(1),
        );
      }
      expect(details()['suspensionState'], 'active');
      expect(
        controller.mediaCalls.where((suspended) => suspended),
        hasLength(1),
      );
      expect(
        controller.mediaCalls.where((suspended) => !suspended).length,
        lessThanOrEqualTo(2),
      );
      expect(controller.mediaDepth, 0);
      expect(controller.maximumMediaDepth, 1);
    });
  });

  test(
    'repeated hidden commands and grace keep media suspend/resume balanced',
    () {
      runWithClock((clock, controller) {
        hide(clock);
        controller.holdResume = true;
        controller.completeResumeOnJavascript = true;
        unawaited(command());
        clock.flushMicrotasks();
        unawaited(command('command-two'));
        clock.flushMicrotasks();
        expect(controller.delivered('command-one'), isTrue);
        expect(controller.delivered('command-two'), isTrue);
        expect(controller.mediaCalls, [true, false]);
        expect(controller.warmups, 1);

        clock.elapse(const Duration(seconds: 91));
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'hidden');
        expect(controller.mediaCalls, [true, false, true]);
        expect(controller.mediaDepth, 1);
        controller.holdResume = false;
        dispatcher.setVisiblePluginInstances({key});
        clock.flushMicrotasks();
        expect(details()['suspensionState'], 'active');
        expect(controller.mediaCalls, [true, false, true, false]);
        expect(controller.mediaDepth, 0);
        expect(controller.maximumMediaDepth, 1);
        expect(controller.warmups, 1);
      });
    },
  );
}
