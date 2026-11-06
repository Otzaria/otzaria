import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

import '../../../integration_test/support/android_startup_protocol.dart';

Map<String, dynamic> _config() => {
  'schemaVersion': 1,
  'campaignId': 'campaign-testing',
  'runId': 'measurement-first',
  'fixtureId': 'fixture-foreground-native',
  'operation': 'measure',
  'scenario': 'foreground',
  'prewarmMode': 'native',
  'fixtureState': 'prepared',
  'buildMode': 'profile',
  'observationMs': 5000,
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('preparation can finish without starting frame measurement', () async {
    final frames = <FrameTiming>[];
    final timings = AndroidStartupTimings(binding, frames.addAll);
    final bodyDone = Completer<void>();
    try {
      expect(frames, isEmpty);
    } finally {
      timings.stop();
      bodyDone.complete();
    }
    await bodyDone.future.timeout(const Duration(seconds: 1));
    binding.platformDispatcher.onReportTimings!([_frame()]);
    expect(frames, isEmpty);
  });

  test('measurement ends once and leaves other timing callbacks active', () {
    final frames = <FrameTiming>[];
    final otherFrames = <FrameTiming>[];
    final timings = AndroidStartupTimings(binding, frames.addAll);
    final otherCallback = otherFrames.addAll;
    binding.addTimingsCallback(otherCallback);
    try {
      timings.start();
      final frame = _frame();
      binding.platformDispatcher.onReportTimings!([frame]);
      expect(frames, [same(frame)]);
      expect(otherFrames, [same(frame)]);
      timings.stop();
      timings.stop();
      binding.platformDispatcher.onReportTimings!([frame]);
      expect(frames, [same(frame)]);
      expect(otherFrames, [same(frame), same(frame)]);
    } finally {
      binding.removeTimingsCallback(otherCallback);
      timings.stop();
    }
  });

  test('duplicate start cannot register or leak a second callback', () {
    final frames = <FrameTiming>[];
    final timings = AndroidStartupTimings(binding, frames.addAll);
    try {
      timings.start();
      expect(timings.start, throwsStateError);
      final frame = _frame();
      binding.platformDispatcher.onReportTimings!([frame]);
      expect(frames, [same(frame)]);
      timings.stop();
      binding.platformDispatcher.onReportTimings!([frame]);
      expect(frames, [same(frame)]);
    } finally {
      timings.stop();
    }
  });

  for (final stage in ['beforeStart', 'duringMeasurement', 'afterStop']) {
    test(
      'cleanup preserves $stage failure and completes the writer gate',
      () async {
        final frames = <FrameTiming>[];
        final timings = AndroidStartupTimings(binding, frames.addAll);
        final failure = StateError('failure at $stage');
        final bodyDone = Completer<void>();
        Object? runError;
        final completion = bodyDone.future.then(
          (_) => {
            'status': runError == null ? 'passed' : 'failed',
            'error': runError,
          },
        );
        Future<void> body() async {
          try {
            if (stage != 'beforeStart') timings.start();
            if (stage == 'afterStop') timings.stop();
            throw failure;
          } catch (error) {
            runError = error;
            rethrow;
          } finally {
            timings.stop();
            bodyDone.complete();
          }
        }

        await expectLater(body(), throwsA(same(failure)));
        expect(await completion.timeout(const Duration(seconds: 1)), {
          'status': 'failed',
          'error': same(failure),
        });
        binding.platformDispatcher.onReportTimings!([_frame()]);
        expect(frames, isEmpty);
      },
    );
  }

  test('Android entrypoint arguments retain one strict per-process config', () {
    final input = _config();
    final config = AndroidStartupConfig.fromArguments([
      base64Url.encode(utf8.encode(jsonEncode(input))),
    ]);
    expect(config.toJson(), input);
    expect(config.enabledPlugin, isTrue);
    expect(config.opensPlugin, isTrue);
    for (final name in ['noEnabled', 'noOpen']) {
      final control = AndroidStartupConfig.fromJson({
        ...input,
        'scenario': name,
      });
      expect(control.opensPlugin, isFalse);
      expect(control.enabledPlugin, name == 'noOpen');
    }
  });

  test('malformed, unsafe, incomplete and falsely labelled configs fail', () {
    for (final change in <Map<String, dynamic>>[
      {'runId': '../outside'},
      {'fixtureId': '/some/user/data'},
      {'campaignId': 'unsafe;command'},
      {'package': 'org.otzaria.otzaria'},
      {'scenario': 'unknown'},
      {'prewarmMode': 'mockSuccess'},
      {'buildMode': 'release'},
      {'schemaVersion': 2},
      {'observationMs': 999},
      {'observationMs': 60001},
      {'observationMs': 5000.0},
      {'operation': 'prepare', 'fixtureState': 'reused'},
    ]) {
      expect(
        () => AndroidStartupConfig.fromJson({..._config(), ...change}),
        throwsFormatException,
        reason: '$change',
      );
    }
    final missing = _config()..remove('runId');
    expect(() => AndroidStartupConfig.fromJson(missing), throwsFormatException);
    for (final arguments in <List<String>>[
      [],
      ['one', 'two'],
      ['!not-base64'],
      ['a' * 4097],
    ]) {
      expect(
        () => AndroidStartupConfig.fromArguments(arguments),
        throwsFormatException,
      );
    }
  });

  test(
    'observer passes native settings, result identity and completion timing through',
    () async {
      var at = 10;
      var calls = 0;
      final pending = Completer<WebViewEnvironmentPrewarmResult?>();
      final settings = WebViewEnvironmentSettings();
      final observation = AndroidPrewarmObservation(
        mode: AndroidPrewarmMode.native,
        elapsedMicros: () => at,
        nativePrewarm: (passed) {
          expect(identical(passed, settings), isTrue);
          calls++;
          return pending.future;
        },
      );
      final actual = observation.observe(settings);
      expect(calls, 1);
      expect(observation.pending, isTrue);
      final captured = observation.snapshot();
      expect(
        (captured['attempts'] as List).single,
        containsPair('status', 'pending'),
      );
      at = 22;
      const result = WebViewEnvironmentPrewarmResult(
        status: 'ok',
        duration: Duration(milliseconds: 7),
      );
      pending.complete(result);
      expect(identical(await actual, result), isTrue);
      expect(observation.pending, isFalse);
      final complete =
          (observation.snapshot()['attempts'] as List).single as Map;
      expect(complete['enteredAtUs'], 10);
      expect(complete['completedAtUs'], 22);
      expect(complete['nativeDurationMs'], 7);
      expect(complete['settingsMatchAndroidDefaults'], isTrue);
      expect(
        (captured['attempts'] as List).single,
        containsPair('status', 'pending'),
        reason:
            'Earlier measurement boundaries must not change after a late callback.',
      );
    },
  );

  test(
    'native null, failed outcome and thrown error are never reported as ok',
    () async {
      for (final result in <WebViewEnvironmentPrewarmResult?>[
        null,
        const WebViewEnvironmentPrewarmResult(
          status: 'timeout',
          duration: Duration(seconds: 30),
        ),
        const WebViewEnvironmentPrewarmResult(
          status: 'unavailable',
          duration: Duration.zero,
        ),
      ]) {
        final observation = AndroidPrewarmObservation(
          mode: AndroidPrewarmMode.native,
          elapsedMicros: () => 0,
          nativePrewarm: (_) async => result,
        );
        expect(
          await observation.observe(WebViewEnvironmentSettings()),
          same(result),
        );
        expect(
          ((observation.snapshot()['attempts'] as List).single
              as Map)['status'],
          result?.status ?? 'unsupported',
        );
      }
      final error = StateError('provider failed');
      final failed = AndroidPrewarmObservation(
        mode: AndroidPrewarmMode.native,
        elapsedMicros: () => 1,
        nativePrewarm: (_) => throw error,
      );
      await expectLater(
        failed.observe(WebViewEnvironmentSettings()),
        throwsA(same(error)),
      );
      expect(failed.pending, isFalse);
      expect(
        ((failed.snapshot()['attempts'] as List).single as Map)['status'],
        'exception',
      );
    },
  );

  test(
    'bypass control never calls native and has no synthetic native duration',
    () async {
      final observation = AndroidPrewarmObservation(
        mode: AndroidPrewarmMode.bypass,
        elapsedMicros: () => 4,
        nativePrewarm: (_) => throw StateError('native must not be called'),
      );
      final result = await observation.observe(WebViewEnvironmentSettings());
      expect(result!.status, 'bypassed_for_probe');
      expect(observation.nativeInvocations, 0);
      expect(observation.pending, isFalse);
      final attempt =
          (observation.snapshot()['attempts'] as List).single as Map;
      expect(attempt['status'], 'bypassedForProbe');
      expect(attempt.containsKey('nativeDurationMs'), isFalse);
    },
  );

  test(
    'missing overlap stays notObserved and bypass is a separate control',
    () {
      expect(
        androidStartupOverlap(
          mode: AndroidPrewarmMode.native,
          requested: true,
          nativePendingAtRequest: false,
        ),
        'notObserved',
      );
      expect(
        androidStartupOverlap(
          mode: AndroidPrewarmMode.native,
          requested: true,
          nativePendingAtRequest: true,
        ),
        'observedAtRequest',
      );
      expect(
        androidStartupOverlap(
          mode: AndroidPrewarmMode.bypass,
          requested: true,
          nativePendingAtRequest: true,
        ),
        'notApplicableToBypass',
      );
      expect(
        androidStartupOverlap(
          mode: AndroidPrewarmMode.native,
          requested: false,
          nativePendingAtRequest: true,
        ),
        'notRequested',
      );
    },
  );

  test(
    'the observer retains the actual coordinator gate and concurrent consumers',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      WebViewEnvironmentHolder.debugIsWindowsOverride = false;
      final native = Completer<WebViewEnvironmentPrewarmResult?>();
      final observation = AndroidPrewarmObservation(
        mode: AndroidPrewarmMode.native,
        elapsedMicros: () => 0,
        nativePrewarm: (_) => native.future,
      );
      WebViewEnvironmentHolder.debugOverridePrewarm(observation.observe);
      Future<bool>? operation;
      try {
        expect(
          WebViewEnvironmentHolder.prewarmWaitLimit,
          const Duration(seconds: 30),
        );
        operation = WebViewEnvironmentHolder.prewarm(
          hasEnabledPlugin: () async => true,
        );
        await pumpEventQueue();
        final completed = <int>[];
        final first = WebViewEnvironmentHolder.initialize().then(
          (_) => completed.add(1),
        );
        final second = WebViewEnvironmentHolder.initialize().then(
          (_) => completed.add(2),
        );
        await pumpEventQueue();
        expect(completed, isEmpty);
        expect(observation.nativeInvocations, 1);
        native.complete(
          const WebViewEnvironmentPrewarmResult(
            status: 'ok',
            duration: Duration.zero,
          ),
        );
        await operation;
        await Future.wait([first, second]);
        expect(completed, [1, 2]);
      } finally {
        if (!native.isCompleted) native.complete(null);
        await operation;
        WebViewEnvironmentHolder.debugOverridePrewarm(null);
        WebViewEnvironmentHolder.debugIsWindowsOverride = null;
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

FrameTiming _frame() => FrameTiming(
  vsyncStart: 1,
  buildStart: 2,
  buildFinish: 3,
  rasterStart: 4,
  rasterFinish: 5,
  rasterFinishWallTime: 5,
);
