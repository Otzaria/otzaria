import 'dart:async';

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

  Future<bool> startPrewarm({bool enabled = true}) => warming =
      WebViewEnvironmentHolder.prewarm(hasEnabledPlugin: () async => enabled);

  setUp(() {
    calls = [];
    pending = null;
    warming = null;
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
