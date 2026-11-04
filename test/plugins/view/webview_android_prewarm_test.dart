import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<WebViewEnvironmentSettings> calls;
  Completer<WebViewEnvironmentPrewarmResult?>? pending;
  Future<bool>? warming;
  Completer<bool>? eligibility;

  Future<bool> startPrewarm({bool enabled = true}) => warming =
      WebViewEnvironmentHolder.prewarm(hasEnabledPlugin: () async => enabled);

  setUp(() {
    calls = [];
    pending = null;
    warming = null;
    eligibility = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    WebViewEnvironmentHolder.debugIsWindowsOverride = false;
    WebViewEnvironmentHolder.debugOverrideInitialize(null);
    WebViewEnvironmentHolder.debugOverridePrewarm((settings) {
      calls.add(settings);
      return pending?.future ?? Future.value(_ok);
    });
    WebView2CreationDiagnostics.debugReset();
  });

  tearDown(() async {
    if (eligibility != null && !eligibility!.isCompleted)
      eligibility!.complete(true);
    final outstanding = pending;
    if (outstanding != null && !outstanding.isCompleted) {
      outstanding.complete(_ok);
    }
    try {
      await warming;
    } catch (_) {
      // Tests that exercise native failures observe the error themselves.
    }
    WebViewEnvironmentHolder.debugOverridePrewarm(null);
    WebViewEnvironmentHolder.debugIsWindowsOverride = null;
    WebViewEnvironmentHolder.prewarmWaitLimit = const Duration(seconds: 30);
    debugDefaultTargetPlatformOverride = null;
    WebView2CreationDiagnostics.debugReset();
  });

  test(
    'Android does not receive WebView2 profile or custom-scheme settings',
    () async {
      expect(await startPrewarm(), isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.toMap(), WebViewEnvironmentSettings().toMap());
      expect(WebViewEnvironmentHolder.environment, isNull);
    },
  );

  test('creation also waits while eligibility is pending', () async {
    eligibility = Completer<bool>();
    pending = Completer<WebViewEnvironmentPrewarmResult?>();
    final prewarm = warming = WebViewEnvironmentHolder.prewarm(
      hasEnabledPlugin: () => eligibility!.future,
    );
    var ready = false;
    final creation = WebViewEnvironmentHolder.initialize().then(
      (_) => ready = true,
    );
    await pumpEventQueue();
    expect(ready, false);
    expect(calls, isEmpty);
    eligibility!.complete(true);
    await pumpEventQueue();
    expect(calls, hasLength(1));
    expect(ready, false);
    pending!.complete(_ok);
    await prewarm;
    await creation;
    expect(ready, true);
  });

  test(
    'eligibility completing after a timeout cannot start a late prewarm',
    () async {
      eligibility = Completer<bool>();
      WebViewEnvironmentHolder.prewarmWaitLimit = Duration.zero;
      final prewarm = warming = WebViewEnvironmentHolder.prewarm(
        hasEnabledPlugin: () => eligibility!.future,
      );
      await WebViewEnvironmentHolder.initialize();
      eligibility!.complete(true);
      expect(await prewarm, false);
      expect(calls, isEmpty);
    },
  );

  test(
    'concurrent prewarm requests share the gate, not native startup',
    () async {
      pending = Completer<WebViewEnvironmentPrewarmResult?>();
      final first = startPrewarm();
      expect(
        await WebViewEnvironmentHolder.prewarm(
          hasEnabledPlugin: () async => true,
        ),
        false,
      );
      await pumpEventQueue();
      expect(calls, hasLength(1));
      pending!.complete(_ok);
      expect(await first, true);
    },
  );

  test('a timeout releases an existing late consumer too', () {
    fakeAsync((time) {
      pending = Completer<WebViewEnvironmentPrewarmResult?>();
      startPrewarm();
      time.flushMicrotasks();
      var firstReady = false;
      var secondReady = false;
      try {
        WebViewEnvironmentHolder.initialize().then((_) => firstReady = true);
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 29));
        WebViewEnvironmentHolder.initialize().then((_) => secondReady = true);
        time.flushMicrotasks();
        expect(firstReady, false);
        expect(secondReady, false);
        time.elapse(const Duration(seconds: 1));
        time.flushMicrotasks();
        expect(firstReady, true);
        expect(secondReady, true);
      } finally {
        if (!pending!.isCompleted) pending!.complete(_ok);
        time.flushMicrotasks();
      }
    });
  });

  test('the supported platform set is explicit', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      WebViewEnvironmentHolder.debugIsWindowsOverride =
          platform == TargetPlatform.windows;
      expect(
        WebViewEnvironmentHolder.supportsPrewarm,
        platform == TargetPlatform.windows ||
            platform == TargetPlatform.android,
        reason: platform.name,
      );
    }
  });

  test('no enabled plugin means no Android startup work', () async {
    expect(await startPrewarm(enabled: false), isFalse);
    expect(calls, isEmpty);
    expect(WebViewEnvironmentHolder.environment, isNull);
  });

  test(
    'Android creation waits asynchronously for an in-flight prewarm',
    () async {
      pending = Completer();
      final prewarm = startPrewarm();
      await pumpEventQueue();
      expect(calls, hasLength(1));

      var firstReady = false;
      var secondReady = false;
      final first = WebViewEnvironmentHolder.initialize().then((_) {
        firstReady = true;
      });
      final second = WebViewEnvironmentHolder.initialize().then((_) {
        secondReady = true;
      });
      await pumpEventQueue();
      expect(firstReady, isFalse);
      expect(secondReady, isFalse);

      pending!.complete(_ok);
      await prewarm;
      await Future.wait([first, second]);
      expect(firstReady, isTrue);
      expect(secondReady, isTrue);
      expect(calls, hasLength(1));
      expect(WebViewEnvironmentHolder.environment, isNull);
    },
  );

  test(
    'a failed prewarm releases Android creation without an environment',
    () async {
      pending = Completer();
      final prewarm = startPrewarm();
      final errorObserved = expectLater(prewarm, throwsStateError);
      await pumpEventQueue();
      expect(calls, hasLength(1));
      final creation = WebViewEnvironmentHolder.initialize();

      pending!.completeError(StateError('provider unavailable'));
      await errorObserved;
      await expectLater(creation, completes);
      expect(WebViewEnvironmentHolder.environment, isNull);
    },
  );

  test('a null native result is nonfatal for Android creation', () async {
    pending = Completer();
    final prewarm = startPrewarm();
    await pumpEventQueue();
    final creation = WebViewEnvironmentHolder.initialize();
    pending!.complete(null);
    await prewarm;
    await expectLater(creation, completes);
    expect(WebViewEnvironmentHolder.environment, isNull);
  });

  test('a timed-out prewarm does not delay every later Android view', () async {
    pending = Completer();
    WebViewEnvironmentHolder.prewarmWaitLimit = Duration.zero;
    final prewarm = startPrewarm();
    await pumpEventQueue();
    expect(calls, hasLength(1));

    await WebViewEnvironmentHolder.initialize();
    WebViewEnvironmentHolder.prewarmWaitLimit = const Duration(seconds: 30);
    await WebViewEnvironmentHolder.initialize().timeout(
      const Duration(seconds: 1),
    );
    expect(WebViewEnvironmentHolder.environment, isNull);
    pending!.complete(_ok);
    await prewarm;
  });
}

const _ok = WebViewEnvironmentPrewarmResult(
  status: 'ok',
  duration: Duration(milliseconds: 12),
);
